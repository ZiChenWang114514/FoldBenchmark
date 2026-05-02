# FoldBenchmark Results


## protein_protein

| Case | af3 | alphafast | boltz2 | openfold3 | protenix | chai1 | intellifold |
|------|---|---|---|---|---|---|---|
| 1BRS_barnase_barstar | pTM=0.94 248s | pTM=0.94 142s | pTM=0.97 56s | 96s FAIL | pLDDT=95.8 pTM=0.96 115s | pTM=0.97 905s | pLDDT=0.9 pTM=0.88 69s |
| 1EMV_trypsin_inhibitor | pTM=0.92 244s | pTM=0.93 142s | pTM=0.96 49s | 96s FAIL | pLDDT=95.2 pTM=0.96 110s | pTM=0.96 178s | pLDDT=0.9 pTM=0.85 68s |
| 2PV7_homodimer | pTM=0.86 276s | pTM=0.84 142s | pTM=0.87 61s | 95s FAIL | pLDDT=89.9 pTM=0.86 1173s | pTM=0.91 285s | pLDDT=0.9 pTM=0.83 140s |
| 3HFM_lysozyme_fab | pTM=0.94 176s | pTM=0.92 142s | pTM=0.96 47s | 95s FAIL | pLDDT=96.7 pTM=0.96 108s | pTM=0.98 88s | pLDDT=1.0 pTM=0.86 57s |

## protein_ligand

| Case | af3 | alphafast | boltz2 | openfold3 | protenix | chai1 | intellifold |
|------|---|---|---|---|---|---|---|
| 1HSG_HIV_protease_indinavir | pTM=0.96 184s | pTM=0.95 135s | pTM=0.97 48s | 90s FAIL | pLDDT=97.3 pTM=0.98 106s | pTM=0.98 126s | pLDDT=0.9 pTM=0.89 63s |
| 3HTB_CDK2_inhibitor | pTM=0.85 186s | pTM=0.91 135s | pTM=0.96 48s | 87s FAIL | pLDDT=96.1 pTM=0.95 108s | pTM=0.91 132s | pLDDT=1.0 pTM=0.83 62s |
| 4LDE_BRAF_vemurafenib | pTM=0.74 329s | pTM=0.76 135s | pTM=0.85 64s | 101s FAIL | pLDDT=88.5 pTM=0.84 122s | pTM=0.83 160s | pLDDT=0.9 pTM=0.74 118s |
| 6LU7_Mpro_N3 | pTM=0.94 292s | pTM=0.94 135s | pTM=0.98 48s | 77s FAIL | pLDDT=96.5 pTM=0.97 103s | pTM=0.99 117s | pLDDT=1.0 pTM=0.89 92s |
| 7RN1_3CL_inhibitor | pTM=0.96 286s | pTM=0.96 135s | pTM=0.98 48s | 74s FAIL | pLDDT=96.9 pTM=0.97 112s | pTM=0.98 115s | pLDDT=1.0 pTM=0.89 87s |

## protein_rna

| Case | af3 | alphafast | boltz2 | openfold3 | protenix | chai1 | intellifold |
|------|---|---|---|---|---|---|---|
| 1ASY_tRNA_synthetase | pTM=0.50 874s | - | pTM=0.52 105s | 78s FAIL | 90s FAIL | 14s FAIL | pLDDT=0.5 pTM=0.45 283s |
| 1URN_U1A_RNA | pTM=0.55 251s | - | pTM=0.64 46s | 80s FAIL | 92s FAIL | 13s FAIL | pLDDT=0.6 pTM=0.54 132s |
| 2AZ0_U1A_RNA_hairpin | pTM=0.41 230s | - | pTM=0.63 46s | 74s FAIL | 84s FAIL | 13s FAIL | pLDDT=0.5 pTM=0.47 55s |
| 5V3F_FUS_RRM_RNA | pTM=0.56 256s | - | pTM=0.44 42s | 77s FAIL | 992s FAIL | pTM=0.37 97s | pLDDT=0.5 pTM=0.34 62s |

## monomer

| Case | af3 | alphafast | boltz2 | openfold3 | protenix | chai1 | intellifold |
|------|---|---|---|---|---|---|---|
| 1CRN_crambin | pTM=0.78 162s | pTM=0.79 109s | pTM=0.88 43s | 76s FAIL | pLDDT=96.8 pTM=0.90 98s | pTM=0.95 85s | pLDDT=0.9 pTM=0.72 50s |
| 1L2Y_trpcage | pTM=0.12 170s | pTM=0.13 109s | pTM=0.48 44s | 76s FAIL | pLDDT=93.8 pTM=0.46 96s | pTM=0.44 84s | pLDDT=0.9 pTM=0.12 45s |
| 1MBN_myoglobin | pTM=0.85 184s | pTM=0.91 109s | pTM=0.95 44s | 81s FAIL | pLDDT=94.0 pTM=0.95 102s | pTM=0.96 93s | pLDDT=0.9 pTM=0.83 60s |
| 1UBQ_ubiquitin | pTM=0.85 196s | pTM=0.86 109s | pTM=0.92 47s | 75s FAIL | pLDDT=94.1 pTM=0.92 102s | pTM=0.92 91s | pLDDT=0.9 pTM=0.78 57s |
| 2GB1_protein_G | pTM=0.83 168s | pTM=0.82 109s | pTM=0.92 45s | 77s FAIL | pLDDT=95.4 pTM=0.92 94s | pTM=0.91 90s | pLDDT=0.9 pTM=0.78 50s |

## antibody_antigen

| Case | af3 | alphafast | boltz2 | openfold3 | protenix | chai1 | intellifold |
|------|---|---|---|---|---|---|---|
| 1AHW_ab_tissue_factor | pTM=0.83 428s | pTM=0.81 179s | pTM=0.96 74s | 76s FAIL | pLDDT=88.4 pTM=0.69 130s | pTM=0.90 470s | pLDDT=0.9 pTM=0.63 161s |
| 1DVF_idiotope | pTM=0.40 420s | pTM=0.51 179s | pTM=0.92 61s | 76s FAIL | pLDDT=86.9 pTM=0.57 124s | pTM=0.72 385s | pLDDT=0.9 pTM=0.72 113s |
| 1MLC_ab_lysozyme | pTM=0.76 429s | pTM=0.75 179s | pTM=0.82 68s | 87s FAIL | pLDDT=91.4 pTM=0.80 126s | pTM=0.80 346s | pLDDT=0.9 pTM=0.69 146s |
| 4FQI_trastuzumab_HER2 | pTM=0.81 357s | pTM=0.82 179s | pTM=0.86 75s | 76s FAIL | pLDDT=87.3 pTM=0.84 113s | pTM=0.89 357s | pLDDT=0.9 pTM=0.66 115s |
| 7N4I_RBD_neutralizing_ab | pTM=0.84 327s | pTM=0.86 179s | pTM=0.91 61s | 79s FAIL | pLDDT=95.0 pTM=0.91 1468s | pTM=0.90 337s | pLDDT=0.9 pTM=0.84 110s |