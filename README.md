# FoldBenchmark

Systematic benchmark of **10** biomolecular structure prediction models across **18** scenarios (**81** test systems) on 4× RTX 4090.

**Quick links**:
[Installation](docs/INSTALL.md) ·
[Per-model usage](docs/MODELS.md) ·
[Input formats](docs/INPUT_FORMATS.md) ·
[Troubleshooting](docs/TROUBLESHOOTING.md)

---

## Results Summary (2026-05-24, 35 cases × 9 models = 315 runs; ESM3 added 2026-05-28 — full results pending)

### Overall ranking

| Model | Avg pTM | Avg Speed (s) | Completion | Highlight |
|-------|---------|---------------|------------|-----------|
| **Boltz-2** v2.2.1 | **0.92** | 85 | 35/35 | Best overall accuracy |
| **Chai-1** | 0.91 | 138 | 35/35 | Top on PPI (0.95) & monomer (0.84) |
| **Protenix** v2.0.0 | 0.89 | 129 | 35/35 | Strong RNA (0.88) & homo-multimer (0.94) |
| **AlphaFast** v1.0 | 0.85 | **52** | 35/35 | Fastest (batch mode, one DB scan) |
| **AlphaFold 3** v3.0.2 | 0.84 | 314 | 35/35 | Gold standard, slowest |
| **OpenFold3** v0.4.1 | 0.82 | 144 | 35/35 | Needs 6 source patches |
| **IntelliFold-2** | 0.80 | 105 | 35/35 | Moderate across all scenarios |
| **RoseTTAFold3** v0.1.12 | 0.51 | **47** | 35/35 | Zero-shot (no MSA); fastest monomer (29 s) |
| **ESMFold2** (Biohub) | 0.81 | **27** | 35/35 | Fastest (no MSA); CCD ligands only |

### pTM by scenario (higher = better)

| Scenario | AF3 | AlphaFast | Boltz-2 | Protenix | Chai-1 | IntelliFold-2 | OpenFold3 | RF3† | ESMFold2 |
|----------|-----|-----------|---------|----------|--------|---------------|-----------|------|----------|
| Protein-Protein (4) | 0.92 | 0.91 | 0.94 | 0.94 | **0.95** | 0.86 | 0.88 | 0.31 | 0.89 |
| Protein-Ligand (5) | 0.89 | 0.90 | **0.95** | 0.94 | 0.94 | 0.84 | 0.89 | 0.45 | 0.91 |
| Protein-RNA (3) | 0.77 | 0.76 | 0.87 | **0.88** | 0.88 | 0.79 | 0.84 | 0.56 | 0.74 |
| Monomer (5) | 0.69 | 0.70 | 0.83 | 0.83 | **0.84** | 0.64 | 0.59 | 0.62 | 0.63 |
| Antibody-Antigen (5) | 0.73 | 0.75 | **0.89** | 0.76 | 0.83 | 0.71 | 0.66 | 0.53 | 0.68 |
| Protein-DNA (4) | 0.89 | 0.89 | **0.97** | 0.89 | 0.94 | 0.85 | 0.87 | 0.75 | 0.85 |
| Homo-Multimer (3) | 0.88 | 0.89 | 0.94 | **0.94** | 0.93 | 0.82 | 0.88 | 0.49 | 0.78 |
| Metal Ion (3) | 0.97 | 0.96 | **0.98** | 0.98 | 0.98 | 0.93 | 0.97 | 0.36 | 0.96 |
| Covalent Mod (3) | 0.93 | 0.93 | **0.96** | 0.95 | 0.92 | 0.86 | 0.94 | 0.47 | 0.90 |

† RF3 zero-shot (Foundry v0.1.12, no MSA); pTM metric computed by RF3 may differ from AF3-style pTM. Multi-chain pTM depressed by lack of paired MSA.

### Speed (seconds/case, bold = fastest)

| Scenario | AF3 | AlphaFast | Boltz-2 | Protenix | Chai-1 | IntelliFold-2 | OpenFold3 | RF3 | ESMFold2 |
|----------|-----|-----------|---------|----------|--------|---------------|-----------|-----|----------|
| Protein-Protein | 283 | **52** | 64 | 119 | 142 | 97 | 140 | 60 | 30 |
| Protein-Ligand | 301 | **52** | 63 | 125 | 121 | 94 | 138 | 55 | 26 |
| Protein-RNA | 351 | 52 | 74 | 146 | 147 | 113 | 141 | **49** | 27 |
| Monomer | 210 | 52 | 57 | 126 | 96 | 58 | 129 | **29** | **20** |
| Antibody-Antigen | 462 | **52** | 110 | 153 | 215 | 168 | 195 | 62 | 40 |
| Protein-DNA | 206 | 52 | 88 | 118 | 109 | 81 | 129 | **38** | **20** |
| Homo-Multimer | 239 | 52 | 85 | 118 | 169 | 107 | 141 | **46** | 29 |
| Metal Ion | 265 | 52 | 93 | 121 | 130 | 119 | 134 | **40** | 27 |
| Covalent Mod | 536 | 52 | 155 | 130 | 114 | 116 | 136 | **42** | 23 |

AlphaFast timings are amortized across the all-in-one batch (all 35 cases, one MMseqs2 DB scan + one JAX compilation cache). Per-case mode is *slower* than AF3.

### Key findings

1. **Boltz-2** achieves the highest overall pTM (0.92 avg) with top scores on ligand (0.95), antibody (0.89), DNA (0.97), metal ion (0.98), and covalent mod (0.96) — the best speed/accuracy tradeoff at 85 s/case.
2. **Chai-1** leads on PPI (0.95) and monomer (0.84), consistently strong across all scenarios.
3. **AlphaFast all-in-one batch** achieves a flat **52 s/case** — 5–10× faster than AF3 (314 s avg), with only marginal pTM loss (0.85 vs 0.84).
4. **Protenix and Chai-1 support RNA** (pTM 0.88 each) — earlier failures were caused by wrong chain IDs in input preparation (silently produced protein homodimers).
5. **RoseTTAFold3** (Foundry v0.1.12) is the fastest model (**29–62 s/case** zero-shot), but pTM is substantially lower on multi-chain systems without paired MSA.
6. **OpenFold3** reaches 35/35 after six source patches; competitive on metal ion (0.97) and covalent mod (0.94), but needs CUTLASS 3.5 + SM 8.9 JIT setup.
7. **Protenix first-run JIT overhead**: new entity type combinations trigger CUDA kernel compilation (+800–1400 s on first case). Always warm up before timing.
8. **ESMFold2** (Biohub, 2026-05-27, MIT) achieves **27 s/case** — fastest single-model; no MSA required. pTM competitive on ligand (0.91), metal ion (0.96), and PPI (0.89); lower on monomer (0.63) and antibody (0.68). CCD ligands only (SMILES-only skipped).

Full per-case results: [results/benchmark_results.csv](results/benchmark_results.csv) and [results/summary.md](results/summary.md).

---

## Quick Start

### 1. Configure paths (first-time setup)

All model/database paths live in `scripts/config.sh`. The defaults point to the
reference installation on Zeus (`/data2/zcwang/…`). If you are a **different user on
the same machine**, copy and edit the file once:

```bash
cp scripts/config.sh scripts/config.local.sh   # gitignored
# Edit scripts/config.local.sh — update CONDA_BASE and any paths that differ
export FOLDBENCH_CONFIG=$PWD/scripts/config.local.sh
```

Key variables to check:

| Variable | What it points to |
|----------|-------------------|
| `CONDA_BASE` | Your anaconda/miniconda root (auto-detected if `conda` is in PATH) |
| `BOLTZ2_CU13_LIB` | `nvidia/cu13/lib` inside your `boltz2` conda env |
| `OPENFOLD_CACHE` | Dir containing `of3-p2-155k.pt` |
| `CUTLASS_PATH` | CUTLASS ≥3.5 checkout (required for OpenFold3 on RTX 4090) |
| `ALPHAFAST_DIR` | AlphaFast native venv install |
| `ALPHAFAST_DB_DIR` | MMseqs2 padded DBs (~388 GB protein + ~27 GB RNA) |
| `AF3_*` | AF3 Docker volumes (models, databases, patched msa.py) |

Shared resources on Zeus that do not need to change:

| Resource | Path |
|----------|------|
| AF3 / AlphaFast model weights | `/data/zxhuang/Shared/Alphafold3params/` |
| Boltz-2 weights | `/data2/zxhuang/.boltz/` (symlinked) |

### 2. Run the benchmark

```bash
cd /data2/zcwang/FoldBenchmark

# Single model, single scenario — good sanity-check after fresh setup
bash scripts/run_single_model.sh boltz2 monomer 1UBQ_ubiquitin 0

# All models, all scenarios (one GPU, sequential)
bash scripts/run_benchmark.sh --gpu 0

# Filter by model or scenario
bash scripts/run_benchmark.sh --model boltz2 --scenario monomer --gpu 0

# Multiple models
bash scripts/run_benchmark.sh --models "boltz2,chai1,rf3" --gpu 0

# AlphaFast all-in-one batch (all 35 cases, recommended)
bash scripts/run_alphafast_all_in_one.sh

# One-shot full benchmark (all 10 models × 35 cases)
bash scripts/master_benchmark.sh
```

### 3. Collect results

```bash
python scripts/collect_results.py
# → results/benchmark_results.csv
# → results/timing.csv
# → results/summary.md
```

### 4. New sequence prediction (batch screening mode)

```bash
# Predict a new FASTA with AlphaFast + Boltz-2, output top-5, generate report
bash scripts/run_benchmark.sh \
  --fasta my_proteins.fasta \
  --models "alphafast,boltz2" \
  --gpu 0 \
  --top-n 5 \
  --report

# UniProt ID list (one ID per line = monomer; two IDs space-separated = PPI)
bash scripts/run_benchmark.sh \
  --uniprot targets.txt \
  --models "rf3,boltz2" \
  --gpu 0 \
  --top-n 10 \
  --report

# Benchmark case sub-set only
bash scripts/run_benchmark.sh \
  --cases "1BRS_barnase_barstar,1HSG_HIV_protease_indinavir" \
  --models "af3,boltz2" \
  --gpu 0

# Screen/rank existing results without re-running predictions
bash scripts/run_benchmark.sh --screen-only --top-n 10 --by ptm --report

# screen.py directly (more control)
python scripts/screen.py \
  --models boltz2,chai1 \
  --top-n 5 \
  --by ptm \
  --copy-cif \
  --report results/screen_report.md
```

FASTA format (Chai-1 style):
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

### `run_benchmark.sh` parameter reference

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--model NAME` | Single model (legacy) | all |
| `--models "a,b"` | Multi-model, comma-separated (overrides `--model`) | all |
| `--scenario NAME` | Scenario filter | all |
| `--gpu N` | GPU ID | 0 |
| `--fasta FILE` | New sequence FASTA input | — |
| `--uniprot FILE` | UniProt ID list | — |
| `--cases "a,b"` | Case name filter, comma-separated | all |
| `--top-n N` | Post-processing: top-N ranking + CIF copy | — |
| `--by METRIC` | Sort metric: `ptm` / `plddt` / `ranking_score` | ptm |
| `--report` | Generate Markdown report | off |
| `--screen-only` | Screen existing results, skip predictions | off |

---

## Models

| Model | Version | Backend | MSA method | License |
|-------|---------|---------|------------|---------|
| AlphaFold 3 | v3.0.2 | Docker `alphafold3` | JackHMMER (sharded local DB) | CC BY-NC-SA 4.0 |
| AlphaFast | v1.0 (2026-04) | native uv venv | MMseqs2 GPU (5 padded DBs, 4× 4090 sharded) | CC BY-NC-SA 4.0 |
| Boltz-2 | v2.2.1 | conda `boltz2` | ColabFold server | MIT |
| Protenix | v2.0.0 | conda `protenix` | Local MSA | Apache 2.0 |
| Chai-1 | latest | conda `chai1` | ColabFold server | Apache 2.0 |
| IntelliFold-2 | latest | conda `intellifold` | ColabFold server | Apache 2.0 |
| OpenFold3 | v0.4.1 | conda `openfold3` | ColabFold server | Apache 2.0 |
| RoseTTAFold3 | v0.1.12 (Foundry) | conda `rf3` | Pre-computed .a3m (no built-in MSA) | BSD-3-Clause |
| ESMFold2 | 2026-05-27 | conda `esmfold2` (Python 3.12) | No MSA (zero-shot) | MIT |
| ESM3 | sm-open-v1 (1.4B) | conda `esm3` | No MSA (generative, zero-shot) | Cambrian non-commercial |

See [docs/MODELS.md](docs/MODELS.md) for verified CLI commands, input formats, and per-model gotchas. See [docs/INSTALL.md](docs/INSTALL.md) for setup instructions.

---

## Test Systems (81 cases, 18 scenarios)

| Scenario | # | Cases |
|----------|---|-------|
| protein_protein | 4 | 1BRS barnase-barstar, 1EMV trypsin-inhibitor, 2PV7 homodimer, 3HFM lysozyme-Fab |
| protein_ligand | 5 | 1HSG HIV protease-indinavir, 3HTB CDK2-inhibitor, 4LDE BRAF-vemurafenib, 6LU7 Mpro-N3, 7RN1 3CL-inhibitor |
| protein_rna | 3 | 1ASY tRNA-synthetase, 1URN U1A-RNA, 2AZ0 U1A-RNA-hairpin |
| monomer | 5 | 1CRN crambin, 1L2Y trp-cage, 1MBN myoglobin, 1UBQ ubiquitin, 2GB1 protein G |
| antibody_antigen | 5 | 1AHW ab-tissue-factor, 1DVF idiotope, 1MLC ab-lysozyme, 4FQI trastuzumab-HER2, 7N4I RBD-neutralizing-Ab |
| protein_dna | 4 | 1BL0 MarA-DNA, 1J1V DnaA-DNA, 1LMB lambda-repressor-DNA, 3HDD homeodomain-DNA |
| homo_multimer | 3 | 14GS GST homodimer, 1HTI TIM homodimer, 1SAK p53-TET tetramer |
| metal_ion | 3 | 1CA2 carbonic-anhydrase (Zn), 2SOD superoxide-dismutase (Cu/Zn), 8TLN thermolysin (Zn/Ca) |
| covalent_mod | 3 | 4G5J EGFR-afatinib, 5P9J BTK-ibrutinib, 6OIM KRAS-G12C-sotorasib |
| ternary_complex | 6 | 5FQD CRBN-lenalidomide-CK1α, 6H0F CRBN-pomalidomide-IKZF1, 5HXB CRBN-CC885-GSPT1, 6ZHC Bcl-xL-VHL-PROTAC, 6HAY SMARCA2-VHL-PROTAC, 7JTP WDR5-VHL-PROTAC |
| gpcr | 5 | 5IU4 A2A-ZM241385, 4GRV NTSR1-neurotensin, 3SN6 β2AR-Gs (Nobel 2012), 6X18 GLP-1R-Gs, 6DDE μOR-Gi |
| membrane_complex | 6 | 3J5P TRPV1-apo, 8X94 TRPV1-SAF312, 7EKI α7-nAChR, 2VL0 ELIC, 6THA GLUT1, 6QEX P-gp-Fab |
| idp | 4 | 1YCR MDM2-p53TAD, 1WKW eIF4E-4EBP1, 4QVF BCL-XL-BIM, 1NEX Cdc4-Skp1-pDegron |
| protein_peptide | 5 | 1SHA SH2-pY, 1CDL CaM-M13, 1BE9 PDZ3-CRIPT, 4QVF BCL-XL-BIM, 3MRG HLA-A2-HCV |
| rna_structure | 5 | 1EHZ tRNA-Phe, 3ZP8 hammerhead, 4OJI twister, 2GIS SAM-I+SAM, 1GID P4-P6 |
| hetero_multimer | 5 | 1LDK SCF-Cul1, 4II2 E1-E2-Ub, 3IKO Nup84, 1SXJ RFC-PCNA, 5CWS nucleoporin |
| glycoprotein | 4 | 5CNA ConA-mannose, 2HRL Siglec7-NAG, 1DBN lectin-NAG, 2UVO WGA-NDG |
| coiled_coil | 6 | 2ZTA GCN4-zipper, 1BB1 designed-CC3, 1SFC SNARE, 1N0R ankyrin, 1A17 TPR, 1QGK importin-β-HEAT |

Full list with PDB IDs is in `scripts/prepare_inputs.py`.

---

## Project Layout

```
FoldBenchmark/
├── README.md
├── LESSONS.md                          # accumulated pitfalls & insights
├── docs/
│   ├── INSTALL.md                      # set up all 10 models from scratch
│   ├── MODELS.md                       # per-model CLI + gotchas
│   ├── INPUT_FORMATS.md                # 6 input formats side-by-side
│   └── TROUBLESHOOTING.md              # known issues + fixes
├── inputs/
│   └── {scenario}/
│       ├── af3_json/                   # AF3 + AlphaFast
│       ├── boltz2_yaml/                # Boltz-2 + IntelliFold-2
│       ├── chai1_fasta/                # Chai-1
│       ├── protenix_json/              # Protenix
│       ├── openfold3_json/             # OpenFold3
│       └── rf3_json/                   # RoseTTAFold3
├── outputs/                            # raw model outputs (gitignored)
│   └── {model}/{scenario}/{case}/
├── scripts/
│   ├── config.sh                       # machine-specific paths (edit once)
│   ├── prepare_inputs.py               # PDB → all 6 input formats
│   ├── prepare_inputs_from_fasta.py    # FASTA/UniProt → all 6 formats (new sequences)
│   ├── screen.py                       # filter, rank, consensus score, Markdown report
│   ├── master_benchmark.sh             # one-shot full benchmark (10 models × 35 cases)
│   ├── run_benchmark.sh                # main runner (+FASTA/UniProt/--top-n/--report)
│   ├── run_single_model.sh             # single (model, scenario, case, gpu)
│   ├── run_alphafast_all_in_one.sh     # AlphaFast batch (35 cases, one DB scan)
│   ├── run_alphafast_batch.sh          # AlphaFast per-scenario batch (fallback)
│   ├── rerun_protenix_anomalous.sh     # re-time Protenix JIT-inflated cases
│   ├── run_esmfold2.py                 # ESMFold2 Python API wrapper (AF3 JSON → CIF)
│   ├── run_esm3.py                     # ESM3 Python API wrapper (AF3 JSON → CIF)
│   ├── wait_and_run.sh                 # wait for GPU idle, then launch benchmark
│   └── collect_results.py              # outputs/ → CSV + summary (dynamic scenario scan)
└── results/
    ├── benchmark_results.csv           # per-case results (models × cases)
    ├── timing.csv
    ├── summary.md
    └── top_N/                          # top-N CIFs (created by --top-n flag)
```

---

## Adding new models or test cases

- **New test case**: Add an entry to `TEST_CASES` in `scripts/prepare_inputs.py` and
  rerun it. **Always verify chain IDs against RCSB** — wrong chain IDs silently produce
  bunk inputs (past bug: RNA chains pointed at protein chains).
- **New model**: Add a `case` branch in `scripts/run_single_model.sh`. The model must
  write a `.cif` file to its output directory (used by the skip-detection logic).
- **New scenario**: Create `inputs/{new_scenario}/` and add entries to `TEST_CASES`.
  `collect_results.py` will auto-discover it (scans `inputs/*/af3_json/`).

---

## Hardware (reference setup)

- 4× NVIDIA RTX 4090 (48 GB each)
- 2× Intel Xeon Silver 4514Y (64 threads total)
- 314 GB RAM
- ~400 GB NVMe for AF3 sharded databases
- ~415 GB for AlphaFast MMseqs2 databases (388 GB protein + 27 GB RNA)

With 4 GPUs, running all 10 models × 35 cases sequentially takes roughly 12–14 hours
(AlphaFast uses all-in-one batch; others run serially on GPU 0).
Models can be parallelized across GPUs with `--gpu N` flags.

---

## License

Code in this repository: MIT.

Each model's outputs are governed by that model's license (see Models table).
AF3 and AlphaFast outputs in particular are CC BY-NC-SA 4.0 (non-commercial only).
