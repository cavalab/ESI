# CHLA: Covariate Binarization

import os
import pandas as pd
import numpy as np
import fire

# TRIAGE VITALS
def get_vitals_rate_std_by_age(data_matrix, triage_vital_col):
    data_matrix = data_matrix.copy()
    # Calculate mean and std for each age group
    stats = data_matrix.groupby('age_group')[triage_vital_col].agg(['mean', 'std']).reset_index()
    # Merge back to original data
    data_matrix = data_matrix.merge(stats, on='age_group', suffixes=('', '_group'))
    # Calculate z-scores
    normalized_col = np.abs((data_matrix[triage_vital_col] - data_matrix['mean']) / data_matrix['std'])
    # Handle missing values
    normalized_col = np.where(data_matrix[triage_vital_col].isna(), 0, normalized_col)
    return normalized_col

def get_pals_threshold(age_group, age):
    """Blood Pressure: score, distance from PALS"""
    if age_group == 'under_3_months':
        return 60
    elif age_group in ['three_to_6_months', 'six_to_12_months']:
        return 70
    elif age_group in ['twelve_to_18_months', 'eighteen_months_to_3_years', 'three_to_5_years','five_to_10_years' ]:
        return 70 + age*2
    elif age_group in ['ten_to_15_years', 'older_than_15_years']:
        return 90


def calculate_systolic_bp_diff_pals(data_matrix):
    data_matrix = data_matrix.copy()
    systolic_bp = data_matrix['blood_pressure_systolic']
    
    # Calculate PALS threshold 
    pals_threshold = data_matrix.apply(lambda row: get_pals_threshold(row['age_group'], row['age']), axis=1)
    
    # Calculate difference (systolic pressure above PALS = 0)
    data_matrix['syst_diff_pals'] = np.maximum(pals_threshold - systolic_bp, 0)
    
    # Missing values = mean of age group
    group_means = data_matrix.groupby('age_group')['syst_diff_pals'].mean()
    data_matrix['syst_diff_pals'] = data_matrix['syst_diff_pals'].fillna(data_matrix['age_group'].map(group_means))
    
    return data_matrix['syst_diff_pals']

def run(
    input_file = (
        '/rc-fs/chip-lacava/Groups/CHLA-ED/preprocessed-data-Aug-2025/'
        'preprocessed_data_with_triage_vitals.csv'
    ),
    output_file='preprocessed_CHLA.csv'
):

    # Load preprocessed data
    data = pd.read_csv(input_file)

    # Create empty data frame for binarized data
    data_bin = pd.DataFrame(index=data.index)

    # Visit ID
    data_bin['id_visit'] = data['id_visit']
    data_bin['id_patient'] = data['id_patient']
    data_bin['age'] = data['age']  # keep raw age values for later use

    # AGE (reference group < 3 months)
    age_group_dummies = (pd.get_dummies(data['age_group'], prefix='is')).astype(int)
    age_group_dummies = (age_group_dummies.rename(columns={'age_group_unknown': 'is_unknown_age'})).astype(int)
    age_group_dummies = age_group_dummies.drop('is_older_than_15_years', axis=1)
    data_bin = pd.concat([data_bin, age_group_dummies], axis=1)

    # SEX (reference group: female)
    data_bin['is_male'] = (data['sex'] == 'M').astype(int)

    # RACE (reference group: non-hispanic white)
    data_bin['is_asian'] = (data['race_ethnicity'] == 'asian').astype(int)
    data_bin['is_hispanic'] = (data['race_ethnicity'] == 'hispanic').astype(int)
    data_bin['is_hispanic_white'] = (data['race_ethnicity'] == 'hispanic_white').astype(int)
    data_bin['is_non_hispanic_black'] = (data['race_ethnicity'] == 'non_hispanic_black').astype(int)
    data_bin['is_other'] = (data['race_ethnicity'] == 'other').astype(int)
    data_bin['is_unknown'] = (data['race_ethnicity'] == 'unknown').astype(int)

    # MEANS OF ARRIVAL (reference group: self)
    data_bin['arrival_EMS'] = (data['arrival_mode'] == 'EMS').astype(int)
    data_bin['arrival_unknown'] = (data['arrival_mode'] == 'unknowm').astype(int)
    data_bin['arrival_other'] = (data['arrival_mode'] == 'other').astype(int)

    # PREFERRED LANGUAGE (reference group: English)
    data_bin['is_language_spanish'] = (data['preferred_language'] == 'Spanish').astype(int)
    data_bin['is_language_mandarin'] = (data['preferred_language'] == 'Mandarin').astype(int)
    data_bin['is_language_russian'] = (data['preferred_language'] == 'Russian').astype(int)
    data_bin['is_language_armenian'] = (data['preferred_language'] == 'Armenian').astype(int)
    data_bin['is_language_other'] = (data['preferred_language'] == 'other_unknown').astype(int)

    # GEOGRAPHIC DATA
    data_bin['state_out_of_state'] = (data['state'] != 'CA').astype(int)
    data_bin['state_unknown'] = data['state'].isna().astype(int)

    data_bin['miles_travelled'] = data['miles_travelled']
    mean_value = pd.to_numeric(data_bin['miles_travelled'], errors='coerce').mean()  # replace NaN by mean value
    data_bin['miles_travelled'] = data_bin['miles_travelled'].fillna(mean_value)

    data_bin['SDI_score'] = data['SDI_score'].replace('unknown', np.nan)  # replace 'NaN' by mean value
    mean_value = pd.to_numeric(data_bin['SDI_score'], errors='coerce').mean() 
    data_bin['SDI_score'] = data_bin['SDI_score'].fillna(mean_value)

    # INSURANCE (reference group: Public)
    data_bin['insurance_private'] = (data['insurance'] == 'Private').astype(int)
    data_bin['insurance_unknown'] = (data['insurance'] == 'unknown').astype(int)

    # ADMISSIONS/DISPOSITION (reference group:discharge)
    data_bin['is_admitted'] = (data['disposition'] == 'Admitted').astype(int)
    data_bin['is_transfer'] = (data['disposition'] == 'Transfer').astype(int)

    # PRIOR VISITS (continuous variable)
    prior_visits_col = ['num_previous_admissions', 'num_previous_visits_without_admission']
    data_bin[prior_visits_col] = data[prior_visits_col]

    # CROWDEDNESS (continuous variable)
    data_bin['num_patients_at_arrival'] = data['crowdedness']

    # # COMORBIDITY SCORE (continuous variable)
    # data_bin['icd_score'] = data['icd_score']
    # mean_value = pd.to_numeric(data_bin['icd_score'], errors='coerce').mean() # replace NaN by mean value
    # data_bin['icd_score'] = data_bin['icd_score'].fillna(mean_value)

    # WEIGHT (continuous variable, normalized weight by age group)
    data_bin['weight'] = data['weight'].replace('not_taken', np.nan) # replace 'not_taken' by mean value
    mean_value = pd.to_numeric(data_bin['weight'], errors='coerce').mean() 
    data_bin['weight'] = data_bin['weight'].fillna(mean_value)



        
    # HEART RATE: std per age group
    data_bin['norm_heart_rate'] = get_vitals_rate_std_by_age(data_matrix=data, triage_vital_col='heart_rate')

    # RESPIRATORY RATE: std per age group
    data_bin['norm_respiratory_rate'] = get_vitals_rate_std_by_age(data_matrix=data, triage_vital_col='respiratory_rate')



    data_bin['syst_diff_pals'] = calculate_systolic_bp_diff_pals(data_matrix=data)
    mean_value = pd.to_numeric(data_bin['syst_diff_pals'], errors='coerce').mean()  # replace NaN by mean value
    data_bin['syst_diff_pals'] = data_bin['syst_diff_pals'].fillna(mean_value)

    # TEMPERATURE: positive distance from 38C
    fever_thresh = 38  # Celsius
    data_bin['temp_fever'] = np.maximum(data['temperature'] - fever_thresh, 0)
    mean_value = pd.to_numeric(data_bin['temp_fever'], errors='coerce').mean()  # replace NaN by mean value
    data_bin['temp_fever'] = data_bin['temp_fever'].fillna(mean_value)

    # TIME STAMPS
    # Arrival year (reference group (2018))
    data_bin['arrival_year_2019'] = (data['arrival_year'] == '2019').astype(int)
    data_bin['arrival_year_2020'] = (data['arrival_year'] == '2020').astype(int)
    data_bin['arrival_year_2021'] = (data['arrival_year'] == '2021').astype(int)
    data_bin['arrival_year_2022'] = (data['arrival_year'] == '2022').astype(int)
    data_bin['arrival_year_2023'] = (data['arrival_year'] == '2023').astype(int)
    data_bin['arrival_year_2024'] = (data['arrival_year'] == '2024').astype(int)
    data_bin['arrival_year_2025'] = (data['arrival_year'] == '2025').astype(int)

    # Arrival season (reference group: Summer)
    data_bin['arrival_season_winter'] = (data['arrival_season'] == 'Winter (Dec-Feb)').astype(int)
    data_bin['arrival_season_fall'] = (data['arrival_season'] == 'Fall (Sep-Nov)').astype(int)
    data_bin['arrival_season_spring'] = (data['arrival_season'] == 'Spring (Mar-May)').astype(int)

    # Arrival day type (reference group: Weekday)
    data_bin['arrival_weekend'] = (data['arrival_day_type'] == 'Weekend').astype(int)

    # Arrival time block (reference group: 18:00-23:59)
    data_bin['arrival_time_afternoon'] = (data['arrival_time_block'] == '12:00-17:59').astype(int)
    data_bin['arrival_time_small_hours'] = (data['arrival_time_block'] == '00:00-05:59').astype(int)
    data_bin['arrival_time_morning'] = (data['arrival_time_block'] == '06:00-11:59').astype(int)

    # LABS & MEDS
    labs_meds_col = ['num_labs', 'any_labs', 'num_meds', 'any_meds', 'num_IV_meds', 'any_IV_meds']
    data_bin[labs_meds_col] = data[labs_meds_col]

    # ADD OTHER RAW INFORMATION
    columns_to_add = [
        'triage_acuity', 'temperature', 'blood_pressure_systolic', 
        'blood_pressure_diastolic', 'raw_complaint', 'raw_reason_for_visit'
    ]
    data_bin[columns_to_add] = data[columns_to_add]
    data_bin['triage_hr'] = data['heart_rate']
    data_bin['triage_rr'] = data['respiratory_rate']
    data_bin['triage_spo2'] = data['oxygen_saturation']

    diagnosis_list = ['diagnosis_anemia', 'diagnosis_pain_conditions', 'diagnosis_congenital_malformations', 
                    'diagnosis_cardiovascular', 'diagnosis_nausea_and_vomiting', 'diagnosis_epilepsy', 
                    'diagnosis_developmental_delays', 'diagnosis_gastrointestinal', 'diagnosis_asthma', 
                    'diagnosis_sleep_disorders', 'diagnosis_anxiety', 'diagnosis_diabetes_mellitus', 
                    'diagnosis_joint_disorders', 'diagnosis_any_malignancy', 'diagnosis_chromosomal_anomalies', 
                    'diagnosis_weight_loss', 'diagnosis_eating_disorders', 'diagnosis_menstrual_disorders', 
                    'diagnosis_alcohol_abuse', 'diagnosis_depression', 'diagnosis_psychotic_disorders', 
                    'diagnosis_drug_abuse', 'diagnosis_conduct_disorders', 'diagnosis_smoking']
    data_bin.loc[:, diagnosis_list] = data[diagnosis_list].fillna(0)

    complaint_groups = ['complaint_contains_abdominal_pain', 'complaint_contains_assault', 
                        'complaint_contains_allergic_reaction', 'complaint_contains_altered_mental_status', 
                        'complaint_contains_asthma_or_wheezing', 'complaint_contains_bites_or_stings', 
                        'complaint_contains_burn', 'complaint_contains_cardiac', 'complaint_contains_chest_pain', 
                        'complaint_contains_congestion', 'complaint_contains_constipation', 
                        'complaint_contains_cough', 'complaint_contains_crying_or_colic', 
                        'complaint_contains_dental', 'complaint_contains_device_complication', 
                        'complaint_contains_diarrhea', 'complaint_contains_ear_complaint', 
                        'complaint_contains_epistaxis', 'complaint_contains_extremity', 
                        'complaint_contains_eye_complaint', 'complaint_contains_syncope', 
                        'complaint_contains_foreign_body', 'complaint_contains_fever', 
                        'complaint_contains_follow_up', 'complaint_contains_general', 
                        'complaint_contains_gi_bleed', 'complaint_contains_gynecologic', 
                        'complaint_contains_head_or_neck', 'complaint_contains_headache', 
                        'complaint_contains_laceration', 'complaint_contains_lump_or_mass', 
                        'complaint_contains_male_genital', 'complaint_contains_mvc', 
                        'complaint_contains_neck_pain', 'complaint_contains_neurologic', 
                        'complaint_contains_poisoning', 'complaint_contains_poor_feeding', 
                        'complaint_contains_primary_care', 'complaint_contains_psych', 'complaint_contains_rash', 
                        'complaint_contains_other_respiratory', 'complaint_contains_seizure', 
                        'complaint_contains_sore_throat', 'complaint_contains_trauma', 'complaint_contains_urinary', 
                        'complaint_contains_vomiting']
    data_bin.loc[:, complaint_groups] = data[complaint_groups].fillna(0)

    # SAVE BINARIZED DATA
    print('saving',output_file,'of shape',data_bin.shape)
    print(data_bin.head())
    data_bin.to_csv(output_file)


if __name__=='__main__':
    fire.Fire(run)