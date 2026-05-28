#!/usr/bin/env python3
"""ESMFold2 wrapper for FoldBenchmark.

Reads an AF3 JSON input, runs ESMFold2 inference, and writes:
  - pred_esmfold2.cif          (mmCIF structure)
  - confidence_esmfold2.json   (ptm, plddt, iptm)

Usage:
  python scripts/run_esmfold2.py \\
      --input  inputs/monomer/af3_json/1UBQ_ubiquitin.json \\
      --outdir outputs/esmfold2/monomer/1UBQ_ubiquitin \\
      --model  biohub/ESMFold2 \\
      --num-loops 3

Released 2026-05-27 by Chan Zuckerberg Biohub; MIT license.
"""

import argparse
import json
import os
import sys
from pathlib import Path

import torch


def af3_json_to_spi(af3_json: dict):
    """Convert AF3 JSON dict → StructurePredictionInput."""
    from esm.models.esmfold2 import (
        DNAInput,
        LigandInput,
        ProteinInput,
        RNAInput,
        StructurePredictionInput,
    )

    sequences = []
    for entry in af3_json.get("sequences", []):
        if "protein" in entry:
            p = entry["protein"]
            ids = p.get("id", ["A"])
            if isinstance(ids, str):
                ids = [ids]
            for cid in ids:
                sequences.append(ProteinInput(id=cid, sequence=p["sequence"]))

        elif "dna" in entry:
            d = entry["dna"]
            ids = d.get("id", ["D"])
            if isinstance(ids, str):
                ids = [ids]
            for cid in ids:
                sequences.append(DNAInput(id=cid, sequence=d["sequence"]))

        elif "rna" in entry:
            r = entry["rna"]
            ids = r.get("id", ["R"])
            if isinstance(ids, str):
                ids = [ids]
            for cid in ids:
                sequences.append(RNAInput(id=cid, sequence=r["sequence"]))

        elif "ligand" in entry:
            lig = entry["ligand"]
            cid = lig.get("id", "L")
            if isinstance(cid, list):
                cid = cid[0]
            ccd_codes = lig.get("ccd_codes", [])
            if isinstance(ccd_codes, str):
                ccd_codes = [ccd_codes]
            # ESMFold2 LigandInput only supports CCD codes, not SMILES directly.
            # SMILES-only ligands (no CCD) are skipped with a warning.
            if ccd_codes:
                sequences.append(LigandInput(id=cid, ccd=ccd_codes))
            elif lig.get("smiles"):
                print(
                    f"[ESMFold2] WARNING: ligand {cid} has SMILES only (no CCD code); "
                    "skipping — ESMFold2 LigandInput requires CCD codes.",
                    file=sys.stderr,
                )

    return StructurePredictionInput(sequences=sequences)


def main():
    parser = argparse.ArgumentParser(description="ESMFold2 FoldBenchmark wrapper")
    parser.add_argument("--input",  required=True,
                        help="AF3 JSON input file")
    parser.add_argument("--outdir", required=True,
                        help="Output directory")
    parser.add_argument("--model",  default="biohub/ESMFold2",
                        help="HuggingFace model ID or local path "
                             "(biohub/ESMFold2 or biohub/ESMFold2-Fast)")
    parser.add_argument("--num-loops",          type=int, default=3,
                        help="Diffusion refinement loops (default 3)")
    parser.add_argument("--num-sampling-steps", type=int, default=50,
                        help="Diffusion sampling steps (default 50)")
    parser.add_argument("--num-diffusion-samples", type=int, default=1,
                        help="Number of diffusion samples (default 1)")
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()

    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)

    # ── HuggingFace cache ─────────────────────────────────────────────────
    hf_cache = os.environ.get("ESMFOLD2_HF_CACHE", "")
    if hf_cache:
        os.environ["HF_HOME"] = hf_cache
        os.environ["HUGGINGFACE_HUB_CACHE"] = hf_cache

    # ── Load input ────────────────────────────────────────────────────────
    with open(args.input) as f:
        af3_json = json.load(f)

    case_name = Path(args.input).stem
    spi = af3_json_to_spi(af3_json)

    if not spi.sequences:
        print(f"[ESMFold2] ERROR: no valid sequences parsed from {args.input}",
              file=sys.stderr)
        sys.exit(1)

    # ── Load model ────────────────────────────────────────────────────────
    from transformers.models.esmfold2.modeling_esmfold2 import ESMFold2Model
    from esm.models.esmfold2 import ESMFold2InputBuilder

    print(f"[ESMFold2] Loading model: {args.model}")
    model = ESMFold2Model.from_pretrained(args.model).cuda().eval()

    # ── Inference ─────────────────────────────────────────────────────────
    print(
        f"[ESMFold2] Folding {case_name} "
        f"(loops={args.num_loops}, steps={args.num_sampling_steps})"
    )
    with torch.no_grad():
        result = ESMFold2InputBuilder().fold(
            model,
            spi,
            num_loops=args.num_loops,
            num_sampling_steps=args.num_sampling_steps,
            num_diffusion_samples=args.num_diffusion_samples,
            seed=args.seed,
        )

    # ── Write CIF ─────────────────────────────────────────────────────────
    cif_path = out / "pred_esmfold2.cif"
    cif_str = result.complex.to_mmcif()
    cif_path.write_text(cif_str)
    print(f"[ESMFold2] CIF written: {cif_path}")

    # ── Write confidence JSON ─────────────────────────────────────────────
    def _scalar(v):
        if v is None:
            return None
        if hasattr(v, "item"):
            return float(v.item())
        if hasattr(v, "mean"):
            return float(v.mean().item())
        return float(v)

    # plddt may be per-residue tensor; take mean
    plddt_val = result.plddt if hasattr(result, "plddt") else None
    if plddt_val is not None and hasattr(plddt_val, "mean"):
        plddt_val = plddt_val.mean()

    conf = {
        "ptm":   _scalar(getattr(result, "ptm",  None)),
        "plddt": _scalar(plddt_val),
        "iptm":  _scalar(getattr(result, "iptm", None)),
    }
    conf_path = out / "confidence_esmfold2.json"
    with open(conf_path, "w") as f:
        json.dump(conf, f, indent=2)

    ptm_str   = f"{conf['ptm']:.3f}"  if conf["ptm"]   is not None else "N/A"
    plddt_str = f"{conf['plddt']:.1f}" if conf["plddt"] is not None else "N/A"
    print(f"[ESMFold2] pTM={ptm_str}  pLDDT={plddt_str}")
    print(f"[ESMFold2] Confidence written: {conf_path}")


if __name__ == "__main__":
    main()
