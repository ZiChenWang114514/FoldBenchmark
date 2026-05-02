#!/usr/bin/env python3
"""
Collect and compare benchmark results across all models.
Usage: python collect_results.py
"""
import csv
import json
import os
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
OUTPUTS_DIR = PROJECT_ROOT / "outputs"
RESULTS_DIR = PROJECT_ROOT / "results"
TIMING_FILE = RESULTS_DIR / "timing.csv"

MODELS = ["af3", "alphafast", "boltz2", "openfold3", "protenix", "chai1", "intellifold"]
SCENARIOS = ["protein_protein", "protein_ligand", "protein_rna", "monomer", "antibody_antigen"]


def find_output_files(model_dir: Path) -> dict:
    """Find output files and extract metrics."""
    result = {"has_output": False, "plddt": None, "ptm": None, "ranking_score": None}

    if not model_dir.exists():
        return result

    # Search for CIF files (universal output)
    cif_files = list(model_dir.rglob("*.cif"))
    if cif_files:
        result["has_output"] = True

    # AF3-style: summary_confidences.json
    for conf_file in model_dir.rglob("*summary_confidences*"):
        try:
            with open(conf_file) as f:
                conf = json.load(f)
            result["ptm"] = conf.get("ptm", conf.get("pTM"))
            result["plddt"] = conf.get("atom_plddts_mean", conf.get("plddt"))
            if "ranking_score" in conf:
                result["ranking_score"] = conf["ranking_score"]
        except Exception:
            pass

    # AF3-style: ranking_scores.csv
    for rank_file in model_dir.rglob("*ranking_scores*"):
        try:
            with open(rank_file) as f:
                reader = csv.DictReader(f)
                scores = [float(row["ranking_score"]) for row in reader]
            if scores:
                result["ranking_score"] = max(scores)
        except Exception:
            pass

    # Boltz-2 style: confidence files
    for conf_file in model_dir.rglob("confidence*"):
        try:
            with open(conf_file) as f:
                conf = json.load(f)
            if "plddt" in conf:
                result["plddt"] = conf["plddt"]
            if "ptm" in conf:
                result["ptm"] = conf["ptm"]
            if "iptm" in conf:
                result["iptm"] = conf["iptm"]
        except Exception:
            pass

    # Chai-1 style: scores.model_idx_0.npz (top-ranked model)
    if result["ptm"] is None:
        npz_files = sorted(model_dir.rglob("scores.model_idx_0.npz"))
        if npz_files:
            try:
                import numpy as np
                d = np.load(npz_files[0])
                if "ptm" in d.files:
                    result["ptm"] = float(d["ptm"].item() if d["ptm"].size == 1 else d["ptm"].max())
                if "iptm" in d.files:
                    result["iptm"] = float(d["iptm"].item() if d["iptm"].size == 1 else d["iptm"].max())
                if "aggregate_score" in d.files:
                    result["ranking_score"] = float(d["aggregate_score"].item() if d["aggregate_score"].size == 1 else d["aggregate_score"].max())
            except Exception:
                pass

    # Generic: look for any JSON with plddt/ptm (only if .cif already proved success)
    if result["has_output"] and result["plddt"] is None:
        for json_file in model_dir.rglob("*.json"):
            try:
                with open(json_file) as f:
                    data = json.load(f)
                if isinstance(data, dict):
                    for key in ["plddt", "pLDDT", "mean_plddt", "atom_plddts_mean"]:
                        if key in data and result["plddt"] is None:
                            val = data[key]
                            result["plddt"] = val if isinstance(val, (int, float)) else None
                    for key in ["ptm", "pTM"]:
                        if key in data and result["ptm"] is None:
                            result["ptm"] = data[key]
            except Exception:
                pass

    return result


def load_timing() -> dict:
    """Load timing data from CSV."""
    timing = {}
    if TIMING_FILE.exists():
        with open(TIMING_FILE) as f:
            reader = csv.DictReader(f)
            for row in reader:
                key = (row["model"], row["scenario"], row["case_name"])
                timing[key] = int(row["elapsed_seconds"])
    return timing


def main():
    RESULTS_DIR.mkdir(exist_ok=True)
    timing = load_timing()

    # Collect all results
    rows = []
    for scenario in SCENARIOS:
        input_dir = PROJECT_ROOT / "inputs" / scenario / "af3_json"
        if not input_dir.exists():
            continue
        for json_file in sorted(input_dir.glob("*.json")):
            case_name = json_file.stem
            for model in MODELS:
                model_output = OUTPUTS_DIR / model / scenario / case_name
                metrics = find_output_files(model_output)
                elapsed = timing.get((model, scenario, case_name), None)
                rows.append({
                    "scenario": scenario,
                    "case_name": case_name,
                    "model": model,
                    "has_output": metrics["has_output"],
                    "plddt": metrics["plddt"],
                    "ptm": metrics["ptm"],
                    "ranking_score": metrics["ranking_score"],
                    "elapsed_seconds": elapsed,
                })

    # Write CSV
    csv_path = RESULTS_DIR / "benchmark_results.csv"
    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["scenario", "case_name", "model", "has_output", "plddt", "ptm", "ranking_score", "elapsed_seconds"])
        writer.writeheader()
        writer.writerows(rows)
    print(f"Results saved to {csv_path}")

    # Generate summary
    summary_lines = ["# FoldBenchmark Results\n"]
    for scenario in SCENARIOS:
        summary_lines.append(f"\n## {scenario}\n")
        scenario_rows = [r for r in rows if r["scenario"] == scenario]
        if not scenario_rows:
            continue

        # Get unique case names
        case_names = sorted(set(r["case_name"] for r in scenario_rows))

        # Header
        summary_lines.append(f"| Case | " + " | ".join(MODELS) + " |")
        summary_lines.append("|------|" + "|".join(["---"] * len(MODELS)) + "|")

        for case in case_names:
            cells = []
            for model in MODELS:
                r = next((r for r in scenario_rows if r["case_name"] == case and r["model"] == model), None)
                if r and r["has_output"]:
                    parts = []
                    if r["plddt"] is not None:
                        parts.append(f"pLDDT={r['plddt']:.1f}" if isinstance(r['plddt'], float) else f"pLDDT={r['plddt']}")
                    if r["ptm"] is not None:
                        parts.append(f"pTM={r['ptm']:.2f}" if isinstance(r['ptm'], float) else f"pTM={r['ptm']}")
                    if r["elapsed_seconds"] is not None:
                        parts.append(f"{r['elapsed_seconds']}s")
                    cells.append(" ".join(parts) if parts else "OK")
                elif r:
                    cells.append(f"{r['elapsed_seconds']}s FAIL" if r["elapsed_seconds"] else "-")
                else:
                    cells.append("-")
            summary_lines.append(f"| {case} | " + " | ".join(cells) + " |")

    summary_path = RESULTS_DIR / "summary.md"
    with open(summary_path, "w") as f:
        f.write("\n".join(summary_lines))
    print(f"Summary saved to {summary_path}")

    # Print summary to terminal
    print("\n" + "\n".join(summary_lines))


if __name__ == "__main__":
    main()
