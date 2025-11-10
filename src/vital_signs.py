
# ESI Handbook High Risk Vital Signs
target_vitals = ["triage_hr", "triage_rr", "triage_spo2"]

# Global danger zone vitals thresholds
danger_thresholds = {
    0: {"triage_hr": 180, "triage_rr": 50},      # <3 months
    1: {"triage_hr": 160, "triage_rr": 40},      # 3 months–2 years
    2: {"triage_hr": 140, "triage_rr": 30},      # 2–8 years
    3: {"triage_hr": 100, "triage_rr": 20}       # >8 years
}
# Fixed thresholds
spo2_thresh = 92
hr_thresh = 100    # adults
rr_thresh = 20     # adults


# Define age group for vital signs thresholds
def _get_age_group(age_years):
    if age_years < 0.25:
        return 0  # < 3 months
    elif age_years < 2:
        return 1  # 3 months to 2 years
    elif age_years < 8:
        return 2  # 2 to 8 years
    else:
        return 3  # > 8 years


def is_danger_zone_vitals(df, center):

    # Pediatric centers: age dependency
    if (center == "BCH") | (center == "CHLA"):
        # Extract age group from raw age
        df['vitals_age_group'] = df['age'].apply(_get_age_group)

        # Map age groups to thresholds
        df['hr_thresh'] = df['vitals_age_group'].map(lambda x: danger_thresholds[x]['triage_hr'])
        df['rr_thresh'] = df['vitals_age_group'].map(lambda x: danger_thresholds[x]['triage_rr'])

        # Create danger zone flags
        df['danger_zone_vitals'] = (
                (df['triage_hr'] > df['hr_thresh']) |
                (df['triage_rr'] > df['rr_thresh']) |
                (df['triage_spo2'] < spo2_thresh)
        )
        # Drop temporary columns
        df = df.drop(['hr_thresh', 'rr_thresh'], axis=1)

    elif (center == "BIDMC") | (center == "Stanford"):
        df['danger_zone_vitals'] = (
            df['triage_hr'].gt(hr_thresh) |
            df['triage_rr'].gt(rr_thresh) |
            df['triage_spo2'].lt(spo2_thresh)
        )
    else:
        raise ValueError(f'Unknown center_name: {center}')

    # Summary statistics
    flagged_count = df['danger_zone_vitals'].sum()
    total_count = len(df)
    print(f"Number of rows flagged as danger zone: {flagged_count}")
    print(f"Percentage of rows flagged: {flagged_count / total_count * 100:.2f}%")


    return df

