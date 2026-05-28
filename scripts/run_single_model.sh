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

# Load path configuration (supports FOLDBENCH_CONFIG override)
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${FOLDBENCH_CONFIG:-${SCRIPTS_DIR}/config.sh}"

mkdir -p "${OUTPUTS}" "$(dirname ${TIMING_FILE})"

# Check if already done
# Use recursive find for models that nest outputs (e.g. OpenFold3)
if [ -d "${OUTPUTS}/${CASE_NAME}" ] && [ "$(find "${OUTPUTS}/${CASE_NAME}" -name "*.cif" 2>/dev/null | wc -l)" -gt 0 ]; then
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
            --volume "${AF3_MODELS_DIR}":/root/models \
            --volume "${AF3_DB_DIR}":/root/public_databases \
            --volume "${AF3_MMCIF_DIR}":/root/public_databases/mmcif_files:ro \
            --volume "${AF3_SEQRES_FASTA}":/root/public_databases/pdb_seqres_2022_09_28.fasta:ro \
            --volume "${AF3_SRC_MSA_PY}":/app/alphafold/src/alphafold3/data/msa.py:ro \
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
                --jackhmmer_n_cpu=4 \
                --jackhmmer_max_parallel_shards=16 \
                --nhmmer_n_cpu=4 \
                --nhmmer_max_parallel_shards=16 \
            2>&1 || echo "FAILED: af3/${SCENARIO}/${CASE_NAME}"
        ;;
    boltz2)
        INPUT_YAML="${INPUTS}/boltz2_yaml/${CASE_NAME}.yaml"
        [ ! -f "$INPUT_YAML" ] && echo "SKIP: no input" && exit 0
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        conda activate boltz2
        export LD_LIBRARY_PATH="${BOLTZ2_CU13_LIB}:${LD_LIBRARY_PATH}"
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
        # OPENFOLD_CACHE and CUTLASS_PATH come from config.sh
        # OpenFold3 uses DeepSpeed4Science's EvoformerAttention, which JIT-compiles a
        # CUDA C++ kernel via nvcc. Three things must be present:
        #   (1) CUDA_HOME = a toolkit with nvcc (conda env ships only runtime libs)
        #   (2) CUTLASS_PATH = NVIDIA CUTLASS template library at version >= 3.1.0
        #       (DeepSpeed checks this and refuses to build without it; the only
        #       error surfaced is "Unable to JIT load... due to hardware/software
        #       issue. None" — misleading, the actual cause is is_compatible()=False
        #       with verbose=False so the CUTLASS_PATH warning never prints)
        #   (3) TORCH_CUDA_ARCH_LIST = the GPU's compute capability so nvcc generates
        #       matching SASS (RTX 4090 = SM 8.9; the kernel only ships the standard
        #       70/80/86/90 list which doesn't include 8.9)
        export CUDA_HOME=/usr/local/cuda
        export PATH=/usr/local/cuda/bin:$PATH
        export CUTLASS_PATH="${CUTLASS_PATH}"
        export TORCH_CUDA_ARCH_LIST="8.9"
        mkdir -p "${OUTPUTS}/${CASE_NAME}"
        # Per-case MSA tmp dir. After the conda-env patches to colabfold_msa_server.py
        # (PID-suffixed default) and run_openfold.py (try/finally cleanup), this
        # explicit yaml is REDUNDANT for race avoidance — kept as defense-in-depth
        # and to make per-case isolation explicit in the script.
        OF3_MSA_DIR="/tmp/of3-of-${USER}/colabfold_msas_${CASE_NAME}_$$"
        rm -rf "$OF3_MSA_DIR" 2>/dev/null || true
        OF3_RUNNER_YAML="/tmp/of3_runner_${CASE_NAME}_$$.yml"
        printf 'msa_computation_settings:\n  msa_output_directory: "%s"\n' "$OF3_MSA_DIR" > "$OF3_RUNNER_YAML"
        trap 'rm -f "$OF3_RUNNER_YAML"' EXIT
        CUDA_VISIBLE_DEVICES=${GPU_ID} run_openfold predict \
            --query-json "$INPUT_JSON" \
            --output-dir "${OUTPUTS}/${CASE_NAME}" \
            --runner-yaml "$OF3_RUNNER_YAML" \
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

        # All ALPHAFAST_* vars come from config.sh
        ALPHAFAST_PYTHON=$ALPHAFAST_DIR/.venv/bin/python
        ALPHAFAST_RUN=$ALPHAFAST_DIR/run_alphafold.py
        MMSEQS_BIN=$ALPHAFAST_DIR/bin/bin/mmseqs

        # Runtime gotchas (verified during smoke test + 4090 OOM workaround):
        # 1. cpp.so was built with system GCC 13 → needs newer libstdc++
        #    than conda ships → LD_PRELOAD system libstdc++.so.6
        # 2. libcifpp expects components.cif at hardcoded build-tmp paths;
        #    symlinks placed in .venv/share/libcifpp/ resolve this (one-time setup)
        # 3. uniref90_padded (49G) and mgnify_padded (108G) don't fit in a single
        #    4090 (48G). MMSEQS_USE_ALL_GPUS=1 + multi-GPU CUDA_VISIBLE_DEVICES
        #    shards the DB across all 4 cards (192G total). Patch in
        #    .venv/lib/.../alphafold3/data/tools/{mmseqs,mmseqs_batch,
        #    mmseqs_template,foldseek}.py allows MMSEQS_USE_ALL_GPUS=1 to bypass
        #    the single-GPU CUDA_VISIBLE_DEVICES override.
        mkdir -p "$ALPHAFAST_JAX_CACHE"
        # NOTE: per-case mode. For best perf use scripts/run_alphafast_batch.sh
        # which batches all cases in a scenario through a single MMseqs2 queryDB
        # (~70-80% time savings on multi-case scenarios).
        LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libstdc++.so.6 \
        MMSEQS_USE_ALL_GPUS=1 \
        CUDA_VISIBLE_DEVICES="${ALPHAFAST_GPUS}" \
        $ALPHAFAST_PYTHON $ALPHAFAST_RUN \
            --json_path="$INPUT_JSON" \
            --output_dir="${OUTPUTS}/${CASE_NAME}" \
            --model_dir="$ALPHAFAST_MODEL_DIR" \
            --db_dir="$ALPHAFAST_DB_DIR" \
            --mmseqs_binary_path="$MMSEQS_BIN" \
            --mmseqs_db_dir="$ALPHAFAST_DB_DIR/mmseqs" \
            --use_mmseqs_gpu=True \
            --jax_compilation_cache_dir="$ALPHAFAST_JAX_CACHE" \
            --run_data_pipeline=True \
            --run_inference=True \
            2>&1 || echo "FAILED: alphafast/${SCENARIO}/${CASE_NAME}"
        ;;
    rf3)
        # RoseTTAFold3 via Foundry (Baker Lab, BSD license)
        # Uses its own JSON format with 'components' array.
        # MSA (.a3m) is optional but recommended for accuracy.
        INPUT_JSON="${INPUTS}/rf3_json/${CASE_NAME}.json"
        [ ! -f "$INPUT_JSON" ] && echo "SKIP: no input" && exit 0
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        conda activate rf3
        mkdir -p "${OUTPUTS}/${CASE_NAME}"
        CUDA_VISIBLE_DEVICES=${GPU_ID} rf3 fold \
            inputs="$(realpath "$INPUT_JSON")" \
            out_dir="${OUTPUTS}/${CASE_NAME}" \
            ckpt_path="${RF3_CKPT_PATH}" \
            2>&1 || echo "FAILED: rf3/${SCENARIO}/${CASE_NAME}"
        ;;
    esmfold2)
        # ESMFold2 (Chan Zuckerberg Biohub, MIT license, 2026-05-27)
        # No CLI — uses Python API wrapper. Input: AF3 JSON (reused from af3_json/).
        # Output: pred_esmfold2.cif + confidence_esmfold2.json
        # NOTE: LigandInput only supports CCD codes; SMILES-only ligands are skipped.
        INPUT_JSON="${INPUTS}/af3_json/${CASE_NAME}.json"
        [ ! -f "$INPUT_JSON" ] && echo "SKIP: no input" && exit 0
        # ESMFold2 is protein-only; skip RNA-only inputs (rna_structure scenario)
        HAS_PROTEIN=$(python3 -c "import json; d=json.load(open('$INPUT_JSON')); print(any('protein' in s for s in d.get('sequences',[])))" 2>/dev/null)
        if [ "$HAS_PROTEIN" = "False" ]; then
            echo "SKIP: esmfold2 does not support RNA-only input: $CASE_NAME"
            exit 0
        fi
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        conda activate esmfold2
        mkdir -p "${OUTPUTS}/${CASE_NAME}"
        CUDA_VISIBLE_DEVICES=${GPU_ID} \
        HF_HOME="${ESMFOLD2_HF_CACHE}" \
        HUGGINGFACE_HUB_CACHE="${ESMFOLD2_HF_CACHE}" \
        ESMCFOLD_CCD_PATH="${ESMFOLD2_MODEL}/ccd.pkl" \
        HTTPS_PROXY="${HTTPS_PROXY:-http://127.0.0.1:7890}" \
        HTTP_PROXY="${HTTP_PROXY:-http://127.0.0.1:7890}" \
            python "${PROJECT_ROOT}/scripts/run_esmfold2.py" \
                --input  "$(realpath "$INPUT_JSON")" \
                --outdir "${OUTPUTS}/${CASE_NAME}" \
                --model  "${ESMFOLD2_MODEL:-biohub/ESMFold2}" \
                --num-loops "${ESMFOLD2_NUM_LOOPS:-3}" \
            2>&1 || echo "FAILED: esmfold2/${SCENARIO}/${CASE_NAME}"
        ;;
    *)
        echo "Unknown model: $MODEL"
        echo "Available: af3, alphafast, boltz2, openfold3, protenix, chai1, intellifold, rf3, esmfold2"
        exit 1
        ;;
esac

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
echo "${MODEL},${SCENARIO},${CASE_NAME},${ELAPSED}" >> "${TIMING_FILE}"
echo "[DONE] ${MODEL}/${SCENARIO}/${CASE_NAME} in ${ELAPSED}s"
