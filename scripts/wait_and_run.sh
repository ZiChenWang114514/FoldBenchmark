#!/bin/bash
# ============================================================
# wait_and_run.sh — 等 GPU 空闲后再启动 benchmark
#
# 用法:
#   bash scripts/wait_and_run.sh [gpu_id] [-- benchmark_args...]
#
# 示例:
#   bash scripts/wait_and_run.sh 0 -- --model esmfold2
#   bash scripts/wait_and_run.sh 0 -- --model esmfold2 --scenario monomer
#
# "空闲"定义: 显存占用 < 1000 MiB 且 GPU 利用率 < 10%
# 每 60 秒检查一次，检测到空闲后再等 30 秒确认稳定。
# ============================================================

GPU_ID=${1:-0}
shift
# 跳过可选的 "--" 分隔符
[ "$1" = "--" ] && shift

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

MEM_THRESHOLD=1000   # MiB：低于此值视为空闲
UTIL_THRESHOLD=10    # %：低于此值视为空闲
POLL_INTERVAL=60     # 秒：检查间隔
CONFIRM_WAIT=30      # 秒：确认稳定的等待时间

echo "============================================"
echo "wait_and_run.sh"
echo "GPU:       ${GPU_ID}"
echo "Threshold: mem < ${MEM_THRESHOLD} MiB, util < ${UTIL_THRESHOLD}%"
echo "Benchmark: bash run_benchmark.sh --gpu ${GPU_ID} $*"
echo "Started:   $(date)"
echo "============================================"

while true; do
    MEM_USED=$(nvidia-smi --id=${GPU_ID} \
        --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
    UTIL=$(nvidia-smi --id=${GPU_ID} \
        --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ' %')

    echo "[$(date '+%H:%M:%S')] GPU ${GPU_ID}: mem=${MEM_USED} MiB, util=${UTIL}%"

    if [ -n "$MEM_USED" ] && [ -n "$UTIL" ] \
       && [ "$MEM_USED" -lt "$MEM_THRESHOLD" ] \
       && [ "$UTIL" -lt "$UTIL_THRESHOLD" ]; then
        echo "[$(date '+%H:%M:%S')] GPU ${GPU_ID} looks idle — waiting ${CONFIRM_WAIT}s to confirm..."
        sleep "$CONFIRM_WAIT"

        # 再检查一次，防止瞬间空闲
        MEM_USED2=$(nvidia-smi --id=${GPU_ID} \
            --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
        UTIL2=$(nvidia-smi --id=${GPU_ID} \
            --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ' %')

        if [ "$MEM_USED2" -lt "$MEM_THRESHOLD" ] && [ "$UTIL2" -lt "$UTIL_THRESHOLD" ]; then
            echo "============================================"
            echo "GPU ${GPU_ID} confirmed idle at $(date)"
            echo "Launching benchmark..."
            echo "============================================"
            break
        else
            echo "[$(date '+%H:%M:%S')] False alarm (mem=${MEM_USED2}, util=${UTIL2}%), continuing to wait..."
        fi
    fi

    sleep "$POLL_INTERVAL"
done

exec bash "${PROJECT_ROOT}/scripts/run_benchmark.sh" --gpu "${GPU_ID}" "$@"
