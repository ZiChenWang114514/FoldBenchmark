# Per-Model Usage Reference

Verified working CLI commands and key gotchas for all 9 models.
This is the canonical "how to actually run each model" reference.

For input format details see [INPUT_FORMATS.md](INPUT_FORMATS.md).
For installation see [INSTALL.md](INSTALL.md).
For known issues see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## Quick command reference

| Model | Conda env | Command | Input |
|-------|-----------|---------|-------|
| AF3 | (Docker) | `docker run alphafold3 python3 run_alphafold.py ...` | AF3 JSON |
| AlphaFast | (native uv venv at `/data2/zcwang/af3/alphafast/.venv`) | `bash scripts/run_alphafast_all_in_one.sh` | AF3 JSON |
| Boltz-2 | `boltz2` | `boltz predict input.yaml --use_msa_server` | YAML |
| OpenFold3 | `openfold3` | `run_openfold predict --query-json input.json` | OpenFold3 JSON |
| Protenix | `protenix` | `protenix pred -i input.json -o output/` | Protenix JSON |
| Chai-1 | `chai1` | `chai-lab fold input.fasta output/ --use-msa-server` | FASTA |
| IntelliFold-2 | `intellifold` | `intellifold predict input.yaml --out_dir output/ --use_msa_server` | YAML |
| RoseTTAFold3 | `rf3` | `rf3 fold inputs=input.json out_dir=output/ ckpt_path=...` | RF3 JSON |
| ESMFold2 | `esmfold2` | `python scripts/run_esmfold2.py --input ... --outdir ...` | AF3 JSON (reused) |

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
        --jackhmmer_n_cpu=4 \
        --jackhmmer_max_parallel_shards=16 \
        --nhmmer_n_cpu=4 \
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

### Measured speed on 4× 4090 (2026-05-23 benchmark)

| Scenario | AF3 (n_cpu=4 sharded) | AlphaFast (all-in-one batch) | Δ |
|----------|---:|---:|---:|
| Monomer (5 cases) | 198 s/case | **75 s/case** | 62% faster |
| Protein-Protein (4) | 254 s/case | **75 s/case** | 70% faster |
| Protein-Ligand (5) | 279 s/case | **75 s/case** | 73% faster |
| Protein-RNA (3) | 341 s/case | **75 s/case** | 78% faster |
| Antibody-Antigen (5) | 416 s/case | **75 s/case** | 82% faster |

All-in-one batch mode (`run_alphafast_all_in_one.sh`) stages all 22 cases together —
one MMseqs2 queryDB, one JAX warm-up — yielding flat **75 s/case** across every scenario.
Per-case mode gave 525-1000 s/case (slower than AF3); per-scenario batch gave ~200 s/case.

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

**Speed**: ~79 seconds per typical PPI (fastest accurate model after AlphaFast batch).

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
5. RNA is supported (pTM 0.88 avg across 3 RNA cases in benchmark).

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
4. RNA is supported (pTM 0.88 avg across 3 RNA cases in benchmark).

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
3. IntelliFold-2 handles RNA (one of 5 models in this benchmark that do — AF3, AlphaFast,
   Boltz-2, Protenix, and Chai-1 also support RNA).

**Output**: `output/intellifold_results/<name>/<name>_pred_0.cif` plus confidence JSON.

**Speed**: ~80 seconds per typical PPI.

---

## 8. RoseTTAFold3 v0.1.12 (Foundry)

```bash
conda activate rf3

CUDA_VISIBLE_DEVICES=0 rf3 fold \
    inputs="$(realpath input.json)" \
    out_dir=output/ \
    ckpt_path="${RF3_CKPT_PATH}"
```

**Critical gotchas**:

1. `inputs=` must be an **absolute path** (`$(realpath ...)`). Relative paths silently
   produce empty output.
2. RF3 runs **zero-shot** — no MSA search is performed. Multi-chain pTM is lower
   because no paired MSA is used. For single-chain quality, `chain_ptm` in
   `summary_confidences.json` is more meaningful than the complex-level pTM.
3. The JSON format uses a `components` array (RF3-specific). Not AF3-compatible.
4. Model weights live at `${RF3_CKPT_PATH}` (set in `scripts/config.sh`).

**Output**: `output/<name>/<name>_pred_0.cif` plus `*_summary_confidences.json`.

**Speed**: **30–60 s/case** — fastest model overall. Monomers ~30s, antibody-antigen ~60s.

---

## 9. ESMFold2 (Biohub, 2026-05-27)

```bash
conda activate esmfold2
python scripts/run_esmfold2.py \
    --input  inputs/monomer/af3_json/1UBQ_ubiquitin.json \
    --outdir outputs/esmfold2/monomer/1UBQ_ubiquitin \
    --model  /data2/zcwang/structure_prediction/esmfold2/hf_cache/biohub_ESMFold2 \
    --num-loops 3
# Output: pred_esmfold2.cif + confidence_esmfold2.json
```

**Installation** (Python 3.12 required, strict):
```bash
conda create -n esmfold2 python=3.12 -y
conda activate esmfold2

# GitHub 直接 clone 不稳定；改用下载 zip + 本地安装
# 1. 下载源码 zip（通过代理）
curl --proxy http://127.0.0.1:7892 -L -o /tmp/esm.zip \
    https://github.com/Biohub/esm/archive/refs/heads/main.zip
curl --proxy http://127.0.0.1:7892 -L -o /tmp/transformers.zip \
    https://github.com/Biohub/transformers/archive/3a8956fb4d4ea16b0ec8e71deef2c2909b6a5cbf.zip
unzip /tmp/esm.zip -d /data2/zcwang/structure_prediction/esmfold2/
unzip /tmp/transformers.zip -d /data2/zcwang/structure_prediction/esmfold2/

# 2. 安装：先装 transformers fork，再装 esm --no-deps，再补依赖
cd /data2/zcwang/structure_prediction/esmfold2/transformers-3a8956fb*/
pip install -e . --no-deps
cd /data2/zcwang/structure_prediction/esmfold2/esm-main/
pip install -e . --no-deps
pip install torch>=2.2.0 biotite>=1.0.0 rdkit biopython scikit-learn \
    zstd cloudpathlib brotli attrs msgpack-numpy pygtrie tenacity \
    httpx accelerate einops ipython boto3 pydssp

# 3. 验证
python -c "from esm.models.esmfold2 import StructurePredictionInput, ProteinInput; print('OK')"
```

**Input format**: Reuses AF3 JSON (already generated for all 35 cases). No new input directory needed. The wrapper script (`run_esmfold2.py`) converts AF3 JSON → `StructurePredictionInput` at runtime.

**Weights (pre-downloaded, offline)**: Two components — both at `/data2/zcwang/structure_prediction/esmfold2/hf_cache/`:
- `biohub_ESMFold2/` — folding head (~1.3 GB: `config.json` + `ccd.pkl` 398 MB + `model.safetensors` 896 MB)
- `biohub_ESMC_6B/` — ESMC-6B backbone (~27 GB: 6 shards × 4.5 GB + metadata)

`config.json`中`esmc_id`已改为本地路径；`ESMCFOLD_CCD_PATH`指向本地`ccd.pkl`（避免联网）。
如需重新下载：`curl --proxy http://127.0.0.1:7892 -L -C - -o <target> https://huggingface.co/biohub/ESMFold2/resolve/main/<file>`

**Architecture**: ESMC-6B language model (2.8B sequence training corpus) + ESMFold2 looped-transformer folding head. Supports inference-time compute scaling via `--num-loops` (higher = more accurate but slower).

**Model variants**:
- `biohub/ESMFold2` — full model, used for benchmark (default)
- `biohub/ESMFold2-Fast` — faster, slightly lower accuracy

**Key differences from other models**:
- No CLI — must use `run_esmfold2.py` wrapper
- `LigandInput` accepts CCD codes only (`ccd=["ATP"]`); SMILES-only ligands are skipped with a warning
- Zero-shot single-sequence by default (no MSA); ColabFold MSA optionally supported
- Output: `result.complex.to_mmcif()` → CIF; `result.ptm`, `result.plddt`, `result.iptm` → confidence

**Speed**: **~27 s/case** avg across 35 cases (no MSA search; model loads in ~3 s after first run). Fastest: monomer/DNA ~20 s; slowest: antibody-antigen ~40 s.

**VRAM**: ~13 GB (ESMC-6B in bfloat16 ~12 GB + folding head ~1 GB); RTX 4090 (48 GB) comfortable.

---

---

## Ternary Complex Scenario (added 2026-05-28)

The `ternary_complex` scenario covers 6 high-resolution structures of bifunctional
degrader systems — the hardest multi-protein+ligand prediction challenge:

| Case | PDB | Class | E3 | POI | Ligand CCD | Resolution |
|------|-----|-------|----|-----|-----------|-----------|
| 5FQD_CRBN_lenalidomide_CK1a | 5FQD | Molecular glue | DDB1/CRBN | CK1α | LVY | 2.45 Å |
| 6H0F_CRBN_pomalidomide_IKZF1 | 6H0F | Molecular glue | DDB1/CRBN | IKZF1 ZF2 | Y70 | 3.25 Å |
| 5HXB_CRBN_CC885_GSPT1 | 5HXB | Molecular glue | DDB1/CRBN | GSPT1 | 85C | 3.60 Å |
| 6ZHC_BclxL_PROTAC_VHL | 6ZHC | PROTAC | VHL+EloB/C | Bcl-xL | QL8 | 1.92 Å |
| 6HAY_SMARCA2_PROTAC_VHL | 6HAY | PROTAC | VHL+EloB/C | SMARCA2 BD1 | FX8 | 2.24 Å |
| 7JTP_WDR5_PROTAC_VHL | 7JTP | PROTAC | VHL+EloB/C | WDR5 | X6M | 2.12 Å |

**Design decisions**:
- **DDB1 included**: 5FQD/6H0F/5HXB all contain DDB1 — omitting it removes the structural
  context that positions CRBN relative to the recruited POI.
- **ElonginB/C included**: Standard VHL system (6ZHC/6HAY/7JTP) always includes EloB+EloC
  as the heterodimer that bridges VHL to Cullin2.
- **CCD codes for all ligands**: More precise than SMILES for small-molecule benchmarking.
  Chai-1 (which only accepts SMILES) gets automatic CCD→SMILES conversion via `CCD_TO_SMILES`
  in `prepare_inputs.py`.
- **6ZHC chain IDs**: Uses triple-character auth_asym_ids (AAA/BBB/CCC/DDD) — `prepare_inputs.py`
  auto-remaps to A/B/C/D in all output formats.

**Prediction notes**:
- PROTAC linkers are highly flexible; consider multiple seeds (`modelSeeds: [1,2,3,4,5]`).
- Focus on **iPTM** (interface pTM) rather than overall pTM for cross-protein interface quality.
- ESMFold2 fully supports all 6 cases (CCD codes). SMILES-only ligands would be skipped.
- RF3 (zero-shot, no paired MSA) may underperform on the large multi-protein assemblies.

---

## Choosing a model for your task

| Use case | Recommended model | Why |
|----------|-------------------|-----|
| General PPI | **Boltz-2** or **ESMFold2** | Boltz-2 pTM 0.94; ESMFold2 pTM 0.89 PPI avg; fastest (27s) |
| Protein-ligand | **Boltz-2** or Chai-1 | pTM 0.95 / 0.94; ESMFold2 CCD only |
| Protein-RNA | **Boltz-2** or Chai-1 | pTM 0.87 / 0.88 |
| Antibody-antigen | **ESMFold2** or Boltz-2 | ESMFold2 SOTA per Biohub benchmarks |
| High-throughput screening | **RF3** | 30-60s zero-shot, no MSA |
| AF3 batch speedup | **AlphaFast** | 52s/case (flat), 5× faster than AF3 |
| Reproducible / publication | **AF3** | Gold standard, JackHMMER MSA |
| Cluster-friendly minimal | **Chai-1** | Lightest weights, simplest input |

See [results/summary.md](../results/summary.md) for full benchmark numbers.
