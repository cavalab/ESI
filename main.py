import numpy as np
import json
import fire
import os

from src.high_risk_dictionary import (
    load_data_filter_acuity_2_3,
    keyword_detection_and_misspelling_correction,
    view_statistics_high_risk_keywords
)

from src.vital_signs import (
    is_danger_zone_vitals
)

from src.propensity_score_matching import (
    define_markers,
    remove_unknown_race,
    calculate_psm_odds_ratios,
    calculate_significance
)


def load_center_configs(config_file: str = "center_configs.json"):
    """"Load all center configurations from JSON file"""
    with open(config_file, "r", encoding="utf-8") as f:
        return json.load(f)


def main(
        path_base='./',
        center: str = "CHLA",  # 'BIDMC', 'Stanford', 'BCH', 'CHLA'
        mode: str = 'flagged_vs_unflagged',  # 'flagged_vs_unflagged', 'all_combinations'
        bin_data: str = None,
        visualize_stats=False,
        save_dir=None,

):
    if not save_dir:
        save_dir = f"results/{center}/{mode}"
    else:
        save_dir += f"/{center}/{mode}"
    os.makedirs(save_dir, exist_ok=True)
    np.random.seed(13)  # set random seed

    print(f'Running {center} data ---------------------------')

    # Get center variables
    configs = load_center_configs()  # load configurations
    if center not in configs:  # check if center exists
        available = ', '.join(configs.keys())
        raise ValueError(f'Unknown center: {center}. Available: {available}')
    config = configs[center]  # get center configuration

    triage_col = config['triage_col']
    complaint_col = config['complaint_col']
    race_predictor = config['race_predictor']
    race_names = config['race_names']
    race_order = config['race_order']
    covariates_name = config['covariate_prefixes']

    print("Running full analysis pipeline...")

    # 1. ESI Handbook: High risk symptoms
    # Define data file name and save file name
    if bin_data is None:
        bin_data = f"preprocessed_{center}.csv"

    # Load data
    data_acuity, bin_data = load_data_filter_acuity_2_3(
        f'{path_base}/{bin_data}',
        triage_col
    )

    os.makedirs('results', exist_ok=True)

    # Compare keywords
    complaint_with_mask, complaint_stats = keyword_detection_and_misspelling_correction(
        data_acuity,
        complaint_col
    )
    # complaint_with_mask.to_csv(f'{save_dir}/complaint_with_mask{center}.csv', index=False)

    if visualize_stats:
        view_statistics_high_risk_keywords(complaint_stats)

    # 2. ESI Handbook: Danger zone vital signs
    complaint_all = is_danger_zone_vitals(complaint_with_mask, center)
    # Save CSV file
    complaint_all.to_csv(f"{save_dir}/complaint_with_mask_and_vitals_{center}.csv", index=False)

    # 3. Calculate Odds Ratios (Propensity Score Matching)
    # Define markers
    complaint_mode = define_markers(complaint_all)

    # Remove visits with unknown race
    complaint_mode = remove_unknown_race(complaint_mode)

    # Calculate odd ratios and save
    odds_ratios = calculate_psm_odds_ratios(
        complaint_df=complaint_mode,
        outcome_col=triage_col,
        outcome_value=2,
        predictor_prefix=race_predictor,
        covariates=covariates_name,
        mode=mode,
        is_love_plot=False
    )

    # Calculate significance between pairs and save
    significance = calculate_significance(
        combined_results=odds_ratios,
        race_order=race_order,
        mode=mode)

    odds_ratios.to_csv(f'{save_dir}/odds_ratios.csv', index=False)
    significance.to_csv(f'{save_dir}/significance.csv', index=False)

    with open(f'{save_dir}/plot_kwargs.json','w') as of:
        json.dump(
            dict(
                predictor_prefix='is_',
                race_names=race_names,
                race_order=race_order,
                center=center,
                mode=mode,
            ),
            of
        )

    print(f'results saved to {save_dir}.')


if __name__ == '__main__':

    fire.Fire(main)

