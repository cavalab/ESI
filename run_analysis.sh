centers=(
    "BIDMC"
    "Stanford"
    "BCH"
    "CHLA"
)

path_base="data"
mode="flagged_vs_unflagged"
# mode="all_combinations"

for center in ${centers[@]}
do 
    echo ${center}
    python main.py \
        --path_base ${path_base} \
        --mode ${mode} \
        --center ${center} \
        --save_dir "results"
done
    

