# FoldBenchmark

Systematic benchmark of biomolecular structure prediction methods across 5 application
scenarios (23 test systems). Currently 6 models benchmarked; AlphaFast is integrated
but the database download is in progress.

**Quick links**:
[Installation](docs/INSTALL.md) ·
[Per-model usage](docs/MODELS.md) ·
[Input formats](docs/INPUT_FORMATS.md) ·
[Troubleshooting](docs/TROUBLESHOOTING.md)

---

## Quick Start

If everything is already installed (e.g. on Zeus), running the benchmark end-to-end
takes three commands:

```bash
cd /data2/zcwang/FoldBenchmark

# 1. Generate inputs from PDB IDs (already done — only re-run if you add cases)
python scripts/prepare_inputs.py

# 2. Run the benchmark (one model on one scenario shown here)
bash scripts/run_benchmark.sh --model boltz2 --scenario monomer --gpu 0

# 3. Collect results into CSV + summary
python scripts/collect_results.py
```

To run a single case for sanity-checking after a fresh install:

```bash
bash scripts/run_single_model.sh boltz2 monomer 1UBQ_ubiquitin 0
```

For the full setup-from-scratch path including conda envs and Docker, see
[docs/INSTALL.md](docs/INSTALL.md).

---

## Models

| Model | Version | Status | Backend | MSA Method | License |
|-------|---------|--------|---------|------------|---------|
| AlphaFold 3 | v3.0.2 | benchmarked | Docker | JackHMMER (sharded local DB) | CC BY-NC-SA 4.0 |
| Boltz-2 | v2.2.1 | benchmarked | conda `boltz2` | ColabFold server | MIT |
| OpenFold3 | v0.4.1 | benchmarked | conda `openfold3` | ColabFold server | Apache 2.0 |
| Protenix | latest | benchmarked | conda `protenix` | Local MSA | Apache 2.0 |
| Chai-1 | latest | benchmarked | conda `chai1` | ColabFold server | Apache 2.0 |
| IntelliFold-2 | latest | benchmarked | conda `intellifold` | ColabFold server | Apache 2.0 |
| AlphaFast | v0.x | DB downloading | Docker | MMseqs2 GPU | CC BY-NC-SA 4.0 |

See [docs/MODELS.md](docs/MODELS.md) for the verified-working CLI command, input format,
and gotchas of each model.

---

## Results Summary

### Completion Rate

| Model | Success | Failed | Notes |
|-------|---------|--------|-------|
| AlphaFold 3 v3.0.2 | **23/23** | 0 | Gold standard |
| Boltz-2 v2.2.1 | **23/23** | 0 | Fastest + highest pTM |
| Protenix | 19/23 | 4 | RNA not supported |
| Chai-1 | 20/23 | 3 | RNA not supported |
| IntelliFold-2 | **23/23** | 0 | All scenarios work |
| OpenFold3 v0.4.1 | 7/23 | 16 | ColabFold MSA unstable in China |
| AlphaFast | pending | — | DB still downloading |

### Average pTM by Scenario (higher = better)

| Scenario | AF3 | Boltz-2 | Protenix | Chai-1 | IntelliFold-2 | OpenFold3 |
|----------|-----|---------|----------|--------|---------------|-----------|
| Protein-Protein | 0.92 | **0.94** | **0.94** | - | 0.86 | - |
| Protein-Ligand | 0.89 | **0.95** | **0.94** | - | 0.85 | - |
| Protein-RNA | 0.51 | **0.56** | FAIL | FAIL | 0.45 | - |
| Monomer | 0.69 | **0.83** | **0.83** | - | 0.65 | - |
| Antibody-Antigen | 0.73 | **0.89** | 0.76 | - | 0.71 | - |

### Average Speed (seconds/system)

| Scenario | AF3 | Boltz-2 | Protenix | Chai-1 | IntelliFold-2 |
|----------|-----|---------|----------|--------|---------------|
| Protein-Protein | 236 | **53** | 377 | 364 | 84 |
| Protein-Ligand | 255 | **51** | 110 | 130 | 84 |
| Protein-RNA | 403 | **60** | - | - | 133 |
| Monomer | 176 | **45** | 98 | 89 | **52** |
| Antibody-Antigen | 392 | **68** | 392 | 379 | 129 |

### Key Findings

1. **Boltz-2** leads in both accuracy (pTM) and speed across all scenarios.
2. **Protenix** matches Boltz-2 accuracy for PPI/ligand/monomer but fails on RNA.
3. **AF3** is the most reliable (23/23) but slowest due to local MSA. Sharded databases
   bring it down from ~5 minutes to ~50 seconds of MSA time per case.
4. **IntelliFold-2** handles all scenarios but with lower accuracy.
5. **RNA prediction** remains challenging — only AF3, Boltz-2, and IntelliFold-2 can
   handle it at all.
6. **Antibody-antigen** shows the largest accuracy spread between models.

For the full per-case results table, see [results/benchmark_results.csv](results/benchmark_results.csv)
and [results/summary.md](results/summary.md).

---

## Test Systems (5 scenarios × ~5 cases = 23 total)

| Scenario | Cases | Description |
|----------|-------|-------------|
| protein_protein | 4 | Homodimers (2PV7), heterodimers (1BRS, 1EMV, 3HFM) |
| protein_ligand | 5 | HIV protease, CDK2, BRAF, SARS-CoV-2 Mpro/3CL |
| protein_rna | 4 | tRNA synthetase, U1A-RNA, FUS-RRM |
| monomer | 5 | Ubiquitin, crambin, myoglobin, GB1, Trp-cage |
| antibody_antigen | 5 | Trastuzumab-HER2, RBD-neutralizing Ab, etc. |

Full list with PDB IDs is in `scripts/prepare_inputs.py`.

---

## Project Layout

```
FoldBenchmark/
├── README.md                            # this file
├── docs/
│   ├── INSTALL.md                       # how to set up all 7 models
│   ├── MODELS.md                        # per-model CLI + gotchas
│   ├── INPUT_FORMATS.md                 # 5 input formats side-by-side
│   └── TROUBLESHOOTING.md               # known issues + fixes
├── inputs/                              # all model-specific input files
│   └── {scenario}/
│       ├── af3_json/                    # AF3 + AlphaFast
│       ├── boltz2_yaml/                 # Boltz-2 + IntelliFold-2
│       ├── chai1_fasta/                 # Chai-1
│       ├── protenix_json/               # Protenix
│       └── openfold3_json/              # OpenFold3
├── outputs/                             # raw model outputs (gitignored)
│   └── {model}/{scenario}/{case}/
├── scripts/
│   ├── prepare_inputs.py                # PDB → all 5 input formats
│   ├── run_benchmark.sh                 # master runner
│   ├── run_single_model.sh              # single (model, scenario, case)
│   └── collect_results.py               # outputs/ → CSV + summary
└── results/
    ├── timing.csv                       # per-case wall clock
    ├── benchmark_results.csv            # pTM, pLDDT, ranking_score, timing
    └── summary.md                       # human-readable summary
```

---

## Adding new models or test cases

- **New test case**: Add an entry to `TEST_CASES` in `scripts/prepare_inputs.py`,
  rerun `python scripts/prepare_inputs.py`. The script auto-fetches sequences from
  RCSB and writes all 5 input formats. See
  [docs/INPUT_FORMATS.md](docs/INPUT_FORMATS.md#auto-conversion) for the schema.

- **New model**: Add a `case` branch in `scripts/run_single_model.sh`. Make sure
  the model writes a `.cif` file to its output directory, otherwise the "already done"
  detection in the runner will rerun it forever. See
  [docs/MODELS.md](docs/MODELS.md) for the structure of the existing branches.

- **New scenario**: Create `inputs/{new_scenario}/` and add a corresponding entry
  to `TEST_CASES`. The runner auto-discovers any directory under `inputs/`.

---

## Hardware (reference setup)

- 4× NVIDIA RTX 4090 (48 GB each)
- 64 CPU cores (Intel Xeon Silver 4514Y)
- 314 GB RAM
- AF3 sharded databases: 397 GB on NVMe SSD (`/data2`)
- AlphaFast MMseqs2 database (planned): ~800 GB on HDD (`/hdd01`)

The benchmark scales linearly with GPU count if you run different models on different
GPUs in parallel. With 4 GPUs the full 6-model × 23-case benchmark takes ~2 hours.

---

## License

Code in this repository: MIT.

Each model's outputs are governed by that model's license — see the Models table above.
AF3 and AlphaFast outputs in particular are CC BY-NC-SA 4.0 (non-commercial only).
