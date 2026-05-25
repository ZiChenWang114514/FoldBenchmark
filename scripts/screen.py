#!/usr/bin/env python3
"""
Post-run screening: filter results, rank by metric, compute multi-model consensus,
copy top-N CIF files, and generate a Markdown report.

Usage:
  python scripts/screen.py \\
      [--results results/benchmark_results.csv] \\
      [--models af3,boltz2] \\
      [--scenarios protein_ligand,monomer] \\
      [--cases case1,case2] \\
      [--top-n 10] \\
      [--by ptm|plddt|ranking_score] \\
      [--copy-cif] \\
      [--report results/screen_report.md]
"""

import argparse
import csv
import shutil
from collections import defaultdict
from datetime import datetime
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
RESULTS_CSV = PROJECT_ROOT / "results" / "benchmark_results.csv"
OUTPUTS_DIR = PROJECT_ROOT / "outputs"
TOP_N_DIR = PROJECT_ROOT / "results" / "top_N"


# ---------------------------------------------------------------------------
# Loading and filtering
# ---------------------------------------------------------------------------

def load_results(csv_path: Path) -> list:
    with open(csv_path, newline="") as f:
        return list(csv.DictReader(f))


def filter_rows(rows: list, models: list | None, scenarios: list | None,
                cases: list | None) -> list:
    out = [r for r in rows if r.get("has_output", "").lower() in ("true", "1", "yes")]
    if models:
        out = [r for r in out if r.get("model") in models]
    if scenarios:
        out = [r for r in out if r.get("scenario") in scenarios]
    if cases:
        out = [r for r in out if r.get("case_name") in cases]
    return out


# ---------------------------------------------------------------------------
# Consensus scoring and ranking
# ---------------------------------------------------------------------------

def compute_summaries(rows: list, sort_by: str) -> list:
    """
    Group by case_name, compute per-model scores and consensus (mean).
    Returns list of summary dicts sorted descending by consensus score.
    """
    by_case: dict = defaultdict(lambda: {"per_model": {}, "scenario": ""})

    for r in rows:
        case = r.get("case_name", "")
        model = r.get("model", "")
        by_case[case]["scenario"] = r.get("scenario", "")
        try:
            val = float(r.get(sort_by) or 0)
        except (ValueError, TypeError):
            val = 0.0
        by_case[case]["per_model"][model] = val

    summaries = []
    for case_name, info in by_case.items():
        per_model = info["per_model"]
        vals = [v for v in per_model.values() if v > 0]
        consensus = sum(vals) / len(vals) if vals else 0.0
        summaries.append({
            "case_name": case_name,
            "scenario": info["scenario"],
            "per_model": per_model,
            "consensus": consensus,
        })

    summaries.sort(key=lambda x: x["consensus"], reverse=True)
    return summaries


# ---------------------------------------------------------------------------
# CIF copying
# ---------------------------------------------------------------------------

def find_cif(model: str, scenario: str, case_name: str) -> Path | None:
    """Return first .cif found under outputs/{model}/{scenario}/{case_name}/."""
    out_dir = OUTPUTS_DIR / model / scenario / case_name
    if not out_dir.exists():
        return None
    for cif in sorted(out_dir.rglob("*.cif")):
        return cif
    return None


def copy_top_n_cifs(summaries: list, n: int, rows: list) -> None:
    """Copy CIFs for top-N cases to results/top_N/{case_name}/."""
    TOP_N_DIR.mkdir(parents=True, exist_ok=True)

    # scenario lookup: (case_name, model) → scenario
    scenario_lut: dict = {}
    for r in rows:
        scenario_lut[(r.get("case_name"), r.get("model"))] = r.get("scenario", "")

    for item in summaries[:n]:
        case_name = item["case_name"]
        dest = TOP_N_DIR / case_name
        dest.mkdir(parents=True, exist_ok=True)

        for model, score in item["per_model"].items():
            scenario = scenario_lut.get((case_name, model), item["scenario"])
            cif = find_cif(model, scenario, case_name)
            if cif:
                dst = dest / f"{model}_{cif.name}"
                shutil.copy2(cif, dst)
                print(f"  Copied: {dst.relative_to(PROJECT_ROOT)}")
            else:
                print(f"  WARNING: No CIF for {model}/{case_name}")


# ---------------------------------------------------------------------------
# Markdown report
# ---------------------------------------------------------------------------

def generate_report(summaries: list, top_n: int, sort_by: str,
                    report_path: Path, copy_cif: bool) -> None:
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    all_models = sorted({m for s in summaries for m in s["per_model"]})
    n_shown = min(top_n, len(summaries))

    def _row(item: dict, rank: int | None = None) -> str:
        cols = []
        if rank is not None:
            cols.append(str(rank))
        cols += [item["case_name"], item["scenario"]]
        for m in all_models:
            v = item["per_model"].get(m)
            cols.append(f"{v:.3f}" if v is not None else "—")
        consensus_str = f"**{item['consensus']:.3f}**" if rank is not None else f"{item['consensus']:.3f}"
        cols.append(consensus_str)
        return "| " + " | ".join(cols) + " |"

    header_prefix = ["Rank", "Case", "Scenario"] if True else ["Case", "Scenario"]
    header = ["Rank", "Case", "Scenario"] + all_models + [f"Consensus {sort_by}"]
    sep = ["---"] * len(header)

    lines = [
        f"# FoldBenchmark Screening Report — {now}",
        "",
        "## Summary",
        f"- Cases screened: {len(summaries)}",
        f"- Models: {', '.join(all_models)}",
        f"- Sorted by: `{sort_by}`",
    ]
    if copy_cif:
        lines.append(f"- Top-{n_shown} CIFs copied to: `results/top_N/`")
    lines += [
        "",
        f"## Top-{n_shown} Results",
        "",
        "| " + " | ".join(header) + " |",
        "| " + " | ".join(sep) + " |",
    ]
    for i, item in enumerate(summaries[:top_n], 1):
        lines.append(_row(item, rank=i))

    if len(summaries) > top_n:
        all_header = ["Rank", "Case", "Scenario"] + all_models + [f"Consensus {sort_by}"]
        all_sep = ["---"] * len(all_header)
        lines += [
            "",
            f"## All Results ({len(summaries)} cases)",
            "",
            "| " + " | ".join(all_header) + " |",
            "| " + " | ".join(all_sep) + " |",
        ]
        for i, item in enumerate(summaries, 1):
            lines.append(_row(item, rank=i))

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(lines) + "\n")
    print(f"Report → {report_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Screen FoldBenchmark results: rank, consensus, report",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--results", type=Path, default=RESULTS_CSV,
                        help="benchmark_results.csv path")
    parser.add_argument("--models", help="Comma-separated model filter (default: all)")
    parser.add_argument("--scenarios", help="Comma-separated scenario filter (default: all)")
    parser.add_argument("--cases", help="Comma-separated case name filter (default: all)")
    parser.add_argument("--top-n", type=int, default=10, metavar="N",
                        help="Show/copy top-N results (default: 10)")
    parser.add_argument("--by", default="ptm",
                        choices=["ptm", "plddt", "ranking_score"],
                        help="Sort metric (default: ptm)")
    parser.add_argument("--copy-cif", action="store_true",
                        help="Copy top-N CIFs to results/top_N/")
    parser.add_argument("--report", type=Path, metavar="FILE",
                        help="Write Markdown report to this path")
    args = parser.parse_args()

    if not args.results.exists():
        print(f"ERROR: {args.results} not found.")
        print("Run:  python scripts/collect_results.py")
        raise SystemExit(1)

    models = args.models.split(",") if args.models else None
    scenarios = args.scenarios.split(",") if args.scenarios else None
    cases = args.cases.split(",") if args.cases else None

    rows = load_results(args.results)
    rows = filter_rows(rows, models, scenarios, cases)

    if not rows:
        print("No results match the specified filters.")
        raise SystemExit(0)

    print(f"Loaded {len(rows)} result rows.")
    summaries = compute_summaries(rows, args.by)

    n_shown = min(args.top_n, len(summaries))
    print(f"\nTop-{n_shown} by consensus {args.by}:")
    for i, s in enumerate(summaries[:args.top_n], 1):
        per_model_str = "  ".join(f"{m}={v:.3f}" for m, v in sorted(s["per_model"].items()))
        print(f"  {i:3d}. {s['case_name']:<42s}  {per_model_str}  consensus={s['consensus']:.3f}")

    if args.copy_cif:
        print("\nCopying CIFs...")
        copy_top_n_cifs(summaries, args.top_n, rows)

    if args.report:
        print("\nGenerating report...")
        generate_report(summaries, args.top_n, args.by, args.report, args.copy_cif)


if __name__ == "__main__":
    main()
