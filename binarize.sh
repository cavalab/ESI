set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") [data-path] [bidmc|stanford ...]" >&2
}

data_path="data"
if [[ $# -gt 0 && ! "$1" =~ ^(bidmc|stanford)$ ]]; then
    data_path=$1
    shift
fi
sites=("$@")
if [[ ${#sites[@]} -eq 0 ]]; then
    sites=(bidmc stanford)
fi

for site in "${sites[@]}"; do
    if [[ ! "$site" =~ ^(bidmc|stanford)$ ]]; then
        usage
        exit 2
    fi
done

for site in "${sites[@]}"; do
    case "$site" in
    bidmc)
        echo "BIDMC ..."
        python binarization_code/binarization-BIDMC.py \
            --input_path "${data_path}/from-r/" \
            --input_file_visits BIDMC-visits.csv \
            --input_file_vitals BIDMC-triage.csv \
            --output_file "${data_path}/preprocessed_BIDMC.csv"
        ;;
    stanford)
        echo "Stanford ..."
        python binarization_code/binarization-Stanford.py \
            --input_file "${data_path}/from-r/stanford.csv" \
            --output_file "${data_path}/preprocessed_Stanford.csv"
        ;;
    esac
done
