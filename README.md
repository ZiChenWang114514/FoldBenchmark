# FoldBenchmark

Systematic benchmark of 6 biomolecular structure prediction methods across 5 application scenarios (25 test systems).

## Models

| Model | Version | Type | MSA Method |
|-------|---------|------|------------|
| AlphaFold 3 | v3.0.2 | JAX/Docker | JackHMMER (sharded) |
| Boltz-2 | v2.2.1 | PyTorch | ColabFold server |
| OpenFold3 | v0.4.1 | PyTorch | ColabFold server |
| Protenix | latest | PyTorch | ColabFold server |
| Chai-1 | latest | PyTorch | ColabFold server |
| IntelliFold-2 | latest | PyTorch | MMseqs2 |

## Scenarios

| Scenario | # Cases | Description |
|----------|---------|-------------|
| protein_protein | 5 | Homodimers, heterodimers |
| protein_ligand | 5 | Small molecule binding |
| protein_rna | 5 | RNA-protein complexes |
| monomer | 5 | Single chain folding |
| antibody_antigen | 5 | Ab-Ag recognition |

## Usage

```bash
# 1. Prepare inputs (fetch from PDB)
python scripts/prepare_inputs.py

# 2. Run benchmark (all models, all scenarios)
bash scripts/run_benchmark.sh

# 3. Run single model or scenario
bash scripts/run_benchmark.sh --model af3
bash scripts/run_benchmark.sh --scenario monomer

# 4. Collect and compare results
python scripts/collect_results.py
```

## Adding new models or test cases

- **New model**: Add a case in `scripts/run_single_model.sh`
- **New test case**: Add entry in `scripts/prepare_inputs.py` TEST_CASES dict, rerun prepare
- **New scenario**: Create `inputs/{scenario}/` directory, add cases to TEST_CASES

## Hardware

- 4x NVIDIA RTX 4090 (48 GB each)
- 64 CPU cores (Intel Xeon Silver 4514Y)
- 314 GB RAM
