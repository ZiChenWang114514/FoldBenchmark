# Troubleshooting Guide

Known issues encountered during benchmark, their root causes, and verified fixes.

---

## AF3

### AF3 RNA scenarios all fail (`Nhmmer.__init__() missing argument: z_value`)

**Cause**: Bug in AF3 v3.0.2 source code. In `src/alphafold3/data/msa.py` around
line 312, the `Nhmmer` constructor call omits `z_value`. JackHMMER (used for protein
MSAs) does pass `z_value`, but the parallel Nhmmer path (used for RNA MSAs) does not.

**Fix**: Patch the local file and volume-mount it into the container. Edit
`/data2/zcwang/af3/alphafold3/src/alphafold3/data/msa.py`:

```python
case msa_config.NhmmerConfig():
    return nhmmer.Nhmmer(
        ...
        e_value=msa_tool_config.e_value,
        z_value=msa_tool_config.z_value,   # <-- ADD THIS
        max_sequences=msa_tool_config.max_sequences,
        alphabet=msa_tool_config.alphabet,
    )
```

Then in your `docker run`:

```bash
--volume /data2/zcwang/af3/alphafold3/src/alphafold3/data/msa.py:/app/alphafold/src/alphafold3/data/msa.py:ro
```

This is already wired into `scripts/run_single_model.sh`.

### AF3 Docker build hits Docker Hub rate limit / SSL errors

**Cause**: Docker Hub is blocked / rate-limited in mainland China.

**Fix**: Configure a registry mirror in `/etc/docker/daemon.json`:

```json
{
  "registry-mirrors": ["https://docker.1ms.run"]
}
```

Then `sudo systemctl restart docker` and retry the build.

For Python wheels during build, also set the Tsinghua PyPI mirror inside the
Dockerfile or via a `pip.conf` mount.

### AF3 inference is slow (5+ minutes per case)

**Cause**: Vanilla AF3 runs JackHMMER serially on each database.

**Fix**: Use sharded databases. We pre-shard 7 databases under
`/data2/zcwang/af3/databases_sharded/`. The sharding script is
`/data2/zcwang/af3/shard_databases.sh`. With 16-way sharding, MSA drops from
~5 minutes to ~50 seconds.

Critical: when using sharded DBs, you must pass each DB's **original Z value**
(`--small_bfd_z_value=65984053` etc.) — see `scripts/run_single_model.sh` for the
full list.

---

## Boltz-2

### Boltz-2 crashes inside `torch.det()`: `cannot find libnvrtc-builtins.so.13.0`

**Cause**: PyTorch in the `boltz2` env is built for CUDA 13.0, but the default
nvidia-cuda-nvrtc package only ships CUDA 12.9. The required runtime library is
shipped in a separate `nvidia/cu13/lib/` directory but not on the linker path.

**Fix**: Always export `LD_LIBRARY_PATH` before running:

```bash
export LD_LIBRARY_PATH="/data/zcwang/anaconda3/envs/boltz2/lib/python3.11/site-packages/nvidia/cu13/lib:$LD_LIBRARY_PATH"
```

This is already wired into `scripts/run_single_model.sh`. If you run Boltz-2 outside
that script, you must set it manually.

### Boltz-2 ligand YAML: `Invalid entity type: smiles`

**Cause**: Earlier versions of `prepare_inputs.py` produced YAML with `smiles:` as a
top-level entity. Boltz-2 schema does not accept this.

**Fix**: Use `ligand:` as the entity type with `smiles:` (or `ccd:`) as a sub-field:

```yaml
- ligand:
    id: C
    smiles: "CC(C)(C)NC(=O)..."
```

`prepare_inputs.py` is now fixed — re-run it to regenerate.

### Boltz-2 hangs on MSA fetch / timeouts to api.colabfold.com

**Cause**: ColabFold MSA server is blocked or rate-limited from China.

**Fix**: Set HTTPS proxy before running:

```bash
export HTTPS_PROXY=http://127.0.0.1:7892
export HTTP_PROXY=http://127.0.0.1:7892
```

Same applies to Chai-1, IntelliFold-2, OpenFold3.

---

## Protenix

### Protenix checkpoint is too small (476 MB instead of 1.4 GB)

**Cause**: Auto-download from the Volces TOS endpoint sometimes truncates.

**Fix**: Verify the file size — it should be 1.4 GB. If 476 MB, manually re-download:

```bash
wget -O /home/zcwang/checkpoint/protenix_base_default_v1.0.0.pt \
    "https://protenix.tos-cn-beijing.volces.com/checkpoint/protenix_base_default_v1.0.0.pt"
```

Verify with `python -c "import torch; torch.load('/home/zcwang/checkpoint/protenix_base_default_v1.0.0.pt', weights_only=True)"`.

### Protenix RNA cases fail

**Status**: Protenix does not currently support RNA prediction. The model card
acknowledges this limitation. There is no fix on our side.

The benchmark records these as `FAIL` and they are excluded from RNA averages.

### Protenix `protenix predict` not found

**Cause**: Wrong subcommand name.

**Fix**: Use `protenix pred`, not `protenix predict`.

---

## Chai-1

### Chai-1: `chai: command not found`

**Cause**: The CLI is named `chai-lab`, not `chai`.

**Fix**: Use `chai-lab fold input.fasta output_dir/ --use-msa-server`.

### Chai-1 RNA cases fail

**Status**: Chai-1's FASTA `>rna` headers are accepted but inference does not handle
RNA properly. Recorded as `FAIL`.

---

## IntelliFold-2

### IntelliFold-2 errors out on missing MSA file

**Cause**: IntelliFold-2 has no built-in MSA fallback.

**Fix**: Always pass `--use_msa_server`. Without it, the command does not produce a
helpful error — it just fails on missing MSA files mid-pipeline.

---

## OpenFold3

### OpenFold3: `openfold: command not found`

**Cause**: The CLI binary is `run_openfold`, not `openfold`.

**Fix**: Use `run_openfold predict --query-json input.json ...`.

### OpenFold3 hangs for ~60 seconds then fails on template search

**Cause**: Template search calls a remote API that is unreliable (especially from
China). 95%+ of runs fail with timeout.

**Fix**: Pass `--use-templates false`:

```bash
run_openfold predict --query-json input.json --use-templates false ...
```

Already wired into `scripts/run_single_model.sh`.

### OpenFold3 still fails ~30% of the time even with `--use-templates false`

**Cause**: ColabFold MSA server itself is unstable from China.

**Fix**: Configure a proxy (see Boltz-2 section above). Even with proxy, expect
some flakiness — re-run failed cases.

---

## AlphaFast

### AlphaFast download stalls

**Cause**: HuggingFace dataset downloads occasionally hit
`SSL: UNEXPECTED_EOF_WHILE_READING` errors. The `hf` CLI retries automatically but
is slow.

**Status (2026-04-30)**: AlphaFast DB at `/hdd01/zcwang/alphafast_db/` has ~130 GB
of ~250 GB downloaded. Download is still running in tmux session `alphafast_db`.

**Fix options**:

1. Authenticate to HF for higher rate limits:
   ```bash
   hf auth login   # paste your HF token
   ```

2. Use `aria2c` for resumable parallel downloads (bypasses `hf` CLI):
   ```bash
   # Look up file URLs from https://huggingface.co/datasets/RomeroLab-Duke/af3-mmseqs-db/tree/main
   aria2c -x 8 -s 8 -c <URL>
   ```

3. Restart download (it resumes from `.incomplete` cache files automatically):
   ```bash
   tmux kill-session -t alphafast_db
   tmux new-session -d -s alphafast_db /tmp/run_alphafast_db_download_v4.sh
   ```

### AlphaFast multi-GPU mode hangs at MSA stage

**Cause**: Phase-separated multi-GPU mode dedicates one GPU to MMseqs2 search.
On a system without enough GPU memory, MMseqs2 may OOM silently.

**Fix**: Try single-GPU mode first (`--gpu_devices 0`). If it works, then test
multi-GPU. RTX 4090 (48 GB) has been verified to work with both modes.

---

## General environment

### `conda activate` says "not initialized"

**Fix**:

```bash
source /data/zcwang/anaconda3/etc/profile.d/conda.sh
conda activate boltz2
```

If you are not the owner of `/data/zcwang/anaconda3`, see [INSTALL.md § Sharing](INSTALL.md#sharing-this-install-with-another-user) for how to make the envs accessible to other users.

### CUDA out of memory

**Cause**: Multiple models running on the same GPU.

**Fix**: Use `CUDA_VISIBLE_DEVICES=N` to pin each job to a different GPU. We have 4
GPUs (0-3); the benchmark runner accepts `--gpu N` to select one.

### `colabfold` host unreachable

See Boltz-2 section above — set HTTPS proxy.

---

## Reporting a new issue

If you hit something not listed here:

1. Check the relevant `outputs/<model>/<scenario>/<case>.log` file.
2. Check that the input file exists in `inputs/<scenario>/<format>/<case>.<ext>`.
3. Confirm the conda env is activated and (for Boltz-2) `LD_LIBRARY_PATH` is set.
4. Try running the model directly (without `run_single_model.sh`) to isolate the
   issue.

When asking for help, include:
- The command you ran
- Last 30 lines of the error log
- `conda env list` and (for AF3) `docker images | grep alphafold3`
