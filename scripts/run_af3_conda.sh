#!/bin/bash
# ============================================================
# FoldBenchmark: AF3 via conda + sharded databases (no Docker)
#
# Usage:
#   bash run_af3_conda.sh [--gpu GPU_ID]
#
# Runs all 22 FoldBenchmark cases through AF3 using the conda
# env `af3` + sharded databases at /data2/zcwang/af3/databases_sharded/
# Appends timing to results/timing.csv
# ============================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIMING="${PROJECT_ROOT}/results/timing.csv"

# AF3 paths
CONDA_BASE="/data/zcwang/anaconda3"
AF3_PY="${CONDA_BASE}/envs/af3/bin/python"
AF3_RUN="/data2/zcwang/af3/alphafold3/run_alphafold.py"
AF3_MODELS="/data2/zcwang/af3/models"
SHARD_DB="/data2/zcwang/af3/databases_sharded"
JAX_CACHE="/data2/zcwang/af3/jax_cache"
BIN="${CONDA_BASE}/envs/af3/bin"

GPU_ID=1
while [[ $# -gt 0 ]]; do
    case $1 in
        --gpu) GPU_ID="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# Ensure timing.csv header exists
if [ ! -f "$TIMING" ]; then
    echo "model,scenario,case_name,elapsed_seconds" > "$TIMING"
fi

source "${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate af3

SCENARIOS="protein_protein protein_ligand protein_rna monomer antibody_antigen"
TOTAL=0
DONE=0
FAILED=0

# Count total cases
for scenario in $SCENARIOS; do
    INPUT_DIR="${PROJECT_ROOT}/inputs/${scenario}/af3_json"
    [ -d "$INPUT_DIR" ] || continue
    for f in "${INPUT_DIR}"/*.json; do
        [ -f "$f" ] && TOTAL=$((TOTAL + 1))
    done
done

echo "============================================"
echo "FoldBenchmark - AF3 (conda + sharded)"
echo "GPU: $GPU_ID | Total cases: $TOTAL"
echo "Start: $(date)"
echo "============================================"

IDX=0
for scenario in $SCENARIOS; do
    INPUT_DIR="${PROJECT_ROOT}/inputs/${scenario}/af3_json"
    [ -d "$INPUT_DIR" ] || continue

    for json_file in "${INPUT_DIR}"/*.json; do
        [ -f "$json_file" ] || continue
        CASE_NAME=$(basename "$json_file" .json)
        OUT_DIR="${PROJECT_ROOT}/outputs/af3/${scenario}/${CASE_NAME}"
        LOG="${PROJECT_ROOT}/outputs/af3/${scenario}/${CASE_NAME}.log"
        mkdir -p "$OUT_DIR" "$(dirname "$LOG")"

        echo ""
        echo "[${IDX}/${TOTAL}] af3 / ${scenario} / ${CASE_NAME}"
        START_TIME=$(date +%s)

        CUDA_VISIBLE_DEVICES=${GPU_ID} "${AF3_PY}" "${AF3_RUN}" \
            --json_path="${json_file}" \
            --model_dir="${AF3_MODELS}" \
            --db_dir="${SHARD_DB}" \
            --output_dir="${OUT_DIR}" \
            --jackhmmer_binary_path="${BIN}/jackhmmer" \
            --nhmmer_binary_path="${BIN}/nhmmer" \
            --hmmalign_binary_path="${BIN}/hmmalign" \
            --hmmsearch_binary_path="${BIN}/hmmsearch" \
            --hmmbuild_binary_path="${BIN}/hmmbuild" \
            --small_bfd_database_path="${SHARD_DB}/bfd-first_non_consensus_sequences.fasta@64" \
            --small_bfd_z_value=65984053 \
            --mgnify_database_path="${SHARD_DB}/mgy_clusters_2022_05.fa@512" \
            --mgnify_z_value=623796864 \
            --uniprot_cluster_annot_database_path="${SHARD_DB}/uniprot_all_2021_04.fa@256" \
            --uniprot_cluster_annot_z_value=225619586 \
            --uniref90_database_path="${SHARD_DB}/uniref90_2022_05.fa@128" \
            --uniref90_z_value=153742194 \
            --ntrna_database_path="${SHARD_DB}/nt_rna_2023_02_23_clust_seq_id_90_cov_80_rep_seq.fasta@256" \
            --ntrna_z_value=76752.808514 \
            --rfam_database_path="${SHARD_DB}/rfam_14_9_clust_seq_id_90_cov_80_rep_seq.fasta@16" \
            --rfam_z_value=138.115553 \
            --rna_central_database_path="${SHARD_DB}/rnacentral_active_seq_id_90_cov_80_linclust.fasta@64" \
            --rna_central_z_value=13271.415730 \
            --jackhmmer_n_cpu=1 \
            --jackhmmer_max_parallel_shards=16 \
            --nhmmer_n_cpu=1 \
            --nhmmer_max_parallel_shards=16 \
            --jax_compilation_cache_dir="${JAX_CACHE}" \
            > "$LOG" 2>&1 && STATUS=OK || STATUS=FAILED

        END_TIME=$(date +%s)
        ELAPSED=$((END_TIME - START_TIME))
        echo "af3,${scenario},${CASE_NAME},${ELAPSED}" >> "$TIMING"

        IDX=$((IDX + 1))
        if [ "$STATUS" = "OK" ]; then
            DONE=$((DONE + 1))
            echo "  OK (${ELAPSED}s)"
        else
            FAILED=$((FAILED + 1))
            echo "  FAILED (${ELAPSED}s) — see $LOG"
        fi
    done
done

echo ""
echo "============================================"
echo "AF3 BENCHMARK COMPLETE: $(date)"
echo "Total: $TOTAL | Done: $DONE | Failed: $FAILED"
echo "============================================"
