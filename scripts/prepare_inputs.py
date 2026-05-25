#!/usr/bin/env python3
"""
Fetch sequences from RCSB PDB and generate inputs for all models.
Usage: python prepare_inputs.py
"""
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
INPUTS_DIR = PROJECT_ROOT / "inputs"

# ============================================================
# Test case definitions
# Format: (name, pdb_id, chains_spec, scenario)
# chains_spec: list of (chain_id, entity_type)
#   entity_type: "protein", "rna", "dna", "ligand"
# For ligands: (chain_id, "ligand", smiles_or_ccd)
# ============================================================

TEST_CASES = {
    "protein_protein": [
        {
            "name": "2PV7_homodimer",
            "pdb_id": "2PV7",
            "chains": [("A", "protein"), ("B", "protein")],
        },
        {
            "name": "1BRS_barnase_barstar",
            "pdb_id": "1BRS",
            "chains": [("A", "protein"), ("D", "protein")],
        },
        {
            "name": "1A2K_GH_receptor",
            "pdb_id": "1A2K",
            "chains": [("A", "protein"), ("B", "protein")],
        },
        {
            "name": "3HFM_lysozyme_fab",
            "pdb_id": "3HFM",
            "chains": [("Y", "protein"), ("A", "protein")],
        },
        {
            "name": "1EMV_trypsin_inhibitor",
            "pdb_id": "1EMV",
            "chains": [("A", "protein"), ("B", "protein")],
        },
    ],
    "protein_ligand": [
        {
            "name": "7RN1_3CL_inhibitor",
            "pdb_id": "7RN1",
            "chains": [("A", "protein")],
            "ligands": [("B", "O=C(C(N(C1=CC=C(C=C1)OC(F)(Cl)F)C(CCl)=O)C2=CN=CN=C2)NCC3=CC=CC=C3")],
        },
        {
            "name": "1HSG_HIV_protease_indinavir",
            "pdb_id": "1HSG",
            "chains": [("A", "protein"), ("B", "protein")],
            "ligands": [("C", "CC(C)(C)NC(=O)[C@@H]1CN(Cc2cccnc2)CCN1C[C@@H](O)C[C@@H](Cc1ccccc1)C(=O)N[C@H]1c2ccccc2C[C@H]1O")],
        },
        {
            "name": "6LU7_Mpro_N3",
            "pdb_id": "6LU7",
            "chains": [("A", "protein")],
            "ligands": [("B", "O=C(/C=C/C(=O)OC)N[C@@H](CC1CCCCC1)C(=O)N[C@@H](C[C@@H]1CCNC1=O)C(=O)[C@H](CC(C)C)NC(=O)[C@@H](NC(=O)OC(C)(C)C)CC(C)C")],
        },
        {
            "name": "4LDE_BRAF_vemurafenib",
            "pdb_id": "4LDE",
            "chains": [("A", "protein")],
            "ligands": [("B", "CCCS(=O)(=O)Nc1ccc(-c2c[nH]c3c(F)cc(-c4cc(F)c(Cl)cc4F)cc23)c(F)c1F")],
        },
        {
            "name": "3HTB_CDK2_inhibitor",
            "pdb_id": "3HTB",
            "chains": [("A", "protein")],
            "ligands": [("B", "ATP")],  # CCD code
        },
    ],
    "protein_rna": [
        # Verified against RCSB chain assignments 2026-05-07.
        # Earlier versions had wrong chain IDs (e.g. 1ASY 'B' is protein, not RNA);
        # 5V3F and 4TZX were RNA-only (no protein chain) and have been removed.
        {
            "name": "2AZ0_U1A_RNA_hairpin",
            "pdb_id": "2AZ0",
            "chains": [("A", "protein"), ("C", "rna")],
        },
        {
            "name": "1ASY_tRNA_synthetase",
            "pdb_id": "1ASY",
            "chains": [("A", "protein"), ("R", "rna")],
        },
        {
            "name": "1URN_U1A_RNA",
            "pdb_id": "1URN",
            "chains": [("A", "protein"), ("P", "rna")],
        },
    ],
    "monomer": [
        {
            "name": "1UBQ_ubiquitin",
            "pdb_id": "1UBQ",
            "chains": [("A", "protein")],
        },
        {
            "name": "1CRN_crambin",
            "pdb_id": "1CRN",
            "chains": [("A", "protein")],
        },
        {
            "name": "1MBN_myoglobin",
            "pdb_id": "1MBN",
            "chains": [("A", "protein")],
        },
        {
            "name": "2GB1_protein_G",
            "pdb_id": "2GB1",
            "chains": [("A", "protein")],
        },
        {
            "name": "1L2Y_trpcage",
            "pdb_id": "1L2Y",
            "chains": [("A", "protein")],
        },
    ],
    "antibody_antigen": [
        {
            "name": "1AHW_ab_tissue_factor",
            "pdb_id": "1AHW",
            "chains": [("A", "protein"), ("B", "protein"), ("C", "protein")],
        },
        {
            "name": "1DVF_idiotope",
            "pdb_id": "1DVF",
            "chains": [("A", "protein"), ("B", "protein"), ("C", "protein"), ("D", "protein")],
        },
        {
            "name": "1MLC_ab_lysozyme",
            "pdb_id": "1MLC",
            "chains": [("A", "protein"), ("B", "protein"), ("E", "protein")],
        },
        {
            "name": "7N4I_RBD_neutralizing_ab",
            "pdb_id": "7N4I",
            "chains": [("A", "protein"), ("H", "protein"), ("L", "protein")],
        },
        {
            "name": "4FQI_trastuzumab_HER2",
            "pdb_id": "4FQI",
            "chains": [("A", "protein"), ("B", "protein"), ("C", "protein")],
        },
    ],
    # ── New scenarios (added 2026-05-24) ──────────────────────────
    # Chain IDs verified against RCSB polymer_entity API.
    "protein_dna": [
        {
            "name": "3HDD_homeodomain_DNA",
            "pdb_id": "3HDD",
            # Engrailed homeodomain homodimer + double-stranded DNA
            "chains": [("A", "protein"), ("B", "protein"), ("C", "dna"), ("D", "dna")],
        },
        {
            "name": "1BL0_MarA_DNA",
            "pdb_id": "1BL0",
            # MarA transcription factor + double-stranded DNA
            "chains": [("A", "protein"), ("B", "dna"), ("C", "dna")],
        },
        {
            "name": "1LMB_lambda_repressor_DNA",
            "pdb_id": "1LMB",
            # Lambda CI repressor homodimer + operator DNA (numeric chain IDs)
            "chains": [("3", "protein"), ("4", "protein"), ("1", "dna"), ("2", "dna")],
        },
        {
            "name": "1J1V_DnaA_DNA",
            "pdb_id": "1J1V",
            # DnaA domain IV + DnaA box DNA
            "chains": [("A", "protein"), ("B", "dna"), ("C", "dna")],
        },
    ],
    "homo_multimer": [
        {
            "name": "1HTI_TIM_homodimer",
            "pdb_id": "1HTI",
            # Human triosephosphate isomerase homodimer (248 aa × 2)
            "chains": [("A", "protein"), ("B", "protein")],
        },
        {
            "name": "1SAK_p53_TET_tetramer",
            "pdb_id": "1SAK",
            # p53 tetramerization domain homotetramer (42 aa × 4, NMR)
            "chains": [("A", "protein"), ("B", "protein"), ("C", "protein"), ("D", "protein")],
        },
        {
            "name": "14GS_GST_homodimer",
            "pdb_id": "14GS",
            # Glutathione S-transferase P1-1 homodimer
            "chains": [("A", "protein"), ("B", "protein")],
        },
    ],
    "metal_ion": [
        {
            "name": "1CA2_carbonic_anhydrase_ZN",
            "pdb_id": "1CA2",
            # Human carbonic anhydrase II + catalytic zinc (259 aa + 1 ZN)
            "chains": [("A", "protein")],
            "ligands": [("B", "ZN")],
        },
        {
            "name": "8TLN_thermolysin_ZN_CA",
            "pdb_id": "8TLN",
            # Thermolysin: 1 catalytic ZN + 4 structural CA
            "chains": [("E", "protein")],
            "ligands": [("A", "ZN"), ("B", "CA"), ("C", "CA"), ("D", "CA"), ("F", "CA")],
        },
        {
            "name": "2SOD_superoxide_dismutase_CU_ZN",
            "pdb_id": "2SOD",
            # Cu/Zn SOD dimer (2 of 4 ASU chains) + 2 CU + 2 ZN
            "chains": [("B", "protein"), ("G", "protein")],
            "ligands": [("A", "CU"), ("C", "ZN"), ("D", "CU"), ("F", "ZN")],
        },
    ],
    "covalent_mod": [
        {
            "name": "5P9J_BTK_ibrutinib",
            "pdb_id": "5P9J",
            # BTK kinase + ibrutinib (covalent at Cys481), CCD=8E8
            "chains": [("A", "protein")],
            "ligands": [("B", "8E8")],
        },
        {
            "name": "4G5J_EGFR_afatinib",
            "pdb_id": "4G5J",
            # EGFR kinase + afatinib/BIBW2992 (covalent at Cys797), CCD=0WN
            "chains": [("A", "protein")],
            "ligands": [("B", "0WN")],
        },
        {
            "name": "6OIM_KRAS_G12C_sotorasib",
            "pdb_id": "6OIM",
            # KRAS G12C + AMG 510/sotorasib (covalent at Cys12) + MG + GDP
            "chains": [("A", "protein")],
            "ligands": [("B", "MOV"), ("C", "MG"), ("D", "GDP")],
        },
    ],
}


def fetch_pdb_sequences(pdb_id: str) -> dict:
    """Fetch entity sequences from RCSB PDB API."""
    url = f"https://data.rcsb.org/rest/v1/core/entry/{pdb_id}"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=30) as resp:
            entry_data = json.loads(resp.read())
    except Exception as e:
        print(f"  WARNING: Failed to fetch entry {pdb_id}: {e}")
        return {}

    # Get polymer entities
    sequences = {}
    entity_ids = entry_data.get("rcsb_entry_container_identifiers", {}).get("polymer_entity_ids", [])
    for eid in entity_ids:
        entity_url = f"https://data.rcsb.org/rest/v1/core/polymer_entity/{pdb_id}/{eid}"
        try:
            req = urllib.request.Request(entity_url)
            with urllib.request.urlopen(req, timeout=30) as resp:
                entity_data = json.loads(resp.read())
            seq = entity_data.get("entity_poly", {}).get("pdbx_seq_one_letter_code_can", "")
            entity_type = entity_data.get("entity_poly", {}).get("type", "")
            auth_chains = entity_data.get("rcsb_polymer_entity_container_identifiers", {}).get("auth_asym_ids", [])
            for chain in auth_chains:
                sequences[chain] = {
                    "sequence": seq.replace("\n", ""),
                    "type": "protein" if "polypeptide" in entity_type else ("rna" if "ribonucleotide" in entity_type else "dna"),
                }
        except Exception as e:
            print(f"  WARNING: Failed to fetch entity {pdb_id}/{eid}: {e}")
    time.sleep(0.2)  # Rate limit
    return sequences


def generate_af3_json(case: dict, sequences: dict, scenario: str) -> dict:
    """Generate AF3-format JSON input.

    AF3/AlphaFast requires chain IDs to be single uppercase letters (A-Z).
    PDBs like 1LMB use numeric chain IDs ('1','2','3','4'). When any chain ID
    is not a single uppercase ASCII letter, we auto-remap all chain IDs to
    A, B, C, ... in the order they appear in the case definition.
    """
    # Build remap if any chain ID is not a single uppercase letter
    all_orig_ids = [cid for cid, _ in case["chains"]] + [lid for lid, _ in case.get("ligands", [])]
    needs_remap = any(not (len(cid) == 1 and cid.isupper()) for cid in all_orig_ids)
    if needs_remap:
        letters = [chr(ord("A") + i) for i in range(26)]
        remap = {orig: letters[i] for i, orig in enumerate(all_orig_ids)}
        print(f"  NOTE: Remapping chain IDs for {case['name']}: {remap}")
    else:
        remap = {cid: cid for cid in all_orig_ids}

    seqs = []
    for chain_id, entity_type in case["chains"]:
        if chain_id not in sequences:
            print(f"  WARNING: Chain {chain_id} not found in PDB {case['pdb_id']}")
            continue
        chain_info = sequences[chain_id]
        out_id = remap[chain_id]
        if entity_type == "protein":
            seqs.append({"protein": {"id": [out_id], "sequence": chain_info["sequence"]}})
        elif entity_type == "rna":
            seqs.append({"rna": {"id": [out_id], "sequence": chain_info["sequence"]}})
        elif entity_type == "dna":
            seqs.append({"dna": {"id": [out_id], "sequence": chain_info["sequence"]}})

    # Add ligands if present
    for lig_id, smiles_or_ccd in case.get("ligands", []):
        out_id = remap[lig_id]
        if len(smiles_or_ccd) <= 5 and smiles_or_ccd.isalnum():
            seqs.append({"ligand": {"id": [out_id], "ccdCodes": [smiles_or_ccd]}})
        else:
            seqs.append({"ligand": {"id": [out_id], "smiles": smiles_or_ccd}})

    return {
        "name": case["name"],
        "sequences": seqs,
        "modelSeeds": [1],
        "dialect": "alphafold3",
        "version": 1,
    }


def generate_boltz2_yaml(af3_json: dict) -> str:
    """Convert AF3 JSON to Boltz-2 YAML format."""
    lines = ["version: 1", "sequences:"]
    for entry in af3_json["sequences"]:
        if "protein" in entry:
            lines.append(f"  - protein:")
            lines.append(f"      id: {entry['protein']['id'][0]}")
            lines.append(f"      sequence: {entry['protein']['sequence']}")
        elif "rna" in entry:
            lines.append(f"  - rna:")
            lines.append(f"      id: {entry['rna']['id'][0]}")
            lines.append(f"      sequence: {entry['rna']['sequence']}")
        elif "dna" in entry:
            lines.append(f"  - dna:")
            lines.append(f"      id: {entry['dna']['id'][0]}")
            lines.append(f"      sequence: {entry['dna']['sequence']}")
        elif "ligand" in entry:
            lines.append(f"  - ligand:")
            lines.append(f"      id: {entry['ligand']['id'][0]}")
            if "smiles" in entry["ligand"]:
                lines.append(f"      smiles: \"{entry['ligand']['smiles']}\"")
            elif "ccdCodes" in entry["ligand"]:
                lines.append(f"      ccd: {entry['ligand']['ccdCodes'][0]}")
    return "\n".join(lines) + "\n"


def generate_chai1_fasta(af3_json: dict) -> str:
    """Convert AF3 JSON to Chai-1 FASTA format."""
    lines = []
    for entry in af3_json["sequences"]:
        if "protein" in entry:
            chain_id = entry["protein"]["id"][0]
            lines.append(f">protein|name=chain_{chain_id}")
            lines.append(entry["protein"]["sequence"])
        elif "rna" in entry:
            chain_id = entry["rna"]["id"][0]
            lines.append(f">rna|name=chain_{chain_id}")
            lines.append(entry["rna"]["sequence"])
        elif "dna" in entry:
            chain_id = entry["dna"]["id"][0]
            lines.append(f">dna|name=chain_{chain_id}")
            lines.append(entry["dna"]["sequence"])
        elif "ligand" in entry:
            chain_id = entry["ligand"]["id"][0]
            if "smiles" in entry["ligand"]:
                lines.append(f">ligand|name=chain_{chain_id}")
                lines.append(entry["ligand"]["smiles"])
    return "\n".join(lines) + "\n"


def generate_protenix_json(af3_json: dict) -> list:
    """Convert AF3 JSON to Protenix format (list of job dicts)."""
    seqs = []
    for entry in af3_json["sequences"]:
        if "protein" in entry:
            seqs.append({"proteinChain": {
                "sequence": entry["protein"]["sequence"],
                "count": 1,
            }})
        elif "rna" in entry:
            seqs.append({"rnaSequence": {
                "sequence": entry["rna"]["sequence"],
                "count": 1,
            }})
        elif "dna" in entry:
            seqs.append({"dnaSequence": {
                "sequence": entry["dna"]["sequence"],
                "count": 1,
            }})
        elif "ligand" in entry:
            lig = entry["ligand"]
            if "smiles" in lig:
                seqs.append({"ligand": {"ligand": lig["smiles"], "count": 1}})
            elif "ccdCodes" in lig:
                seqs.append({"ligand": {"ligand": f"CCD_{lig['ccdCodes'][0]}", "count": 1}})
    return [{"name": af3_json["name"], "sequences": seqs, "modelSeeds": af3_json.get("modelSeeds", [1])}]


def generate_rf3_json(af3_json: dict) -> list:
    """Convert AF3 JSON to RoseTTAFold3 (Foundry) format.

    RF3 uses a flat list of dicts, each with 'name' and 'components'.
    Each component is a dict with 'seq'+'chain_id' (protein/RNA/DNA) or
    'smiles'/'ccd_code' (ligand).  MSA paths are optional ('msa_path').
    """
    components = []
    for entry in af3_json["sequences"]:
        if "protein" in entry:
            components.append({
                "seq": entry["protein"]["sequence"],
                "chain_id": entry["protein"]["id"][0],
            })
        elif "rna" in entry:
            components.append({
                "seq": entry["rna"]["sequence"],
                "chain_id": entry["rna"]["id"][0],
            })
        elif "dna" in entry:
            components.append({
                "seq": entry["dna"]["sequence"],
                "chain_id": entry["dna"]["id"][0],
            })
        elif "ligand" in entry:
            lig = entry["ligand"]
            if "smiles" in lig:
                components.append({"smiles": lig["smiles"]})
            elif "ccdCodes" in lig:
                components.append({"ccd_code": lig["ccdCodes"][0]})
    return {"name": af3_json["name"], "components": components}


def generate_openfold3_json(af3_json: dict) -> dict:
    """Convert AF3 JSON to OpenFold3 query format."""
    chains = []
    for entry in af3_json["sequences"]:
        if "protein" in entry:
            chains.append({
                "molecule_type": "protein",
                "chain_ids": entry["protein"]["id"][0],
                "sequence": entry["protein"]["sequence"],
            })
        elif "rna" in entry:
            chains.append({
                "molecule_type": "rna",
                "chain_ids": entry["rna"]["id"][0],
                "sequence": entry["rna"]["sequence"],
            })
        elif "dna" in entry:
            chains.append({
                "molecule_type": "dna",
                "chain_ids": entry["dna"]["id"][0],
                "sequence": entry["dna"]["sequence"],
            })
        elif "ligand" in entry:
            lig = entry["ligand"]
            chain_entry = {
                "molecule_type": "ligand",
                "chain_ids": lig["id"][0],
            }
            if "smiles" in lig:
                chain_entry["smiles"] = lig["smiles"]
            elif "ccdCodes" in lig:
                chain_entry["ccd_codes"] = lig["ccdCodes"][0]
            chains.append(chain_entry)
    return {"queries": {af3_json["name"]: {"use_msas": True, "chains": chains}}}


def main():
    total = sum(len(cases) for cases in TEST_CASES.values())
    print(f"Preparing {total} test cases across {len(TEST_CASES)} scenarios...")

    for scenario, cases in TEST_CASES.items():
        print(f"\n=== {scenario} ({len(cases)} cases) ===")
        for case in cases:
            print(f"  Processing {case['name']} (PDB: {case['pdb_id']})...")

            # Fetch sequences from PDB
            sequences = fetch_pdb_sequences(case["pdb_id"])
            if not sequences:
                print(f"    SKIP: Could not fetch sequences")
                continue

            # Generate AF3 JSON
            af3_json = generate_af3_json(case, sequences, scenario)
            if not af3_json["sequences"]:
                print(f"    SKIP: No valid sequences")
                continue

            # Save AF3 JSON
            json_dir = INPUTS_DIR / scenario / "af3_json"
            json_dir.mkdir(parents=True, exist_ok=True)
            json_path = json_dir / f"{case['name']}.json"
            with open(json_path, "w") as f:
                json.dump(af3_json, f, indent=2)

            # Save Protenix JSON
            ptx_dir = INPUTS_DIR / scenario / "protenix_json"
            ptx_dir.mkdir(parents=True, exist_ok=True)
            ptx_path = ptx_dir / f"{case['name']}.json"
            with open(ptx_path, "w") as f:
                json.dump(generate_protenix_json(af3_json), f, indent=2)

            # Save OpenFold3 JSON
            of3_dir = INPUTS_DIR / scenario / "openfold3_json"
            of3_dir.mkdir(parents=True, exist_ok=True)
            of3_path = of3_dir / f"{case['name']}.json"
            with open(of3_path, "w") as f:
                json.dump(generate_openfold3_json(af3_json), f, indent=2)

            # Save RF3 JSON
            rf3_dir = INPUTS_DIR / scenario / "rf3_json"
            rf3_dir.mkdir(parents=True, exist_ok=True)
            rf3_path = rf3_dir / f"{case['name']}.json"
            with open(rf3_path, "w") as f:
                json.dump(generate_rf3_json(af3_json), f, indent=2)

            # Save Boltz-2 YAML
            yaml_dir = INPUTS_DIR / scenario / "boltz2_yaml"
            yaml_dir.mkdir(parents=True, exist_ok=True)
            yaml_path = yaml_dir / f"{case['name']}.yaml"
            with open(yaml_path, "w") as f:
                f.write(generate_boltz2_yaml(af3_json))

            # Save Chai-1 FASTA
            fasta_dir = INPUTS_DIR / scenario / "chai1_fasta"
            fasta_dir.mkdir(parents=True, exist_ok=True)
            fasta_path = fasta_dir / f"{case['name']}.fasta"
            with open(fasta_path, "w") as f:
                f.write(generate_chai1_fasta(af3_json))

            print(f"    OK: {len(af3_json['sequences'])} chains")

    print(f"\nDone! Inputs saved to {INPUTS_DIR}/")


if __name__ == "__main__":
    main()
