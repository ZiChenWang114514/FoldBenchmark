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
            --volume /data2/zcwang/af3/alphafold3/src/alphafold3/data/msa.py:/app/alphafold/src/alphafold3/data/msa.py:ro \
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
        export LD_LIBRARY_PATH="/data/zcwang/anaconda3/envs/boltz2/lib/python3.11/site-packages/nvidia/cu13/lib:${LD_LIBRARY_PATH}"
        CUDA_VISIBLE_DEVICES=${GPU_ID} boltz predict "$INPUT_YAML" \
            --out_dir "${OUTPUTS}/${CASE_NAME}" \
            --use_msa_server \
            2>&1 || echo "FAILED: boltz2/${SCENARIO}/${CASE_NAME}"
        ;;
    openfold3)
        INPUT_JSON="${INPUTS}/openfold3_json/${CASE_NAME}.json"
        [ ! -f "$INPUT_JSON" ] && INPUT_JSON="${INPUTS}/af3_json/${CASE_NAME}.json"
        [ ! -f "$INPUT_JSON" ] && echo "SKIP: no input" && exit 0
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        conda activate openfold3
        export OPENFOLD_CACHE="/data2/zcwang/structure_prediction/openfold3/cache"
        mkdir -p "${OUTPUTS}/${CASE_NAME}"
        CUDA_VISIBLE_DEVICES=${GPU_ID} run_openfold predict \
            --query-json "$INPUT_JSON" \
            --output-dir "${OUTPUTS}/${CASE_NAME}" \
            --inference-ckpt-path "${OPENFOLD_CACHE}/of3-p2-155k.pt" \
            --use-templates false \
            2>&1 || echo "FAILED: openfold3/${SCENARIO}/${CASE_NAME}"
        ;;
    protenix)
        INPUT_JSON="${INPUTS}/protenix_json/${CASE_NAME}.json"
        [ ! -f "$INPUT_JSON" ] && INPUT_JSON="${INPUTS}/af3_json/${CASE_NAME}.json"
        [ ! -f "$INPUT_JSON" ] && echo "SKIP: no input" && exit 0
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        conda activate protenix
        mkdir -p "${OUTPUTS}/${CASE_NAME}"
        CUDA_VISIBLE_DEVICES=${GPU_ID} protenix pred \
            -i "$INPUT_JSON" \
            -o "${OUTPUTS}/${CASE_NAME}" \
            2>&1 || echo "FAILED: protenix/${SCENARIO}/${CASE_NAME}"
        ;;
    chai1)
        INPUT_FASTA="${INPUTS}/chai1_fasta/${CASE_NAME}.fasta"
        [ ! -f "$INPUT_FASTA" ] && echo "SKIP: no input" && exit 0
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        conda activate chai1
        mkdir -p "${OUTPUTS}/${CASE_NAME}"
        CUDA_VISIBLE_DEVICES=${GPU_ID} chai-lab fold \
            "$INPUT_FASTA" \
            "${OUTPUTS}/${CASE_NAME}" \
            --use-msa-server \
            2>&1 || echo "FAILED: chai1/${SCENARIO}/${CASE_NAME}"
        ;;
    intellifold)
        INPUT_YAML="${INPUTS}/boltz2_yaml/${CASE_NAME}.yaml"
        [ ! -f "$INPUT_YAML" ] && echo "SKIP: no input" && exit 0
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        conda activate intellifold
        mkdir -p "${OUTPUTS}/${CASE_NAME}"
        CUDA_VISIBLE_DEVICES=${GPU_ID} intellifold predict \
            "$INPUT_YAML" \
            --out_dir "${OUTPUTS}/${CASE_NAME}" \
            --use_msa_server \
            2>&1 || echo "FAILED: intellifold/${SCENARIO}/${CASE_NAME}"
        ;;
    alphafast)
        # AlphaFast = AF3 with MMseqs2-GPU MSA (~22x faster end-to-end on H100)
        # Native install (Docker Hub blocked from PRC); reuses AF3 JSON inputs.
        INPUT_JSON="${INPUTS}/af3_json/${CASE_NAME}.json"
        [ ! -f "$INPUT_JSON" ] && echo "SKIP: no input" && exit 0
        mkdir -p "${OUTPUTS}/${CASE_NAME}"

        ALPHAFAST_DIR=/data2/zcwang/af3/alphafast
        ALPHAFAST_PYTHON=$ALPHAFAST_DIR/.venv/bin/python
        ALPHAFAST_RUN=$ALPHAFAST_DIR/run_alphafold.py
        MMSEQS_BIN=$ALPHAFAST_DIR/bin/bin/mmseqs
        # DB on /hdd01 by default; pass ALPHAFAST_DB_DIR=... to override (e.g. NVMe)
        ALPHAFAST_DB_DIR="${ALPHAFAST_DB_DIR:-/hdd01/zcwang/alphafast_db}"
        ALPHAFAST_MODEL_DIR="${ALPHAFAST_MODEL_DIR:-/data/zxhuang/Shared/Alphafold3params}"

        # Runtime gotchas (verified during smoke test):
        # 1. cpp.so was built with system GCC 13 → needs newer libstdc++
        #    than conda ships → LD_PRELOAD system libstdc++.so.6
        # 2. libcifpp expects components.cif at hardcoded build-tmp paths;
        #    symlinks placed in .venv/share/libcifpp/ resolve this (one-time setup)
        LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libstdc++.so.6 \
        CUDA_VISIBLE_DEVICES=${GPU_ID} \
        $ALPHAFAST_PYTHON $ALPHAFAST_RUN \
            --json_path="$INPUT_JSON" \
            --output_dir="${OUTPUTS}/${CASE_NAME}" \
            --model_dir="$ALPHAFAST_MODEL_DIR" \
            --db_dir="$ALPHAFAST_DB_DIR" \
            --mmseqs_binary_path="$MMSEQS_BIN" \
            --mmseqs_db_dir="$ALPHAFAST_DB_DIR/mmseqs" \
            --use_mmseqs_gpu=True \
            --run_data_pipeline=True \
            --run_inference=True \
            2>&1 || echo "FAILED: alphafast/${SCENARIO}/${CASE_NAME}"
        ;;
    *)
        echo "Unknown model: $MODEL"
        echo "Available: af3, alphafast, boltz2, openfold3, protenix, chai1, intellifold"
        exit 1
        ;;
esac

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
echo "${MODEL},${SCENARIO},${CASE_NAME},${ELAPSED}" >> "${TIMING_FILE}"
echo "[DONE] ${MODEL}/${SCENARIO}/${CASE_NAME} in ${ELAPSED}s"
