# Input Format Reference

The 6 currently-benchmarked models use 5 different input formats (Boltz-2 and
IntelliFold-2 share the same YAML format). AlphaFast uses the same format as AF3.

All examples below show the **same** test case: PDB 1BRS (barnase + barstar, two
chains A and D). Compare them side-by-side to see the structural differences.

For ligand and RNA examples, see [§ Ligand inputs](#ligand-inputs) and
[§ RNA inputs](#rna-inputs) below.

---

## 1. AF3 JSON (used by AF3 and AlphaFast)

`inputs/protein_protein/af3_json/1BRS_barnase_barstar.json`:

```json
{
  "name": "1BRS_barnase_barstar",
  "sequences": [
    {
      "protein": {
        "id": ["A"],
        "sequence": "AQVINTFDGVADYLQTYHKLPDNYITKSEAQALG..."
      }
    },
    {
      "protein": {
        "id": ["D"],
        "sequence": "KKAVINGEQIRSISDLHQTLKKELALPEYYGENL..."
      }
    }
  ],
  "modelSeeds": [1],
  "dialect": "alphafold3",
  "version": 1
}
```

Entity types: `protein`, `rna`, `dna`, `ligand`. The `id` field is a list (supports
multi-chain).

---

## 2. Boltz-2 YAML (used by Boltz-2 and IntelliFold-2)

`inputs/protein_protein/boltz2_yaml/1BRS_barnase_barstar.yaml`:

```yaml
version: 1
sequences:
  - protein:
      id: A
      sequence: AQVINTFDGVADYLQTYHKLPDNYITKSEAQALG...
  - protein:
      id: D
      sequence: KKAVINGEQIRSISDLHQTLKKELALPEYYGENL...
```

Note: `id` is a single string (not a list, unlike AF3). IntelliFold-2 reads the same file.

---

## 3. Chai-1 FASTA

`inputs/protein_protein/chai1_fasta/1BRS_barnase_barstar.fasta`:

```
>protein|name=chain_A
AQVINTFDGVADYLQTYHKLPDNYITKSEAQALG...
>protein|name=chain_D
KKAVINGEQIRSISDLHQTLKKELALPEYYGENL...
```

Header format: `>{type}|name={chain_name}`. Type is `protein`, `rna`, or `ligand`.
Ligand "sequence" is the SMILES string.

---

## 4. Protenix JSON

`inputs/protein_protein/protenix_json/1BRS_barnase_barstar.json`:

```json
[
  {
    "name": "1BRS_barnase_barstar",
    "sequences": [
      {
        "proteinChain": {
          "sequence": "AQVINTFDGVADYLQTYHKLPDNYITKSEAQALG...",
          "count": 1
        }
      },
      {
        "proteinChain": {
          "sequence": "KKAVINGEQIRSISDLHQTLKKELALPEYYGENL...",
          "count": 1
        }
      }
    ],
    "modelSeeds": [1]
  }
]
```

Key differences from AF3 JSON:

- Top level is a **list** (one entry per job).
- Entity type is `proteinChain` / `rnaSequence` / `dnaSequence` (not `protein` etc.).
- `count` field for stoichiometry (e.g. `count: 2` for a homodimer with one entry).
- No explicit chain `id` — chain letters are auto-assigned in order.

---

## 5. OpenFold3 JSON

`inputs/protein_protein/openfold3_json/1BRS_barnase_barstar.json`:

```json
{
  "queries": {
    "1BRS_barnase_barstar": {
      "use_msas": true,
      "chains": [
        {
          "molecule_type": "protein",
          "chain_ids": "A",
          "sequence": "AQVINTFDGVADYLQTYHKLPDNYITKSEAQALG..."
        },
        {
          "molecule_type": "protein",
          "chain_ids": "D",
          "sequence": "KKAVINGEQIRSISDLHQTLKKELALPEYYGENL..."
        }
      ]
    }
  }
}
```

Key differences:

- Top level is `queries` dict (key = job name).
- Each job has `chains` list with `molecule_type` field.
- `chain_ids` is a string (single chain) or list.
- `use_msas: true` enables ColabFold MSA fetching.

---

## Ligand inputs

Same case (1HSG: HIV protease + indinavir), all 5 formats:

### AF3 JSON
```json
{
  "ligand": {
    "id": ["C"],
    "smiles": "CC(C)(C)NC(=O)..."
  }
}
```
For CCD codes: `{"ligand": {"id": ["C"], "ccdCodes": ["ATP"]}}`.

### Boltz-2 YAML
```yaml
  - ligand:
      id: C
      smiles: "CC(C)(C)NC(=O)..."
```
For CCD: `ccd: ATP` instead of `smiles:`.

### Chai-1 FASTA
```
>ligand|name=chain_C
CC(C)(C)NC(=O)...
```
Chai-1 only supports SMILES (not CCD codes).

### Protenix JSON
```json
{"ligand": {"ligand": "CC(C)(C)NC(=O)...", "count": 1}}
```
For CCD: `{"ligand": {"ligand": "CCD_ATP", "count": 1}}` — note the `CCD_` prefix.

### OpenFold3 JSON
```json
{
  "molecule_type": "ligand",
  "chain_ids": "C",
  "smiles": "CC(C)(C)NC(=O)..."
}
```
For CCD: replace `smiles` with `ccd_codes`.

---

## RNA inputs

Same case (2AZ0: U1A + RNA hairpin), key differences only:

### AF3 JSON
```json
{"rna": {"id": ["B"], "sequence": "GGCAUGCC"}}
```

### Boltz-2 YAML
```yaml
  - rna:
      id: B
      sequence: GGCAUGCC
```

### Chai-1 FASTA
```
>rna|name=chain_B
GGCAUGCC
```
**Warning**: Chai-1 does not currently support RNA prediction in practice — the
input is accepted but inference fails.

### Protenix JSON
```json
{"rnaSequence": {"sequence": "GGCAUGCC", "count": 1}}
```
**Warning**: Protenix does not currently support RNA prediction.

### OpenFold3 JSON
```json
{"molecule_type": "rna", "chain_ids": "B", "sequence": "GGCAUGCC"}
```

---

## Auto-conversion

The script `scripts/prepare_inputs.py` does all 5 conversions in one pass. It fetches
sequences from RCSB PDB and writes 5 input files per case:

```bash
python scripts/prepare_inputs.py
```

For a new test case, edit the `TEST_CASES` dict in that file:

```python
TEST_CASES = {
    "protein_protein": [
        {
            "name": "MY_NEW_CASE",
            "pdb_id": "1ABC",
            "chains": [("A", "protein"), ("B", "protein")],
        },
        ...
    ],
}
```

For ligands, add `"ligands": [(chain_id, smiles_or_ccd), ...]`. Whether the string
is treated as SMILES or a CCD code is auto-detected (CCD codes are short and
alphanumeric — see `generate_af3_json` in the script).

---

## Common conversion pitfalls

| Problem | Symptom | Fix |
|---------|---------|-----|
| Boltz-2 ligand as top-level entity | "Invalid entity type: smiles" | Use `ligand:` with `smiles:` sub-field |
| Protenix `protein` instead of `proteinChain` | KeyError or silent skip | Use `proteinChain` |
| Protenix CCD without prefix | "Unknown ligand ATP" | Use `CCD_ATP` |
| OpenFold3 sent AF3 JSON | "queries field missing" | Use OpenFold3 JSON format |
| Chai-1 has `--input` flag | "no such option: --input" | Args are positional: `chai-lab fold input.fasta out/` |
| IntelliFold without `--use_msa_server` | Errors on missing MSA file | Always pass `--use_msa_server` |
