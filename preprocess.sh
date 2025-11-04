Rscript ed-preprocessing/bch-preprocess-data.r
# Rscript ed-preprocessing/bidmc-preprocess-data.r
# Rscript ed-preprocessing/stanford-preprocess-data.r
# Rscript ed-preprocessing/chla-preprocess-data.r

# # soft link files
# mkdir -p data
# mkdir -p data/from-r
# ln -s \
#     /rc-fs/chip-lacava/Groups/BCH-ED/reprocessing-bill/preprocessed-visits.csv \
#     data/from-r/BCH.csv

# ln -s \
#     /rc-fs/chip-lacava/Public/physionet.org/files/mimic-iv-ed/2.2/disparities/preprocessed-visits.csv \
#     data/from-r/BIDMC-visits.csv
# ln -s \
#     /rc-fs/chip-lacava/Public/physionet.org/files/mimic-iv-ed/2.2/disparities/triage.csv  \
#     data/from-r/BIDMC-triage.csv

# ln -s \
#     /rc-fs/chip-lacava/Public/physionet.org/files/mc-med/disparities/preprocessed-visits.csv \
#     data/from-r/stanford.csv

# ln -s \
#     /rc-fs/chip-lacava/Groups/CHLA-ED/preprocessed-bill/preprocessed_data_with_triage_vitals.csv \
#     data/from-r/CHLA.csv 