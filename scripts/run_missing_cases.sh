#!/usr/bin/env bash
# ============================================================
# run_missing_cases.sh — 补跑缺失 case，完成公平 81-case benchmark
#
# 缺失原因（2026-05-28 统计）：
#   1. ESM3 只跑了 1 个原有 case（1UBQ_ubiquitin），还差 34 个
#   2. 9 个新场景（46 cases）无任何模型曾跑过
#   3. AlphaFast 需要重跑 all-in-one（81 cases 统一摊销计时）
#
# 新场景（46 cases）：
#   coiled_coil(6), glycoprotein(4), gpcr(5), hetero_multimer(5),
#   idp(4), membrane_complex(6), protein_peptide(5),
#   rna_structure(5), ternary_complex(6)
#
# 安全性：
#   - 非 AlphaFast 模型通过 run_single_model.sh 的 CIF 检测跳过已完成 case
#   - AlphaFast 重跑 all-in-one（旧 timing 条目被替换，结果文件覆盖）
#
# 用法：
#   bash scripts/run_missing_cases.sh [GPU_ID]
#   GPU_ID 默认 0；AF3 Docker 也使用此 GPU
#
# 预估时间（4× RTX 4090）：
#   Phase 1: ESM3  × 34 cases         ≈  10 min
#   Phase 2: 9 models × 46 new cases  ≈  6-8 h (AF3 最慢 ~300 s/case)
#   Phase 3: AlphaFast 81-case batch  ≈  90-120 min（4 GPU 并行）
# ============================================================
set -u  # 不用 -e / pipefail — 单个 case 失败不中断整个 benchmark

GPU=${1:-0}
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="${PROJECT_ROOT}/scripts"
TIMING_FILE="${PROJECT_ROOT}/results/timing.csv"

cd "$PROJECT_ROOT"
source "${FOLDBENCH_CONFIG:-${SCRIPTS}/config.sh}"

TS=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${PROJECT_ROOT}/results/run_missing_${TS}"
FAILED_LOG="${LOG_DIR}/FAILED.txt"
mkdir -p "$LOG_DIR" "${PROJECT_ROOT}/results"
: > "$FAILED_LOG"
FAIL_COUNT=0

# 确保 timing.csv 存在
[ -f "$TIMING_FILE" ] || echo "model,scenario,case_name,elapsed_seconds" > "$TIMING_FILE"

echo "========================================================"
echo "FoldBenchmark — run_missing_cases.sh"
echo "Start  : $(date)"
echo "GPU    : $GPU"
echo "Log dir: $LOG_DIR"
echo "========================================================"

# ----------------------------------------------------------------
# 辅助：运行单个 case，带日志
# ----------------------------------------------------------------
run_one() {
    local model=$1 scenario=$2 case_name=$3
    echo "[$(date +%H:%M:%S)] $model / $scenario / $case_name"
    bash "${SCRIPTS}/run_single_model.sh" "$model" "$scenario" "$case_name" "$GPU" \
        2>&1 | tee -a "${LOG_DIR}/${model}.log" \
        || true
    local rc=${PIPESTATUS[0]:-0}
    if [ "$rc" -ne 0 ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "${model},${scenario},${case_name},exit=${rc}" >> "$FAILED_LOG"
        echo "  [FAIL] ${model}/${scenario}/${case_name} (exit=${rc})"
    fi
    return 0
}

# ================================================================
# Phase 1: ESM3 — 34 original-scenario cases
# ================================================================
echo ""
echo "========================================================"
echo "Phase 1: ESM3 × 34 original-scenario cases (GPU $GPU)"
echo "========================================================"

# 原有 35 个 case 对应的 (scenario, case_name) 对，ESM3 中已跑 1UBQ_ubiquitin
ORIGINAL_CASES=(
    "antibody_antigen 1AHW_ab_tissue_factor"
    "antibody_antigen 1DVF_idiotope"
    "antibody_antigen 1MLC_ab_lysozyme"
    "antibody_antigen 4FQI_trastuzumab_HER2"
    "antibody_antigen 7N4I_RBD_neutralizing_ab"
    "covalent_mod     4G5J_EGFR_afatinib"
    "covalent_mod     5P9J_BTK_ibrutinib"
    "covalent_mod     6OIM_KRAS_G12C_sotorasib"
    "homo_multimer    14GS_GST_homodimer"
    "homo_multimer    1HTI_TIM_homodimer"
    "homo_multimer    1SAK_p53_TET_tetramer"
    "metal_ion        1CA2_carbonic_anhydrase_ZN"
    "metal_ion        2SOD_superoxide_dismutase_CU_ZN"
    "metal_ion        8TLN_thermolysin_ZN_CA"
    "monomer          1CRN_crambin"
    "monomer          1L2Y_trpcage"
    "monomer          1MBN_myoglobin"
    "monomer          2GB1_protein_G"
    "protein_dna      1BL0_MarA_DNA"
    "protein_dna      1J1V_DnaA_DNA"
    "protein_dna      1LMB_lambda_repressor_DNA"
    "protein_dna      3HDD_homeodomain_DNA"
    "protein_ligand   1HSG_HIV_protease_indinavir"
    "protein_ligand   3HTB_CDK2_inhibitor"
    "protein_ligand   4LDE_BRAF_vemurafenib"
    "protein_ligand   6LU7_Mpro_N3"
    "protein_ligand   7RN1_3CL_inhibitor"
    "protein_protein  1BRS_barnase_barstar"
    "protein_protein  1EMV_trypsin_inhibitor"
    "protein_protein  2PV7_homodimer"
    "protein_protein  3HFM_lysozyme_fab"
    "protein_rna      1ASY_tRNA_synthetase"
    "protein_rna      1URN_U1A_RNA"
    "protein_rna      2AZ0_U1A_RNA_hairpin"
)

P1_DONE=0; P1_SKIP=0
for entry in "${ORIGINAL_CASES[@]}"; do
    sc=$(echo "$entry" | awk '{print $1}')
    ca=$(echo "$entry" | awk '{print $2}')
    run_one esm3 "$sc" "$ca"
    # 统计（skip vs run 由 run_single_model.sh 内部处理）
done

echo ""
echo "[Phase 1 DONE] $(date)"

# ================================================================
# Phase 2: 9 non-AlphaFast models × 46 new-scenario cases
# ================================================================
echo ""
echo "========================================================"
echo "Phase 2: 9 models × 46 new-scenario cases (GPU $GPU)"
echo "  Models: af3 boltz2 openfold3 protenix chai1 intellifold rf3 esmfold2 esm3"
echo "  Note  : rna_structure (RNA-only) → ESM3/ESMFold2 auto-SKIP"
echo "========================================================"

NEW_SCENARIOS=(
    "coiled_coil"
    "glycoprotein"
    "gpcr"
    "hetero_multimer"
    "idp"
    "membrane_complex"
    "protein_peptide"
    "rna_structure"
    "ternary_complex"
)

# 9 non-AlphaFast models（AlphaFast 在 Phase 3 统一处理）
NON_AF_MODELS=(af3 boltz2 openfold3 protenix chai1 intellifold rf3 esmfold2 esm3)

for model in "${NON_AF_MODELS[@]}"; do
    echo ""
    echo "-------- $model --------"
    for sc in "${NEW_SCENARIOS[@]}"; do
        INPUT_DIR="${PROJECT_ROOT}/inputs/${sc}/af3_json"
        [ -d "$INPUT_DIR" ] || continue
        for json in "${INPUT_DIR}"/*.json; do
            [ -f "$json" ] || continue
            ca=$(basename "$json" .json)
            run_one "$model" "$sc" "$ca"
        done
    done
    echo "  $model new-scenario cases done: $(date)"
done

echo ""
echo "[Phase 2 DONE] $(date)"

# ================================================================
# Phase 3: AlphaFast — all-in-one batch for ALL 81 cases
# (DB 只扫一遍；覆盖旧 alphafast timing 条目，获得公平摊销计时)
# ================================================================
echo ""
echo "========================================================"
echo "Phase 3: AlphaFast all-in-one batch (ALL 81 cases, 4 GPUs)"
echo "  Overwrites existing alphafast outputs & timing entries"
echo "========================================================"

if ! bash "${SCRIPTS}/run_alphafast_all_in_one.sh" 2>&1 | tee "${LOG_DIR}/alphafast.log"; then
    echo "alphafast,ALL,all-in-one,exit=1" >> "$FAILED_LOG"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  [FAIL] AlphaFast all-in-one batch failed"
fi

echo ""
echo "[Phase 3 DONE] $(date)"

# ================================================================
# Collect results
# ================================================================
echo ""
echo "========================================================"
echo "Collecting results..."
echo "========================================================"
python3 "${SCRIPTS}/collect_results.py" 2>&1 | tee "${LOG_DIR}/collect.log"

echo ""
echo "========================================================"
echo "ALL MISSING CASES COMPLETE"
echo "End    : $(date)"
echo "Logs   : $LOG_DIR/"
echo "Results: results/summary.md"
echo "========================================================"

# ── 失败汇总 ──
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "========================================================"
    echo "  WARNING: ${FAIL_COUNT} case(s) FAILED"
    echo "  Failed log: ${FAILED_LOG}"
    echo "========================================================"
    while IFS= read -r line; do echo "  $line"; done < "$FAILED_LOG"
    echo ""
    echo "To retry failed cases:"
    echo "  while IFS=, read -r model sc ca _; do"
    echo "    bash scripts/run_single_model.sh \"\$model\" \"\$sc\" \"\$ca\" $GPU"
    echo "  done < ${FAILED_LOG}"
else
    echo ""
    echo "ALL CASES PASSED — no failures."
    rm -f "$FAILED_LOG"
fi
