#!/bin/bash
# ============================================================
# FoldBenchmark — user path configuration
#
# All variables support three override methods (highest → lowest):
#   1. Export in your shell before running any script
#   2. Point FOLDBENCH_CONFIG=/path/to/your/config.sh
#   3. Edit this file directly
#
# Quick-start for a new user on the same Zeus machine:
#   1. Copy this file:   cp scripts/config.sh scripts/config.local.sh
#   2. Edit the paths in config.local.sh to match your install
#   3. Export:           export FOLDBENCH_CONFIG=$PWD/scripts/config.local.sh
#   scripts/config.local.sh is gitignored.
# ============================================================

# ── Conda ────────────────────────────────────────────────────────────
# Auto-detected via `conda info --base` if conda is in PATH.
# Override if your conda lives outside PATH:
#   export CONDA_BASE=/path/to/your/anaconda3
: "${CONDA_BASE:=$(conda info --base 2>/dev/null)}"

# ── Boltz-2 ──────────────────────────────────────────────────────────
# nvidia/cu13 runtime libs inside the boltz2 conda env.
# Must match the Python version in that env (currently 3.11).
: "${BOLTZ2_CU13_LIB:=${CONDA_BASE}/envs/boltz2/lib/python3.11/site-packages/nvidia/cu13/lib}"

# ── OpenFold3 ─────────────────────────────────────────────────────────
# Cache dir containing of3-p2-155k.pt (2.2 GB, auto-downloaded on first run).
: "${OPENFOLD_CACHE:=/data2/zcwang/structure_prediction/openfold3/cache}"
# CUTLASS 3.5+ checkout required for DeepSpeed evoformer_attn JIT on RTX 4090.
: "${CUTLASS_PATH:=/data2/zcwang/structure_prediction/openfold3/cutlass}"

# ── AlphaFold 3 (Docker) ─────────────────────────────────────────────
# Model weights directory (contains af3.bin.zst).
: "${AF3_MODELS_DIR:=/data2/zcwang/af3/models}"
# Sharded databases root (~397 GB NVMe).
: "${AF3_DB_DIR:=/data2/zcwang/af3/databases_sharded}"
# mmCIF files (symlinked or real; mounted read-only).
: "${AF3_MMCIF_DIR:=/data2/zcwang/af3/databases/mmcif_files}"
# pdb_seqres FASTA for template search.
: "${AF3_SEQRES_FASTA:=/data2/zcwang/af3/databases/pdb_seqres_2022_09_28.fasta}"
# Patched msa.py with z_value fix (volume-mounted into the container).
: "${AF3_SRC_MSA_PY:=/data2/zcwang/af3/alphafold3/src/alphafold3/data/msa.py}"

# ── AlphaFast ─────────────────────────────────────────────────────────
# Native uv-venv install of AlphaFast.
: "${ALPHAFAST_DIR:=/data2/zcwang/af3/alphafast}"
# MMseqs2 padded DB root (~388 GB protein + ~27 GB RNA).
: "${ALPHAFAST_DB_DIR:=/data2/zcwang/alphafast_db}"
# AF3 model weights (shared with AF3 Docker — same files).
: "${ALPHAFAST_MODEL_DIR:=/data/zxhuang/Shared/Alphafold3params}"
# JAX compilation cache (persists across runs; saves ~30 s per cold start).
: "${ALPHAFAST_JAX_CACHE:=${ALPHAFAST_DIR}/jax_cache}"
# GPUs available for MMseqs2 DB sharding (all 4 required on 4× RTX 4090).
: "${ALPHAFAST_GPUS:=0,1,2,3}"
