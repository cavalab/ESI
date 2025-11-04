set -e
data_path="data"

echo "BCH ..."
python binarization_code/binarization-BCH.py \
    --input_file ${data_path}/from-r/BCH.csv \
    --output_file ${data_path}/preprocessed_BCH.csv

echo "BIDMC ..."
python binarization_code/binarization-BIDMC.py \
    --input_path ${data_path}/from-r/ \
    --input_file_visits BIDMC-visits.csv \
    --input_file_vitals BIDMC-triage.csv \
    --output_file ${data_path}/preprocessed_BIDMC.csv

echo "CHLA ..."
python binarization_code/binarization-CHLA.py \
    --input_file ${data_path}/from-r/CHLA.csv \
    --output_file ${data_path}/preprocessed_CHLA.csv

echo "Stanford ..."
python binarization_code/binarization-Stanford.py \
    --input_file ${data_path}/from-r/stanford.csv \
    --output_file ${data_path}/preprocessed_Stanford.csv