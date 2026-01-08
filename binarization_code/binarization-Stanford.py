# CHLA: Covariate Binarization

import pandas as pd
import fire

def run(
    input_file=(
        '/rc-fs/chip-lacava/Public/physionet.org/files/mc-med/disparities/'
        'preprocessed-visits-for-blanca.csv'
    ),
    output_file='preprocessed_Stanford.csv'
):
    # Load preprocessed data
    data = pd.read_csv(input_file)
    print('loaded',input_file)
    print(data.columns)

    # Create empty data frame
    data_bin = pd.DataFrame(index=data.index)

    # CSN VALUES
    data_bin['csn'] = data['csn']

    # SEX: Add binary column (reference group: female)
    # print(f"Existent Gender Values: {data['gender'].unique()}")
    data_bin['is_male'] = (data['gender'] == 'M').astype(int)

    # AGE: Add binary columns (reference group: < 30)
    data_bin['age_group_30_39'] = (data['age_group'] == '30-39').astype(int)
    data_bin['age_group_40_49'] = (data['age_group'] == '40-49').astype(int)
    data_bin['age_group_50_59'] = (data['age_group'] == '50-59').astype(int)
    data_bin['age_group_60_69'] = (data['age_group'] == '60-69').astype(int)
    data_bin['age_group_70_79'] = (data['age_group'] == '70-79').astype(int)
    data_bin['age_group_80'] = (data['age_group'] == '80+').astype(int)

    # RACE: Add binary columns (reference gorup: Non-Hispanic White)
    # print(f"Existent Race Values: {data['race'].unique()}")
    data_bin['is_asian'] = (data['race'] == 'Asian').astype(int)
    data_bin['is_hispanic'] = (data['race'] == 'Hispanic').astype(int)
    data_bin['is_hispanic_white'] = (data['race'] == 'Hispanic White').astype(int)
    data_bin['is_black'] = (data['race'] == 'Non-Hispanic Black').astype(int)
    data_bin['is_other'] = (data['race'] == 'Other').astype(int)
    data_bin['is_unknown'] = (data['race'] == 'Unknown').astype(int)

    # MEANS OF ARRIVAL: Add binary columns (reference group: Self)
    # print(f"Means of arrival values: {data['means_of_arrival'].unique()}")
    data_bin['arrival_EMS'] = (data['means_of_arrival'] == 'EMS').astype(int)
    data_bin['arrival_other_unknown'] = (data['means_of_arrival'] == 'Other/Unknown').astype(int)

    # INSURANCE
    # print(f"Insurance values: {data['insurance'].unique()}")
    # Add binary columns (reference group: Medicaid)
    data_bin['insurance_medicare'] = (data['insurance'] == 'Medicare').astype(int)
    data_bin['insurance_other'] = (data['insurance'] == 'Other').astype(int)

    # PRIOR VISITS
    data_bin['num_previous_admissions'] = data['num_previous_admissions']
    data_bin['num_previous_visits_without_admission'] = data['num_previous_visits_without_admission']

    # COMORBIDITY SCORE
    data_bin['cci_before_visit'] = data['cci_before_visit']

    # TRIAGE VITALS (reference group: normal)

    # HR: 
    # print(f"HR values: {data['triage_hr'].unique()}")
    data_bin['triage_HR_high'] = (data['triage_hr'] == 'high').astype(int)
    data_bin['triage_HR_low'] = (data['triage_hr'] == 'low').astype(int)
    data_bin['triage_HR_very_high'] = (data['triage_hr'] == 'very_high').astype(int)
    data_bin['triage_HR_unknown'] = (data['triage_hr'] == 'nan').astype(int)

    # RR: 
    # print(f"RR values: {data['triage_rr'].unique()}")
    data_bin['triage_RR_high'] = (data['triage_rr'] == 'high').astype(int)
    data_bin['triage_RR_low'] = (data['triage_rr'] == 'low').astype(int)
    data_bin['triage_RR_unknown'] = (data['triage_rr'] == 'nan').astype(int)

    # O2 saturation: 
    # print(f"SpO2 values: {data['triage_sp_o2'].unique()}")
    data_bin['triage_SpO2_very_low'] = (data['triage_sp_o2'] == 'very_low').astype(int)
    data_bin['triage_SpO2_low'] = (data['triage_sp_o2'] == 'low').astype(int)
    data_bin['triage_SpO2_unknown'] = (data['triage_sp_o2'] == 'nan').astype(int)

    # BP:
    # print(f"BP values: {data['triage_bp'].unique()}")
    data_bin['triage_bp_stage_2'] = (data['triage_bp'] == 'Stage 2 Hypertension').astype(int)
    data_bin['triage_bp_stage_1'] = (data['triage_bp'] == 'Stage 1 Hypertension').astype(int)
    data_bin['triage_bp_elevated'] = (data['triage_bp'] == 'Elevated').astype(int)
    data_bin['triage_bp_hypertensive_crisis'] = (data['triage_bp'] == 'Hypertensive Crisis').astype(int)
    data_bin['triage_bp_unknown'] = (data['triage_bp'] == 'nan').astype(int)

    # Temperature
    # print(f"Temperature values: {data['triage_temp'].unique()}")
    data_bin['triage_temp_fever'] = (data['triage_temp'] == 'fever').astype(int)
    data_bin['triage_temp_unknown'] = (data['triage_temp'] == 'nan').astype(int)

    # CHIEF COMPLAINTS:
    chief_complaints = [
        'complaint_contains_abdominal_pain', 'complaint_contains_pelvic_pain', 'complaint_contains_chest_pain', 
        'complaint_contains_shortness_of_breath', 'complaint_contains_headache', 'complaint_contains_fever', 
        'complaint_contains_fall', 'complaint_contains_ortho', 'complaint_contains_dizziness', 
        'complaint_contains_weakness', 'complaint_contains_other_abdomen_complaint', 'complaint_contains_cough', 
        'complaint_contains_chest', 'complaint_contains_flank_pain', 'complaint_contains_neuro', 
        'complaint_contains_psych', 'complaint_contains_seizure', 'complaint_contains_crash', 
        'complaint_contains_vaginal', 'complaint_contains_cardiac', 'complaint_contains_syncope', 
        'complaint_contains_head_and_neck', 'complaint_contains_hypertension', 'complaint_contains_skin', 
        'complaint_contains_genitourinary', 'complaint_contains_assault', 'complaint_contains_pregnancy', 
        'complaint_contains_shingles']

    data_bin[chief_complaints] = data[chief_complaints]

    # ADD OTHER INFORMATION: triage acuity, triage vital signs, raw chief complaints
    columns_to_add = [
        "triage_acuity",
        "cc",
        "pre_diagnosis_mi",
        "pre_diagnosis_chf",
        "pre_diagnosis_pvd",
        "pre_diagnosis_cevd",
        "pre_diagnosis_dementia",
        "pre_diagnosis_cpd",
        "pre_diagnosis_rheumd",
        "pre_diagnosis_pud",
        "pre_diagnosis_mld",
        "pre_diagnosis_diab",
        "pre_diagnosis_diabwc",
        "pre_diagnosis_hp",
        "pre_diagnosis_rend",
        "pre_diagnosis_canc",
        "pre_diagnosis_msld",
        "pre_diagnosis_metacanc",
        "pre_diagnosis_aids",
        "raw_triage_sbp",
        "raw_triage_dbp",
        "raw_triage_temp",
        "raw_chief_complaint",
        "is_admitted",
        'ed_los'
    ]
    data_bin[columns_to_add] = data[columns_to_add]
    data_bin['triage_hr'] = data['raw_triage_hr']
    data_bin['triage_rr'] = data['raw_triage_rr']
    data_bin['triage_spo2'] = data['raw_triage_ox_sat']

    # SAVE BINARIZED DATA
    print('saving',output_file,'of shape',data_bin.shape)
    print(data_bin.head())
    data_bin.to_csv(output_file)

if __name__=='__main__':
    fire.Fire(run)

