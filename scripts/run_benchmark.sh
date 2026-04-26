#!/bin/bash
# ============================================================
# FoldBenchmark: Run all or selected models/scenarios
# Usage:
#   bash run_benchmark.sh                          # All models, all scenarios
#   bash run_benchmark.sh --model af3              # Single model, all scenarios
#   bash run_benchmark.sh --scenario monomer       # All models, single scenario
#   bash run_benchmark.sh --model af3 --scenario monomer  # Both
#   bash run_benchmark.sh --gpu 0                  # Specify GPU
# ============================================================

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="${PROJECT_ROOT}/scripts"

# Parse arguments
MODEL_FILTER=""
SCENARIO_FILTER=""
GPU_ID=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --model) MODEL_FILTER="$2"; shift 2 ;;
        --scenario) SCENARIO_FILTER="$2"; shift 2 ;;
        --gpu) GPU_ID="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

ALL_MODELS="af3 boltz2 openfold3 protenix chai1 intellifold"
ALL_SCENARIOS="protein_protein protein_ligand protein_rna monomer antibody_antigen"

MODELS=${MODEL_FILTER:-$ALL_MODELS}
SCENARIOS=${SCENARIO_FILTER:-$ALL_SCENARIOS}

# Initialize timing file
TIMING="${PROJECT_ROOT}/results/timing.csv"
if [ ! -f "$TIMING" ]; then
    echo "model,scenario,case_name,elapsed_seconds" > "$TIMING"
fi

echo "============================================"
echo "FoldBenchmark"
echo "Models: $MODELS"
echo "Scenarios: $SCENARIOS"
echo "GPU: $GPU_ID"
echo "Start: $(date)"
echo "============================================"

TOTAL=0
DONE=0
FAILED=0

for scenario in $SCENARIOS; do
    # Find all case names from af3_json directory
    INPUT_DIR="${PROJECT_ROOT}/inputs/${scenario}/af3_json"
    if [ ! -d "$INPUT_DIR" ]; then
        echo "SKIP scenario: $scenario (no inputs)"
        continue
    fi

    for json_file in "${INPUT_DIR}"/*.json; do
        [ ! -f "$json_file" ] && continue
        CASE_NAME=$(basename "$json_file" .json)

        for model in $MODELS; do
            TOTAL=$((TOTAL + 1))
            LOG="${PROJECT_ROOT}/outputs/${model}/${scenario}/${CASE_NAME}.log"
            mkdir -p "$(dirname $LOG)"

            echo ""
            echo "[${DONE}/${TOTAL}] ${model} / ${scenario} / ${CASE_NAME}"

            bash "${SCRIPTS}/run_single_model.sh" "$model" "$scenario" "$CASE_NAME" "$GPU_ID" \
                > "$LOG" 2>&1

            if grep -q "FAILED" "$LOG" 2>/dev/null; then
                FAILED=$((FAILED + 1))
                echo "  FAILED (see $LOG)"
            else
                DONE=$((DONE + 1))
                # Extract elapsed time from last line of timing
                ELAPSED=$(tail -1 "$TIMING" | cut -d',' -f4)
                echo "  OK (${ELAPSED}s)"
            fi
        done
    done
done

echo ""
echo "============================================"
echo "BENCHMARK COMPLETE: $(date)"
echo "Total: $TOTAL | Done: $DONE | Failed: $FAILED"
echo "Results: $TIMING"
echo "============================================"
