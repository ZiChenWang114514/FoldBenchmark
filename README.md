# FoldBenchmark

Systematic benchmark of 7 biomolecular structure prediction models across 5 application
scenarios (22 test systems).

**Quick links**:
[Installation](docs/INSTALL.md) ·
[Per-model usage](docs/MODELS.md) ·
[Input formats](docs/INPUT_FORMATS.md) ·
[Troubleshooting](docs/TROUBLESHOOTING.md)

---

## Quick Start

### 1. Configure paths (first-time setup)

All model/database paths live in `scripts/config.sh`. The defaults point to the
reference installation on Zeus (`/data2/zcwang/…`). If you are a **different user on
the same machine**, copy and edit the file once — you will not need to touch it again:

```bash
cp scripts/config.sh scripts/config.local.sh   # gitignored
# Edit scripts/config.local.sh — update CONDA_BASE and any paths that differ
export FOLDBENCH_CONFIG=$PWD/scripts/config.local.sh
```

Key variables to check in your copy:

| Variable | What it points to |
|----------|-------------------|
| `CONDA_BASE` | Your anaconda/miniconda root (auto-detected if `conda` is in PATH) |
| `BOLTZ2_CU13_LIB` | `nvidia/cu13/lib` inside your `boltz2` conda env |
| `OPENFOLD_CACHE` | Dir containing `of3-p2-155k.pt` |
| `CUTLASS_PATH` | CUTLASS ≥3.5 checkout (required for OpenFold3 on RTX 4090) |
| `ALPHAFAST_DIR` | AlphaFast native venv install |
| `ALPHAFAST_DB_DIR` | MMseqs2 padded DBs (~388 GB protein + ~27 GB RNA) |
| `AF3_*` | AF3 Docker volumes (models, databases, patched msa.py) |

Shared resources on Zeus that **do not need to change** for any user:

| Resource | Path |
|----------|------|
| AF3 / AlphaFast model weights | `/data/zxhuang/Shared/Alphafold3params/` |
| Boltz-2 weights | `/data2/zxhuang/.boltz/` (symlinked) |

### 2. Run the benchmark

```bash
cd /data2/zcwang/FoldBenchmark   # or your clone

# Single model, single scenario — good sanity-check after fresh setup
bash scripts/run_single_model.sh boltz2 monomer 1UBQ_ubiquitin 0

# All models, all scenarios (one GPU, sequential)
bash scripts/run_benchmark.sh --gpu 0

# Filter by model or scenario
bash scripts/run_benchmark.sh --model boltz2 --scenario monomer --gpu 0

# AlphaFast: must use the batch runner (per-case mode is slower than AF3)
bash scripts/run_alphafast_batch.sh protein_protein
```

### 3. Collect results

```bash
python scripts/collect_results.py
# → results/benchmark_results.csv
# → results/timing.csv
# → results/summary.md
```

---

## Models

| Model | Version | Backend | MSA method | License |
|-------|---------|---------|------------|---------|
| AlphaFold 3 | v3.0.2 | Docker `alphafold3` | JackHMMER (sharded local DB) | CC BY-NC-SA 4.0 |
| AlphaFast | v1.0 (2026-04) | native uv venv | MMseqs2 GPU (5 padded DBs, 4× 4090 sharded) | CC BY-NC-SA 4.0 |
| Boltz-2 | v2.2.1 | conda `boltz2` | ColabFold server | MIT |
| Protenix | latest | conda `protenix` | Local MSA | Apache 2.0 |
| Chai-1 | latest | conda `chai1` | ColabFold server | Apache 2.0 |
| IntelliFold-2 | latest | conda `intellifold` | ColabFold server | Apache 2.0 |
| OpenFold3 | v0.4.1 | conda `openfold3` | ColabFold server | Apache 2.0 |

See [docs/MODELS.md](docs/MODELS.md) for verified CLI commands, input formats, and
per-model gotchas. See [docs/INSTALL.md](docs/INSTALL.md) for setup instructions.

---

## Results Summary

### Completion rate (2026-05-07, 22 cases)

| Model | Success | Notes |
|-------|---------|-------|
| AlphaFold 3 v3.0.2 | **22/22** | Gold standard |
| AlphaFast v1.0 | **22/22** | RNA DB built locally from FASTAs (HF mirror unreliable) |
| Boltz-2 v2.2.1 | **22/22** | Best speed/accuracy tradeoff |
| Protenix | **22/22** | RNA support confirmed after input bug fix |
| Chai-1 | **22/22** | RNA support confirmed after input bug fix |
| IntelliFold-2 | **22/22** | All scenarios |
| OpenFold3 v0.4.1 | **22/22** | Requires 6 source patches — see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |

### Average pTM by scenario (higher = better)

| Scenario | AF3 | AlphaFast | Boltz-2 | Protenix | Chai-1 | IntelliFold-2 | OpenFold3 |
|----------|-----|-----------|---------|----------|--------|---------------|-----------|
| Protein-Protein | 0.92 | 0.91 | 0.94 | 0.94 | **0.96** | 0.86 | 0.70 |
| Protein-Ligand | 0.89 | 0.90 | **0.95** | 0.94 | 0.94 | 0.85 | 0.74 |
| Protein-RNA | 0.77 | 0.76 | **0.90** | 0.88 | 0.88 | 0.79 | 0.53 |
| Monomer | 0.69 | 0.70 | 0.83 | 0.83 | **0.84** | 0.65 | 0.59 |
| Antibody-Antigen | 0.73 | 0.75 | **0.89** | 0.76 | 0.84 | 0.71 | 0.73 |

### Average speed (seconds/case)

| Scenario | AF3 | AlphaFast | Boltz-2 | Protenix | Chai-1 | IntelliFold-2 | OpenFold3 |
|----------|-----|-----------|---------|----------|--------|---------------|-----------|
| Protein-Protein | 236 | 142 | **53** | 377 | 364 | 84 | 126 |
| Protein-Ligand | 255 | 135 | **51** | 110 | 130 | 84 | 119 |
| Protein-RNA | 338 | 208 | **115** | 168 | 135 | **91** | 100 |
| Monomer | 176 | 109 | **45** | 98 | 89 | **52** | 102 |
| Antibody-Antigen | 392 | 179 | **68** | 392 | 379 | 129 | 184 |

AlphaFast timings are amortized across the per-scenario batch (one MMseqs2 queryDB +
JAX compilation cache shared across all cases). Per-case mode is *slower* than AF3.

### Key findings

1. **Chai-1** posts the highest pTM on PPI, ligand, and monomer scenarios.
2. **Boltz-2** is the best speed/accuracy tradeoff: fastest accurate model, top-tier
   pTM across all scenarios including RNA and antibody-antigen.
3. **AlphaFast** matches AF3 accuracy (same weights) and is 40–54% faster in batch mode.
4. **Protenix and Chai-1 do support RNA** — earlier failures were caused by wrong chain
   IDs in `prepare_inputs.py` (silently produced protein homodimers labelled as RNA pairs).
5. **OpenFold3** reaches 22/22 after six source patches (see Troubleshooting); pTM is
   10–20% lower than other models but the pipeline is now fully stable.

Full per-case results: [results/benchmark_results.csv](results/benchmark_results.csv)
and [results/summary.md](results/summary.md).

---

## Test Systems

22 cases across 5 scenarios:

| Scenario | Cases | Examples |
|----------|-------|---------|
| protein_protein | 4 | 1BRS barnase-barstar, 2PV7 homodimer, 3HFM lysozyme-Fab |
| protein_ligand | 5 | 1HSG HIV protease, 6LU7 Mpro-N3, 4LDE BRAF-vemurafenib |
| protein_rna | 3 | 1ASY tRNA-synthetase, 1URN U1A, 2AZ0 U1A-hairpin |
| monomer | 5 | 1UBQ ubiquitin, 1CRN crambin, 1MBN myoglobin |
| antibody_antigen | 5 | 4FQI trastuzumab-HER2, 7N4I RBD-neutralizing Ab |

Full list with PDB IDs is in `scripts/prepare_inputs.py`.

---

## Project Layout

```
FoldBenchmark/
├── README.md
├── docs/
│   ├── INSTALL.md              # set up all 7 models from scratch
│   ├── MODELS.md               # per-model CLI + gotchas
│   ├── INPUT_FORMATS.md        # 5 input formats side-by-side
│   └── TROUBLESHOOTING.md      # known issues + fixes
├── inputs/
│   └── {scenario}/
│       ├── af3_json/           # AF3 + AlphaFast
│       ├── boltz2_yaml/        # Boltz-2 + IntelliFold-2
│       ├── chai1_fasta/        # Chai-1
│       ├── protenix_json/      # Protenix
│       └── openfold3_json/     # OpenFold3
├── outputs/                    # raw model outputs (gitignored)
│   └── {model}/{scenario}/{case}/
├── scripts/
│   ├── config.sh               # all machine-specific paths (edit once per user)
│   ├── prepare_inputs.py       # PDB → all 5 input formats
│   ├── run_benchmark.sh        # master runner (all models / all scenarios)
│   ├── run_single_model.sh     # single (model, scenario, case, gpu)
│   ├── run_alphafast_batch.sh  # AlphaFast scenario-batch runner (required for perf)
│   └── collect_results.py      # outputs/ → CSV + summary
└── results/
    ├── benchmark_results.csv
    ├── timing.csv
    └── summary.md
```

---

## Adding new models or test cases

- **New test case**: Add an entry to `TEST_CASES` in `scripts/prepare_inputs.py` and
  rerun it. **Always verify chain IDs against RCSB** — wrong chain IDs silently produce
  bunk inputs (past bug: RNA chains pointed at protein chains).
- **New model**: Add a `case` branch in `scripts/run_single_model.sh`. The model must
  write a `.cif` file to its output directory (used by the skip-detection logic).
- **New scenario**: Create `inputs/{new_scenario}/` and add entries to `TEST_CASES`.

---

## Hardware (reference setup)

- 4× NVIDIA RTX 4090 (48 GB each)
- 2× Intel Xeon Silver 4514Y (64 threads total)
- 314 GB RAM
- ~400 GB NVMe for AF3 sharded databases
- ~415 GB for AlphaFast MMseqs2 databases (388 GB protein + 27 GB RNA)

With 4 GPUs, running all 7 models × 22 cases sequentially takes roughly 3–4 hours.
Models can be parallelized across GPUs with `--gpu N` flags.

---

## License

Code in this repository: MIT.

Each model's outputs are governed by that model's license (see Models table).
AF3 and AlphaFast outputs in particular are CC BY-NC-SA 4.0 (non-commercial only).
