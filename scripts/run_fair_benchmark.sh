#!/usr/bin/env bash
# ============================================================
# run_fair_benchmark.sh — 公平 + 高效的 10 模型 × 81 case benchmark
#
# 三大保障：
#   1. CPU idle gate  — CPU < threshold 连续 N 秒后才启动重负载阶段
#   2. 单 GPU 推理    — 所有非 AlphaFast 模型均在 GPU 3 串行推理
#   3. ColabFold MSA 共享 — 每条序列只调 API 一次，Boltz-2 + IntelliFold 复用
#
# 异步流水线：
#   Phase 0: [GPU 3] no-MSA 模型推理  ‖  [CPU/网络] 预取 ColabFold MSA
#   Phase 1: [GPU 3] MSA-cached 模型   (boltz2, intellifold 用 patched YAML)
#   Phase 2: [GPU 3] 独立 MSA 模型     (openfold3, chai1 各自 ColabFold)
#   Phase 3: [CPU gate → GPU 3] 本地 MSA 模型 (af3-Docker, protenix)
#   Phase 4: [4 GPU] AlphaFast all-in-one 重跑 81 cases
#   Phase 5: collect_results.py
#
# 用法：
#   bash scripts/run_fair_benchmark.sh \
#       [--cpu-threshold 20] [--cpu-wait 30] [--gpu 3]
# ============================================================
# 不用 set -e / pipefail — 单个 case 失败不中断整个 benchmark
set -u

# ── 参数解析 ──────────────────────────────────────────────────
CPU_THRESHOLD=20     # CPU 使用率阈值 (%)
CPU_WAIT_SEC=30      # 需持续低于阈值的秒数
GPU_ID=3             # 推理 GPU
GPU_UTIL_THRESHOLD=10  # GPU 使用率阈值 (%)，低于此视为空闲
GPU_MEM_THRESHOLD=500  # GPU 显存阈值 (MiB)，低于此视为空闲
GPU_WAIT_SEC=10        # GPU 需持续空闲的秒数
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu-threshold)  CPU_THRESHOLD=$2;      shift 2 ;;
        --cpu-wait)       CPU_WAIT_SEC=$2;        shift 2 ;;
        --gpu)            GPU_ID=$2;              shift 2 ;;
        --gpu-util)       GPU_UTIL_THRESHOLD=$2;  shift 2 ;;
        --gpu-mem)        GPU_MEM_THRESHOLD=$2;   shift 2 ;;
        --gpu-wait)       GPU_WAIT_SEC=$2;        shift 2 ;;
        --dry-run)        DRY_RUN=1;              shift   ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="${PROJECT_ROOT}/scripts"
TIMING_FILE="${PROJECT_ROOT}/results/timing.csv"
MSA_CACHE="${PROJECT_ROOT}/msa_cache"

cd "$PROJECT_ROOT"
source "${FOLDBENCH_CONFIG:-${SCRIPTS}/config.sh}"

TS=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${PROJECT_ROOT}/results/run_fair_${TS}"
FAILED_LOG="${LOG_DIR}/FAILED.txt"
mkdir -p "$LOG_DIR" "${PROJECT_ROOT}/results" "$MSA_CACHE"
[ -f "$TIMING_FILE" ] || echo "model,scenario,case_name,elapsed_seconds" > "$TIMING_FILE"
: > "$FAILED_LOG"   # 清空失败记录
FAIL_COUNT=0

# ── 工具函数 ──────────────────────────────────────────────────

wait_cpu_idle() {
    # 等待 CPU 使用率连续 $CPU_WAIT_SEC 秒低于 $CPU_THRESHOLD%
    local idle_streak=0
    echo "[CPU GATE] Waiting for CPU < ${CPU_THRESHOLD}% for ${CPU_WAIT_SEC}s consecutive..."
    while [ $idle_streak -lt $CPU_WAIT_SEC ]; do
        # 采样两次 /proc/stat，间隔 1 秒
        local s1 s2
        s1=$(head -1 /proc/stat)
        sleep 1
        s2=$(head -1 /proc/stat)

        local idle1 total1 idle2 total2
        idle1=$(echo "$s1" | awk '{print $5}')
        total1=$(echo "$s1" | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')
        idle2=$(echo "$s2" | awk '{print $5}')
        total2=$(echo "$s2" | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')

        local d_idle=$((idle2 - idle1))
        local d_total=$((total2 - total1))
        if [ $d_total -eq 0 ]; then
            idle_streak=$((idle_streak + 1))
            continue
        fi

        local usage=$((100 * (d_total - d_idle) / d_total))
        if [ $usage -lt $CPU_THRESHOLD ]; then
            idle_streak=$((idle_streak + 1))
        else
            if [ $idle_streak -gt 0 ]; then
                echo "[CPU GATE] CPU=${usage}% — streak reset (was ${idle_streak}s)"
            fi
            idle_streak=0
        fi
    done
    echo "[CPU GATE] CPU idle confirmed (< ${CPU_THRESHOLD}% for ${CPU_WAIT_SEC}s). Proceeding."
}

wait_gpu_idle() {
    # 等待 GPU $GPU_ID 使用率和显存连续 $GPU_WAIT_SEC 秒低于阈值
    local idle_streak=0
    echo "[GPU GATE] Waiting for GPU ${GPU_ID}: util < ${GPU_UTIL_THRESHOLD}% AND mem < ${GPU_MEM_THRESHOLD} MiB for ${GPU_WAIT_SEC}s..."
    while [ $idle_streak -lt $GPU_WAIT_SEC ]; do
        # nvidia-smi 查询指定 GPU
        local info
        info=$(nvidia-smi --id="$GPU_ID" \
                   --query-gpu=utilization.gpu,memory.used \
                   --format=csv,noheader,nounits 2>/dev/null) || {
            echo "[GPU GATE] nvidia-smi failed — skipping GPU check"
            return 0
        }
        local util mem
        util=$(echo "$info" | awk -F',' '{gsub(/ /,"",$1); print $1}')
        mem=$(echo "$info" | awk -F',' '{gsub(/ /,"",$2); print $2}')

        if [ "$util" -lt "$GPU_UTIL_THRESHOLD" ] && [ "$mem" -lt "$GPU_MEM_THRESHOLD" ]; then
            idle_streak=$((idle_streak + 1))
        else
            if [ $idle_streak -gt 0 ]; then
                echo "[GPU GATE] GPU ${GPU_ID}: util=${util}% mem=${mem}MiB — streak reset (was ${idle_streak}s)"
            fi
            idle_streak=0
        fi
        sleep 1
    done
    echo "[GPU GATE] GPU ${GPU_ID} idle confirmed (util<${GPU_UTIL_THRESHOLD}% mem<${GPU_MEM_THRESHOLD}MiB for ${GPU_WAIT_SEC}s)."
}

run_case() {
    # run_case <model> <scenario> <case_name> [env_vars...]
    # 单个 case 失败不中断：记录到 FAILED.txt，继续下一个
    local model=$1 scenario=$2 case_name=$3
    shift 3

    echo "[$(date +%H:%M:%S)] ${model} / ${scenario} / ${case_name}"

    local rc=0
    env "$@" \
        bash "${SCRIPTS}/run_single_model.sh" "$model" "$scenario" "$case_name" "$GPU_ID" \
        2>&1 | tee -a "${LOG_DIR}/${model}.log" \
        || true   # tee 管道本身不 abort

    # 检查实际 model 进程退出码（PIPESTATUS[0]）
    rc=${PIPESTATUS[0]:-0}
    if [ "$rc" -ne 0 ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "${model},${scenario},${case_name},exit=${rc}" >> "$FAILED_LOG"
        echo "  [FAIL] ${model}/${scenario}/${case_name} (exit=${rc}) — logged"
    fi
    return 0   # 始终返回 0，不中断主循环
}

get_all_cases() {
    # 输出 "scenario case_name" 行
    for d in inputs/*/af3_json; do
        [ -d "$d" ] || continue
        local sc
        sc=$(basename "$(dirname "$d")")
        for f in "$d"/*.json; do
            [ -f "$f" ] || continue
            echo "$sc $(basename "$f" .json)"
        done
    done | sort
}

# ── 打印概要 ──────────────────────────────────────────────────

TOTAL_CASES=$(get_all_cases | wc -l)

echo "============================================================"
echo "FoldBenchmark — Fair Benchmark"
echo "Start      : $(date)"
echo "GPU        : $GPU_ID"
echo "GPU gate   : util < ${GPU_UTIL_THRESHOLD}%, mem < ${GPU_MEM_THRESHOLD} MiB, for ${GPU_WAIT_SEC}s"
echo "CPU gate   : < ${CPU_THRESHOLD}% for ${CPU_WAIT_SEC}s"
echo "Cases      : $TOTAL_CASES"
echo "MSA cache  : $MSA_CACHE"
echo "Logs       : $LOG_DIR"
echo "============================================================"

if [ $DRY_RUN -eq 1 ]; then
    echo "[DRY RUN] Would run $TOTAL_CASES cases × 10 models"
    get_all_cases
    exit 0
fi

# ================================================================
# Phase 0: PARALLEL
#   Background — 预取 ColabFold MSA（CPU/网络，不占 GPU）
#   Foreground — no-MSA 模型推理（GPU $GPU_ID）
# ================================================================
echo ""
echo "============================================================"
echo "Phase 0: [PARALLEL] MSA pre-fetch + no-MSA inference"
echo "============================================================"

# ── 后台：MSA 预取 ──
echo "[Phase 0-bg] Starting MSA pre-computation in background..."
/data/zcwang/anaconda3/envs/boltz2/bin/python \
    "${SCRIPTS}/precompute_msa.py" \
    --inputs-dir "${PROJECT_ROOT}/inputs" \
    --cache-dir "$MSA_CACHE" \
    > "${LOG_DIR}/msa_precompute.log" 2>&1 &
MSA_PID=$!
echo "[Phase 0-bg] MSA pre-compute PID=$MSA_PID"

# ── 前台：no-MSA 模型（rf3, esmfold2, esm3）──
wait_gpu_idle
for model in rf3 esmfold2 esm3; do
    echo ""
    echo "-------- $model (no-MSA, GPU $GPU_ID) --------"
    while IFS=' ' read -r sc ca; do
        run_case "$model" "$sc" "$ca"
    done < <(get_all_cases)
done

# ── 等待 MSA 预取完成 ──
echo ""
echo "[Phase 0-bg] Waiting for MSA pre-compute to finish..."
if wait $MSA_PID; then
    echo "[Phase 0-bg] MSA pre-compute DONE"
else
    echo "[Phase 0-bg] MSA pre-compute had errors — check ${LOG_DIR}/msa_precompute.log"
    echo "  Falling back to --use_msa_server for boltz2/intellifold"
fi

echo "[Phase 0 DONE] $(date)"

# ================================================================
# Phase 1: MSA-cached 模型 (boltz2, intellifold)
#   使用 patched YAML（msa: field → 无需 --use_msa_server）
# ================================================================
echo ""
echo "============================================================"
echo "Phase 1: boltz2 + intellifold with cached MSA (GPU $GPU_ID)"
echo "============================================================"

wait_gpu_idle
for model in boltz2 intellifold; do
    echo ""
    echo "-------- $model (cached MSA) --------"
    while IFS=' ' read -r sc ca; do
        PATCHED="${MSA_CACHE}/patched_yaml/${sc}/${ca}.yaml"
        if [ -f "$PATCHED" ]; then
            # 使用 patched YAML，不调用 MSA server
            if [ "$model" = "boltz2" ]; then
                run_case "$model" "$sc" "$ca" \
                    "BOLTZ_INPUT_YAML=$PATCHED" \
                    "BOLTZ_NO_MSA_SERVER=1"
            else
                run_case "$model" "$sc" "$ca" \
                    "INTELLIFOLD_INPUT_YAML=$PATCHED" \
                    "INTELLIFOLD_NO_MSA_SERVER=1"
            fi
        else
            # Fallback: 无 patched YAML，用 MSA server（正常路径）
            run_case "$model" "$sc" "$ca"
        fi
    done < <(get_all_cases)
done

echo "[Phase 1 DONE] $(date)"

# ================================================================
# Phase 2: 独立 MSA 模型 (openfold3, chai1)
#   OpenFold3: 稳定 MSA 缓存目录（跨 case 复用同序列 MSA）
#   Chai-1:    --use-msa-server（不同格式，无法共享）
# ================================================================
echo ""
echo "============================================================"
echo "Phase 2: openfold3 + chai1 (own MSA, GPU $GPU_ID)"
echo "============================================================"

OF3_STABLE_MSA="${MSA_CACHE}/openfold3_msa"
mkdir -p "$OF3_STABLE_MSA"

wait_gpu_idle

echo ""
echo "-------- openfold3 (stable MSA cache) --------"
while IFS=' ' read -r sc ca; do
    run_case openfold3 "$sc" "$ca" "OF3_MSA_CACHE_DIR=$OF3_STABLE_MSA"
done < <(get_all_cases)

echo ""
echo "-------- chai1 --------"
while IFS=' ' read -r sc ca; do
    run_case chai1 "$sc" "$ca"
done < <(get_all_cases)

echo "[Phase 2 DONE] $(date)"

# ================================================================
# Phase 3: 本地 MSA 模型 (af3, protenix)
#   CPU-intensive MSA → 先等 CPU idle
# ================================================================
echo ""
echo "============================================================"
echo "Phase 3: af3 + protenix (local MSA, CPU gate → GPU $GPU_ID)"
echo "============================================================"

wait_cpu_idle

echo ""
echo "-------- protenix --------"
while IFS=' ' read -r sc ca; do
    run_case protenix "$sc" "$ca"
done < <(get_all_cases)

wait_cpu_idle

echo ""
echo "-------- af3 (Docker) --------"
while IFS=' ' read -r sc ca; do
    run_case af3 "$sc" "$ca"
done < <(get_all_cases)

echo "[Phase 3 DONE] $(date)"

# ================================================================
# Phase 4: AlphaFast all-in-one (4 GPU, 81 cases 单次 DB 扫描)
# ================================================================
echo ""
echo "============================================================"
echo "Phase 4: AlphaFast all-in-one (4 GPUs, $TOTAL_CASES cases)"
echo "============================================================"

wait_cpu_idle

wait_gpu_idle
bash "${SCRIPTS}/run_alphafast_all_in_one.sh" \
    2>&1 | tee "${LOG_DIR}/alphafast.log" \
    || true
AF_RC=${PIPESTATUS[0]:-0}
if [ "$AF_RC" -ne 0 ]; then
    echo "alphafast,ALL,all-in-one,exit=${AF_RC}" >> "$FAILED_LOG"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  [FAIL] AlphaFast all-in-one batch (exit=${AF_RC}) — check ${LOG_DIR}/alphafast.log"
fi

echo "[Phase 4 DONE] $(date)"

# ================================================================
# Phase 5: 汇总结果
# ================================================================
echo ""
echo "============================================================"
echo "Phase 5: Collecting results"
echo "============================================================"

python3 "${SCRIPTS}/collect_results.py" 2>&1 | tee "${LOG_DIR}/collect.log"

# ── 完成 + 失败汇总 ──────────────────────────────────────────
echo ""
echo "============================================================"
echo "FAIR BENCHMARK COMPLETE"
echo "End      : $(date)"
echo "Logs     : $LOG_DIR/"
echo "Results  : results/summary.md"
echo "Timing   : results/timing.csv"
echo "============================================================"

# 每模型完成数
echo ""
echo "Per-model completion:"
awk -F, 'NR>1{c[$1]++} END{for(m in c) printf "  %-12s %d\n", m, c[m]}' "$TIMING_FILE" | sort -k2 -rn

# ── 失败汇总 ──
echo ""
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "============================================================"
    echo "  WARNING: ${FAIL_COUNT} case(s) FAILED"
    echo "  Failed log: ${FAILED_LOG}"
    echo "============================================================"
    echo ""
    # 按模型分组显示
    while IFS= read -r line; do
        echo "  $line"
    done < "$FAILED_LOG"
    echo ""
    echo "To retry failed cases:"
    echo "  while IFS=, read -r model sc ca _; do"
    echo "    bash scripts/run_single_model.sh \"\$model\" \"\$sc\" \"\$ca\" $GPU_ID"
    echo "  done < ${FAILED_LOG}"
else
    echo "ALL CASES PASSED — no failures."
    rm -f "$FAILED_LOG"
fi
