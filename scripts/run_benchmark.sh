#!/bin/bash
# ============================================================
# FoldBenchmark: Run all or selected models/scenarios
#
# Basic usage (backward compatible):
#   bash run_benchmark.sh                          # All models, all scenarios
#   bash run_benchmark.sh --model af3              # Single model, all scenarios
#   bash run_benchmark.sh --scenario monomer       # All models, single scenario
#   bash run_benchmark.sh --model af3 --scenario monomer
#   bash run_benchmark.sh --gpu 0
#
# Advanced usage:
#   bash run_benchmark.sh --fasta my.fasta --models "af3,boltz2" --top-n 5 --report
#   bash run_benchmark.sh --uniprot ids.txt --models "rf3" --gpu 0
#   bash run_benchmark.sh --cases "1BRS_barnase_barstar,1UBQ_ubiquitin" --models "boltz2"
#   bash run_benchmark.sh --screen-only --top-n 10 --by ptm --report
# ============================================================

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="${PROJECT_ROOT}/scripts"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
MODEL_FILTER=""       # legacy --model (single value)
MODELS_FILTER=""      # --models (comma-separated)
SCENARIO_FILTER=""
GPU_ID=0
FASTA_FILE=""
UNIPROT_FILE=""
CASES_FILTER=""       # comma-separated case names
TOP_N=""
SORT_BY="ptm"
DO_REPORT=0
SCREEN_ONLY=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --model)     MODEL_FILTER="$2";   shift 2 ;;
        --models)    MODELS_FILTER="$2";  shift 2 ;;
        --scenario)  SCENARIO_FILTER="$2"; shift 2 ;;
        --gpu)       GPU_ID="$2";         shift 2 ;;
        --fasta)     FASTA_FILE="$2";     shift 2 ;;
        --uniprot)   UNIPROT_FILE="$2";   shift 2 ;;
        --cases)     CASES_FILTER="$2";   shift 2 ;;
        --top-n)     TOP_N="$2";          shift 2 ;;
        --by)        SORT_BY="$2";        shift 2 ;;
        --report)    DO_REPORT=1;         shift 1 ;;
        --screen-only) SCREEN_ONLY=1;     shift 1 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

ALL_MODELS="af3 alphafast boltz2 openfold3 protenix chai1 intellifold rf3 esmfold2 esm3"
ALL_SCENARIOS="protein_protein protein_ligand protein_rna monomer antibody_antigen protein_dna homo_multimer metal_ion covalent_mod"

# --models takes precedence over --model
if [ -n "$MODELS_FILTER" ]; then
    MODELS="${MODELS_FILTER//,/ }"   # replace commas with spaces
elif [ -n "$MODEL_FILTER" ]; then
    MODELS="$MODEL_FILTER"
else
    MODELS="$ALL_MODELS"
fi

SCENARIOS=${SCENARIO_FILTER:-$ALL_SCENARIOS}

# ---------------------------------------------------------------------------
# Step 1: Generate inputs from FASTA or UniProt if requested
# ---------------------------------------------------------------------------
if [ -n "$FASTA_FILE" ] || [ -n "$UNIPROT_FILE" ]; then
    PREP_CMD="python ${SCRIPTS}/prepare_inputs_from_fasta.py"
    if [ -n "$FASTA_FILE" ]; then
        PREP_CMD="$PREP_CMD --fasta $FASTA_FILE"
    else
        PREP_CMD="$PREP_CMD --uniprot $UNIPROT_FILE"
    fi
    echo "Generating inputs..."
    $PREP_CMD
    # Append "screening" to the scenario list so the main loop picks it up
    SCENARIOS="$SCENARIOS screening"
fi

# ---------------------------------------------------------------------------
# Ensure timing file exists
# ---------------------------------------------------------------------------
TIMING="${PROJECT_ROOT}/results/timing.csv"
if [ ! -f "$TIMING" ]; then
    echo "model,scenario,case_name,elapsed_seconds" > "$TIMING"
fi

echo "============================================"
echo "FoldBenchmark"
echo "Models:    $MODELS"
echo "Scenarios: $SCENARIOS"
echo "GPU:       $GPU_ID"
[ -n "$CASES_FILTER" ]  && echo "Cases:     $CASES_FILTER"
[ -n "$TOP_N" ]         && echo "Top-N:     $TOP_N (by $SORT_BY)"
echo "Start:     $(date)"
echo "============================================"

# ---------------------------------------------------------------------------
# Step 2: Prediction loop (skipped with --screen-only)
# ---------------------------------------------------------------------------
TOTAL=0
DONE=0
FAILED=0

if [ "$SCREEN_ONLY" -eq 0 ]; then
    for scenario in $SCENARIOS; do
        INPUT_DIR="${PROJECT_ROOT}/inputs/${scenario}/af3_json"
        if [ ! -d "$INPUT_DIR" ]; then
            echo "SKIP scenario: $scenario (no inputs at $INPUT_DIR)"
            continue
        fi

        for json_file in "${INPUT_DIR}"/*.json; do
            [ ! -f "$json_file" ] && continue
            CASE_NAME=$(basename "$json_file" .json)

            # --cases filter: skip if not in the allow-list
            if [ -n "$CASES_FILTER" ]; then
                echo ",$CASES_FILTER," | grep -q ",${CASE_NAME}," || continue
            fi

            for model in $MODELS; do
                TOTAL=$((TOTAL + 1))
                LOG="${PROJECT_ROOT}/outputs/${model}/${scenario}/${CASE_NAME}.log"
                mkdir -p "$(dirname "$LOG")"

                echo ""
                echo "[${DONE}+${FAILED}/${TOTAL}] ${model} / ${scenario} / ${CASE_NAME}"

                bash "${SCRIPTS}/run_single_model.sh" "$model" "$scenario" "$CASE_NAME" "$GPU_ID" \
                    > "$LOG" 2>&1

                if grep -q "FAILED" "$LOG" 2>/dev/null; then
                    FAILED=$((FAILED + 1))
                    echo "  FAILED (see $LOG)"
                else
                    DONE=$((DONE + 1))
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
fi

# ---------------------------------------------------------------------------
# Step 3: Post-run screening / report
# ---------------------------------------------------------------------------
if [ -n "$TOP_N" ] || [ "$DO_REPORT" -eq 1 ] || [ "$SCREEN_ONLY" -eq 1 ]; then
    SCREEN_ARGS=""

    # Collect results first
    echo ""
    echo "Collecting results..."
    python "${SCRIPTS}/collect_results.py"

    # Build screen.py arguments
    [ -n "$MODELS_FILTER" ] && SCREEN_ARGS="$SCREEN_ARGS --models $MODELS_FILTER"
    [ -n "$MODEL_FILTER" ]  && [ -z "$MODELS_FILTER" ] && SCREEN_ARGS="$SCREEN_ARGS --models $MODEL_FILTER"
    [ -n "$CASES_FILTER" ]  && SCREEN_ARGS="$SCREEN_ARGS --cases $CASES_FILTER"
    [ -n "$TOP_N" ]         && SCREEN_ARGS="$SCREEN_ARGS --top-n $TOP_N --copy-cif"
    SCREEN_ARGS="$SCREEN_ARGS --by $SORT_BY"

    if [ "$DO_REPORT" -eq 1 ]; then
        REPORT_PATH="${PROJECT_ROOT}/results/screen_$(date +%Y%m%d_%H%M%S).md"
        SCREEN_ARGS="$SCREEN_ARGS --report $REPORT_PATH"
    fi

    echo "Screening results..."
    python "${SCRIPTS}/screen.py" $SCREEN_ARGS
fi
