#!/usr/bin/env python3
"""
Convert Chai-1 style FASTA (or UniProt ID list) to all 6 model input formats.
Outputs to inputs/screening/ (flat structure matching existing benchmark layout).

FASTA format (Chai-1 compatible):
  >protein|name=chain_A
  MTEEKLISEE...
  >protein|name=chain_B
  MARLKASEE...
  >ligand|name=L1|smiles=O=C(NC...)...
  >ligand|name=L2|ccd=ATP
  >dna|name=D1
  ATCGATCG
  >rna|name=R1
  AUGCAUGC

UniProt ID list format (one ID per line = monomer; two space-separated = PPI):
  P68871
  P02686 P14780

Usage:
  python scripts/prepare_inputs_from_fasta.py \\
      --fasta my_proteins.fasta [--name my_complex] [--out-dir inputs/screening]
  python scripts/prepare_inputs_from_fasta.py \\
      --uniprot targets.txt [--out-dir inputs/screening]
"""

import argparse
import json
import sys
import time
import urllib.request
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(Path(__file__).parent))

from prepare_inputs import (
    generate_boltz2_yaml,
    generate_chai1_fasta,
    generate_openfold3_json,
    generate_protenix_json,
    generate_rf3_json,
)


# ---------------------------------------------------------------------------
# FASTA parsing
# ---------------------------------------------------------------------------

def _parse_header(header: str) -> dict:
    """Parse 'protein|name=X|smiles=Y' style header into a dict."""
    parts = header.split("|")
    entity_type = parts[0].strip().lower()
    result: dict = {"entity_type": entity_type}
    for part in parts[1:]:
        if "=" in part:
            key, _, val = part.partition("=")
            result[key.strip()] = val.strip()
    return result


def parse_fasta_chains(fasta_text: str) -> list:
    """
    Parse Chai-1 style FASTA into a list of chain dicts.

    Each dict has:
      - entity_type: "protein" | "rna" | "dna" | "ligand"
      - name: str (from name= in header)
      - sequence: str  (protein/rna/dna)
      - smiles: str    (ligand, if smiles= in header or next line)
      - ccd: str       (ligand, if ccd= in header)
    """
    chains = []
    current_header = None
    seq_lines: list = []

    def _flush():
        if current_header is None:
            return
        chain = _parse_header(current_header)
        seq = "".join(seq_lines).strip()
        et = chain["entity_type"]
        if et in ("protein", "rna", "dna"):
            chain["sequence"] = seq
        elif et == "ligand":
            # smiles/ccd may come from header or from the next sequence line
            if seq and "smiles" not in chain and "ccd" not in chain:
                chain["smiles"] = seq
        chains.append(chain)

    for line in fasta_text.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith(">"):
            _flush()
            current_header = line[1:]
            seq_lines = []
        else:
            seq_lines.append(line)

    _flush()
    return chains


# ---------------------------------------------------------------------------
# Scenario detection
# ---------------------------------------------------------------------------

def detect_scenario(chains: list) -> str:
    """Infer scenario label from entity types present."""
    types = [c["entity_type"] for c in chains]
    protein_seqs = [c.get("sequence", "") for c in chains if c["entity_type"] == "protein"]
    n_protein = types.count("protein")

    has_rna = "rna" in types
    has_dna = "dna" in types
    has_ligand = "ligand" in types

    if not protein_seqs:
        return "nucleic_acid"

    if has_rna:
        return "protein_rna"
    if has_dna:
        return "protein_dna"
    if has_ligand:
        return "protein_ligand"

    if n_protein == 1:
        return "monomer"
    if len(set(protein_seqs)) == 1:
        return "homo_multimer"
    return "protein_protein"


# ---------------------------------------------------------------------------
# Build AF3 JSON from parsed chains
# ---------------------------------------------------------------------------

def build_af3_json(case_name: str, chains: list) -> dict:
    """Construct AF3-format input dict from parsed chain list."""
    letters = [chr(ord("A") + i) for i in range(26)]
    seqs = []
    idx = 0

    for chain in chains:
        if idx >= 26:
            raise ValueError("Too many chains: AF3/AlphaFast supports at most 26 (A-Z)")
        chain_id = letters[idx]
        idx += 1
        et = chain["entity_type"]

        if et == "protein":
            seqs.append({"protein": {"id": [chain_id], "sequence": chain["sequence"]}})
        elif et == "rna":
            seqs.append({"rna": {"id": [chain_id], "sequence": chain["sequence"]}})
        elif et == "dna":
            seqs.append({"dna": {"id": [chain_id], "sequence": chain["sequence"]}})
        elif et == "ligand":
            if "ccd" in chain:
                seqs.append({"ligand": {"id": [chain_id], "ccdCodes": [chain["ccd"]]}})
            elif "smiles" in chain:
                seqs.append({"ligand": {"id": [chain_id], "smiles": chain["smiles"]}})
            else:
                print(f"  WARNING: ligand '{chain.get('name', '?')}' has no smiles or ccd — skipped")
                idx -= 1
        else:
            print(f"  WARNING: unknown entity_type '{et}' — skipped")
            idx -= 1

    if not seqs:
        raise ValueError(f"No valid chains found for case '{case_name}'")

    return {
        "name": case_name,
        "sequences": seqs,
        "modelSeeds": [1],
        "dialect": "alphafold3",
        "version": 1,
    }


# ---------------------------------------------------------------------------
# Save all 6 formats (flat structure: out_dir/{format}/{case_name}.ext)
# ---------------------------------------------------------------------------

def save_all_formats(af3_json: dict, out_dir: Path) -> None:
    """Write all 6 model input formats to out_dir, flat structure."""
    case_name = af3_json["name"]

    # AF3 JSON
    d = out_dir / "af3_json"
    d.mkdir(parents=True, exist_ok=True)
    with open(d / f"{case_name}.json", "w") as f:
        json.dump(af3_json, f, indent=2)

    # Boltz-2 YAML (also used by IntelliFold)
    d = out_dir / "boltz2_yaml"
    d.mkdir(parents=True, exist_ok=True)
    with open(d / f"{case_name}.yaml", "w") as f:
        f.write(generate_boltz2_yaml(af3_json))

    # Chai-1 FASTA
    d = out_dir / "chai1_fasta"
    d.mkdir(parents=True, exist_ok=True)
    with open(d / f"{case_name}.fasta", "w") as f:
        f.write(generate_chai1_fasta(af3_json))

    # Protenix JSON
    d = out_dir / "protenix_json"
    d.mkdir(parents=True, exist_ok=True)
    with open(d / f"{case_name}.json", "w") as f:
        json.dump(generate_protenix_json(af3_json), f, indent=2)

    # RoseTTAFold3 JSON
    d = out_dir / "rf3_json"
    d.mkdir(parents=True, exist_ok=True)
    with open(d / f"{case_name}.json", "w") as f:
        json.dump(generate_rf3_json(af3_json), f, indent=2)

    # OpenFold3 JSON
    d = out_dir / "openfold3_json"
    d.mkdir(parents=True, exist_ok=True)
    with open(d / f"{case_name}.json", "w") as f:
        json.dump(generate_openfold3_json(af3_json), f, indent=2)

    n_chains = len(af3_json["sequences"])
    print(f"  OK: {case_name} ({n_chains} chains) → {out_dir.name}/*/")


# ---------------------------------------------------------------------------
# UniProt fetching
# ---------------------------------------------------------------------------

def fetch_uniprot_sequence(uniprot_id: str) -> str:
    """Fetch protein sequence from UniProt REST API."""
    url = f"https://rest.uniprot.org/uniprotkb/{uniprot_id}.fasta"
    try:
        req = urllib.request.Request(url, headers={"Accept": "text/plain"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            fasta_text = resp.read().decode("utf-8")
    except Exception as e:
        raise RuntimeError(f"Failed to fetch UniProt {uniprot_id}: {e}")
    lines = fasta_text.strip().splitlines()
    seq = "".join(l for l in lines if not l.startswith(">"))
    if not seq:
        raise ValueError(f"Empty sequence returned for UniProt {uniprot_id}")
    return seq


# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

def process_fasta_file(fasta_path: Path, name: str | None, out_dir: Path,
                        scenario_override: str | None = None) -> list:
    """Process a Chai-1 style FASTA file. Returns list of (case_name, scenario)."""
    text = fasta_path.read_text()
    chains = parse_fasta_chains(text)
    if not chains:
        print("ERROR: No chains found in FASTA file")
        return []

    case_name = name or fasta_path.stem
    scenario = scenario_override or detect_scenario(chains)
    af3_json = build_af3_json(case_name, chains)
    save_all_formats(af3_json, out_dir)
    return [(case_name, scenario)]


def process_uniprot_file(ids_path: Path, out_dir: Path,
                          scenario_override: str | None = None) -> list:
    """Process UniProt ID list file. Returns list of (case_name, scenario)."""
    created = []
    for raw_line in ids_path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        ids = line.split()
        chains = []
        for uid in ids:
            print(f"  Fetching UniProt {uid}...")
            seq = fetch_uniprot_sequence(uid)
            chains.append({"entity_type": "protein", "name": uid, "sequence": seq})
            time.sleep(0.2)  # rate limit

        case_name = "_".join(ids)
        scenario = scenario_override or detect_scenario(chains)
        af3_json = build_af3_json(case_name, chains)
        save_all_formats(af3_json, out_dir)
        created.append((case_name, scenario))
    return created


def main():
    parser = argparse.ArgumentParser(
        description="Convert FASTA/UniProt inputs to all 6 FoldBenchmark formats",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    src = parser.add_mutually_exclusive_group(required=True)
    src.add_argument("--fasta", type=Path, metavar="FILE",
                     help="Chai-1 style FASTA file")
    src.add_argument("--uniprot", type=Path, metavar="FILE",
                     help="UniProt ID list (one ID or two IDs per line)")
    parser.add_argument("--name", metavar="NAME",
                        help="Case name (FASTA mode; default: filename stem)")
    parser.add_argument("--out-dir", type=Path,
                        default=PROJECT_ROOT / "inputs" / "screening",
                        help="Output root dir (default: inputs/screening)")
    parser.add_argument("--scenario", metavar="SCENARIO",
                        help="Override auto-detected scenario label")
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)

    if args.fasta:
        created = process_fasta_file(args.fasta, args.name, args.out_dir, args.scenario)
    else:
        created = process_uniprot_file(args.uniprot, args.out_dir, args.scenario)

    print(f"\nCreated {len(created)} case(s):")
    for case_name, scenario in created:
        print(f"  {case_name}  (scenario={scenario})")
    print(f"Output dir: {args.out_dir}")


if __name__ == "__main__":
    main()
