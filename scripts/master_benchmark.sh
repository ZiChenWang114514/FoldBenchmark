#!/usr/bin/env bash
# master_benchmark.sh — 全量重跑 35 cases × 10 models，公平 benchmark
# Usage: bash scripts/master_benchmark.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export HTTPS_PROXY=http://127.0.0.1:7892
export HTTP_PROXY=http://127.0.0.1:7892

# ---- 1. 清空旧结果 ----
echo "[$(date)] Clearing old outputs and timing..."
rm -rf outputs/
mkdir -p outputs results
echo "model,scenario,case_name,elapsed_seconds" > results/timing.csv

TS=$(date +%Y%m%d_%H%M%S)
LOG_DIR="results/run_${TS}"
mkdir -p "$LOG_DIR"
echo "[$(date)] Logs → $LOG_DIR"

# ---- 2. AlphaFast: all-in-one batch（全 35 cases，4 GPUs）----
echo ""
echo "[$(date)] ===== 1/10 AlphaFast (all-in-one batch, 4 GPUs) ====="
bash scripts/run_alphafast_all_in_one.sh 2>&1 | tee "$LOG_DIR/alphafast.log"

# ---- 3-10. 其余 9 个模型，串行 GPU 0 ----
for model in rf3 boltz2 intellifold protenix chai1 openfold3 af3 esmfold2 esm3; do
    echo ""
    echo "[$(date)] ===== Running $model (GPU 0) ====="
    bash scripts/run_benchmark.sh --model "$model" --gpu 0 2>&1 | tee "$LOG_DIR/${model}.log"
done

# ---- 10. 汇总结果 ----
echo ""
echo "[$(date)] ===== Collecting results ====="
python scripts/collect_results.py

echo ""
echo "[$(date)] ============================================"
echo "[$(date)] BENCHMARK COMPLETE"
echo "[$(date)] Logs:    $LOG_DIR/"
echo "[$(date)] Results: results/summary.md"
echo "[$(date)] ============================================"
