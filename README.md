# FoldBenchmark

Systematic benchmark of 6 biomolecular structure prediction methods across 5 application scenarios (23 test systems).

## Results Summary

### Completion Rate

| Model | Version | Success | Failed | Notes |
|-------|---------|---------|--------|-------|
| AlphaFold 3 | v3.0.2 | **23/23** | 0 | Gold standard |
| Boltz-2 | v2.2.1 | **23/23** | 0 | Fastest + highest pTM |
| Protenix | latest | 19/23 | 4 | RNA not supported |
| Chai-1 | latest | 20/23 | 3 | RNA not supported |
| IntelliFold-2 | latest | **23/23** | 0 | All scenarios work |
| OpenFold3 | v0.4.1 | 7/23 | 16 | ColabFold MSA unstable in China |

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

1. **Boltz-2** leads in both accuracy (pTM) and speed across all scenarios
2. **Protenix** matches Boltz-2 accuracy for PPI/ligand/monomer but fails on RNA
3. **AF3** is the most reliable (23/23) but slowest due to local MSA (JackHMMER)
4. **IntelliFold-2** handles all scenarios but with lower accuracy
5. **RNA prediction** remains challenging — only AF3, Boltz-2, and IntelliFold-2 can handle it
6. **Antibody-antigen** shows the largest accuracy spread between models

## Models

| Model | Framework | MSA Method | License |
|-------|-----------|------------|---------|
| AlphaFold 3 v3.0.2 | JAX/Docker | JackHMMER (sharded local DB) | CC BY-NC-SA 4.0 |
| Boltz-2 v2.2.1 | PyTorch | ColabFold server | MIT |
| OpenFold3 v0.4.1 | PyTorch | ColabFold server | Apache 2.0 |
| Protenix | PyTorch | Local MSA | Apache 2.0 |
| Chai-1 | PyTorch | ColabFold server | Apache 2.0 |
| IntelliFold-2 | PyTorch | ColabFold server | Apache 2.0 |

## Test Systems (5 scenarios × ~5 cases)

| Scenario | Cases | Description |
|----------|-------|-------------|
| protein_protein | 4 | Homodimers (2PV7), heterodimers (1BRS, 1EMV, 3HFM) |
| protein_ligand | 5 | HIV protease, CDK2, BRAF, SARS-CoV-2 Mpro/3CL |
| protein_rna | 4 | tRNA synthetase, U1A-RNA, FUS-RRM |
| monomer | 5 | Ubiquitin, crambin, myoglobin, GB1, Trp-cage |
| antibody_antigen | 5 | Trastuzumab-HER2, RBD-neutralizing Ab, etc. |

## Usage

```bash
# 1. Prepare inputs (fetch from PDB)
python scripts/prepare_inputs.py

# 2. Run benchmark
bash scripts/run_benchmark.sh                          # all models
bash scripts/run_benchmark.sh --model af3 --gpu 3      # single model
bash scripts/run_benchmark.sh --scenario monomer        # single scenario

# 3. Collect results
python scripts/collect_results.py
```

## Adding new models or test cases

- **New model**: Add a case branch in `scripts/run_single_model.sh`
- **New test case**: Add entry to `TEST_CASES` in `scripts/prepare_inputs.py`, rerun `prepare_inputs.py`
- **New scenario**: Create `inputs/{scenario}/` directory, add cases

## Hardware

- 4x NVIDIA RTX 4090 (48 GB each)
- 64 CPU cores (Intel Xeon Silver 4514Y)
- 314 GB RAM
- AF3 sharded databases: 397 GB on NVMe SSD
