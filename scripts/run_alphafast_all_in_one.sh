#!/bin/bash
# ============================================================
# AlphaFast ALL-IN-ONE batch: 全部22个case放入单次batch
# DB只扫一遍，比5次分scenario快约5倍
#
# 运行完后：
#   - outputs按scenario归位: outputs/alphafast/{scenario}/{case}/
#   - timing.csv中alphafast旧条目被替换为新计时
#
# Usage:
#   bash run_alphafast_all_in_one.sh
# ============================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
TIMING_FILE="${PROJECT_ROOT}/results/timing.csv"

source "${FOLDBENCH_CONFIG:-${SCRIPTS_DIR}/config.sh}"

ALPHAFAST_PYTHON=$ALPHAFAST_DIR/.venv/bin/python
ALPHAFAST_RUN=$ALPHAFAST_DIR/run_alphafold.py
MMSEQS_BIN=$ALPHAFAST_DIR/bin/bin/mmseqs
mkdir -p "$ALPHAFAST_JAX_CACHE"

SCENARIOS="protein_protein protein_ligand protein_rna monomer antibody_antigen"

# ---- 1. 收集所有22个case，建立 case→scenario 映射 ----
TMPDIR_INPUT=$(mktemp -d -t alphafast_all_XXXXXX)
TMPDIR_OUTPUT=$(mktemp -d -t alphafast_out_XXXXXX)
trap "rm -rf $TMPDIR_INPUT $TMPDIR_OUTPUT" EXIT

declare -A CASE_SCENARIO
PENDING=()

for scenario in $SCENARIOS; do
    INPUT_DIR="${PROJECT_ROOT}/inputs/${scenario}/af3_json"
    [ -d "$INPUT_DIR" ] || continue
    for json in "$INPUT_DIR"/*.json; do
        [ -f "$json" ] || continue
        case_name=$(basename "$json" .json)
        cp "$json" "$TMPDIR_INPUT/"
        CASE_SCENARIO["$case_name"]="$scenario"
        PENDING+=("$case_name")
    done
done

BATCH_SIZE=${#PENDING[@]}
echo "============================================"
echo "AlphaFast ALL-IN-ONE Batch"
echo "Cases: $BATCH_SIZE | GPUs: $ALPHAFAST_GPUS"
echo "Start: $(date)"
echo "============================================"

# ---- 2. 单次batch运行全部case ----
START=$(date +%s)

LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libstdc++.so.6 \
MMSEQS_USE_ALL_GPUS=1 \
CUDA_VISIBLE_DEVICES="${ALPHAFAST_GPUS}" \
$ALPHAFAST_PYTHON $ALPHAFAST_RUN \
    --input_dir="$TMPDIR_INPUT" \
    --output_dir="$TMPDIR_OUTPUT" \
    --model_dir="$ALPHAFAST_MODEL_DIR" \
    --db_dir="$ALPHAFAST_DB_DIR" \
    --mmseqs_binary_path="$MMSEQS_BIN" \
    --mmseqs_db_dir="$ALPHAFAST_DB_DIR/mmseqs" \
    --use_mmseqs_gpu=True \
    --batch_size="$BATCH_SIZE" \
    --jax_compilation_cache_dir="$ALPHAFAST_JAX_CACHE" \
    --run_data_pipeline=True \
    --run_inference=True \
    2>&1 || { echo "FAILED: alphafast all-in-one batch"; exit 1; }

END=$(date +%s)
ELAPSED=$((END - START))
PER_CASE=$((ELAPSED / BATCH_SIZE))

echo ""
echo "[DONE] ${BATCH_SIZE} cases in ${ELAPSED}s (avg ${PER_CASE}s/case)"

# ---- 3. 将输出移到正确的 scenario/case 目录 ----
echo "Moving outputs to outputs/alphafast/{scenario}/{case}/ ..."
for case_name in "${PENDING[@]}"; do
    scenario="${CASE_SCENARIO[$case_name]}"
    SRC="$TMPDIR_OUTPUT/$case_name"
    DST="${PROJECT_ROOT}/outputs/alphafast/${scenario}/${case_name}"
    if [ -d "$SRC" ]; then
        mkdir -p "$(dirname "$DST")"
        rm -rf "$DST"
        mv "$SRC" "$DST"
        echo "  OK: $scenario/$case_name"
    else
        echo "  WARN: no output for $case_name"
    fi
done

# ---- 4. 更新 timing.csv：删除旧alphafast条目，写入新计时 ----
echo "Updating timing.csv ..."
TMPCSV=$(mktemp)
# 保留非alphafast行
awk -F, '$1 != "alphafast"' "$TIMING_FILE" > "$TMPCSV"
# 追加新计时
for case_name in "${PENDING[@]}"; do
    scenario="${CASE_SCENARIO[$case_name]}"
    echo "alphafast,${scenario},${case_name},${PER_CASE}" >> "$TMPCSV"
done
mv "$TMPCSV" "$TIMING_FILE"

echo ""
echo "============================================"
echo "ALL-IN-ONE COMPLETE: $(date)"
echo "Total: ${ELAPSED}s | Per case (amortized): ${PER_CASE}s"
echo "============================================"
echo "Run: python scripts/collect_results.py"
