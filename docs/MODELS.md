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
| AlphaFast | (native uv venv at `/data2/zcwang/af3/alphafast/.venv`) | `LD_PRELOAD=... python run_alphafold.py ...` | AF3 JSON |
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

Native install (Docker Hub blocked from PRC). On 4× RTX 4090, **always use batch mode**
— per-case mode is slower than vanilla AF3 because the MMseqs2 GPU search is
the bottleneck and amortizes well across cases.

### Batch mode (recommended — used for all benchmark numbers)

```bash
# Run a whole scenario in one shot (one MMseqs2 queryDB, one JAX cache warm-up)
ALPHAFAST_DB_DIR=/data2/zcwang/alphafast_db \
ALPHAFAST_GPUS=0,1,2,3 \
bash scripts/run_alphafast_batch.sh monomer
```

The batch runner stages every JSON in `inputs/<scenario>/af3_json/` into a temp dir
and invokes AlphaFast once with `--input_dir` + `--batch_size=N` + a persistent
`--jax_compilation_cache_dir`.

### Per-case mode (for one-off prediction, not benchmarking)

```bash
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libstdc++.so.6 \
MMSEQS_USE_ALL_GPUS=1 \
CUDA_VISIBLE_DEVICES=0,1,2,3 \
/data2/zcwang/af3/alphafast/.venv/bin/python \
    /data2/zcwang/af3/alphafast/run_alphafold.py \
    --json_path=/path/to/my_complex.json \
    --output_dir=/path/to/output \
    --model_dir=/data/zxhuang/Shared/Alphafold3params \
    --db_dir=/data2/zcwang/alphafast_db \
    --mmseqs_binary_path=/data2/zcwang/af3/alphafast/bin/bin/mmseqs \
    --mmseqs_db_dir=/data2/zcwang/alphafast_db/mmseqs \
    --use_mmseqs_gpu=True \
    --jax_compilation_cache_dir=/data2/zcwang/af3/alphafast/jax_cache \
    --run_data_pipeline=True \
    --run_inference=True
```

**Input**: AF3 JSON format (same as AF3 itself — fully compatible).

### Critical gotchas (verified 2026-05-02 with full benchmark)

1. **`LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libstdc++.so.6`** is mandatory.
   The `cpp.so` C++ extension was built with system GCC 13.3 → needs `GLIBCXX_3.4.32+`,
   but conda's bundled libstdc++ caps at 3.4.29 → `ImportError: GLIBCXX_3.4.32 not found`.

2. **`components.cif` symlinks** are pre-set in
   `.venv/share/libcifpp/components.cif` and `.venv/lib/python3.12/site-packages/share/libcifpp/components.cif`
   (one-time setup). Without these, libcifpp throws `Could not find the libcifpp components.cif file.`

3. **DBs don't fit on a single 4090** (uniref90_padded 49G, mgnify_padded 108G vs
   48G GPU). You **must** shard across all 4 GPUs by setting
   `CUDA_VISIBLE_DEVICES=0,1,2,3` AND `MMSEQS_USE_ALL_GPUS=1`. The latter is read
   by a small patch in `src/alphafold3/data/tools/{mmseqs,mmseqs_batch,mmseqs_template,foldseek}.py`
   that allows the env-level CUDA_VISIBLE_DEVICES to pass through to MMseqs2
   subprocesses (vanilla AlphaFast hardcodes the subprocess to a single GPU).

4. **MMseqs2 padded DBs** at `/data2/zcwang/alphafast_db/mmseqs/` were built locally
   from existing FASTAs at `/data/zxhuang/Shared/genetic_database/` via
   `mmseqs createdb` + `mmseqs makepaddedseqdb` (5 protein DBs, ~388 GB total).
   This is 100% functionally equivalent to AlphaFast's HuggingFace pre-built DBs
   but bypassed the rate-limited HF download.

5. The MMseqs2 RNA database is **not built** (we did `--protein-only`). RNA scenarios
   are skipped in the benchmark. For RNA-containing inputs you can add
   `--use_nhmmer=True` to fall back to AF3-style nhmmer; that requires the AF3-style
   RNA databases at `--db_dir`.

6. **Use batch mode whenever possible.** Per-case mode runs the 5 padded DBs through
   MMseqs2 once per case — that is the dominant cost. Batch mode runs MMseqs2 once
   for all cases in the batch (one combined queryDB), which is what makes AlphaFast
   actually faster than AF3 on this hardware.

### Measured speed on 4× 4090 (2026-05-02 benchmark)

| Scenario | AF3 (sharded JackHMMER) | AlphaFast (batch, 4-GPU mmseqs) | Δ |
|----------|---:|---:|---:|
| Monomer (5 cases) | 176 s/case | **109 s/case** | 38% faster |
| Protein-Protein (4) | 236 s/case | **142 s/case** | 40% faster |
| Protein-Ligand (5) | 255 s/case | **135 s/case** | 47% faster |
| Antibody-Antigen (5) | 392 s/case | **179 s/case** | 54% faster |

Per-case mode (no batching) gave 525-1000 s/case — slower than AF3. The speedup is
entirely from amortizing MMseqs2 search across cases plus warm JAX kernel cache.

**Output**: same structure as AF3 (`.cif` + `*_summary_confidences.json` + `*_ranking_scores.csv`).

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
