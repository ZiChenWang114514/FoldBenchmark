---
name: fold-bench
description: Run the FoldBenchmark comparative benchmark across 8 structure prediction models (AF3, AlphaFast, Boltz-2, OpenFold3, Protenix, Chai-1, IntelliFold-2, RoseTTAFold3). TRIGGER when the user asks to benchmark fold models, compare structure predictions, add new test cases, add new models to the benchmark, or check benchmark results. DO NOT TRIGGER for running a single model on a single input — use af3-local or fold-models instead.
---

# fold-bench

Systematic benchmark of **8** biomolecular structure prediction models at `/data2/zcwang/FoldBenchmark/`.
**GitHub**: https://github.com/ZiChenWang114514/FoldBenchmark (latest: commit `13364aa`)

## When this skill applies

- "跑一下 benchmark / 对比一下这几个模型"
- "benchmark 跑完了吗 / 看看结果"
- "加一个新的测试体系 / 加一个新模型到 benchmark"
- "哪个模型在 PPI 上最好"
- Any cross-model comparison of structure prediction accuracy or speed

## Latest Benchmark Results (2026-05-07)

22 test cases total: 4 PPI + 5 ligand + 3 RNA + 5 monomer + 5 antibody.
(Original 23 trimmed to 22 — 5V3F and 4TZX were RNA-only PDB entries with no protein chain.)

### Completion Rate

| Model | Success | Notes |
|-------|---------|-------|
| AF3 v3.0.2 | **22/22** | Gold standard, sharded local JackHMMER |
| AlphaFast v1.0 | **22/22** | AF3 + GPU MMseqs2; 4-GPU sharded; batch mode required |
| Boltz-2 v2.2.1 | **22/22** | Best speed/accuracy tradeoff |
| Protenix | **22/22** | Confirmed RNA support after input bug fix |
| Chai-1 | **22/22** | Confirmed RNA support after input bug fix |
| IntelliFold-2 | **22/22** | All scenarios work |
| OpenFold3 v0.4.1 | **22/22** | 6 source patches: msa-dedup width / ordinal-rank res_id / makedirs / template-remap try-except / try-finally cleanup / PID-namespaced default tmpdir |
| RoseTTAFold3 v0.1.12 (Foundry) | **22/22** | Zero-shot (no paired MSA); multi-chain pTM lower as expected |

### pTM by Scenario

| Scenario | AF3 | AlphaFast | Boltz-2 | Protenix | Chai-1 | IntelliFold | OpenFold3 | RF3 |
|----------|-----|-----------|---------|----------|--------|-------------|-----------|-----|
| PPI | 0.92 | 0.91 | 0.94 | 0.94 | **0.96** | 0.86 | 0.88 | 0.32† |
| Ligand | 0.89 | 0.90 | 0.95 | 0.94 | **0.94** | 0.85 | 0.74 | 0.45† |
| RNA | 0.77 | 0.76 | **0.90** | 0.88 | 0.88 | 0.79 | 0.61 | 0.56† |
| Monomer | 0.69 | 0.70 | 0.83 | 0.83 | **0.84** | 0.64 | 0.59 | 0.61† |
| Antibody | 0.73 | 0.75 | **0.89** | 0.76 | 0.84 | 0.71 | 0.73 | 0.53† |

† RF3 zero-shot (no MSA); pTM metric may differ from AF3-style; multi-chain depressed by lack of paired MSA.

### Speed (s/case)

| Scenario | AF3 | AlphaFast | Boltz-2 | Protenix | Chai-1 | IntelliFold | OpenFold3 | RF3 |
|----------|-----|-----------|---------|----------|--------|-------------|-----------|-----|
| PPI | 236 | 142 | **53** | 376 | 364 | 83 | 127 | 65 |
| Ligand | 255 | 135 | **51** | 110 | 130 | 84 | 129 | 63 |
| RNA | 338 | 208 | **115** | 168 | 134 | 91 | 122 | 71 |
| Monomer | 176 | 109 | **45** | 98 | 88 | 52 | 102 | **42** |
| Antibody | 392 | 179 | **68** | 392 | 379 | 129 | 204 | 95 |

## Project layout

```
/data2/zcwang/FoldBenchmark/
├── inputs/{scenario}/{af3_json,boltz2_yaml,chai1_fasta,protenix_json,openfold3_json,rf3_json}/
├── outputs/{model}/{scenario}/{case}/
├── scripts/
│   ├── config.sh                # Machine-specific paths (Zeus defaults; copy to config.local.sh for other users)
│   ├── prepare_inputs.py        # PDB → all input formats (RNA chain IDs verified)
│   ├── run_benchmark.sh         # Master runner (per-case, includes rf3)
│   ├── run_single_model.sh      # Per-model runner with all env workarounds
│   ├── run_alphafast_batch.sh   # AlphaFast scenario-batch runner (REQUIRED for perf)
│   └── collect_results.py       # Results → CSV + summary (reads Chai-1 .npz)
├── docs/
│   ├── INSTALL.md               # 8 models setup
│   ├── MODELS.md                # per-model CLI + gotchas
│   ├── INPUT_FORMATS.md         # 6 input formats side-by-side
│   └── TROUBLESHOOTING.md       # known issues + fixes
├── results/{timing.csv, benchmark_results.csv, summary.md}
└── .gitignore
```

## 8 Models — Verified CLI

| Model | Env | CLI | Input format |
|-------|-----|-----|-------------|
| **AF3** | Docker `alphafold3` | `python3 run_alphafold.py` | AF3 JSON |
| **AlphaFast** | native uv venv `/data2/zcwang/af3/alphafast/.venv` | `bash scripts/run_alphafast_all_in_one.sh` | AF3 JSON (all-in-one batch, 推荐) |
| **Boltz-2** | conda `boltz2` | `boltz predict input.yaml` | YAML |
| **OpenFold3** | conda `openfold3` | `run_openfold predict --query-json` | OpenFold3 JSON |
| **Protenix** | conda `protenix` | `protenix pred -i input.json` | Protenix JSON |
| **Chai-1** | conda `chai1` | `chai-lab fold input.fasta output/` | FASTA |
| **IntelliFold-2** | conda `intellifold` | `intellifold predict input.yaml --out_dir` + `--use_msa_server` | YAML (Boltz-2 format) |
| **RoseTTAFold3** | conda `rf3` | `rf3 fold inputs=input.json out_dir=output/ ckpt_path=...` | RF3 JSON (components list) |

**Per-model input format** (each is incompatible with the others):
- AF3 JSON: `{"sequences": [{"protein": {"id": ["A"], "sequence": "..."}}], ...}`
- Protenix JSON: `[{"sequences": [{"proteinChain": {"sequence": "...", "count": 1}}], ...}]`
- OpenFold3 JSON: `{"queries": {"name": {"chains": [{"molecule_type": "protein", "chain_ids": "A", "sequence": "..."}]}}}`
- Boltz-2/IntelliFold YAML: `sequences: [{protein: {id: A, sequence: ...}}]`
- Chai-1 FASTA: `>protein|name=chain_A\nSEQUENCE`
- RF3 JSON: `{"name": "case", "components": [{"seq": "...", "chain_id": "A"}, {"smiles": "..."}]}`

## Running the benchmark

```bash
cd /data2/zcwang/FoldBenchmark

# Per-case across all 7 non-AlphaFast models (includes rf3)
bash scripts/run_benchmark.sh --gpu 0
bash scripts/run_benchmark.sh --model af3 --gpu 3
bash scripts/run_benchmark.sh --model rf3 --gpu 0
bash scripts/run_benchmark.sh --scenario monomer --gpu 0

# AlphaFast: 推荐 all-in-one batch（22个case单次DB扫描，最快）
bash scripts/run_alphafast_all_in_one.sh        # 全部22 cases，DB只扫一遍，75s/case
# 若只跑某个scenario（次优，DB扫5次）：
# bash scripts/run_alphafast_batch.sh monomer

# Collect (parses Chai-1 .npz too)
python scripts/collect_results.py
```

## Adding new test cases / models

- **New test case**: Add entry to `TEST_CASES` in `scripts/prepare_inputs.py`. **CRITICAL**: verify chain IDs against RCSB — earlier cases had wrong chain IDs and silently produced bunk inputs (e.g. RNA chains pointing at protein chains, giving fake homodimer benchmarks).
- **New model**: Add a `case` branch in `scripts/run_single_model.sh`.
- **New scenario**: Create `inputs/{new_scenario}/`.

## Known issues and fixes (verified 2026-05-07)

### AF3
1. **AF3 RNA + sharded DB**: v3.0.2 bug in `msa.py:312` — Nhmmer constructor missing `z_value`. Fixed by patching local source and volume-mounting into Docker (`run_single_model.sh` already does this).

### AlphaFast
2. **DBs don't fit on a single 4090**: uniref90_padded 49G, mgnify_padded 108G > 48G. **Must** shard across 4 GPUs via `CUDA_VISIBLE_DEVICES=0,1,2,3` + `MMSEQS_USE_ALL_GPUS=1`. Latter requires patch in `src/alphafold3/data/tools/{mmseqs,mmseqs_batch,mmseqs_template,foldseek}.py` to honor the env var (vanilla AlphaFast hardcodes single-GPU).
3. **All-in-one batch 最快**: 22个case放入单次batch，DB只扫一遍，实测 75s/case（摊销）。per-scenario batch（`run_alphafast_batch.sh`）扫5次，约200s/case。per-case mode 最慢（每次扫全库）。**默认用 `run_alphafast_all_in_one.sh`**。
4. **HF mirror download is unreliable**: stale `.incomplete` files reassemble into corrupt zst. Built RNA DBs locally instead from `/data/zxhuang/Shared/genetic_database/{nt_rna,rfam,rnacentral}*.fasta` via `mmseqs createdb --dbtype 2` + `mmseqs makepaddedseqdb`. 22 min total.
5. **GLIBCXX**: `LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libstdc++.so.6` mandatory (cpp.so built with system GCC 13).

### Boltz-2
6. **CUDA 13.0 nvrtc**: Must `export LD_LIBRARY_PATH="...nvidia/cu13/lib:..."` or `torch.det()` crashes.
7. **Ligand YAML**: Use `ligand:` entity with `smiles:`/`ccd:` sub-field. NOT `smiles:` as top-level entity.

### Protenix
8. **JSON format**: `proteinChain`/`rnaSequence`/`dnaSequence` (NOT `protein`/`rna`/`dna`). CCD ligands need `CCD_` prefix.
9. **Checkpoint**: Must be 1.4G. If 476M, corrupted — re-download.
10. **Does support RNA**: earlier "fails on RNA" was caused by buggy inputs (wrong chain IDs).

### Chai-1
11. **CLI**: `chai-lab fold` not `chai fold`. Positional args.
12. **Score format**: Confidences in `scores.model_idx_*.npz` (numpy format, not JSON). `collect_results.py` now parses these via numpy.
13. **Does support RNA**: same as Protenix — input fix unlocked it.

### OpenFold3
14. **JIT compile env**: requires THREE env vars to compile DeepSpeed4Science's evoformer_attn:
    - `CUDA_HOME=/usr/local/cuda` (conda env only ships runtime libs)
    - `CUTLASS_PATH=/data2/zcwang/structure_prediction/openfold3/cutlass` (CUTLASS 3.5+ checkout)
    - `TORCH_CUDA_ARCH_LIST=8.9` (default kernel only ships 70/80/86/90, not 4090's SM 8.9)
    Without these, JIT fails with cryptic `Unable to JIT load... due to hardware/software issue. None`.
15. **MSA dedup numpy 2.x bug**: `msa.py:create_main` uses void-view `np.isin` for dedup. Fails with `DTypePromotionError` when paired-MSA width ≠ main-MSA width (every multi-chain input). Patched at `/data/zcwang/anaconda3/envs/openfold3/lib/python3.11/site-packages/openfold3/core/data/pipelines/sample_processing/msa.py` to skip dedup when widths mismatch.
16. **Templates**: `--use-templates false` ONLY skips template ALIGNMENTS during inference — it does NOT skip the pdb70.m8 chain-remap step in `query_format_main()`. That step calls RCSB GraphQL and crashes if a hit (e.g. `8d35` for 6LU7/7RN1) returns empty `polymer_entities`. Patched `colabfold_msa_server.py:820` to wrap the remap in try/except and `return` on RuntimeError → templates skipped, MSA proceeds.
17. **`map_msas_to_tokens` IndexError on non-1-based residues**: `msa_column_positions = res_id - 1` fails when PDB residue numbering starts at 2 (e.g. 4LDE BRAF, 7RN1 Mpro, 1ASY tRNA-synth) → `index N out of bounds for size N`. Patched `featurization/msa.py:193` to use `np.unique(res_id, return_inverse=True)` for ordinal rank.
18. **Race condition on shared `/tmp/of3-of-zcwang/colabfold_msas/`** — root-fixed in the conda env, not just the benchmark. When multiple GPU instances ran concurrently, one's `cleanup()` would `rmtree` `raw/paired/<hash>/` while another was still writing `out.tar.gz`. Three patches now make the issue impossible:
    - `colabfold_msa_server.py:252` `os.mkdir → os.makedirs(exist_ok=True)` (defensive parent-dir).
    - `colabfold_msa_server.py:1014` (`MsaComputationSettings.create_dir`) — default `msa_output_directory` now PID-namespaced (`colabfold_msas_<pid>` instead of `colabfold_msas`).
    - `run_openfold.py:194-203` — `expt_runner.run()` wrapped in `try/finally` so `cleanup()` runs even when run raises; no leftover `raw/` to contaminate the next process.
    Verified by running 1BRS+1HSG concurrently on GPU 0/1, both succeed and `/tmp/of3-of-zcwang/` is clean afterward. The benchmark's per-case `--runner-yaml` is now redundant (kept as defense-in-depth).
19. **Skip-logic bug**: `run_single_model.sh` used to use `ls "${OUTPUTS}/${CASE_NAME}"/*.cif` which doesn't recurse into OpenFold3's nested `<case>/seed_*/sample_*/` layout — re-ran completed cases needlessly. Now uses recursive `find ... -name '*.cif'`.

### IntelliFold-2
20. **Required flag**: must pass `--use_msa_server` even if it sounds optional (no fallback).

### General
21. **ColabFold proxy**: `HTTPS_PROXY=http://127.0.0.1:7892` already in env (Boltz-2/Chai-1/IntelliFold/OpenFold3 use it).
22. **Test data validation**: ALWAYS verify chain IDs from RCSB match what TEST_CASES specifies. Past bug: 1ASY/1URN/2AZ0 had wrong RNA chain IDs → all "RNA" outputs were actually protein homodimers.
