import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
from sklearn.linear_model import LogisticRegressionCV
from sklearn.neighbors import NearestNeighbors
from statsmodels.stats.contingency_tables import mcnemar
from sklearn.preprocessing import StandardScaler
from statsmodels.stats.outliers_influence import variance_inflation_factor
from scipy.stats import norm
import itertools
from matplotlib.ticker import ScalarFormatter
from forestplot import forestplot


def _compute_smd(x_treated, x_control):
    """Compute standardized mean differences"""
    means_treated = x_treated.mean(axis=0)
    means_control = x_control.mean(axis=0)
    sd_treated = x_treated.std(axis=0)
    smd = (means_treated - means_control) / sd_treated.replace(0, np.nan)
    return smd


def _view_love_plot(smd_before, smd_after, covariate_cols, race_label):
    """Visualize violin plots"""
    # Prepare data for plotting
    love_df = pd.DataFrame({
        'Covariate': covariate_cols,
        'SMD Before Matching': smd_before,
        'SMD After Matching': smd_after}).melt(
        id_vars='Covariate',
        var_name='Stage',
        value_name='SMD')

    # Sort covariates by absolute SMD After Matching
    sort_order_after = (
        love_df[love_df['Stage'] == 'SMD After Matching']
        .set_index('Covariate')['SMD']
        .abs()
        .sort_values(ascending=False))

    # Determine top 25%
    num_covariates = len(sort_order_after)
    top_n = max(1, int(np.ceil(num_covariates * 0.25)))
    top_covariates = sort_order_after.head(top_n).index

    # Filter to top 25%
    love_df = love_df[love_df['Covariate'].isin(top_covariates)]

    # Set order for plotting
    love_df['Covariate'] = pd.Categorical(
        love_df['Covariate'],
        categories=sort_order_after.loc[top_covariates].index,
        ordered=True)

    # Plot
    plt.figure(figsize=(6, len(top_covariates) * 0.35))
    sns.pointplot(
        data=love_df,
        y='Covariate',
        x='SMD',
        hue='Stage',
        dodge=0.4,
        join=False,
        palette=['#999999', '#e76f51'])

    plt.axvline(x=0, color='black', lw=1)
    plt.axvline(x=0.1, color='gray', linestyle='--')
    plt.axvline(x=-0.1, color='gray', linestyle='--')
    plt.title(f'Love Plot: {race_label} vs White (Top 25% Imbalanced)')
    plt.xlabel('Standardized Mean Difference')
    plt.ylabel('')
    plt.legend(title='')
    plt.tight_layout()
    plt.show()


def _calculate_vif(df, thresh=10.0):
    print(f"\n--- VIF filtering ---")
    dropped = True
    while dropped:
        dropped = False
        vif = pd.DataFrame()
        vif["variable"] = df.columns
        vif["VIF"] = [variance_inflation_factor(df.values, i) for i in range(df.shape[1])]

        max_vif = vif['VIF'].max()
        if max_vif > thresh:
            drop_var = vif.sort_values('VIF', ascending=False).iloc[0]['variable']
            print(f"Dropping '{drop_var}' with VIF = {max_vif:.2f}")
            df = df.drop(columns=[drop_var])
            dropped = True
    return df.columns.tolist()


def _view_ps_propensity_scores(sub, race):
    plt.figure(figsize=(8, 5))
    sns.kdeplot(sub.loc[sub['exposure'] == 1, 'propensity_score'], label=f'{race} (exposed)', fill=True, alpha=0.5)
    sns.kdeplot(sub.loc[sub['exposure'] == 0, 'propensity_score'], label='White (control)', fill=True, alpha=0.5)
    plt.title(f'Propensity Score Distribution: {race} vs White')
    plt.xlabel('Propensity Score')
    plt.ylabel('Density')
    plt.legend()
    plt.tight_layout()
    plt.show()


def define_markers(complaint_df):
    complaint_df['final_mask_corrected'] = complaint_df['final_mask_corrected'].fillna(False).astype(bool)
    complaint_df['danger_zone_vitals'] = complaint_df['danger_zone_vitals'].fillna(False).astype(bool)
    complaint_df['any_flagged'] = (complaint_df['final_mask_corrected'] | complaint_df['danger_zone_vitals'])
    return complaint_df


def remove_unknown_race(complaint_df):
    # Check if 'is_race_unknown' or 'is_unknown' exist in the dataframe
    if 'is_race_unknown' in complaint_df.columns:
        unknown_col = 'is_race_unknown'
    elif 'is_unknown' in complaint_df.columns:
        unknown_col = 'is_unknown'
    else:
        # Neither column exists, return the input dataframe unchanged
        print("No 'is_race_unknown' or 'is_unknown' column found. Returning original dataframe.")
        return complaint_df

    # Identify unknown race and remove
    total_rows = len(complaint_df)
    num_unknown = (complaint_df[unknown_col] == 1).sum()
    prop = num_unknown / total_rows
    print(f"Unknown race num patients: {num_unknown}")
    print(f"Unknown race proportion: {prop:.2%}")

    # Remove from dataframe
    complaint_df = complaint_df[complaint_df[unknown_col] != 1].reset_index(drop=True)
    return complaint_df


def calculate_psm_odds_ratios(complaint_df, outcome_col, outcome_value, predictor_prefix,
                              covariates, is_love_plot=False, mode='flagged_vs_unflagged'):
    # Define modes
    config = {
        'flagged_vs_unflagged': ['all', 'HB level 2', 'HB level 3'],  # Updated order and labels
        'all_combinations': ['HB2', 'final_mask_corrected', 'danger_zone_vitals', 'HB3'],
    }

    if mode not in config:
        raise ValueError("Invalid mode. Choose 'flagged_vs_unflagged' or 'all_combinations'.")

    # Define covariates
    covariate_cols = [c for c in complaint_df.columns if any(c.startswith(p) for p in covariates)]
    race_cols = [p for p in predictor_prefix if p in complaint_df.columns]
    complaint_df['outcome'] = (complaint_df[outcome_col] == outcome_value).astype(int)

    # Calculate propensity scores for each group ----------------------------------------------------------
    propensity_data = {}
    shuffled_data_per_race = {}

    for race in race_cols:
        print(f"  Calculating propensity scores for: {race} vs. White")

        # Randomly shuffle data before each propensity score matching
        complaint_df_shuffled = complaint_df.sample(frac=1, random_state=13).reset_index()
        complaint_df_shuffled.rename(columns={'index': 'original_index'}, inplace=True)
        shuffled_data_per_race[race] = complaint_df_shuffled

        # Filter to current race vs reference
        # other_races = [col for col in race_cols if col != race]
        # sub = complaint_df_shuffled[(complaint_df_shuffled[race] == 1) |
        #                             (complaint_df_shuffled[other_races].sum(axis=1) == 0)].copy()
        sub = complaint_df_shuffled[
            (complaint_df_shuffled[race] == 1) |
            (complaint_df_shuffled[race_cols].sum(axis=1) == 0)
            ].copy()
        sub['exposure'] = (sub[race] == 1).astype(int)

        if sub['exposure'].nunique() < 2:
            print(f"   Skipping {race}: Not enough variation in exposure.")
            continue

        # Propensity score matching
        x_scaled = StandardScaler().fit_transform(sub[covariate_cols])
        ridge = LogisticRegressionCV(penalty='l2', random_state=13).fit(x_scaled, sub['exposure'])
        sub['propensity_score'] = ridge.predict_proba(x_scaled)[:, 1]

        # Store the data with propensity scores
        propensity_data[race] = {
            'data': sub,
            'model': ridge,
            'scaler_fitted_data': x_scaled
        }

    # Calculate odds ratios ---------------------------------------------------------------------------------
    results = []

    for flag_combo in config[mode]:
        print(f"\nProcessing flag combination: {flag_combo}")

        for race in race_cols:
            if race not in propensity_data:
                continue

            print(f"    Matching and analyzing: {race} vs. White")

            # Get data for this race
            complaint_df_shuffled = shuffled_data_per_race[race]
            race_data = propensity_data[race]['data'].copy()

            # Create mask based on mode and combination
            if mode == 'flagged_vs_unflagged':
                if flag_combo == 'all':
                    mask = pd.Series([True] * len(complaint_df_shuffled))
                elif flag_combo == 'HB level 2':
                    mask = complaint_df_shuffled['any_flagged'] == True
                elif flag_combo == 'HB level 3':
                    mask = complaint_df_shuffled['any_flagged'] == False
                p_correction = 3

            elif mode == 'all_combinations':
                if flag_combo == 'HB2':
                    mask = complaint_df_shuffled['any_flagged'] == True
                elif flag_combo == 'final_mask_corrected':
                    mask = complaint_df_shuffled['final_mask_corrected'] == True
                elif flag_combo == 'danger_zone_vitals':
                    mask = (complaint_df_shuffled['final_mask_corrected'] == False) & (
                                complaint_df_shuffled['danger_zone_vitals'] == True)
                elif flag_combo == 'HB3':
                    mask = complaint_df_shuffled['any_flagged'] == False
                p_correction = 4

            # Apply filtering based on flag combination
            if flag_combo == 'all':
                # Use all data for "all" comparison
                flag_filtered_data = race_data.copy()
            else:
                # Filter based on the mask
                flag_indices = complaint_df_shuffled[mask].index.tolist()
                flag_filtered_data = race_data[race_data['original_index'].isin(
                    complaint_df_shuffled.loc[flag_indices, 'original_index']
                )].copy()

            if len(flag_filtered_data) == 0:
                print(f"     Skipping: No data after flag filtering")
                continue

            if flag_filtered_data['exposure'].nunique() < 2:
                print(f"     Skipping: Not enough variation in exposure after flag filtering")
                continue

            # Perform matching using pre-calculated propensity scores
            exposed = flag_filtered_data[flag_filtered_data['exposure'] == 1]
            control = flag_filtered_data[flag_filtered_data['exposure'] == 0]

            # Match subjects using existing propensity scores
            nn = NearestNeighbors(n_neighbors=1, algorithm='ball_tree').fit(control[['propensity_score']])
            distances, indices = nn.kneighbors(exposed[['propensity_score']])
            within_caliper = distances.flatten() <= 0.2

            matched_exposed = exposed.reset_index(drop=True).loc[within_caliper]
            matched_controls = control.iloc[indices.flatten()[within_caliper]].reset_index(drop=True)

            # Love plot
            if is_love_plot:
                smd_before = _compute_smd(flag_filtered_data.loc[flag_filtered_data['exposure'] == 1, covariate_cols],
                                          flag_filtered_data.loc[flag_filtered_data['exposure'] == 0, covariate_cols])
                smd_after = _compute_smd(matched_exposed[covariate_cols], matched_controls[covariate_cols])
                _view_love_plot(smd_before, smd_after, covariate_cols, race_label=f"{race} (Flag={flag_combo})")

            # McNemar's test and odds ratio calculation
            table = pd.crosstab(matched_exposed['outcome'], matched_controls['outcome'])
            table = table.reindex(index=[0, 1], columns=[0, 1], fill_value=0)

            b, c = table.loc[0, 1], table.loc[1, 0]
            odds_ratio = (c + 0.5) / (b + 0.5)
            log_or = np.log(odds_ratio)
            se = np.sqrt(1 / (b + 0.5) + 1 / (c + 0.5))

            results.append({
                'Variable': f"{race} vs. White",
                'flag_combination': flag_combo,
                'OR': odds_ratio,
                'log_OR': log_or,
                'SE': se,
                'CI_lower': np.exp(log_or - 1.96 * se),
                'CI_upper': np.exp(log_or + 1.96 * se),
                'pval': mcnemar(table, exact=False, correction=True).pvalue * p_correction,
                'n_visits': len(matched_exposed),
                'total_exposed': len(exposed),
                'total_control': len(control)
            })

    return pd.DataFrame(results)


def calculate_significance(combined_results, race_order, mode='flagged_vs_unflagged'):
    # Configuration for different modes
    config = {
        'flagged_vs_unflagged': {
            'combinations': ['all', 'HB level 2', 'HB level 3'],
            'names': {'all': 'Both HB levels',
                      'HB level 2': 'HB level 2',
                      'HB level 3': 'HB level 3'}
        },
        'all_combinations': {
            'combinations': ['HB2', 'final_mask_corrected', 'danger_zone_vitals', 'HB3'],
            'names': {'HB2': 'Handbook ESI level 2',
                      'final_mask_corrected': 'Final mask corrected',
                      'danger_zone_vitals': 'Danger zone vitals',
                      'HB3': 'No flags'}
        }
    }

    if mode not in config:
        raise ValueError("Invalid mode. Choose 'flagged_vs_unflagged', 'compare_flags', or 'all_combinations'.")

    cfg = config[mode]

    # Filter and prepare data
    race_data = combined_results[combined_results['Variable'].str.startswith('is_')].copy()
    race_data['Variable'] = pd.Categorical(race_data['Variable'], categories=race_order, ordered=True)

    # Pivot and flatten columns
    pivot = race_data.pivot(index='Variable', columns='flag_combination', values=['log_OR', 'SE'])
    pivot.columns = [f"{val}_{cfg['names'][combo]}" for val, combo in pivot.columns]

    # Calculate significance for all combinations
    results = []
    for combo1, combo2 in itertools.combinations(cfg['combinations'], 2):
        name1, name2 = cfg['names'][combo1], cfg['names'][combo2]

        # Calculate z-scores and p-values
        beta_diff = pivot[f"log_OR_{name1}"] - pivot[f"log_OR_{name2}"]
        se_diff = (pivot[f"SE_{name1}"] ** 2 + pivot[f"SE_{name2}"] ** 2) ** 0.5
        p_values = 2 * (1 - norm.cdf(abs(beta_diff / se_diff)))

        # Build results for this combination
        results.extend([
            {'Variable': var, 'Combination1': name1, 'Combination2': name2, 'p_value': p}
            for var, p in zip(pivot.index, p_values)
        ])

    # Return sorted DataFrame
    df = pd.DataFrame(results)
    df['Variable'] = pd.Categorical(df['Variable'], categories=race_order, ordered=True)
    return df.sort_values('Variable')


# New x-axis formatting
def _fix_axis_formatting(ax, df):

    formatter = ScalarFormatter()
    formatter.set_scientific(False)
    formatter.set_useOffset(False)
    ax.xaxis.set_major_formatter(formatter)

    # Set nice tick positions
    min_val = df['CI_lower'].min() * 0.9
    max_val = df['CI_upper'].max() * 1.1
    base_ticks = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9,
                  1.0, 1.2, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]
    ticks = [t for t in base_ticks if min_val <= t <= max_val]
    ax.set_xticks(ticks)
    ax.set_xticklabels([str(t) for t in ticks])


# Add significance stars to OR CI
def _get_stars(p):
    return ' ***' if p < 0.001 else ' **' if p < 0.01 else ' *' if p < 0.05 else ''


def plot_odds_ratios_with_forestplot(combined_data, predictor_prefix, race_names, race_order,
                                     center: str, significance_df=None, mode='flagged_vs_unflagged', ax=None):
    # Configuration for different modes
    config = {
        'flagged_vs_unflagged': {
            'group_map': {'all': "Both HB levels",
                          'HB level 2': "HB level 2",
                          'HB level 3': "HB level 3"},
            'esi_order': ['Both HB levels', 'HB level 2', 'HB level 3'],
            'sig_map': {'Both HB levels': 'all',
                        'HB level 2': 'HB level 2',
                        'HB level 3': 'HB level 3'}
        },
        'all_combinations': {
            'group_map': {'HB2': "Handbook ESI level 2",
                          'danger_zone_vitals': " -- ESI 2: Danger Zone Vitals",
                          'final_mask_corrected': " -- ESI 2: High Risk Symptoms",
                          'HB3': "Handbook ESI level 3"},
            'esi_order': ['Handbook ESI level 3', 'Handbook ESI level 2', ' -- ESI 2: Danger Zone Vitals',
                          ' -- ESI 2: High Risk Symptoms'],
            'sig_map': {'Handbook ESI level 2': 'HB2',
                        'Danger zone vitals': 'danger_zone_vitals',
                        'Final mask corrected': 'final_mask_corrected',
                        'No flags': 'HB3'}
        }
    }

    if mode not in config:
        raise ValueError("Invalid mode")

    cfg = config[mode]

    # Prepare data
    plot_data = combined_data[combined_data['Variable'].str.startswith(predictor_prefix)].copy()
    plot_data['group'] = plot_data['flag_combination'].map(cfg['group_map'])
    plot_data['term'] = plot_data['Variable']

    plot_data['OR [95% CI]'] = (plot_data['OR'].round(2).astype(str) +
                                ' [' + plot_data['CI_lower'].round(2).astype(str) +
                                ', ' + plot_data['CI_upper'].round(2).astype(str) + ']' +
                                plot_data['pval'].apply(_get_stars))

    # Build and sort forestplot DataFrame
    df_fp = plot_data[['term', 'group', 'OR', 'CI_lower', 'CI_upper', 'OR [95% CI]', 'n_visits']].copy()
    df_fp.rename(columns={'n_visits': 'n'}, inplace=True)

    def sort_key(row):
        race_idx = race_order.index(row['term']) if row['term'] in race_order else len(race_order)
        esi_idx = cfg['esi_order'].index(row['group']) if row['group'] in cfg['esi_order'] else len(cfg['esi_order'])
        return race_idx * 10 + esi_idx

    df_fp['sort_key'] = df_fp.apply(sort_key, axis=1)
    df_fp = df_fp.sort_values('sort_key').reset_index(drop=True).drop('sort_key', axis=1)
    df_fp['n'] = df_fp['n'].apply(lambda x: str(int(float(x))) if pd.notnull(x) else '')

    # Rename race groups
    df_fp['term'] = df_fp['term'].map(race_names)

    # Create y-position mapping (accounting for different group counts per mode)
    y_positions = {}
    groups_per_race = len(cfg['esi_order'])  # 3 for flagged_vs_unflagged (all, HB2, HB3)

    for idx, row in df_fp.iterrows():
        if row['term'] not in y_positions:
            y_positions[row['term']] = {}

        # Adjust spacing based on number of groups per race
        if groups_per_race == 2:
            spacing = 1.5
            xlim_factor = 1.1
            y_factor = 1
        elif groups_per_race == 3:
            spacing = 1.3
            xlim_factor = 1.3
            y_factor = 1
        else:  # 4 groups
            spacing = 1.2
            xlim_factor = 1.3
            y_factor = 1

        y_positions[row['term']][row['group']] = (len(df_fp) - y_factor - idx) * spacing

    # Create plot
    if not ax:
        fig, ax = plt.subplots(figsize=(10, len(df_fp) * 0.6))
    ax = forestplot(df_fp,
                    estimate='OR',
                    ll='CI_lower',
                    hl='CI_upper',
                    varlabel='group',
                    groupvar='term',
                    annote=['OR [95% CI]', 'n'],
                    annoteheaders=['OR [95% CI]', 'n'],
                    xlabel='Odds Ratio',
                    color_alt_rows=True,
                    flush=True,
                    table=False,
                    logscale=True,
                    ax=ax)

    ax.axvline(x=1, color='black', linestyle='--', linewidth=1)

    # Adjust x-axis ticks
    _fix_axis_formatting(ax, df_fp)

    # Add significance brackets
    if significance_df is not None:
        xlim = ax.get_xlim()
        bracket_x_base = xlim[1] + 0.05 * (xlim[1] - xlim[0])

        reverse_race_names = {v: k for k, v in race_names.items()}

        for race in y_positions.keys():
            original_var = reverse_race_names.get(race, race)
            p_values = significance_df[significance_df['Variable'] == original_var]

            if len(p_values) == 0 or len(y_positions[race]) < 2:
                continue

            for bracket_idx, (_, row) in enumerate(p_values.iterrows()):

                # Only add bracket if the difference is significant (p < 0.05)
                if row['p_value'] >= 0.05:
                    continue

                # Map significance combinations to groups
                combo1_group = cfg['group_map'][cfg['sig_map'][row['Combination1']]]
                combo2_group = cfg['group_map'][cfg['sig_map'][row['Combination2']]]

                # Get bracket positions and draw
                y1, y2 = y_positions[race][combo1_group], y_positions[race][combo2_group]
                bracket_x = bracket_x_base + (bracket_idx * 0.1 * (xlim[1] - xlim[0]))

                # Draw bracket
                ax.plot([bracket_x, bracket_x], [y1, y2], 'k-', linewidth=1, zorder=10)
                ax.plot([bracket_x - 0.015, bracket_x], [y1, y1], 'k-', linewidth=1, zorder=10)
                ax.plot([bracket_x - 0.015, bracket_x], [y2, y2], 'k-', linewidth=1, zorder=10)

                # Add significance text
                stars = '***' if row['p_value'] < 0.001 else '**' if row['p_value'] < 0.01 else '*' if row[
                                                                                                           'p_value'] < 0.05 else 'ns'
                ax.text(bracket_x + 0.01, (y1 + y2) / 2 - 0.15, stars,
                        ha='left', va='center', fontsize=15, zorder=10)

        ax.set_xlim(xlim[0], xlim[1] * xlim_factor)
        ax.grid(False)

    # plt.savefig(f"figures/forestplot_{center}_{mode}.png", bbox_inches='tight', dpi=600)
    # plt.show()
    return df_fp, ax
