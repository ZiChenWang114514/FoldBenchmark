# Installation Guide

How to set up all 7 structure prediction models on a fresh machine.
Reference setup: 4× NVIDIA RTX 4090 (48 GB), Ubuntu 22.04, CUDA 12.x or 13.x.

---

## Overview

| Model | Backend | Disk (weights + DB) | Notes |
|-------|---------|---------------------|-------|
| AlphaFold 3 v3.0.2 | Docker | ~400 GB (sharded) | Local JackHMMER MSA |
| Boltz-2 v2.2.1 | conda | ~8 GB | ColabFold MSA server |
| OpenFold3 v0.4.1 | conda | ~3 GB | ColabFold MSA server |
| Protenix | conda | ~2 GB | Local MSA |
| Chai-1 | conda | ~1.5 GB | ColabFold MSA server |
| IntelliFold-2 | conda | ~2 GB | ColabFold MSA server |
| AlphaFast | Docker | ~800 GB (MMseqs2) | GPU MMseqs2 MSA |

Total: ~1.2 TB (most goes to AF3 sharded DBs and AlphaFast MMseqs2 DB).

---

## Reference paths on Zeus

```
/data2/zcwang/af3/                       # AF3 v3.0.2 install
├── alphafold3/                          # source (with patched msa.py)
├── databases_sharded/                   # 397 GB sharded DBs
├── models/                              # AF3 weights
└── alphafast/                           # AlphaFast install
/hdd01/zcwang/alphafast_db/              # AlphaFast MMseqs2 DB
/data2/zcwang/structure_prediction/      # 5 alternatives
├── boltz2/, openfold3/, protenix/, chai1/, intellifold2/
└── install_all.sh                       # one-shot installer
/data/zcwang/anaconda3/envs/             # conda envs
└── boltz2/, openfold3/, protenix/, chai1/, intellifold/, af3/
```

---

## 1. AlphaFold 3 v3.0.2 (Docker)

### Build the image

```bash
cd /data2/zcwang/af3
git clone https://github.com/google-deepmind/alphafold3.git
cd alphafold3
git checkout v3.0.2
docker build -t alphafold3 -f docker/Dockerfile .
```

In China, you must configure a Docker registry mirror (Docker Hub is blocked):

```bash
# /etc/docker/daemon.json
{ "registry-mirrors": ["https://docker.1ms.run"] }
sudo systemctl restart docker
```

### Patch the v3.0.2 RNA bug

Edit `src/alphafold3/data/msa.py` around line 312 — the `Nhmmer` constructor is missing `z_value`:

```python
case msa_config.NhmmerConfig():
    return nhmmer.Nhmmer(
        ...
        e_value=msa_tool_config.e_value,
        z_value=msa_tool_config.z_value,   # <-- ADD THIS LINE
        max_sequences=msa_tool_config.max_sequences,
        alphabet=msa_tool_config.alphabet,
    )
```

The patched file is volume-mounted into the container at runtime, so no need to rebuild.

### Get weights

Request weights at https://github.com/google-deepmind/alphafold3 (CC BY-NC-SA 4.0).
Place in `/data2/zcwang/af3/models/`.

### Shard the databases (≈6× MSA speedup)

```bash
bash /data2/zcwang/af3/shard_databases.sh
```

This shards 7 protein/RNA databases into chunks under `databases_sharded/`. The script
does NOT modify source databases (it only writes to `databases_sharded/`).

### Verify

```bash
docker run --rm --gpus all alphafold3 python3 -c "import alphafold3; print(alphafold3.__version__)"
# expected: 3.0.2
```

---

## 2-6. Open-source alternatives (one-shot installer)

```bash
cd /data2/zcwang/structure_prediction
nohup bash install_all.sh > install.log 2>&1 &
tail -f install.log
```

This script creates 5 conda envs (`boltz2`, `openfold3`, `protenix`, `chai1`, `intellifold`)
and downloads weights as needed.

If you want to install one model at a time, here are the key per-model steps:

### Boltz-2 v2.2.1

```bash
conda create -n boltz2 python=3.11 -y
conda activate boltz2
pip install "boltz[cuda]" -U
```

**Critical**: Boltz-2 ships PyTorch built for CUDA 13.0 but the installer only ships
CUDA 12.9 nvrtc. Set this every time you activate (or add to env activation):

```bash
export LD_LIBRARY_PATH="/data/zcwang/anaconda3/envs/boltz2/lib/python3.11/site-packages/nvidia/cu13/lib:$LD_LIBRARY_PATH"
```

Without this, `torch.det()` crashes inside the model.

Weights auto-download on first run (~7.6 GB) to `~/.boltz/`.

### OpenFold3 v0.4.1

```bash
conda create -n openfold3 python=3.11 -y
conda activate openfold3
pip install openfold3
# Initialize cache (interactive — feed answers via printf)
export OPENFOLD_CACHE=/data2/zcwang/structure_prediction/openfold3/cache
printf "${OPENFOLD_CACHE}\n${OPENFOLD_CACHE}\n1\nno\n" | setup_openfold
```

Checkpoint `of3-p2-155k.pt` (2.2 GB) downloads to `$OPENFOLD_CACHE/`.

### Protenix

```bash
conda create -n protenix python=3.10 -y
conda activate protenix
pip install protenix
```

Weights download on first run, but the download is **fragile**: the file should be
1.4 GB. If you get a 476 MB file, it is corrupt. Manual download:

```bash
wget -O /home/zcwang/checkpoint/protenix_base_default_v1.0.0.pt \
    "https://protenix.tos-cn-beijing.volces.com/checkpoint/protenix_base_default_v1.0.0.pt"
```

### Chai-1

```bash
conda create -n chai1 python=3.11 -y
conda activate chai1
pip install chai_lab
```

Weights (~1.2 GB ESM-2) auto-download on first run.

### IntelliFold-2

```bash
conda create -n intellifold python=3.10 -y
conda activate intellifold
pip install intellifold
```

Weights (~2 GB) auto-download on first run.

---

## 7. AlphaFast (optional — heavy)

AlphaFast is a derivative of AlphaFold 3 from Romero Lab, Duke University, that swaps
JackHMMER for **MMseqs2 GPU search** (~10× MSA speedup). It needs an ~800 GB MMseqs2
database that we host on `/hdd01`.

### Source

```bash
cd /data2/zcwang/af3
git clone https://github.com/RomeroLab/alphafast.git
cd alphafast
uv sync
```

### Download the MMseqs2 padded database

```bash
export https_proxy="http://127.0.0.1:7890"   # or a proxy you have
export HF_HUB_DOWNLOAD_TIMEOUT=600
export HF_HUB_ENABLE_HF_TRANSFER=1
bash scripts/setup_databases.sh /hdd01/zcwang/alphafast_db --from-prebuilt --protein-only
```

This downloads from HuggingFace (`RomeroLab-Duke/af3-mmseqs-db`) and converts to padded
MMseqs2 format. ~250 GB download + ~540 GB conversion. Plan for 6+ hours on a fast network.

### Run

```bash
bash scripts/run_alphafast.sh \
    --input_dir /path/to/input_jsons \
    --output_dir /path/to/output \
    --db_dir /hdd01/zcwang/alphafast_db \
    --weights_dir /data2/zcwang/af3/models \
    --gpu_devices 0
```

Note: as of 2026-04-30, the AlphaFast DB on Zeus is still downloading. See
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#alphafast-download-stalls) for resume tips.

---

## Verification

After install, run a quick sanity check on each model:

```bash
cd /data2/zcwang/FoldBenchmark
# Smallest test case (46-residue crambin)
bash scripts/run_benchmark.sh --model boltz2     --scenario monomer --gpu 0
bash scripts/run_benchmark.sh --model protenix   --scenario monomer --gpu 0
bash scripts/run_benchmark.sh --model chai1      --scenario monomer --gpu 0
bash scripts/run_benchmark.sh --model intellifold --scenario monomer --gpu 0
bash scripts/run_benchmark.sh --model openfold3  --scenario monomer --gpu 0
bash scripts/run_benchmark.sh --model af3        --scenario monomer --gpu 0
```

Each should complete in under 5 minutes for a small monomer. If any fail, see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## Sharing this install with another user

If you are user `A` and want user `B` to be able to use your envs and weights:

```bash
# 1. Project directories
chmod -R o+rX /data2/zcwang/af3 \
              /data2/zcwang/structure_prediction \
              /data2/zcwang/FoldBenchmark

# 2. Conda envs (only the envs/ subdir, not your home)
chmod o+x /data/zcwang /data/zcwang/anaconda3 /data/zcwang/anaconda3/envs
chmod -R o+rX /data/zcwang/anaconda3/envs/{boltz2,openfold3,protenix,chai1,intellifold,af3}
```

User B then runs:

```bash
source /data/zcwang/anaconda3/etc/profile.d/conda.sh
conda activate /data/zcwang/anaconda3/envs/boltz2
# (then use Boltz-2 normally — see MODELS.md)
```

For Docker (AF3, AlphaFast) the image is system-wide; user B just needs to be in the
`docker` group.
