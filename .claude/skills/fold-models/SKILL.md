---
name: fold-models
description: Run individual open-source structure prediction models (AlphaFast, Boltz-2, OpenFold3, Protenix, Chai-1, IntelliFold-2, RoseTTAFold3) on user-provided inputs. TRIGGER when the user asks to predict a structure with a specific non-AF3 model, run AlphaFast/Boltz-2/Chai/Protenix/OpenFold/IntelliFold/RF3 on a protein, or compare a specific model's output. DO NOT TRIGGER for AF3 (use af3-local) or for cross-model benchmarks (use fold-bench).
---

# fold-models

Run open-source structure prediction models at `/data2/zcwang/structure_prediction/` and `/data2/zcwang/af3/alphafast/` on the 4-GPU box (4× RTX 4090, 48GB each).

## When this skill applies

- "用 Boltz-2 跑一下这个蛋白"
- "Chai-1 预测一下这个复合物"
- "用 Protenix 跑一下 PPI"
- "OpenFold3 预测这个序列"
- "IntelliFold 跑一下抗体-抗原"
- "AlphaFast 加速 AF3 / GPU MMseqs2"
- "RoseTTAFold3 / RF3 跑一下这个结构"

## 7 Models — Verified Working Commands

### Boltz-2 (recommended: fastest + top-tier accuracy)

```bash
conda activate boltz2
export LD_LIBRARY_PATH="/data/zcwang/anaconda3/envs/boltz2/lib/python3.11/site-packages/nvidia/cu13/lib:${LD_LIBRARY_PATH}"
CUDA_VISIBLE_DEVICES=0 boltz predict input.yaml --out_dir output/ --use_msa_server
```

**CRITICAL**: Must set `LD_LIBRARY_PATH` for `nvidia/cu13/lib/` or `torch.det()` crashes.

Input (YAML):
```yaml
version: 1
sequences:
  - protein:
      id: A
      sequence: MTEE...
  - protein:
      id: B
      sequence: MARL...
```

Ligand: `- ligand: { id: C, smiles: "O=C(..." }` or `- ligand: { id: C, ccd: ATP }`.
RNA: `- rna: { id: B, sequence: AUGC... }`.

### AlphaFast (AF3 weights + GPU MMseqs2 — only fast in batch mode)

**CRITICAL**: per-case mode is SLOWER than vanilla AF3 on 4× 4090. Only batch mode (one MMseqs2 queryDB + JAX cache amortized across N cases) gives the speedup.

**Batch mode (recommended)**: see FoldBenchmark `scripts/run_alphafast_batch.sh` — stages multiple AF3-format JSONs into a temp dir, runs once with `--input_dir` + `--batch_size=N`.

**Per-case mode (one-off prediction)**:
```bash
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libstdc++.so.6 \
MMSEQS_USE_ALL_GPUS=1 \
CUDA_VISIBLE_DEVICES=0,1,2,3 \
/data2/zcwang/af3/alphafast/.venv/bin/python \
    /data2/zcwang/af3/alphafast/run_alphafold.py \
    --json_path=/path/to/input.json \
    --output_dir=/path/to/output \
    --model_dir=/data/zxhuang/Shared/Alphafold3params \
    --db_dir=/data2/zcwang/alphafast_db \
    --mmseqs_binary_path=/data2/zcwang/af3/alphafast/bin/bin/mmseqs \
    --mmseqs_db_dir=/data2/zcwang/alphafast_db/mmseqs \
    --use_mmseqs_gpu=True \
    --jax_compilation_cache_dir=/data2/zcwang/af3/alphafast/jax_cache \
    --run_data_pipeline=True --run_inference=True
```

**4× 4090 OOM workaround**: uniref90_padded (49G) and mgnify_padded (108G) don't fit on a single 4090 (48G). Must use ALL 4 GPUs sharded:
- `CUDA_VISIBLE_DEVICES=0,1,2,3` (let mmseqs see all 4)
- `MMSEQS_USE_ALL_GPUS=1` env var, only effective with the patch applied to `src/alphafold3/data/tools/{mmseqs,mmseqs_batch,mmseqs_template,foldseek}.py` (vanilla AlphaFast hardcodes single-GPU subprocess).

**Input**: AF3 JSON format (fully compatible with AF3).

**RNA support**: requires RNA mmseqs DBs at `/data2/zcwang/alphafast_db/mmseqs_rna/` (built locally from `/data/zxhuang/Shared/genetic_database/{nt_rna,rfam,rnacentral}*.fasta` via `mmseqs createdb --dbtype 2` + `mmseqs makepaddedseqdb`; HF mirror download was unreliable).

### Protenix (ByteDance, AF3 reproduction — DOES support RNA)

```bash
conda activate protenix
CUDA_VISIBLE_DEVICES=0 protenix pred -i input.json -o output/
```

**JSON format** (NOT AF3-compatible):
```json
[{
  "name": "my_complex",
  "sequences": [
    {"proteinChain": {"sequence": "MTEE...", "count": 1}},
    {"proteinChain": {"sequence": "MARL...", "count": 1}}
  ],
  "modelSeeds": [1]
}]
```

Ligand: `{"ligand": {"ligand": "O=C(...", "count": 1}}` (SMILES) or `{"ligand": {"ligand": "CCD_ATP", "count": 1}}`.
RNA: `{"rnaSequence": {"sequence": "AUGC...", "count": 1}}` — earlier reports of "Protenix doesn't support RNA" were caused by buggy benchmark inputs, not the model.

**Checkpoint**: `/home/zcwang/checkpoint/protenix_base_default_v1.0.0.pt` (1.4G). If corrupted (~476M), re-download:
```bash
wget -O /home/zcwang/checkpoint/protenix_base_default_v1.0.0.pt \
    "https://protenix.tos-cn-beijing.volces.com/checkpoint/protenix_base_default_v1.0.0.pt"
```

### Chai-1 (lightest, 1.2G weights — DOES support RNA; scores in .npz)

```bash
conda activate chai1
CUDA_VISIBLE_DEVICES=0 chai-lab fold input.fasta output/ --use-msa-server
```

Note: command is `chai-lab` not `chai`. Positional args: `fasta_file output_dir`.

Input (FASTA):
```
>protein|name=chain_A
MTEE...
>protein|name=chain_B
MARL...
```

Ligand: `>ligand|name=chain_C\nO=C(C(N...`.
RNA: `>rna|name=chain_X\nAUGC...` — earlier "RNA fails" claim was input bug, not model.

**Reading scores**: `scores.model_idx_0.npz` contains `ptm`, `iptm`, `aggregate_score`, `per_chain_ptm`, `has_inter_chain_clashes`. NumPy format, not JSON.
```python
import numpy as np
d = np.load('scores.model_idx_0.npz')
print(float(d['ptm'].item()), float(d['iptm'].item()))
```

### IntelliFold-2 (best speed on monomer/RNA among ColabFold-MSA models)

```bash
conda activate intellifold
CUDA_VISIBLE_DEVICES=0 intellifold predict input.yaml --out_dir output/ --use_msa_server
```

Uses same YAML format as Boltz-2. **Must pass `--use_msa_server`** or it errors on missing MSA file.

### OpenFold3 (research preview — needs CUTLASS + msa.py patch on 4090)

```bash
conda activate openfold3
export OPENFOLD_CACHE="/data2/zcwang/structure_prediction/openfold3/cache"
# Three env vars required for DeepSpeed evoformer_attn JIT compile on RTX 4090:
export CUDA_HOME=/usr/local/cuda
export PATH=/usr/local/cuda/bin:$PATH
export CUTLASS_PATH=/data2/zcwang/structure_prediction/openfold3/cutlass
export TORCH_CUDA_ARCH_LIST=8.9
CUDA_VISIBLE_DEVICES=0 run_openfold predict \
    --query-json input.json \
    --output-dir output/ \
    --inference-ckpt-path "$OPENFOLD_CACHE/of3-p2-155k.pt" \
    --use-templates false
```

Note: command is `run_openfold` not `openfold`. `--use-templates false` to avoid template search fragility.

Input JSON (NOT AF3-compatible):
```json
{
  "queries": {
    "my_protein": {
      "use_msas": true,
      "chains": [
        {"molecule_type": "protein", "chain_ids": "A", "sequence": "MTEE..."},
        {"molecule_type": "protein", "chain_ids": "B", "sequence": "MARL..."}
      ]
    }
  }
}
```

**Six patches required to make OpenFold3 v0.4.1 robust** (all in `/data/zcwang/anaconda3/envs/openfold3/lib/python3.11/site-packages/openfold3/`). Patches 1-4 fix specific input-dependent crashes; patches 5-6 fix infrastructure-level race conditions and apply machine-wide.

1. **`core/data/pipelines/sample_processing/msa.py:290`** — numpy 2.x void-view dedup fails with mismatched widths (multi-chain DTypePromotionError):
   ```python
   if paired_arr.shape[1] == arr.shape[1]:
       # original void-view np.isin dedup
       ...
   else:
       filtered_msa = main_msa_redundant
       filtered_deletion = main_deletion_matrix_redundant
   ```

2. **`core/data/primitives/featurization/msa.py:193`** — `res_id - 1` fails when PDB residue numbering doesn't start at 1 (4LDE BRAF, 7RN1 Mpro, 1ASY tRNA-synth all start at res 2). Replace with ordinal rank:
   ```python
   _, msa_column_positions = np.unique(msa_token_mapper.res_id, return_inverse=True)
   ```

3. **`core/data/tools/colabfold_msa_server.py:252`** — `os.mkdir(path)` → `os.makedirs(path, exist_ok=True)` (defensive vs. parent-dir races).

4. **`core/data/tools/colabfold_msa_server.py:820`** — wrap `remap_colabfold_template_chain_ids` in try/except: RCSB returns empty `polymer_entities` for some PDB hits (e.g. `8d35`), and `--use-templates false` does NOT skip this code path. Catch `RuntimeError` → log warning → `return` (templates skipped, MSA proceeds).

5. **`run_openfold.py:194-203`** — wrap `expt_runner.run(query_set)` in `try/finally` so `expt_runner.cleanup()` always runs even when `run()` raises. Without this, FileNotFoundError / RuntimeError in `prepare_data()` left `/tmp/of3-of-<user>/colabfold_msas/raw/` populated, contaminating the next invocation. `_maybe_remove_dir` (checks `exists()`) and `ColabFoldQueryRunner.cleanup()` (`ignore_errors=True`) are both idempotent → safe in finally.

6. **`core/data/tools/colabfold_msa_server.py:1014-1031`** (`MsaComputationSettings.create_dir`) — default `msa_output_directory` now `get_of3_tmpdir(f"colabfold_msas_{os.getpid()}")` instead of `get_of3_tmpdir("colabfold_msas")`. Two concurrent OpenFold3 invocations no longer race on a shared `colabfold_msas/` dir; each gets its own PID-namespaced tmpdir, cleaned by `cleanup_msa_dir=True` on exit. Note: changed at the `MsaComputationSettings` layer (not `get_of3_tmpdir`) to avoid breaking 8 unit tests in `tests/core/data/tools/test_utils.py` that pin the legacy default. The `template.py` caller of `get_of3_tmpdir` is untouched (separate concern).

After patches 5-6, the FoldBenchmark per-case `--runner-yaml` workaround in `run_single_model.sh` is **redundant but kept as defense-in-depth and explicit per-case declaration**.

**Status (2026-05-07)**: 22/22 on FoldBenchmark; concurrent multi-GPU invocations verified race-free.

### RoseTTAFold3 (Baker Lab Foundry — pre-computed MSA, no built-in MSA pipeline)

```bash
conda activate rf3
CUDA_VISIBLE_DEVICES=0 rf3 fold \
    inputs=/path/to/input.json \
    out_dir=/path/to/output/ \
    ckpt_path=/data2/zcwang/structure_prediction/RoseTTAFold3/weights/rf3_foundry_01_24_latest_remapped.ckpt
```

**Input JSON** (RF3 components format, distinct from all other models):
```json
{
  "name": "my_complex",
  "components": [
    {"seq": "MTEE...", "chain_id": "A"},
    {"seq": "MARL...", "chain_id": "B"}
  ]
}
```

Ligand (SMILES): `{"smiles": "O=C(C(N...)..."}` — no `chain_id` needed.
RNA: `{"seq": "AUGC...", "chain_id": "B", "molecule_type": "rna"}`.

**Note on MSA**: RF3 Foundry uses pre-computed .a3m MSA files. It does NOT have a built-in MSA search pipeline. For the FoldBenchmark (standard test cases), pre-computed MSAs are not needed since RF3 can run in "no-MSA" mode.

**Weights**: Two checkpoints available:
- `rf3_foundry_01_24_latest_remapped.ckpt` (recommended)
- `rf3_foundry_01_24_latest.ckpt`
Both at `/data2/zcwang/structure_prediction/RoseTTAFold3/weights/`

**Install status (2026-05-22)**: ✓ Installed. `conda activate rf3 && rf3 fold ...` works. 22/22 benchmark complete.

## Benchmark Results (FoldBenchmark, 2026-05-07, 22 cases)

| Feature | AlphaFast | Boltz-2 | Protenix | Chai-1 | IntelliFold-2 | OpenFold3 | RF3 |
|---------|-----------|---------|----------|--------|---------------|-----------|-----|
| PPI pTM | 0.91 | 0.94 | 0.94 | **0.96** | 0.86 | 0.88 | 0.32† |
| Ligand pTM | 0.90 | 0.95 | 0.94 | **0.94** | 0.85 | 0.74 | 0.45† |
| RNA pTM | 0.76 | **0.90** | 0.88 | 0.88 | 0.79 | 0.61 | 0.56† |
| Monomer pTM | 0.70 | 0.83 | 0.83 | **0.84** | 0.64 | 0.59 | 0.61† |
| Antibody pTM | 0.75 | **0.89** | 0.76 | 0.84 | 0.71 | 0.73 | 0.53† |
| Speed PPI | 142s | **53s** | 376s | 364s | 83s | 127s | 65s |
| Speed Monomer | 109s | **44s** | 98s | 88s | 52s | 102s | **42s** |
| Stability | 22/22 | **22/22** | 22/22 | 22/22 | 22/22 | **22/22** | **22/22** |
| License | CC BY-NC-SA | MIT | Apache 2.0 | Apache 2.0 | Apache 2.0 | Apache 2.0 | BSD-3 |

† RF3 zero-shot (no paired MSA); multi-chain pTM depressed; single-chain pTM meaningful.

**Recommendation**:
- **General default**: Boltz-2 — fastest accurate model, best on RNA/antibody.
- **Highest PPI/ligand/monomer pTM**: Chai-1.
- **AF3-style outputs (5 samples + ranking)**: Protenix or AlphaFast.
- **Need GPU MSA speedup over AF3**: AlphaFast batch mode (40-50% faster than AF3 sharded JackHMMER). Skip on RTX 4090 if you don't have all 4 GPUs to shard DBs.
- **OpenFold3 status (2026-05-07)**: 22/22 with the four patches above; pTM still ~10-20% lower than other models on most scenarios. Use only if you specifically need its outputs (e.g. multimer ranking, AF3-style 5-sample diffusion).
- **RF3 status (2026-05-22)**: install in progress, benchmark results pending.

## Directory layout

```
/data2/zcwang/structure_prediction/
├── boltz2/        (weights symlink → /data2/zxhuang/.boltz/)
├── openfold3/     (cache/of3-p2-155k.pt, 2.2G + cutlass/ checkout)
├── protenix/
├── chai1/
└── intellifold2/

/data2/zcwang/af3/alphafast/      (native uv venv install)
└── .venv/lib/.../alphafold3/data/tools/{mmseqs,mmseqs_batch,mmseqs_template,foldseek}.py
                                  (patched to honor MMSEQS_USE_ALL_GPUS=1)

/data2/zcwang/alphafast_db/        (388G protein + 27G RNA, padded MMseqs2 DBs)
├── mmseqs/{mgnify,uniref90,uniprot,small_bfd,pdb_seqres}_padded*
└── mmseqs_rna/{nt_rna,rfam,rnacentral}_padded*
```

## Common pitfalls (verified 2026-05-07)

1. **Boltz-2 CUDA**: MUST set `LD_LIBRARY_PATH` to `nvidia/cu13/lib/`.
2. **Boltz-2 ligand YAML**: Entity type is `ligand:` with `smiles:` sub-field. NOT `smiles:` as top-level.
3. **AlphaFast multi-GPU**: `CUDA_VISIBLE_DEVICES=0,1,2,3` + `MMSEQS_USE_ALL_GPUS=1` + the 4 patched files in `src/alphafold3/data/tools/`. Without all three, OOM on uniref90 (49G > 48G single-GPU).
4. **AlphaFast batch mode**: per-case mode runs MMseqs2 once per case = slower than AF3. Use `run_alphafast_batch.sh` for real perf.
5. **Protenix JSON format**: Uses `proteinChain`/`rnaSequence` NOT `protein`/`rna`. CCD ligands need `CCD_` prefix.
6. **Protenix checkpoint**: Must be 1.4G. If 476M, corrupted — re-download.
7. **Chai-1 CLI**: `chai-lab fold` not `chai fold`. Positional args, not `--input`.
8. **Chai-1 scores**: in `scores.model_idx_*.npz` (numpy), not JSON. Load with `np.load(f)['ptm']`.
9. **IntelliFold-2**: Must pass `--use_msa_server` or it errors on missing MSA.
10. **OpenFold3 CLI**: `run_openfold predict` not `openfold predict`. Three env vars required (CUDA_HOME / CUTLASS_PATH / TORCH_CUDA_ARCH_LIST). SIX source patches in the conda env (see "Six patches" section above): 4 input-bug fixes + 2 infrastructure fixes (try/finally cleanup, PID-namespaced default tmpdir).
11. **OpenFold3 parallel runs**: with patches 5+6 applied, concurrent invocations are race-free out of the box (each process gets its own `/tmp/of3-of-<user>/colabfold_msas_<pid>/`). Without those patches, must pass per-case `--runner-yaml` setting `msa_computation_settings.msa_output_directory` to a unique tmpdir.
12. **ColabFold server proxy**: `HTTPS_PROXY=http://127.0.0.1:7892` already in env globally (Boltz-2/Chai-1/IntelliFold/OpenFold3 inherit).
13. **First-run downloads**: Boltz-2 (~7.6G), Chai-1 (~1.2G ESM2), IntelliFold (~2G), OpenFold3 (~2.2G) auto-download weights on first run.
14. **RF3 CLI**: command is `rf3 fold`, uses Hydra config syntax (`inputs=...` not `--inputs`). Positional-style key=value args.
15. **RF3 no built-in MSA**: unlike all other models, RF3 does not search MSAs internally. For best accuracy, provide pre-computed .a3m files per chain via `msa_files=[chainA.a3m,chainB.a3m]`. For benchmark comparisons, can run without MSA.
16. **RF3 install (2026-05-22)**: conda `rf3` (Python 3.12) with `rc-foundry[all]`. Install was in progress at session end; verify with `conda activate rf3 && rf3 --help`.
