#!/bin/bash
# ============================================================
# FoldBenchmark: Full re-run of all 8 models × 22 cases
# Serial execution for fair timing comparison.
#
# Order: boltz2 → protenix → chai1 → intellifold → openfold3
#        → rf3 → af3 → alphafast (all-in-one batch)
#
# - Models 1-6: GPU 1 (single-card)
# - AF3: Docker with GPU 1 (or conda fallback via run_af3_conda.sh)
# - AlphaFast: ALL-IN-ONE batch (22 cases × single DB scan), GPU 0-3
#   Uses run_alphafast_all_in_one.sh — 75 s/case vs ~200 s/case per-scenario
# ============================================================
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="${PROJECT_ROOT}/scripts"
GPU_SINGLE=1

echo "========================================================"
echo "FoldBenchmark — Full Re-run"
echo "Start: $(date)"
echo "GPU (single-card models): ${GPU_SINGLE}"
echo "GPU (AlphaFast batch):    0,1,2,3"
echo "========================================================"

TOTAL_START=$(date +%s)

# --- Models 1-6: single-card on GPU 1 ---
for model in boltz2 protenix chai1 intellifold openfold3 rf3; do
    echo ""
    echo "========================================================"
    echo "[MODEL] ${model} — Start: $(date)"
    echo "========================================================"
    bash "${SCRIPTS}/run_benchmark.sh" --model "$model" --gpu "${GPU_SINGLE}"
    echo "[MODEL] ${model} — End: $(date)"
done

# --- Model 7: AF3 (Docker, GPU 1) ---
echo ""
echo "========================================================"
echo "[MODEL] af3 — Start: $(date)"
echo "========================================================"
bash "${SCRIPTS}/run_benchmark.sh" --model af3 --gpu "${GPU_SINGLE}"
echo "[MODEL] af3 — End: $(date)"

# --- Model 8: AlphaFast (all-in-one batch, GPU 0-3) ---
# All 22 cases in a single batch → DB scanned once → fastest timing
echo ""
echo "========================================================"
echo "[MODEL] alphafast (all-in-one) — Start: $(date)"
echo "========================================================"
bash "${SCRIPTS}/run_alphafast_all_in_one.sh"
echo "[MODEL] alphafast (all-in-one) — End: $(date)"

# --- Summary ---
TOTAL_END=$(date +%s)
TOTAL_ELAPSED=$(( TOTAL_END - TOTAL_START ))
TOTAL_HOURS=$(( TOTAL_ELAPSED / 3600 ))
TOTAL_MINS=$(( (TOTAL_ELAPSED % 3600) / 60 ))

echo ""
echo "========================================================"
echo "ALL MODELS COMPLETE"
echo "End: $(date)"
echo "Total elapsed: ${TOTAL_HOURS}h ${TOTAL_MINS}m (${TOTAL_ELAPSED}s)"
echo ""
echo "Timing entries:"
awk -F, 'NR>1{print $1}' "${PROJECT_ROOT}/results/timing.csv" | sort | uniq -c | sort -rn
echo ""
echo "Run: python scripts/collect_results.py"
echo "========================================================"
