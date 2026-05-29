#!/usr/bin/env python3
"""
Pre-compute ColabFold MSA for all benchmark cases.

Downloads MSA once per unique protein sequence, caches A3M files,
and generates patched Boltz-2/IntelliFold YAMLs with msa: fields.

Cache layout:
  msa_cache/
    by_seq/{sha256_hash}/           ← one dir per unique sequence
      out.tar.gz                    ← raw ColabFold response
      uniref.a3m                    ← UniRef90 alignment
      bfd.mgnify30.metaeuk30.smag30.a3m ← BFD/MGnify alignment
    patched_yaml/{scenario}/        ← Boltz-2 YAMLs with msa: field
      {case_name}.yaml

Usage:
  python scripts/precompute_msa.py --inputs-dir inputs/ --cache-dir msa_cache/
"""
import argparse
import hashlib
import json
import os
import random
import sys
import tarfile
import time
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("ERROR: requests not installed. Run: pip install requests")

COLABFOLD_URL = "https://api.colabfold.com"
USER_AGENT = "FoldBenchmark/1.0"
MAX_RETRIES = 5
POLL_INTERVAL = (5, 10)  # (min, max) seconds


def seq_hash(sequence: str) -> str:
    return hashlib.sha256(sequence.encode()).hexdigest()


def get_protein_chains(af3_json_path: str) -> list[dict]:
    with open(af3_json_path) as f:
        job = json.load(f)
    chains = []
    for entry in job.get("sequences", []):
        if "protein" in entry:
            p = entry["protein"]
            cid = p.get("id", ["?"])
            if isinstance(cid, list):
                cid = cid[0]
            seq = p.get("sequence", "")
            if seq:
                chains.append({"id": str(cid), "sequence": seq, "hash": seq_hash(seq)})
    return chains


def fetch_msa(sequence: str, server_url: str = COLABFOLD_URL) -> bytes:
    """Submit one sequence to ColabFold, return tar.gz bytes."""
    query = f">101\n{sequence}\n"

    # Submit
    for attempt in range(MAX_RETRIES):
        try:
            r = requests.post(
                f"{server_url}/ticket/msa",
                data={"q": query, "mode": "env"},
                headers={"User-Agent": USER_AGENT},
                timeout=30,
            )
            r.raise_for_status()
            ticket = r.json()
            break
        except Exception as e:
            if attempt == MAX_RETRIES - 1:
                raise
            wait = 10 * (attempt + 1)
            print(f"      Submit error ({attempt+1}/{MAX_RETRIES}): {e}, retry in {wait}s")
            time.sleep(wait)

    tid = ticket["id"]
    status = ticket.get("status", "PENDING")
    print(f"      Ticket {tid} ({status})", flush=True)

    # Poll
    errors = 0
    while True:
        time.sleep(random.uniform(*POLL_INTERVAL))
        try:
            r = requests.get(
                f"{server_url}/ticket/{tid}",
                headers={"User-Agent": USER_AGENT},
                timeout=30,
            )
            r.raise_for_status()
            status_data = r.json()
            status = status_data.get("status", "UNKNOWN")
        except Exception as e:
            errors += 1
            if errors > MAX_RETRIES:
                raise
            print(f"      Poll error ({errors}/{MAX_RETRIES}): {e}")
            continue

        if status == "COMPLETE":
            break
        elif status in ("ERROR", "MAINTENANCE"):
            raise RuntimeError(f"ColabFold error: {status}")
        elif status == "RATELIMIT":
            print("      Rate limited, waiting 60s...", flush=True)
            time.sleep(60)

    # Download
    r = requests.get(
        f"{server_url}/result/download/{tid}",
        headers={"User-Agent": USER_AGENT},
        timeout=120,
    )
    r.raise_for_status()
    return r.content


def ensure_msa_cached(sequence: str, cache_dir: Path, server_url: str) -> Path:
    """Fetch MSA for a sequence if not already cached. Return cache dir."""
    h = seq_hash(sequence)
    seq_dir = cache_dir / "by_seq" / h
    tar_path = seq_dir / "out.tar.gz"

    if tar_path.exists():
        # Already cached — verify A3M extracted
        a3m_path = seq_dir / "uniref.a3m"
        if a3m_path.exists():
            return seq_dir
        # tar exists but not extracted
        with tarfile.open(tar_path, "r:gz") as tar:
            try:
                tar.extractall(seq_dir, filter="data")
            except TypeError:
                tar.extractall(seq_dir)
        return seq_dir

    seq_dir.mkdir(parents=True, exist_ok=True)
    print(f"    Fetching MSA for {h[:12]}... ({len(sequence)} aa)", flush=True)
    tar_bytes = fetch_msa(sequence, server_url)
    tar_path.write_bytes(tar_bytes)

    with tarfile.open(tar_path, "r:gz") as tar:
        try:
            tar.extractall(seq_dir, filter="data")
        except TypeError:
            tar.extractall(seq_dir)

    return seq_dir


def generate_patched_yaml(case_name: str, scenario: str, chains: list[dict],
                          cache_dir: Path, inputs_dir: Path, output_dir: Path) -> Path | None:
    """Generate Boltz-2 YAML with msa: field pointing to cached A3M."""
    orig_yaml = inputs_dir / scenario / "boltz2_yaml" / f"{case_name}.yaml"
    if not orig_yaml.exists():
        return None

    # Build chain_id → A3M path mapping
    msa_paths = {}
    for c in chains:
        seq_dir = cache_dir / "by_seq" / c["hash"]
        a3m = seq_dir / "uniref.a3m"
        if a3m.exists():
            msa_paths[c["id"]] = str(a3m.resolve())

    if not msa_paths:
        return None

    # Parse and patch YAML
    try:
        import yaml
    except ImportError:
        # Fallback: text-based patching
        return _patch_yaml_text(orig_yaml, msa_paths, output_dir / scenario / f"{case_name}.yaml")

    with open(orig_yaml) as f:
        data = yaml.safe_load(f)

    for entry in data.get("sequences", []):
        if "protein" in entry:
            pid = entry["protein"].get("id", "")
            if isinstance(pid, list):
                pid = pid[0] if pid else ""
            pid = str(pid)
            if pid in msa_paths:
                entry["protein"]["msa"] = msa_paths[pid]

    out_path = output_dir / scenario / f"{case_name}.yaml"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)

    return out_path


def _patch_yaml_text(orig_yaml: Path, msa_paths: dict, out_path: Path) -> Path:
    """Fallback YAML patcher without PyYAML: insert msa: after sequence: line."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    lines = orig_yaml.read_text().splitlines(keepends=True)
    result = []
    current_id = None
    for line in lines:
        result.append(line)
        stripped = line.strip()
        # Track chain id
        if stripped.startswith("id:"):
            current_id = stripped.split(":", 1)[1].strip().strip("'\"")
        # After sequence line, insert msa if we have one for this chain
        if stripped.startswith("sequence:") and current_id in msa_paths:
            indent = len(line) - len(line.lstrip())
            result.append(" " * indent + f"msa: {msa_paths[current_id]}\n")
            current_id = None
    out_path.write_text("".join(result))
    return out_path


def main():
    ap = argparse.ArgumentParser(description="Pre-compute ColabFold MSA for FoldBenchmark")
    ap.add_argument("--inputs-dir", default="inputs", help="Benchmark inputs/ directory")
    ap.add_argument("--cache-dir", default="msa_cache", help="MSA cache directory")
    ap.add_argument("--server-url", default=COLABFOLD_URL, help="ColabFold API URL")
    ap.add_argument("--scenario", default="", help="Only process this scenario (empty=all)")
    args = ap.parse_args()

    inputs_dir = Path(args.inputs_dir)
    cache_dir = Path(args.cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)

    # ── Collect all cases ────────────────────────────────────
    cases = []
    for scenario_dir in sorted(inputs_dir.iterdir()):
        if not scenario_dir.is_dir():
            continue
        if args.scenario and scenario_dir.name != args.scenario:
            continue
        af3_dir = scenario_dir / "af3_json"
        if not af3_dir.exists():
            continue
        for jf in sorted(af3_dir.glob("*.json")):
            chains = get_protein_chains(str(jf))
            if chains:
                cases.append((scenario_dir.name, jf.stem, str(jf), chains))

    print(f"Cases: {len(cases)}", flush=True)

    # ── Deduplicate sequences ────────────────────────────────
    unique_seqs: dict[str, str] = {}  # hash → sequence
    for _, _, _, chains in cases:
        for c in chains:
            unique_seqs[c["hash"]] = c["sequence"]

    print(f"Unique protein sequences: {len(unique_seqs)}", flush=True)

    # ── Fetch MSA for each unique sequence ───────────────────
    done = 0
    for h, seq in sorted(unique_seqs.items()):
        done += 1
        cached = (cache_dir / "by_seq" / h / "uniref.a3m").exists()
        tag = "CACHED" if cached else f"FETCH ({done}/{len(unique_seqs)})"
        print(f"  [{tag}] {h[:12]} ({len(seq)} aa)", flush=True)
        try:
            ensure_msa_cached(seq, cache_dir, args.server_url)
        except Exception as e:
            print(f"    ERROR: {e}", file=sys.stderr, flush=True)

    # ── Generate patched Boltz-2 YAMLs ───────────────────────
    patched_dir = cache_dir / "patched_yaml"
    n_patched = 0
    for scenario, case_name, _, chains in cases:
        p = generate_patched_yaml(case_name, scenario, chains, cache_dir, inputs_dir, patched_dir)
        if p:
            n_patched += 1

    print(f"\nMSA cache  : {cache_dir}/by_seq/  ({len(unique_seqs)} sequences)")
    print(f"Patched YAML: {patched_dir}/  ({n_patched} files)")
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
