# ESI analysis

Analysis of racial disparities in Emergency Severity Index (ESI) triage decisions using propensity score matching and high-risk symptom detection.

## Overview

This repository analyzes emergency department triage data and computational implements the ESI algorithm to identify potential racial disparities in ESI triage assignments. The analysis combines:
- High-risk symptom detection from patient complaints
- Danger zone vital signs identification
- Propensity score matching to control for confounding variables
- Statistical analysis of odds ratios across racial groups

## Repository Structure
```
ESI-LaCava/
├── binarization_code/          # Data binarization code 
├── CHLA_preprocessing/         # R code to preprocess CHLA data
├── figures/                    # Generated forest plots 
├── results/                    # Output CSV files with analysis results
├── src/                        # Core analysis modules
│   ├── high_risk_dictionary.py # High-risk symptom detection functions
│   ├── vital_signs.py          # Danger zone vital signs analysis
│   └── propensity_score_matching.py # PSM analysis, odds ratio calculations, and plotting
├── center_configs.json         # Hospital-specific configuration variables
├── figure-ORs.ipynb            # Notebook for creating styled forest plots
├── main.py                     # Main analysis pipeline
├── plot.py                     # Forest plot generation
├── requirements.txt            # Python dependencies
└── README.md                   
```


## Quick Start

### 1. Installation

```
# Clone the repository
git clone https://github.com/yourusername/ESI.git
cd ESI-LaCava

# if desired, make an environment with Python 3.11 in it using conda or mamba
mamba env create

# Create virtual environment with Python 3.11
python3.11 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Install dependencies 
pip install -r requirements.txt
```

### 2. Data Preparation

tl;dr:

```
bash preprocess.sh
bash binarize.sh
bash run_analysis.sh
```

#### 2.1 Data Preprocessing Pipeline

If you need to generate these files from **raw data**, follow this two-step process:

**Step 1: Raw Data → Preprocessed Data**

Use the following repository for center-specific preprocessing: https://github.com/hcoggan/ed-preprocessing

This script results in the following preprocessed datasets:

* preprocessed_CHLA.csv : Private data from Children's Los Angeles (Pediatric West)
* preprocessed_BIDMC.csv : Derived from the publicly available [MIMIC-IV-ED](https://physionet.org/content/mimic-iv-ed/2.2/) dataset from Beth Israel Deaconess (Adult East)
* preprocessed_Stanford.csv : Derived from the publicly available [MC-MED](https://physionet.org/content/mc-med/1.0.0/) dataset from Stanford Hospital (Adult West)
* preprocessed_BCH.csv: Private data from Boston Children's Hospital (Pediatric East)

**Step 2: Preprocessed Data → Binarized Covariates**

Run the appropriate binarization script for each center: 

```bash
python binarization-CHLA.py      
python binarization-BIDMC.py     
python binarization-Stanford.py  
python binarization-BCH.py       
```

This creates {dataset}_binarized.csv datasets which are used in the main analysis.

### 3. Run Complete Analysis 
See `run_analysis.sh`, which computes the OR comparisons as follows:

```
python main.py \
     --path_base ${data_base_directory} \
     --mode flagged_vs_unflagged \
     --center ${center} \ #e.g. BIDMC
     --save_dir ${results_directory}
```

`forest_plot.ipynb` visualizes these results.

## Configuration
### Hospital Centers
The analysis supports four hospital centers:
* **CHLA**: Children's Hospital Los Angeles
* **BIDMC**: Beth Israel Deaconess Medical Center
* **Stanford**: Stanford Hospital
* **BCH**: Boston Children's Hospital

### Analysis Modes
* **flagged_vs_unflagged**: Compares HB level 2, HB level 3, and HB level 2+3
* **all_combinations**: Compares HB level 2, HB2: danger zone vitals, HB2: high risk symptoms, HB level 3

### Center Configuration
Hospital-specific variables are defined in **center_configs.json**:

```json
{
  "CHLA": {
    "triage_col": "esi_acuity",
    "complaint_col": "chief_complaint", 
    "race_predictor": "race_",
    "race_names": ["White", "Black", "Hispanic", "Asian"],
    "race_order": ["White", "Black", "Hispanic", "Asian"],
    "covariate_prefixes": ["age", "gender", "insurance"]
  }
}
```
## Output Files
### Results Directory
* complaint_with_mask_{center}.csv: Filtered acuity data
* complaint_with_mask_and_vitals_{center}.csv: Data with high-risk flags
* odds_{center}_{mode}.csv: Odds ratios and confidence intervals
* sign_{center}_{mode}.csv: Statistical significance results
### Figures Directory
* or_all_{mode}.pdf: Multi-panel forest plots for all centers
