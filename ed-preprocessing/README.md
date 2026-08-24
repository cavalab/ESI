# ed-preprocessing
Code to preprocess the two public emergency-department datasets used in this study.

# Usage

## Requirements

- R version 4.4.2 or higher
- `packages.txt` contains the R libraries that are needed. To install them, run `Rscript install-packages.r`.

## Usage

Each script links together files containing demographic and visit information to create a database describing >100k visits to a particular emergency department. The script creates the 'base files', containing all information at the start of the visit (sex, race, chief complaint, triage acuity etc.) but not necessarily information about decisions taken over the course of the visit (medications, imaging etc), as the level of detail required may vary depending on the analysis.

From the repository root, run the preprocessing workflow with the directory holding the raw source files and an output directory:

```bash
./preprocess.sh bidmc /path/to/mimic-iv-ed /path/to/esi/data/from-r
```

Valid site arguments are `bidmc` and `stanford`.

- bidmc-preprocess-data.r: Preprocesses files from MIMIC-IV-ED (edstays.csv, medrecon.csv, triage.csv, diagnosis.csv) and MIMIC-IV (patients.csv) to create a database of ~400k visits to the emergency department of Beth Israel Deaconess Medical Center (adult hospital in Boston, MA).
- stanford-preprocess-data.r: Preprocesses files from MC-MED (visits.csv, pmh.csv) to create a database of ~115k visits to the emergency department of Stanford Medical Center (adult hospital in Stanford, CA).


# References

- MIMIC-IV-ED: Johnson, A., Bulgarelli, L., Pollard, T., Celi, L. A., Mark, R., & Horng, S. (2023). MIMIC-IV-ED (version 2.2). PhysioNet. RRID:SCR_007345. https://doi.org/10.13026/5ntk-km72.
- MC-MED: Kansal, A., Chen, E., Jin, B.T. et al. MC-MED, multimodal clinical monitoring in the emergency department. Sci Data 12, 1094 (2025). https://doi.org/10.1038/s41597-025-05419-5.
