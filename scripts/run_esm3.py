#!/usr/bin/env python3
"""ESM3 structure prediction wrapper for FoldBenchmark.

Reads an AF3 JSON input, runs ESM3 structure generation, and writes:
  - pred_esm3.cif          (mmCIF structure; PDB fallback if gemmi absent)
  - confidence_esm3.json   (ptm, plddt)

Protein chains are folded jointly (multi-chain via ':' separator).
RNA / DNA / ligand chains in the AF3 JSON are silently ignored — ESM3 is
a protein-only model.

Local weight loading: set ESM3_MODEL_DIR to the directory containing the
'data/weights/' folder (e.g. /data2/.../esm3/hf_cache/esm3-sm-open-v1).
ESM3's internal data_root() is bypassed via INFRA_PROVIDER=local, so
weights are resolved relative to ESM3_MODEL_DIR (no HF download needed).

Usage:
  python scripts/run_esm3.py \\
      --input  inputs/monomer/af3_json/1UBQ_ubiquitin.json \\
      --outdir outputs/esm3/monomer/1UBQ_ubiquitin \\
      --num-steps 8

ESM3 open weights: EvolutionaryScale/esm3-sm-open-v1
License: Cambrian Non-Commercial License Agreement (non-commercial use only)
"""

import argparse
import json
import os
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
    ap.add_argument("--input",       required=True,  help="AF3 JSON input file")
    ap.add_argument("--outdir",      required=True,  help="Output directory")
    ap.add_argument("--model",       default="esm3-sm-open-v1",
                    help="Model name (only 'esm3-sm-open-v1' supported locally)")
    ap.add_argument("--num-steps",   type=int, default=8,
                    help="Structure generation steps (default 8)")
    ap.add_argument("--temperature", type=float, default=0.0,
                    help="Sampling temperature (0 = deterministic greedy)")
    args = ap.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    # ── Resolve local weight directory ────────────────────────────────────
    # ESM3's data_root() calls snapshot_download("biohub/esm3-sm-open-v1").
    # When INFRA_PROVIDER is set, data_root() returns Path(""), so weights
    # are resolved relative to the current working directory.
    # We cd into the model dir so Path("") / "data/weights/..." resolves correctly.
    model_dir = os.environ.get("ESM3_MODEL_DIR", "")
    if not model_dir:
        # Fallback: derive from ESM3_HF_CACHE env var
        hf_cache = os.environ.get("ESM3_HF_CACHE", "")
        model_dir = os.path.join(hf_cache, "esm3-sm-open-v1") if hf_cache else ""

    if model_dir and os.path.isdir(model_dir):
        weights_dir = os.path.join(model_dir, "data", "weights")
        if os.path.isdir(weights_dir):
            os.chdir(model_dir)
            os.environ["INFRA_PROVIDER"] = "local"
            print(f"[ESM3] Using local weights: {model_dir}", flush=True)
        else:
            print(f"[ESM3] WARNING: weights not found at {weights_dir}; "
                  "will attempt HF download (may fail without token)", flush=True)
    else:
        print("[ESM3] WARNING: ESM3_MODEL_DIR not set; attempting HF download", flush=True)

    # ── Parse AF3 JSON — extract protein chains only ──────────────────────
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
          f"{sum(len(c) for c in protein_chains)} aa total)", flush=True)

    # ── Load ESM3 model ───────────────────────────────────────────────────
    try:
        from esm.models.esm3 import ESM3
        from esm.sdk.api import ESMProtein, GenerationConfig
    except ImportError as e:
        print(f"[ESM3] ERROR: cannot import esm package: {e}", file=sys.stderr)
        print("[ESM3] Install with: pip install -e /path/to/esm-main --no-deps", file=sys.stderr)
        sys.exit(1)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"[ESM3] Loading model on {device} ...", flush=True)
    try:
        model = ESM3.from_pretrained(args.model, device=device).eval()
    except Exception as e:
        print(f"[ESM3] ERROR loading model: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)

    # ── Run structure generation ──────────────────────────────────────────
    protein = ESMProtein(sequence=full_seq)
    cfg = GenerationConfig(
        track="structure",
        num_steps=args.num_steps,
        temperature=args.temperature,
    )

    print(f"[ESM3] Generating structure (steps={args.num_steps}, T={args.temperature}) ...",
          flush=True)
    with torch.no_grad():
        result = model.generate(protein, cfg)

    # ── Write structure ───────────────────────────────────────────────────
    cif_path = outdir / "pred_esm3.cif"

    # Try to export as mmCIF via gemmi (preferred for downstream parsing)
    pdb_str = None
    try:
        pdb_str = result.to_pdb_string()
    except Exception as e:
        print(f"[ESM3] WARNING: to_pdb_string() failed: {e}", file=sys.stderr)

    if pdb_str:
        try:
            import gemmi
            st = gemmi.read_pdb_string(pdb_str)
            cif_doc = st.make_mmcif_document()
            cif_doc.write_file(str(cif_path))
            print(f"[ESM3] CIF written (via gemmi): {cif_path}", flush=True)
        except Exception:
            # gemmi failed — write PDB and a stub CIF so collect_results.py sees a .cif
            pdb_path = outdir / "pred_esm3.pdb"
            pdb_path.write_text(pdb_str)
            print(f"[ESM3] PDB written: {pdb_path}", flush=True)
            cif_path.write_text(
                "# ESM3 prediction — structure in pred_esm3.pdb (gemmi CIF conversion failed)\n"
                "data_ESM3\n"
                "_entry.id ESM3\n"
            )
            print(f"[ESM3] Stub CIF written: {cif_path}", flush=True)
    else:
        cif_path.write_text(
            "# ESM3 prediction — structure decoding failed\n"
            "data_ESM3\n"
            "_entry.id ESM3\n"
        )

    # ── Extract and write confidence metrics ─────────────────────────────
    # ESM3 3.3.0: result.ptm and result.plddt may be tensors or None
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
    print(f"[ESM3] pTM={ptm_str}  pLDDT={plddt_str}", flush=True)
    print(f"[ESM3] Confidence written: {conf_path}", flush=True)


if __name__ == "__main__":
    main()
