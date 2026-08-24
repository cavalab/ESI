# ESI analysis

[![DOI](https://zenodo.org/badge/1081431914.svg)](https://doi.org/10.5281/zenodo.22085433)

Analysis of racial disparities in Emergency Severity Index (ESI) triage decisions using propensity score matching and high-risk symptom detection.

**Authors:** Blanca Romero Milà, Helena Coggan, Andrew M. Fine, Yuval Barak-Corren, Ben Y. Reis, Jaya Aysola, Pradip P. Chaudhari, and William G. La Cava.

This archive contains the public-data reproduction workflow for ESI triage-assignment analyses using MIMIC-IV-ED and MC-MED.

## Overview

This repository analyzes emergency department triage data and computationally implements the ESI algorithm to identify potential racial disparities in ESI triage assignments. The analysis combines:

- High-risk symptom detection from patient complaints
- Danger zone vital signs identification
- Propensity score matching to control for confounding variables
- Statistical analysis of odds ratios across racial groups

## Repository Structure
```
esi/
├── binarization_code/          # BIDMC and Stanford covariate-binarization scripts
├── ed-preprocessing/           # R preprocessing scripts and package requirements
├── scripts/
│   └── stage_diff.py           # Compare saved outputs from two analysis runs
├── src/                        # Core ESI, vital-sign, and matching functions
├── binarize.sh                 # Run public-site binarization
├── preprocess.sh               # Run one public-site raw-data preprocessor
├── run_analysis.sh             # Run the pipeline for one or both public sites
├── main.py                     # Main analysis pipeline
├── plot.py                     # Forest-plot entry point
├── center_configs.json         # Center-specific analysis configuration
├── environment.yml             # Conda environment specification
└── requirements.txt            # Python dependencies
```

## Quick Start

### 1. Installation

```bash
# Clone the repository
git clone https://github.com/cavalab/ESI.git
cd ESI

# if desired, make an environment with Python 3.11 in it using conda or mamba
mamba env create

# Create virtual environment with Python 3.11
python3.11 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Install dependencies 
pip install -r requirements.txt
```

### 2. Reproduce the public-data analyses

This release reproduces the analyses for the two public adult emergency-department datasets only:

* **BIDMC (Adult East):** [MIMIC-IV-ED v2.2](https://physionet.org/content/mimic-iv-ed/2.2/) together with the linked MIMIC-IV patient file.
* **Stanford (Adult West):** [MC-MED](https://physionet.org/content/mc-med).

The manuscript also reports results from two non-public pediatric datasets. Their data and center-specific preprocessing scripts are intentionally not included here. References to those centers that remain in the shared analysis code document the full study design; this public release is executable for BIDMC and Stanford only.

Download each source dataset in accordance with its access terms. Place the raw files for each site in separate directories, then run:

```bash
./preprocess.sh bidmc /path/to/mimic-iv-ed /path/to/esi/data/from-r
./preprocess.sh stanford /path/to/mc-med /path/to/esi/data/from-r
./binarize.sh /path/to/esi/data bidmc stanford
./run_analysis.sh results /path/to/esi/data BIDMC Stanford
```

The preprocessing scripts write `BIDMC-visits.csv`, `BIDMC-triage.csv`, and `stanford.csv` to `data/from-r/`; the binarization step creates `preprocessed_BIDMC.csv` and `preprocessed_Stanford.csv`; the final command writes results by center. The required R packages are listed in `ed-preprocessing/packages.txt` and can be installed with `Rscript ed-preprocessing/install-packages.r`.

### 3. Run one analysis directly

```bash
python main.py \
     --path_base ${data_base_directory} \
     --mode flagged_vs_unflagged \
     --center ${center} \
     --save_dir ${results_directory}
```

Use `plot.py` to visualize the saved results.

## Configuration

### Publicly reproducible centers

* **BIDMC**: Beth Israel Deaconess Medical Center
* **Stanford**: Stanford Hospital

### Analysis Modes

* **flagged_vs_unflagged**: Compares HB level 2, HB level 3, and HB level 2+3
* **all_combinations**: Compares HB level 2, HB2: danger zone vitals, HB2: high risk symptoms, HB level 3

### Center Configuration

Hospital-specific variables are defined in **center_configs.json**:

```json
{
  "BIDMC": {
    "triage_col": "acuity",
    "complaint_col": "chiefcomplaint",
    "race_predictor": ["is_hispanic", "is_black", "is_asian", "is_other"]
  }
}
```

## Output Files

Output is written to `{save_dir}/{center}/{mode}/`:

* `complaint_with_mask_and_vitals_{center}.csv`: Acuity data with high-risk flags
* `odds_ratios.csv`: Odds ratios and confidence intervals
* `significance.csv`: Statistical significance results

# Acknowledgments

This work was partially supported by NLM R01LM014300. 

Contact: @lacava 

https://cavalab.org
