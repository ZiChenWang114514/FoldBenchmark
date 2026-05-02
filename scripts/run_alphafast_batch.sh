#!/bin/bash
# ============================================================
# AlphaFast batch runner: one MMseqs2 queryDB per scenario.
# Massively faster than per-case mode because the 5 padded DBs
# (uniref90 49G, uniprot 74G, mgnify 108G, small_bfd 16G,
# pdb_seqres 0.2G) are scanned ONCE for all cases in a scenario,
# not N times.
#
# Usage:
#   bash run_alphafast_batch.sh <scenario>
#   bash run_alphafast_batch.sh monomer
#
# Skips cases that already have outputs (CIF + summary_confidences).
# ============================================================
set -e

SCENARIO=${1:?"Usage: bash run_alphafast_batch.sh <scenario>"}

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT_DIR="${PROJECT_ROOT}/inputs/${SCENARIO}/af3_json"
OUTPUTS="${PROJECT_ROOT}/outputs/alphafast/${SCENARIO}"
TIMING_FILE="${PROJECT_ROOT}/results/timing.csv"
mkdir -p "$OUTPUTS" "$(dirname "$TIMING_FILE")"

if [ ! -d "$INPUT_DIR" ]; then
    echo "[ERROR] No input dir: $INPUT_DIR"
    exit 1
fi

ALPHAFAST_DIR=/data2/zcwang/af3/alphafast
ALPHAFAST_PYTHON=$ALPHAFAST_DIR/.venv/bin/python
ALPHAFAST_RUN=$ALPHAFAST_DIR/run_alphafold.py
MMSEQS_BIN=$ALPHAFAST_DIR/bin/bin/mmseqs
ALPHAFAST_DB_DIR="${ALPHAFAST_DB_DIR:-/data2/zcwang/alphafast_db}"
ALPHAFAST_MODEL_DIR="${ALPHAFAST_MODEL_DIR:-/data/zxhuang/Shared/Alphafold3params}"
ALPHAFAST_GPUS="${ALPHAFAST_GPUS:-0,1,2,3}"
ALPHAFAST_JAX_CACHE="${ALPHAFAST_JAX_CACHE:-/data2/zcwang/af3/alphafast/jax_cache}"
mkdir -p "$ALPHAFAST_JAX_CACHE"

# Stage only un-finished cases into a tmp dir so AlphaFast batches them
TMPDIR=$(mktemp -d -t alphafast_batch_${SCENARIO}_XXXXXX)
trap "rm -rf $TMPDIR" EXIT

PENDING=()
for json in "$INPUT_DIR"/*.json; do
    [ ! -f "$json" ] && continue
    case_name=$(basename "$json" .json)
    # Skip if output already complete (model.cif present in nested AlphaFast layout)
    if find "${OUTPUTS}/${case_name}" -name "*_model.cif" 2>/dev/null | grep -q .; then
        echo "[SKIP] alphafast/${SCENARIO}/${case_name}: already done"
        continue
    fi
    cp "$json" "$TMPDIR/"
    PENDING+=("$case_name")
done

if [ ${#PENDING[@]} -eq 0 ]; then
    echo "[BATCH] alphafast/${SCENARIO}: nothing to do"
    exit 0
fi

BATCH_SIZE=${#PENDING[@]}
echo "[BATCH] alphafast/${SCENARIO}: $BATCH_SIZE cases to run: ${PENDING[*]}"
echo "[BATCH] GPUs: $ALPHAFAST_GPUS, DB: $ALPHAFAST_DB_DIR"

START=$(date +%s)

LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libstdc++.so.6 \
MMSEQS_USE_ALL_GPUS=1 \
CUDA_VISIBLE_DEVICES="${ALPHAFAST_GPUS}" \
$ALPHAFAST_PYTHON $ALPHAFAST_RUN \
    --input_dir="$TMPDIR" \
    --output_dir="$OUTPUTS" \
    --model_dir="$ALPHAFAST_MODEL_DIR" \
    --db_dir="$ALPHAFAST_DB_DIR" \
    --mmseqs_binary_path="$MMSEQS_BIN" \
    --mmseqs_db_dir="$ALPHAFAST_DB_DIR/mmseqs" \
    --use_mmseqs_gpu=True \
    --batch_size="$BATCH_SIZE" \
    --jax_compilation_cache_dir="$ALPHAFAST_JAX_CACHE" \
    --run_data_pipeline=True \
    --run_inference=True \
    2>&1 || { echo "FAILED: alphafast/${SCENARIO} (batch)"; exit 1; }

END=$(date +%s)
ELAPSED=$((END - START))
PER_CASE=$((ELAPSED / BATCH_SIZE))

# Write per-case timing (amortized across batch)
for case_name in "${PENDING[@]}"; do
    echo "alphafast,${SCENARIO},${case_name},${PER_CASE}" >> "$TIMING_FILE"
done

echo "[BATCH DONE] alphafast/${SCENARIO}: ${BATCH_SIZE} cases in ${ELAPSED}s (avg ${PER_CASE}s/case)"
