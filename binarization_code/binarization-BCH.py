# BCH: Covariate Binarization

import os
import pandas as pd
import numpy as np

# Define the data directory and filename
data_dir = '/Volumes/chip-lacava/Groups/BCH-ED/reprocessing'
filename = 'preprocessed-visits.csv'
file_path = os.path.join(data_dir, filename)

# Load preprocessed data
data = pd.read_csv(file_path)

# Create empty dataframe
data_bin = pd.DataFrame(index=data.index)

# CSN Values
data_bin['csn'] = data['csn']

# SEX: Add binary column (reference group: female)
# print(f"Existent Gender Values: {data['sex'].unique()}")
#
data_bin['is_male'] = (data['sex'] == 'M').astype(int)
data_bin['is_trans_or_nb'] = data['is_trans_or_nb']

# AGE (reference group < 3 months)
# print(f"Existent Age Values: {data['age_group'].unique()}")
data_bin['three_to_6_months'] = (data['age_group'] == 'three_to_6_months').astype(int)
data_bin['six_to_12_months'] = (data['age_group'] == 'six_to_12_months').astype(int)
data_bin['twelve_to_18_months'] = (data['age_group'] == 'twelve_to_18_months').astype(int)
data_bin['eighteen_months_to_3_years'] = (data['age_group'] == 'eighteen_months_to_3_years').astype(int)
data_bin['three_to_5_years'] = (data['age_group'] == 'three_to_5_years').astype(int)
data_bin['five_to_10_years'] = (data['age_group'] == 'five_to_10_years').astype(int)
data_bin['ten_to_15_years'] = (data['age_group'] == 'ten_to_15_years').astype(int)
data_bin['fifteen_and_older'] = (data['age_group'] == 'fifteen_and_older').astype(int)

# RACE (reference group: Non-Hispanic White)
# print(f"Existent Race Values: {data['race'].unique()}")
data_bin['is_asian'] = (data['race'] == 'Asian').astype(int)
data_bin['is_hispanic'] = (data['race'] == 'Hispanic').astype(int)
data_bin['is_hispanic_white'] = (data['race'] == 'Hispanic White').astype(int)
data_bin['is_black'] = (data['race'] == 'Non-Hispanic Black').astype(int)
data_bin['is_race_other'] = (data['race'] == 'Other').astype(int)
data_bin['is_race_unknown'] = (data['race'] == 'Unknown').astype(int)

# MEANS OF ARRIVAL (reference group: 'Walk in')
# print(f"Existent Means of Arrival Values: {data['ed_arrival_mode'].unique()}")
data_bin['arrival_EMS'] = (data['ed_arrival_mode'] == 'EMS').astype(int)
data_bin['arrival_transfer'] = (data['ed_arrival_mode'] == 'Transfer').astype(int)
data_bin['arrival_other_unknown'] = (data['ed_arrival_mode'] == 'ther/Unknown').astype(int)

# PREFERRED LANGUAGE (reference group: English)
# print(f"Existent Preferred Language Values: {data['language'].unique()}")
data_bin['is_language_spanish'] = (data['language'] == 'Spanish').astype(int)
data_bin['is_language_mandarin'] = (data['language'] == 'Chinese Mandarin').astype(int)
data_bin['is_language_portuguese'] = (data['language'] == 'Portuguese').astype(int)
data_bin['is_language_cape_verdean'] = (data['language'] == 'Cape Verdean').astype(int)
data_bin['is_language_haitian_creole'] = (data['language'] == 'Haitian Creole').astype(int)
data_bin['is_language_arabic'] = (data['language'] == 'Arabic').astype(int)
data_bin['is_language_other'] = (data['language'] == 'Other').astype(int)

# GEOGRAPHIC DATA
# State (reference group: in-state)
# print(f"Existent State Values: {data['state_of_origin'].unique()}")
data_bin['state_out_of_state'] = (data['state_of_origin'] == 'out-of-state').astype(int)
data_bin['state_unknown'] = data['state_of_origin'].isna().astype(int)

# Miles travelled
data_bin['miles_travelled'] = data['miles_travelled']
mean_value = pd.to_numeric(data_bin['miles_travelled'], errors='coerce').mean() # replace NaN by mean value
data_bin['miles_travelled'] = data_bin['miles_travelled'].fillna(mean_value)

# SDI score
data_bin['sdi_score'] = data['sdi_score'].replace('unknown', np.nan) # replace 'NaN' by mean value
mean_value = pd.to_numeric(data_bin['sdi_score'], errors='coerce').mean() 
data_bin['sdi_score'] = data_bin['sdi_score'].fillna(mean_value)

# INSURANCE (reference group: Public)
# print(f"Existent Insurance Values: {data['insurance'].unique()}")
data_bin['insurance_private'] = (data['insurance'] == 'Private').astype(int)

# ADMISSION/DISPOSITION (reference group: discharged)
data_bin['is_admitted'] = data['is_admitted']

# PRIOR VISITS (continuous variable)
prior_visits_col = ['num_previous_admissions', 'num_previous_visits_without_admission']
data_bin[prior_visits_col] = data[prior_visits_col]

# CROWDEDNESS (continuous variable)
data_bin['crowdedness'] = data['crowdedness']

# COMORBIDITY (index + diagnosis)
data_bin['pci_before_visit'] = data['pci_before_visit'].replace('unknown', np.nan) # replace 'NaN' by mean value
mean_value = pd.to_numeric(data_bin['pci_before_visit'], errors='coerce').mean() 
data_bin['pci_before_visit'] = data_bin['pci_before_visit'].fillna(mean_value)

pre_diagnosis_list = ['pre_diagnosis_any_malignancy', 'pre_diagnosis_gastrointestinal',
                      'pre_diagnosis_nausea_and_vomiting', 'pre_diagnosis_diabetes_mellitus', 
                      'pre_diagnosis_pain_conditions', 'pre_diagnosis_cardiovascular', 
                      'pre_diagnosis_developmental_delays', 'pre_diagnosis_epilepsy', 
                      'pre_diagnosis_asthma', 'pre_diagnosis_anemia', 
                      'pre_diagnosis_congenital_malformations', 'pre_diagnosis_conduct_disorders', 
                      'pre_diagnosis_chromosomal_anomalies', 'pre_diagnosis_anxiety', 
                      'pre_diagnosis_weight_loss', 'pre_diagnosis_psychotic_disorders', 
                      'pre_diagnosis_drug_abuse', 'pre_diagnosis_smoking', 'pre_diagnosis_depression', 
                      'pre_diagnosis_eating_disorders', 'pre_diagnosis_menstrual_disorders', 
                      'pre_diagnosis_sleep_disorders', 'pre_diagnosis_joint_disorders', 
                      'pre_diagnosis_alcohol_abuse']
data_bin[pre_diagnosis_list] = data[pre_diagnosis_list]

# WEIGHT (continuous variable)
data_bin['weight'] = data['weight'].replace('nan', np.nan) # replace 'not_taken' by mean value
mean_value = pd.to_numeric(data_bin['weight'], errors='coerce').mean() 
data_bin['weight'] = data_bin['weight'].fillna(mean_value)

# TRIAGE VITALS (already normalized)
data_bin['norm_heart_rate'] = data['triage_hr']
data_bin['norm_respiratory_rate'] = data['triage_rr']
data_bin['norm_sbp'] = data['triage_sbp']
data_bin['norm_temp'] = data['triage_temp']

# TIME STAMPS
# Arrival year (reference group 2019)
data_bin['arrival_year_2020'] = (data['year_of_arrival'] == '2020').astype(int)
data_bin['arrival_year_2021'] = (data['year_of_arrival'] == '2021').astype(int)
data_bin['arrival_year_2022'] = (data['year_of_arrival'] == '2022').astype(int)
data_bin['arrival_year_2023'] = (data['year_of_arrival'] == '2023').astype(int)
data_bin['arrival_year_2024'] = (data['year_of_arrival'] == '2024').astype(int)

# Arrival season (reference group: summer)
data_bin['arrival_season_winter'] = (data['season'] == 'winter').astype(int)
data_bin['arrival_season_fall'] = (data['season'] == 'autumn').astype(int)
data_bin['arrival_season_spring'] = (data['season'] == 'spring').astype(int)

# Arrival day type 
data_bin['arrival_weekend'] = data['is_weekend']

# Arrival time block (reference group: evening)
data_bin['arrival_time_afternoon'] = (data['time_of_day'] == 'afternoon').astype(int)
data_bin['arrival_time_small_hours'] = (data['time_of_day'] == 'small hours').astype(int)
data_bin['arrival_time_morning'] = (data['time_of_day'] == 'morning').astype(int)

# CHIEF COMPLAINTS GROUPS
chief_complaints = ['complaint_contains_abdominal_pain', 'complaint_contains_assault', 
                    'complaint_contains_allergic_reaction', 'complaint_contains_altered_mental_status', 
                    'complaint_contains_asthma_or_wheezing', 'complaint_contains_bites_or_stings', 
                    'complaint_contains_burn', 'complaint_contains_cardiac', 'complaint_contains_chest_pain',
                    'complaint_contains_chronic_disease', 'complaint_contains_congestion', 
                    'complaint_contains_constipation', 'complaint_contains_cough', 
                    'complaint_contains_croup', 'complaint_contains_crying_or_colic', 
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
                    'complaint_contains_pregnancy', 'complaint_contains_primary_care', 
                    'complaint_contains_psych', 'complaint_contains_rash', 
                    'complaint_contains_other_respiratory', 'complaint_contains_seizure', 
                    'complaint_contains_sore_throat', 'complaint_contains_trauma', 
                    'complaint_contains_urinary', 'complaint_contains_vomiting']
data_bin.loc[:, chief_complaints] = data[chief_complaints].copy()

# OTHER RAW INFORMATION
columns_to_add = ['triage_acuity', 'triage_pain', 'triage_sbp', 'triage_temp', 'complaint']
data_bin.loc[:, columns_to_add] = data[columns_to_add]
data_bin.loc[:, 'triage_spo2'] = data['triage_sp_o2']
data_bin.loc[:, 'triage_hr'] = data['raw_triage_hr']
data_bin.loc[:, 'triage_rr'] = data['raw_triage_rr']
data_bin.loc[:, 'age'] = data['age_in_days']/365  # age in years for consistency with CHLA

# Save binarized data
data_bin.to_csv('preprocessed_BCH.csv')

