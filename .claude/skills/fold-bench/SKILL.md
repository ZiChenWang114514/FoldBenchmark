---
name: fold-bench
description: Run the FoldBenchmark comparative benchmark across 9 structure prediction models (AF3, AlphaFast, Boltz-2, OpenFold3, Protenix, Chai-1, IntelliFold-2, RoseTTAFold3, ESMFold2). TRIGGER when the user asks to benchmark fold models, compare structure predictions, add new test cases, add new models to the benchmark, or check benchmark results. DO NOT TRIGGER for running a single model on a single input — use af3-local or fold-models instead. 35 test cases.
---

# fold-bench

Systematic benchmark of **9** biomolecular structure prediction models at `/data2/zcwang/FoldBenchmark/`.
**GitHub**: https://github.com/ZiChenWang114514/FoldBenchmark (latest: commit `8403f23`)

## When this skill applies

- "跑一下 benchmark / 对比一下这几个模型"
- "benchmark 跑完了吗 / 看看结果"
- "加一个新的测试体系 / 加一个新模型到 benchmark"
- "哪个模型在 PPI 上最好"
- Any cross-model comparison of structure prediction accuracy or speed

## Latest Benchmark Results (2026-05-24, 35 cases, 9 scenarios)

35 test cases total: 4 PPI + 5 ligand + 3 RNA + 5 monomer + 5 antibody + 4 protein_dna + 3 homo_multimer + 3 metal_ion + 3 covalent_mod.

### Completion Rate

| Model | Success | Notes |
|-------|---------|-------|
| AF3 v3.0.2 | **35/35** | Gold standard, sharded local JackHMMER |
| AlphaFast v1.0 | **35/35** | AF3 + GPU MMseqs2; 4-GPU sharded; batch mode required |
| Boltz-2 v2.2.1 | **35/35** | Best speed/accuracy tradeoff |
| Protenix | **35/35** | Confirmed RNA support after input bug fix |
| Chai-1 | **35/35** | Confirmed RNA support after input bug fix |
| IntelliFold-2 | **35/35** | All scenarios work |
| OpenFold3 v0.4.1 | **35/35** | 6 source patches: msa-dedup width / ordinal-rank res_id / makedirs / template-remap try-except / try-finally cleanup / PID-namespaced default tmpdir |
| RoseTTAFold3 v0.1.12 (Foundry) | **35/35** | Zero-shot (no paired MSA); multi-chain pTM lower as expected |
| ESMFold2 (Biohub, 2026-05-27) | **35/35** | No MSA; ESMCFOLD_CCD_PATH=local; ESMC-6B backbone ~27 GB pre-downloaded |

### pTM by Scenario

| Scenario | AF3 | AlphaFast | Boltz-2 | Protenix | Chai-1 | IntelliFold | OpenFold3 | RF3 | ESMFold2 |
|----------|-----|-----------|---------|----------|--------|-------------|-----------|-----|----------|
| PPI | 0.92 | 0.91 | 0.94 | 0.94 | **0.95** | 0.86 | 0.88 | 0.31† | 0.89 |
| Ligand | 0.89 | 0.90 | **0.95** | 0.94 | 0.94 | 0.84 | 0.89 | 0.45† | 0.91 |
| RNA | 0.77 | 0.76 | 0.87 | **0.88** | 0.88 | 0.79 | 0.84 | 0.56† | 0.74 |
| Monomer | 0.69 | 0.70 | 0.83 | 0.83 | **0.84** | 0.64 | 0.59 | 0.62† | 0.63 |
| Antibody | 0.73 | 0.75 | **0.89** | 0.76 | 0.83 | 0.71 | 0.66 | 0.53† | 0.68 |
| DNA | 0.89 | 0.89 | **0.97** | 0.89 | 0.94 | 0.85 | 0.87 | 0.75† | 0.85 |
| Homo-Multimer | 0.88 | 0.89 | 0.94 | **0.94** | 0.93 | 0.82 | 0.88 | 0.49† | 0.78 |
| Metal Ion | 0.97 | 0.96 | **0.98** | 0.98 | 0.98 | 0.93 | 0.97 | 0.36† | 0.96 |
| Covalent Mod | 0.93 | 0.93 | **0.96** | 0.95 | 0.92 | 0.86 | 0.94 | 0.47† | 0.90 |

† RF3 zero-shot (no MSA); pTM metric may differ from AF3-style; multi-chain depressed by lack of paired MSA.

### Speed (s/case)

| Scenario | AF3 | AlphaFast | Boltz-2 | Protenix | Chai-1 | IntelliFold | OpenFold3 | RF3 | ESMFold2 |
|----------|-----|-----------|---------|----------|--------|-------------|-----------|-----|----------|
| PPI | 283 | **52** | 64 | 119 | 142 | 97 | 140 | 60 | 30 |
| Ligand | 301 | **52** | 63 | 125 | 121 | 94 | 138 | 55 | 26 |
| RNA | 351 | 52 | 74 | 146 | 147 | 113 | 141 | **49** | 27 |
| Monomer | 210 | 52 | 57 | 126 | 96 | 58 | 129 | **29** | **20** |
| Antibody | 462 | **52** | 110 | 153 | 215 | 168 | 195 | 62 | 40 |
| DNA | 206 | 52 | 88 | 118 | 109 | 81 | 129 | **38** | **20** |
| Homo-Multimer | 239 | 52 | 85 | 118 | 169 | 107 | 141 | **46** | 29 |
| Metal Ion | 265 | 52 | 93 | 121 | 130 | 119 | 134 | **40** | 27 |
| Covalent Mod | 536 | 52 | 155 | 130 | 114 | 116 | 136 | **42** | 23 |

## Project layout

```
/data2/zcwang/FoldBenchmark/
├── inputs/{scenario}/{af3_json,boltz2_yaml,chai1_fasta,protenix_json,openfold3_json,rf3_json}/
├── outputs/{model}/{scenario}/{case}/
├── scripts/
│   ├── config.sh                # Machine-specific paths (Zeus defaults; copy to config.local.sh for other users)
│   ├── prepare_inputs.py               # PDB → 6 格式（含 chain ID auto-remap）
│   ├── prepare_inputs_from_fasta.py    # FASTA/UniProt → 6 格式 → inputs/screening/
│   ├── screen.py                       # 过滤+排名+共识分+CIF复制+Markdown报告
│   ├── run_benchmark.sh                # 主运行器（+8 新参数，含 FASTA/screening）
│   ├── run_single_model.sh             # 单模型运行器（含全部 env 补丁）
│   ├── run_alphafast_batch.sh          # AlphaFast 场景批处理（REQUIRED for perf）
│   ├── master_benchmark.sh             # 一键重跑全部 35×8
│   ├── rerun_protenix_anomalous.sh     # 重跑 Protenix JIT 异常 case
│   └── collect_results.py             # outputs/ → CSV + summary（动态扫描 screening/）
├── docs/
│   ├── INSTALL.md               # 8 models setup
│   ├── MODELS.md                # per-model CLI + gotchas
│   ├── INPUT_FORMATS.md         # 6 input formats side-by-side
│   └── TROUBLESHOOTING.md       # known issues + fixes
├── results/{timing.csv, benchmark_results.csv, summary.md}
└── .gitignore
```

## 9 Models — Verified CLI

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
| **ESMFold2** | conda `esmfold2` | `python scripts/run_esmfold2.py --input ... --outdir ...` | AF3 JSON (reused) |

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

# AlphaFast: 推荐 all-in-one batch（35个case单次DB扫描，最快）
bash scripts/run_alphafast_all_in_one.sh        # 全部35 cases，DB只扫一遍，52s/case（摊销）
# 若只跑某个scenario（次优，DB扫5次）：
# bash scripts/run_alphafast_batch.sh monomer

bash scripts/master_benchmark.sh               # 一键重跑全部35×8，含自动清空+汇总

# Collect (parses Chai-1 .npz too)
python scripts/collect_results.py
```

## Batch Screening Mode (新序列 / 快速筛选)

### 新序列输入 (FASTA)

Chai-1 style FASTA — 与 Chai-1 fold 输入格式完全兼容：
```
>protein|name=chain_A
MTEYKLVVVGA...
>protein|name=chain_B
MARLKASEE...
>ligand|name=L1|smiles=O=C(NC...)...
>ligand|name=L2|ccd=ATP
>dna|name=D1
ATCGATCG
>rna|name=R1
AUGCAUGC
```

UniProt ID 列表（`--uniprot`）：每行一个 ID → monomer；两个空格分隔 → PPI。

```bash
# 独立生成 6 种格式到 inputs/screening/（可自定义 --name、--scenario）
python scripts/prepare_inputs_from_fasta.py --fasta proteins.fasta --name my_complex

# 端到端：FASTA + 预测 + top-N + 报告（一条命令）
bash scripts/run_benchmark.sh \
  --fasta proteins.fasta \
  --models "alphafast,boltz2" \
  --gpu 0 \
  --top-n 5 \
  --report

# UniProt ID 列表
bash scripts/run_benchmark.sh --uniprot targets.txt --models "rf3" --gpu 0
```

自动场景检测：`monomer` / `protein_protein` / `homo_multimer` / `protein_ligand` / `protein_rna` / `protein_dna`。Chain IDs 自动分配 A/B/C/...（最多 26 条链）。

### 结果筛选 (screen.py)

```bash
# 对已有结果排名，不重跑预测
bash scripts/run_benchmark.sh --screen-only --top-n 10 --by ptm --report

# 直接调用（更多控制）
python scripts/screen.py \
  --models boltz2,chai1 \
  --scenarios protein_ligand \
  --top-n 5 \
  --by ptm \           # ptm / plddt / ranking_score
  --copy-cif \         # 复制到 results/top_N/{case_name}/
  --report results/screen_report.md

# Benchmark case 子集
bash scripts/run_benchmark.sh \
  --cases "1BRS_barnase_barstar,1HSG_HIV_protease_indinavir" \
  --models "af3,boltz2" --gpu 0
```

### run_benchmark.sh 完整参数表

| 参数 | 说明 | 默认 |
|------|------|------|
| `--model NAME` | 单模型（旧用法） | 全部 |
| `--models "a,b"` | 多模型，逗号分隔（优先于 --model） | 全部 |
| `--scenario NAME` | 场景过滤 | 全部 |
| `--gpu N` | GPU 编号 | 0 |
| `--fasta FILE` | 新序列 FASTA 输入 | — |
| `--uniprot FILE` | UniProt ID 列表 | — |
| `--cases "a,b"` | case 名过滤，逗号分隔 | 全部 |
| `--top-n N` | 后处理：top-N 排名 + CIF 复制 | — |
| `--by METRIC` | 排序：ptm / plddt / ranking_score | ptm |
| `--report` | 生成 Markdown 报告 | 不生成 |
| `--screen-only` | 仅筛选，不跑预测 | 不跳过 |

---

## Adding new test cases / models

- **New test case**: Add entry to `TEST_CASES` in `scripts/prepare_inputs.py`. **CRITICAL**: verify chain IDs against RCSB — earlier cases had wrong chain IDs and silently produced bunk inputs (e.g. RNA chains pointing at protein chains, giving fake homodimer benchmarks).
- **New model**: Add a `case` branch in `scripts/run_single_model.sh`.
- **New scenario**: Create `inputs/{new_scenario}/`.

## Known issues and fixes (verified 2026-05-07)

### AF3
1. **AF3 RNA + sharded DB**: v3.0.2 bug in `msa.py:312` — Nhmmer constructor missing `z_value`. Fixed by patching local source and volume-mounting into Docker (`run_single_model.sh` already does this).

### AlphaFast
2. **DBs don't fit on a single 4090**: uniref90_padded 49G, mgnify_padded 108G > 48G. **Must** shard across 4 GPUs via `CUDA_VISIBLE_DEVICES=0,1,2,3` + `MMSEQS_USE_ALL_GPUS=1`. Latter requires patch in `src/alphafold3/data/tools/{mmseqs,mmseqs_batch,mmseqs_template,foldseek}.py` to honor the env var (vanilla AlphaFast hardcodes single-GPU).
3. **All-in-one batch 最快**: 35个case放入单次batch，DB只扫一遍，实测 52s/case（摊销）。per-scenario batch（`run_alphafast_batch.sh`）扫9次，约200s/case。per-case mode 最慢（每次扫全库）。**默认用 `run_alphafast_all_in_one.sh`**。
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
23. **Numeric PDB chain IDs**: PDBs like 1LMB use numeric chain IDs (`1`, `2`, `3`, `4`). AF3/AlphaFast require uppercase letter chain IDs (A-Z). `prepare_inputs.py` auto-remaps in `generate_af3_json()` when any chain ID is not a single uppercase letter. All downstream formats (Boltz-2/Chai-1/Protenix/RF3/OF3) inherit the remapped IDs. **When adding new cases, check RCSB auth_asym_ids**.
24. **Protenix JIT overhead on new entity types**: First run with a new entity type combination (e.g., DNA chains, homo-multimers) triggers CUDA kernel compilation, adding 800–1400 s. Subsequent cases complete in ~100–130 s. The `rerun_protenix_anomalous.sh` script can be used to re-time cases after warmup.

### ESMFold2
25. **ESMCFOLD_CCD_PATH**: Must set `ESMCFOLD_CCD_PATH=/data2/zcwang/structure_prediction/esmfold2/hf_cache/biohub_ESMFold2/ccd.pkl` or the processor tries to download `ccd.pkl` from HF hub (fails offline). Already set in `run_single_model.sh`.
26. **esmc_id local path**: `biohub_ESMFold2/config.json` has `esmc_id` patched to `/data2/.../biohub_ESMC_6B` (local path). Do not restore to `biohub/ESMC-6B` or it will try to download ~27 GB on every run.
27. **SMILES ligands skipped**: ESMFold2 `LigandInput` accepts CCD codes only. SMILES-only ligands print a warning and are dropped from the input. Affects protein_ligand and covalent_mod cases with SMILES-only ligands.
28. **wait_and_run.sh**: Use `bash scripts/wait_and_run.sh 0 -- --model esmfold2` to queue benchmark until GPU 0 is idle (polls every 60s, confirms 30s, then launches). Safe with concurrent Schrödinger/GROMACS jobs.
