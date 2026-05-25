#!/usr/bin/env bash
# 重跑 Protenix 5 个异常 case
set -euo pipefail
cd "$(dirname "$0")/.."

GPU=${1:-0}
LOG="results/rerun_protenix_$(date +%Y%m%d_%H%M%S).log"

echo "Rerunning 5 anomalous Protenix cases on GPU $GPU"
echo "Log: $LOG"

{
    bash scripts/run_single_model.sh protenix protein_dna  1LMB_lambda_repressor_DNA "$GPU"
    bash scripts/run_single_model.sh protenix protein_dna  3HDD_homeodomain_DNA      "$GPU"
    bash scripts/run_single_model.sh protenix homo_multimer 1HTI_TIM_homodimer       "$GPU"
    bash scripts/run_single_model.sh protenix metal_ion    2SOD_superoxide_dismutase_CU_ZN "$GPU"
    bash scripts/run_single_model.sh protenix homo_multimer 1SAK_p53_TET_tetramer    "$GPU"
} 2>&1 | tee "$LOG"

echo "Done. Checking timing.csv..."
grep "protenix" results/timing.csv | grep -E "1LMB|3HDD|1HTI|2SOD|1SAK"
