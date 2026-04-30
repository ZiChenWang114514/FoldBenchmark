# Per-Model Usage Reference

Verified working CLI commands and key gotchas for all 7 models.
This is the canonical "how to actually run each model" reference.

For input format details see [INPUT_FORMATS.md](INPUT_FORMATS.md).
For installation see [INSTALL.md](INSTALL.md).
For known issues see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## Quick command reference

| Model | Conda env | Command | Input |
|-------|-----------|---------|-------|
| AF3 | (Docker) | `docker run alphafold3 python3 run_alphafold.py ...` | AF3 JSON |
| AlphaFast | (Docker) | `bash scripts/run_alphafast.sh ...` | AF3 JSON |
| Boltz-2 | `boltz2` | `boltz predict input.yaml --use_msa_server` | YAML |
| OpenFold3 | `openfold3` | `run_openfold predict --query-json input.json` | OpenFold3 JSON |
| Protenix | `protenix` | `protenix pred -i input.json -o output/` | Protenix JSON |
| Chai-1 | `chai1` | `chai-lab fold input.fasta output/ --use-msa-server` | FASTA |
| IntelliFold-2 | `intellifold` | `intellifold predict input.yaml --out_dir output/ --use_msa_server` | YAML |

---

## 1. AlphaFold 3 v3.0.2

```bash
docker run --rm \
    --volume /path/to/inputs:/root/af_input \
    --volume /path/to/output:/root/af_output \
    --volume /data2/zcwang/af3/models:/root/models \
    --volume /data2/zcwang/af3/databases_sharded:/root/public_databases \
    --volume /data2/zcwang/af3/databases/mmcif_files:/root/public_databases/mmcif_files:ro \
    --volume /data2/zcwang/af3/alphafold3/src/alphafold3/data/msa.py:/app/alphafold/src/alphafold3/data/msa.py:ro \
    --gpus "device=0" \
    alphafold3 \
    python3 run_alphafold.py \
        --json_path=/root/af_input/my_complex.json \
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
        --nhmmer_max_parallel_shards=16
```

**Critical gotchas**:

1. The `--volume .../msa.py:.../msa.py:ro` line patches the v3.0.2 RNA bug (Nhmmer
   constructor missing `z_value`). Without it, every RNA-containing input fails.
2. The `*_z_value` flags must match the **original** Z values of the unsharded databases
   (we are running 1 shard at a time but each shard claims to be the full DB).
3. `@N` after a database path means "split into N shards for parallel JackHMMER". With
   sharding, MSA is ~6× faster than vanilla AF3.
4. Without GPU access (`--gpus`), JAX falls back to CPU — inference becomes ~50× slower.
5. The `mmcif_files/` volume must be mounted **read-only** because it points to a shared
   directory.

**Output**: `<output_dir>/<name>/seed-1_sample-0/model.cif` plus confidence JSON.

**Speed**: ~3-7 minutes per typical PPI on RTX 4090 with sharded DB.

---

## 2. AlphaFast (AF3 + GPU MMseqs2 MSA)

```bash
cd /data2/zcwang/af3/alphafast

bash scripts/run_alphafast.sh \
    --input_dir /path/to/input_jsons \
    --output_dir /path/to/output \
    --db_dir /hdd01/zcwang/alphafast_db \
    --weights_dir /data2/zcwang/af3/models \
    --gpu_devices 0 \
    --jax_compilation_cache_dir /data2/zcwang/af3/jax_cache
```

**Multi-GPU**: `--gpu_devices 0,1,2,3` runs phase-separated multi-GPU (1 GPU does MSA,
others do inference). On a 4× 4090 box this is the fastest configuration.

**Input**: AF3 JSON format (same as AF3 itself — fully compatible).

**Critical gotchas**:

1. Status as of 2026-04-30: **DB is still downloading**. See
   [TROUBLESHOOTING.md](TROUBLESHOOTING.md#alphafast-download-stalls).
2. AlphaFast uses MMseqs2 GPU search instead of JackHMMER. The MSAs are ~95% identical
   to JackHMMER's but built in seconds instead of minutes.
3. The MMseqs2 RNA database is optional. Use `--use_nhmmer` to fall back to AF3-style
   nhmmer for RNA if the RNA MMseqs2 DB is not available.
4. `--temp_dir /scratch` is recommended on HPC — MMseqs2 writes large temp files.

**Output**: same structure as AF3 (`.cif` + confidence JSON).

**Speed**: ~30 seconds per typical PPI (MSA dropped from minutes to seconds).

---

## 3. Boltz-2 v2.2.1

```bash
conda activate boltz2
export LD_LIBRARY_PATH="/data/zcwang/anaconda3/envs/boltz2/lib/python3.11/site-packages/nvidia/cu13/lib:$LD_LIBRARY_PATH"

CUDA_VISIBLE_DEVICES=0 boltz predict input.yaml \
    --out_dir output/ \
    --use_msa_server
```

**Critical gotchas**:

1. **Always** export `LD_LIBRARY_PATH` to include `nvidia/cu13/lib`. PyTorch ships
   built for CUDA 13.0 but only the cu12.9 nvrtc is on the default linker path.
   Symptom: `torch.det()` crashes with `cannot find libnvrtc-builtins.so.13.0`.
2. `--use_msa_server` calls `api.colabfold.com`. In China this needs a proxy:
   `export HTTPS_PROXY=http://127.0.0.1:7892`.
3. Ligand entity in YAML must use `ligand:` with `smiles:` or `ccd:` as a sub-field.
   `smiles:` as a top-level entity type is **not** valid.

**Output**: `output/boltz_results_<name>/predictions/<name>/<name>_model_0.cif` plus
confidence JSON containing pTM, ipTM, ranking_score.

**Speed**: ~50 seconds per typical PPI (fastest of all 7 models).

---

## 4. OpenFold3 v0.4.1

```bash
conda activate openfold3
export OPENFOLD_CACHE="/data2/zcwang/structure_prediction/openfold3/cache"

CUDA_VISIBLE_DEVICES=0 run_openfold predict \
    --query-json input.json \
    --output-dir output/ \
    --inference-ckpt-path "$OPENFOLD_CACHE/of3-p2-155k.pt" \
    --use-templates false
```

**Critical gotchas**:

1. Command is `run_openfold` (with underscore), not `openfold`.
2. Pass `--use-templates false`. The default template-search step calls a remote API
   that times out in ~95% of runs from China.
3. Even with `--use-templates false`, the MSA step still calls ColabFold and is
   unstable. Expect ~30% failure rate.
4. The JSON format is OpenFold3-specific (uses `queries` dict, `chains` list, and
   `molecule_type` field). Not AF3-compatible.

**Output**: `output/<name>/<name>_model_0.cif` plus confidence JSON.

**Speed**: ~85 seconds per typical PPI when MSA succeeds.

---

## 5. Protenix

```bash
conda activate protenix

CUDA_VISIBLE_DEVICES=0 protenix pred \
    -i input.json \
    -o output/
```

**Critical gotchas**:

1. Command is `protenix pred`, not `protenix predict`.
2. The JSON is **not** AF3-compatible. Uses `proteinChain` / `rnaSequence` /
   `dnaSequence` (not `protein` / `rna` / `dna`).
3. Ligands: `{"ligand": {"ligand": "SMILES_OR_CCD", "count": 1}}`. CCD codes need
   the `CCD_` prefix, e.g. `"ligand": "CCD_ATP"`.
4. Protenix uses **local** MSA (no proxy needed) — this is rare among the open-source
   tools.
5. **RNA scenarios fail**: Protenix does not currently support RNA prediction.

**Output**: `output/<name>/predictions/<name>_seed_1_sample_0.cif` plus
`<name>_seed_1_sample_0_confidence.json`.

**Speed**: ~110 seconds per typical PPI.

---

## 6. Chai-1

```bash
conda activate chai1

CUDA_VISIBLE_DEVICES=0 chai-lab fold \
    input.fasta \
    output/ \
    --use-msa-server
```

**Critical gotchas**:

1. Command is `chai-lab fold`, not `chai fold`.
2. Arguments are **positional**: `<fasta_file> <output_dir>`. There is no `--input`
   flag.
3. Note the dashes: `--use-msa-server` (Chai-1 / OpenFold3) versus `--use_msa_server`
   (Boltz-2 / IntelliFold). Easy to confuse.
4. **RNA scenarios fail**: Chai-1 does not currently support RNA in FASTA inputs.

**Output**: `output/pred.model_idx_0.cif` and confidence file.

**Speed**: ~200 seconds per typical PPI (slowest among the open-source models).

---

## 7. IntelliFold-2

```bash
conda activate intellifold

CUDA_VISIBLE_DEVICES=0 intellifold predict \
    input.yaml \
    --out_dir output/ \
    --use_msa_server
```

**Critical gotchas**:

1. **Must** pass `--use_msa_server` even though it sounds optional. Without it, the
   command errors out on missing MSA files. There is no built-in MSA mode.
2. Input format is **identical** to Boltz-2 YAML — you can reuse Boltz-2 input files
   directly.
3. IntelliFold-2 handles RNA (one of only 3 models in this benchmark that does — the
   others are AF3 and Boltz-2).

**Output**: `output/intellifold_results/<name>/<name>_pred_0.cif` plus confidence JSON.

**Speed**: ~80 seconds per typical PPI.

---

## Choosing a model for your task

| Use case | Recommended model | Why |
|----------|-------------------|-----|
| General PPI | **Boltz-2** | Highest pTM (0.94), fastest (~50s) |
| Protein-ligand | **Boltz-2** or Protenix | Both at pTM 0.94-0.95 |
| Protein-RNA | **AF3** or Boltz-2 | Only AF3/Boltz-2/IntelliFold support RNA |
| Antibody-antigen | **Boltz-2** | Best pTM (0.89) on Ab-Ag scenario |
| AF3 reproduction (dev) | **Protenix** | Closest implementation to AF3 |
| Need GPU MSA speedup | **AlphaFast** | MMseqs2 GPU, drop-in AF3 replacement |
| Reproducible / publication | **AF3** | Gold standard, deterministic, JackHMMER MSA |
| Cluster-friendly minimal | **Chai-1** | Lightest weights (1.2 GB), simplest input |

See [results/summary.md](../results/summary.md) for full benchmark numbers.
