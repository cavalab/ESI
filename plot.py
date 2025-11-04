from src.propensity_score_matching import plot_odds_ratios_with_forestplot
import fire
import json
import pandas as pd

def forest_plot(load_dir, **extra_kwargs):
    with open(f'{load_dir}/plot_kwargs.json','r') as of:
        kwargs = json.load(of)
    kwargs['odds_ratios']=pd.read_csv(f'{load_dir}/odds_ratios.csv')
    kwargs['significance_df']=pd.read_csv(f'{load_dir}/significance.csv')

    return plot_odds_ratios_with_forestplot(
        **kwargs, **extra_kwargs
    )

if __name__ == '__main__':

    fire.Fire(forest_plot)