set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $(basename "$0") RESULTS_DIR [data-path] [BIDMC|Stanford ...]" >&2
    exit 2
fi

path_base=${2:-data}
if [[ $# -gt 2 ]]; then
    centers=("${@:3}")
else
    centers=("BIDMC" "Stanford")
fi

for center in "${centers[@]}"; do
    if [[ ! "$center" =~ ^(BIDMC|Stanford)$ ]]; then
        echo "Unknown center: $center" >&2
        exit 2
    fi
done

mode="flagged_vs_unflagged"
# mode="all_combinations"

for center in "${centers[@]}"
do 
    echo ${center}
    python main.py \
        --path_base ${path_base} \
        --mode ${mode} \
        --center ${center} \
        --save_dir "$1"
done
    
