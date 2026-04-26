#!/bin/bash
# ============================================================
# Run a single model on a single input
# Usage: bash run_single_model.sh <model> <scenario> <case_name> <gpu_id>
# ============================================================
set -e

MODEL=${1:?"Usage: bash run_single_model.sh <model> <scenario> <case_name> [gpu_id]"}
SCENARIO=$2
CASE_NAME=$3
GPU_ID=${4:-0}

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUTS="${PROJECT_ROOT}/inputs/${SCENARIO}"
OUTPUTS="${PROJECT_ROOT}/outputs/${MODEL}/${SCENARIO}"
TIMING_FILE="${PROJECT_ROOT}/results/timing.csv"
CONDA_BASE=$(/data/zcwang/anaconda3/bin/conda info --base)

mkdir -p "${OUTPUTS}" "$(dirname ${TIMING_FILE})"

# Check if already done
if [ -d "${OUTPUTS}/${CASE_NAME}" ] && [ "$(ls ${OUTPUTS}/${CASE_NAME}/*.cif 2>/dev/null | wc -l)" -gt 0 ]; then
    echo "[SKIP] ${MODEL}/${SCENARIO}/${CASE_NAME}: already done"
    exit 0
fi

echo "[RUN] ${MODEL}/${SCENARIO}/${CASE_NAME} on GPU ${GPU_ID}"
START_TIME=$(date +%s)

case "$MODEL" in
    af3)
        INPUT_JSON="${INPUTS}/af3_json/${CASE_NAME}.json"
        [ ! -f "$INPUT_JSON" ] && echo "SKIP: no input" && exit 0
        mkdir -p "${OUTPUTS}/${CASE_NAME}"
        docker run --rm \
            --volume "$(dirname $(realpath $INPUT_JSON))":/root/af_input \
            --volume "${OUTPUTS}/${CASE_NAME}":/root/af_output \
            --volume /data2/zcwang/af3/models:/root/models \
            --volume /data2/zcwang/af3/databases_sharded:/root/public_databases \
            --volume /data2/zcwang/af3/databases/mmcif_files:/root/public_databases/mmcif_files:ro \
            --volume /data2/zcwang/af3/databases/pdb_seqres_2022_09_28.fasta:/root/public_databases/pdb_seqres_2022_09_28.fasta:ro \
            --gpus "device=${GPU_ID}" \
            alphafold3 \
            python3 run_alphafold.py \
                --json_path="/root/af_input/${CASE_NAME}.json" \
                --model_dir=/root/models \
                --db_dir=/root/public_databases \
                --output_dir=/root/af_output \
                --small_bfd_database_path="/root/public_databases/bfd-first_non_consensus_sequences.fasta@64" \
                --small_bfd_z_value=65984053 \
                --mgnify_database_path="/root/public_databases/mgy_clusters_2022_05.fa@512" \
                --mgnify_z_value=623796864 \
                --uniprot_cluster_annot_database_path="/root/public_databases/uniprot_all_2021_04.fa@256" \
                --uniprot_cluster_annot_z_value=225619586 \
                --uniref90_database_path="/root/public_databases/uniref90_2022_05.fa@128" \
                --uniref90_z_value=153742194 \
                --ntrna_database_path="/root/public_databases/nt_rna_2023_02_23_clust_seq_id_90_cov_80_rep_seq.fasta@256" \
                --ntrna_z_value=76752.808514 \
                --rfam_database_path="/root/public_databases/rfam_14_9_clust_seq_id_90_cov_80_rep_seq.fasta@16" \
                --rfam_z_value=138.115553 \
                --rna_central_database_path="/root/public_databases/rnacentral_active_seq_id_90_cov_80_linclust.fasta@64" \
                --rna_central_z_value=13271.415730 \
                --jackhmmer_n_cpu=1 \
                --jackhmmer_max_parallel_shards=16 \
                --nhmmer_n_cpu=1 \
                --nhmmer_max_parallel_shards=16 \
            2>&1 || echo "FAILED: af3/${SCENARIO}/${CASE_NAME}"
        ;;
    boltz2)
        INPUT_YAML="${INPUTS}/boltz2_yaml/${CASE_NAME}.yaml"
        [ ! -f "$INPUT_YAML" ] && echo "SKIP: no input" && exit 0
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        conda activate boltz2
        CUDA_VISIBLE_DEVICES=${GPU_ID} boltz predict "$INPUT_YAML" \
            --out_dir "${OUTPUTS}/${CASE_NAME}" \
            --use_msa_server \
            2>&1 || echo "FAILED: boltz2/${SCENARIO}/${CASE_NAME}"
        ;;
    openfold3)
        INPUT_JSON="${INPUTS}/af3_json/${CASE_NAME}.json"
        [ ! -f "$INPUT_JSON" ] && echo "SKIP: no input" && exit 0
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        conda activate openfold3
        mkdir -p "${OUTPUTS}/${CASE_NAME}"
        CUDA_VISIBLE_DEVICES=${GPU_ID} openfold predict \
            --input "$INPUT_JSON" \
            --output_dir "${OUTPUTS}/${CASE_NAME}" \
            2>&1 || echo "FAILED: openfold3/${SCENARIO}/${CASE_NAME}"
        ;;
    protenix)
        INPUT_JSON="${INPUTS}/af3_json/${CASE_NAME}.json"
        [ ! -f "$INPUT_JSON" ] && echo "SKIP: no input" && exit 0
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        conda activate protenix
        mkdir -p "${OUTPUTS}/${CASE_NAME}"
        CUDA_VISIBLE_DEVICES=${GPU_ID} protenix predict \
            --input "$INPUT_JSON" \
            --output_dir "${OUTPUTS}/${CASE_NAME}" \
            --use_msa_server \
            2>&1 || echo "FAILED: protenix/${SCENARIO}/${CASE_NAME}"
        ;;
    chai1)
        INPUT_FASTA="${INPUTS}/chai1_fasta/${CASE_NAME}.fasta"
        [ ! -f "$INPUT_FASTA" ] && echo "SKIP: no input" && exit 0
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        conda activate chai1
        mkdir -p "${OUTPUTS}/${CASE_NAME}"
        CUDA_VISIBLE_DEVICES=${GPU_ID} chai fold \
            --input "$INPUT_FASTA" \
            --output_dir "${OUTPUTS}/${CASE_NAME}" \
            --use-msa-server \
            2>&1 || echo "FAILED: chai1/${SCENARIO}/${CASE_NAME}"
        ;;
    intellifold)
        INPUT_JSON="${INPUTS}/af3_json/${CASE_NAME}.json"
        [ ! -f "$INPUT_JSON" ] && echo "SKIP: no input" && exit 0
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        conda activate intellifold
        mkdir -p "${OUTPUTS}/${CASE_NAME}"
        CUDA_VISIBLE_DEVICES=${GPU_ID} intellifold predict \
            --input "$INPUT_JSON" \
            --output_dir "${OUTPUTS}/${CASE_NAME}" \
            2>&1 || echo "FAILED: intellifold/${SCENARIO}/${CASE_NAME}"
        ;;
    *)
        echo "Unknown model: $MODEL"
        echo "Available: af3, boltz2, openfold3, protenix, chai1, intellifold"
        exit 1
        ;;
esac

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
echo "${MODEL},${SCENARIO},${CASE_NAME},${ELAPSED}" >> "${TIMING_FILE}"
echo "[DONE] ${MODEL}/${SCENARIO}/${CASE_NAME} in ${ELAPSED}s"
