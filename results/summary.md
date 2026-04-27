# FoldBenchmark Results


## protein_protein

| Case | af3 | boltz2 | openfold3 | protenix | chai1 | intellifold |
|------|---|---|---|---|---|---|
| 1BRS_barnase_barstar | pTM=0.94 248s | pTM=0.97 56s | 38900s | 83s FAIL | 905s | pLDDT=0.9 pTM=0.88 69s |
| 1EMV_trypsin_inhibitor | pTM=0.92 244s | pTM=0.96 49s | - | 83s FAIL | 178s | pLDDT=0.9 pTM=0.85 68s |
| 2PV7_homodimer | pTM=0.86 276s | pTM=0.87 61s | - | 89s FAIL | 285s | pLDDT=0.9 pTM=0.83 140s |
| 3HFM_lysozyme_fab | pTM=0.94 176s | pTM=0.96 47s | - | 85s FAIL | 88s | pLDDT=1.0 pTM=0.86 57s |

## protein_ligand

| Case | af3 | boltz2 | openfold3 | protenix | chai1 | intellifold |
|------|---|---|---|---|---|---|
| 1HSG_HIV_protease_indinavir | pTM=0.96 184s | pTM=0.97 48s | - | 86s FAIL | 126s | pLDDT=0.9 pTM=0.89 63s |
| 3HTB_CDK2_inhibitor | pTM=0.85 186s | pTM=0.96 48s | - | 85s FAIL | 132s | pLDDT=1.0 pTM=0.83 62s |
| 4LDE_BRAF_vemurafenib | pTM=0.74 329s | pTM=0.85 64s | - | 83s FAIL | 160s | pLDDT=0.9 pTM=0.74 118s |
| 6LU7_Mpro_N3 | pTM=0.94 292s | pTM=0.98 48s | - | 83s FAIL | 117s | pLDDT=1.0 pTM=0.89 92s |
| 7RN1_3CL_inhibitor | pTM=0.96 286s | pTM=0.98 48s | - | 84s FAIL | 115s | pLDDT=1.0 pTM=0.89 87s |

## protein_rna

| Case | af3 | boltz2 | openfold3 | protenix | chai1 | intellifold |
|------|---|---|---|---|---|---|
| 1ASY_tRNA_synthetase | pTM=0.50 874s | pTM=0.52 105s | - | 86s FAIL | 14s FAIL | pLDDT=0.5 pTM=0.45 283s |
| 1URN_U1A_RNA | pTM=0.55 251s | pTM=0.64 46s | - | 88s FAIL | 13s FAIL | pLDDT=0.6 pTM=0.54 132s |
| 2AZ0_U1A_RNA_hairpin | pTM=0.41 230s | pTM=0.63 46s | - | 86s FAIL | 13s FAIL | pLDDT=0.5 pTM=0.47 55s |
| 5V3F_FUS_RRM_RNA | pTM=0.56 256s | pTM=0.44 42s | - | 88s FAIL | 97s | pLDDT=0.5 pTM=0.34 62s |

## monomer

| Case | af3 | boltz2 | openfold3 | protenix | chai1 | intellifold |
|------|---|---|---|---|---|---|
| 1CRN_crambin | pTM=0.78 162s | pTM=0.88 43s | - | 86s FAIL | 85s | pLDDT=0.9 pTM=0.72 50s |
| 1L2Y_trpcage | pTM=0.12 170s | pTM=0.48 44s | - | 82s FAIL | 84s | pLDDT=0.9 pTM=0.12 45s |
| 1MBN_myoglobin | pTM=0.85 184s | pTM=0.95 44s | - | 89s FAIL | 93s | pLDDT=0.9 pTM=0.83 60s |
| 1UBQ_ubiquitin | pTM=0.85 196s | pTM=0.92 47s | - | 75s FAIL | 91s | pLDDT=0.9 pTM=0.78 57s |
| 2GB1_protein_G | pTM=0.83 168s | pTM=0.92 45s | - | 78s FAIL | 90s | pLDDT=0.9 pTM=0.78 50s |

## antibody_antigen

| Case | af3 | boltz2 | openfold3 | protenix | chai1 | intellifold |
|------|---|---|---|---|---|---|
| 1AHW_ab_tissue_factor | pTM=0.83 428s | pTM=0.96 74s | - | 83s FAIL | 470s | pLDDT=0.9 pTM=0.63 161s |
| 1DVF_idiotope | pTM=0.40 420s | pTM=0.92 61s | - | 81s FAIL | 385s | pLDDT=0.9 pTM=0.72 113s |
| 1MLC_ab_lysozyme | pTM=0.76 429s | pTM=0.82 68s | - | 79s FAIL | 346s | pLDDT=0.9 pTM=0.69 146s |
| 4FQI_trastuzumab_HER2 | pTM=0.81 357s | pTM=0.86 75s | - | 82s FAIL | 357s | pLDDT=0.9 pTM=0.66 115s |
| 7N4I_RBD_neutralizing_ab | pTM=0.84 327s | pTM=0.91 61s | - | 75s FAIL | 337s | pLDDT=0.9 pTM=0.84 110s |