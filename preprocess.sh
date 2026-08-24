#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") {bidmc|stanford} RAW_DATA_DIR OUTPUT_DIR" >&2
}

if [[ $# -ne 3 ]]; then
    usage
    exit 2
fi

site=${1,,}
shift
raw_data_dir=$1
output_dir=$2
case "$site" in
    bidmc)
        preprocess_script="bidmc-preprocess-data.r"
        output_files=(BIDMC-visits.csv BIDMC-triage.csv)
        ;;
    stanford)
        preprocess_script="stanford-preprocess-data.r"
        output_files=(stanford.csv)
        ;;
    *)
        echo "Unknown site: $1" >&2
        usage
        exit 2
        ;;
esac

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$output_dir"
Rscript "$repo_dir/ed-preprocessing/$preprocess_script" "$raw_data_dir" "$output_dir"
