from pathlib import Path
import numpy as np
import json
import fire

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
    calculate_significance,
    plot_odds_ratios_with_forestplot
)


def load_center_configs(config_file: str = "center_configs.json"):
    """"Load all center configurations from JSON file"""
    with open(config_file, "r", encoding="utf-8") as f:
        return json.load(f)


def main(
        path_base=Path('/Volumes/chip-lacava/Groups/CHLA-ED/data_binarized_ESI'),
        center: str = "CHLA",  # 'BIDMC', 'Stanford', 'BCH', 'CHLA'
        mode: str = 'flagged_vs_unflagged',  # 'flagged_vs_unflagged', 'all_combinations'
        bin_data: str = None,
        visualize_stats=False,
        **plot_kwargs
):

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

    # 1. ESI Handbook: High risk symptoms
    # Define data file name and save file name
    if bin_data is None:
        bin_data = f"preprocessed_{center}.csv"

    # Load data
    data_acuity, bin_data = load_data_filter_acuity_2_3(
        path_base / bin_data,
        triage_col
    )
    data_acuity.to_csv(f'results/complaint_with_mask_{center}.csv', index=False)

    # Compare keywords
    complaint_with_mask, complaint_stats = keyword_detection_and_misspelling_correction(
        data_acuity,
        complaint_col
    )
    complaint_with_mask.to_csv(f'results/complaint_with_mask_and_vitals_{center}.csv', index=False)

    if visualize_stats:
        view_statistics_high_risk_keywords(complaint_stats)

    # 2. ESI Handbook: Danger zone vital signs
    complaint_all = is_danger_zone_vitals(complaint_with_mask, center)

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
    odds_ratios.to_csv(f'results/odds_{center}_{mode}.csv', index=False)

    # Calculate significance between pairs and save
    significance = calculate_significance(
        combined_results=odds_ratios,
        race_order=race_order,
        mode=mode)
    significance.to_csv(f'results/sign_{center}_{mode}.csv', index=False)

    # Create forest plot
    try:
        return plot_odds_ratios_with_forestplot(
            combined_data=odds_ratios,
            predictor_prefix='is_',
            race_names=race_names,
            race_order=race_order,
            center=center,
            significance_df=significance,
            mode=mode,
            **plot_kwargs
        )
    except Exception as e:
        raise Exception(f"Error creating forest plot: {e}")


if __name__ == '__main__':

    fire.Fire(main)

