import pandas as pd

def ohc(series: pd.Series):
    """One hot encodes the series """ 
    print(series.name)
    if series.dtype == 'object':
        series = series.apply(lambda x: x.replace(' ','-').lower())
    return pd.get_dummies(
        series, 
        prefix=series.name, 
        drop_first=True, 
        dummy_na=True
        ).astype(int)