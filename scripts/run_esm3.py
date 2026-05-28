#!/usr/bin/env python3
"""ESM3 structure prediction wrapper for FoldBenchmark.

Reads an AF3 JSON input, runs ESM3 structure generation, and writes:
  - pred_esm3.cif          (mmCIF structure; PDB fallback if gemmi absent)
  - confidence_esm3.json   (ptm, plddt)

Protein chains are folded jointly (multi-chain via ':' separator).
RNA / DNA / ligand chains in the AF3 JSON are silently ignored — ESM3 is
a protein-only model.

Usage:
  python scripts/run_esm3.py \\
      --input  inputs/monomer/af3_json/1UBQ_ubiquitin.json \\
      --outdir outputs/esm3/monomer/1UBQ_ubiquitin \\
      --model  esm3-sm-open-v1 \\
      --num-steps 8

ESM3 open weights: EvolutionaryScale/esm3-sm-open-v1 (HuggingFace)
License: Cambrian Non-Commercial License Agreement (non-commercial use only)
"""

import argparse
import json
import sys
from pathlib import Path

import torch


def _scalar(v):
    """Safely convert a tensor/array/scalar to a Python float."""
    if v is None:
        return None
    if hasattr(v, "item"):
        return float(v.item())
    if hasattr(v, "mean"):
        return float(v.mean().item())
    try:
        return float(v)
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser(description="ESM3 FoldBenchmark wrapper")
    ap.add_argument("--input",      required=True,  help="AF3 JSON input file")
    ap.add_argument("--outdir",     required=True,  help="Output directory")
    ap.add_argument("--model",      default="esm3-sm-open-v1",
                    help="ESM3 model: 'esm3-sm-open-v1' (local HF) or Forge model name")
    ap.add_argument("--num-steps",  type=int, default=8,
                    help="Structure generation steps (default 8; higher = slower but more accurate)")
    ap.add_argument("--temperature", type=float, default=0.0,
                    help="Sampling temperature (0.0 = deterministic greedy)")
    args = ap.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    # ── Parse AF3 JSON — extract protein chains ───────────────────────────
    with open(args.input) as f:
        job = json.load(f)

    protein_chains = []
    for entry in job.get("sequences", []):
        if "protein" in entry:
            seq = entry["protein"].get("sequence", "")
            if seq:
                protein_chains.append(seq)

    if not protein_chains:
        print(f"[ESM3] SKIP: no protein sequences in {args.input}", file=sys.stderr)
        sys.exit(0)

    # Multi-chain: join with ':' (ESM3 multi-chain format)
    full_seq = ":".join(protein_chains)
    case_name = Path(args.input).stem
    print(f"[ESM3] Folding {case_name} ({len(protein_chains)} chain(s), "
          f"{sum(len(c) for c in protein_chains)} aa total)")

    # ── Load ESM3 model ───────────────────────────────────────────────────
    try:
        from esm.models.esm3 import ESM3
        from esm.sdk.api import ESMProtein, GenerationConfig
    except ImportError as e:
        print(f"[ESM3] ERROR: cannot import esm package: {e}", file=sys.stderr)
        print("[ESM3] Install with: pip install esm", file=sys.stderr)
        sys.exit(1)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"[ESM3] Loading model '{args.model}' on {device} ...")
    try:
        client = ESM3.from_pretrained(args.model).to(device).eval()
    except Exception as e:
        print(f"[ESM3] ERROR loading model: {e}", file=sys.stderr)
        sys.exit(1)

    # ── Run structure generation ──────────────────────────────────────────
    protein = ESMProtein(sequence=full_seq)
    cfg = GenerationConfig(
        track="structure",
        num_steps=args.num_steps,
        temperature=args.temperature,
    )

    print(f"[ESM3] Generating structure (steps={args.num_steps}, T={args.temperature}) ...")
    with torch.no_grad():
        result = client.generate(protein, cfg)

    # ── Write structure ───────────────────────────────────────────────────
    cif_path = outdir / "pred_esm3.cif"

    # Try to export as mmCIF via gemmi (preferred for downstream parsing)
    try:
        pdb_str = result.to_pdb_string()
        import gemmi
        st = gemmi.read_pdb_string(pdb_str)
        cif_doc = st.make_mmcif_document()
        cif_doc.write_file(str(cif_path))
        print(f"[ESM3] CIF written (via gemmi): {cif_path}")
    except Exception:
        # gemmi unavailable or CIF write failed — write PDB and a stub CIF
        pdb_path = outdir / "pred_esm3.pdb"
        try:
            pdb_path.write_text(result.to_pdb_string())
            print(f"[ESM3] PDB written: {pdb_path}")
        except Exception as e2:
            print(f"[ESM3] WARNING: could not write PDB: {e2}", file=sys.stderr)
        # Write a minimal stub so collect_results.py sees a .cif file
        cif_path.write_text(
            "# ESM3 prediction — structure in pred_esm3.pdb (gemmi CIF conversion failed)\n"
            "data_ESM3\n"
            "_entry.id ESM3\n"
        )
        print(f"[ESM3] Stub CIF written (PDB is the real structure): {cif_path}")

    # ── Extract and write confidence metrics ─────────────────────────────
    # ESM3 API: result.ptm and result.plddt may be tensors or None
    ptm_raw   = getattr(result, "ptm",   None)
    plddt_raw = getattr(result, "plddt", None)

    # plddt is typically per-residue; take mean
    if plddt_raw is not None and hasattr(plddt_raw, "mean"):
        plddt_raw = plddt_raw.mean()

    ptm_val   = _scalar(ptm_raw)
    plddt_val = _scalar(plddt_raw)

    conf = {"ptm": ptm_val, "plddt": plddt_val}
    conf_path = outdir / "confidence_esm3.json"
    with open(conf_path, "w") as f:
        json.dump(conf, f, indent=2)

    ptm_str   = f"{ptm_val:.3f}"   if ptm_val   is not None else "N/A"
    plddt_str = f"{plddt_val:.1f}" if plddt_val is not None else "N/A"
    print(f"[ESM3] pTM={ptm_str}  pLDDT={plddt_str}")
    print(f"[ESM3] Confidence written: {conf_path}")


if __name__ == "__main__":
    main()
