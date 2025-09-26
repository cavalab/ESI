library(tidycensus)
library(raster)
library(zipcodeR)
library(dplyr)
library(lubridate)
library(purrr)
library(tidyr)
library(stringr)
library(testit)

# Working directory and paths
setwd("/Volumes/chip-lacava/Groups/CHLA-ED/raw-data/2025-07-14/De-identified dataset")



# DEFINE FUNCTIONS -------------------------------------------------------------

# Convert age in days into age-groups
get_age_group <- function(age_in_years) {
  case_when(
    age_in_years < 0.25 ~ "under_3_months",
    age_in_years < 0.5  ~ "three_to_6_months",
    age_in_years < 1 ~ "six_to_12_months",
    age_in_years < 1.5 ~ "twelve_to_18_months",
    age_in_years < 3 ~ "eighteen_months_to_3_years",
    age_in_years < 5 ~ "three_to_5_years",
    age_in_years < 10 ~ "five_to_10_years",
    age_in_years < 15 ~ "ten_to_15_years",
    age_in_years >= 15 ~ "older_than_15_years",
    .default = NA
  )
}

# Get state from ZIP code
get_state <- function(zip_code) {
  if(is.na(zip_code) || zip_code == "") return(NA)  # Handle missing values
  zip_clean <- substr(as.character(zip_code), 1, 5) # Only keep the first 5 digits (ex: 90220-2463)
  # Check if there are 5 characters and they are numeric
  if (nchar(zip_clean) == 5 && grepl("^[0-9]{5}$", zip_clean)) { # matches digit 0-9 and has 5 digits
    result <- reverse_zipcode(zip_clean)
  } else {
    return(NA)
  }
}

# Get and group normalized weight
get_weight_normalize  <- function(data, data_weight) {
  # Get first weight per visit and add to data
  data <- data %>%
    left_join(data_weight %>% group_by(id_visit) %>%
        slice_min(datetime, n=1, with_ties=FALSE) %>%
        ungroup() %>% dplyr::select(id_visit, weightkg), by = "id_visit",  copy = TRUE
    ) %>%  rename(weight = weightkg)
  
  # Normalize and categorize weights
  for (group in unique(data$age_group)) {
    indices <- which(data$age_group == group)
    mu <- mean(as.numeric(data$weight[indices]), na.rm = TRUE)
    sigma <- sd(as.numeric(data$weight[indices]), na.rm = TRUE)
    data$weight[indices] <- ifelse(is.na(data$weight[indices]), 
                                       "not_taken", 
                                       abs((as.numeric(data$weight[indices]) - mu) / sigma))
  }
  return(data)
}

# Get triage vitals recording time
get_vital_signs_triage_time <- function(data_RR, data_HR, data_So2, data_temp, data_blood_pressure) {
  
  # Rename encounter id columns
  data_RR <- data_RR %>% rename(encounter_id = pecarn_submit_respiratoryrate.encntr_id)
  data_HR <- data_HR %>% rename(encounter_id = pecarn_submit_heartrate.encntr_id)
  data_So2 <- data_So2 %>% rename(encounter_id = pecarn_submit_respiratorysupport.encntr_id)
  data_temp <- data_temp %>% rename(encounter_id = pecarn_submit_tempc.encntr_id)
  data_blood_pressure <- data_blood_pressure %>% rename(encounter_id = pecarn_submit_bloodpressure.encntr_id)
  
  # Format recording times
  data_RR <- data_RR %>%
    mutate(vitals_datetime = paste(pecarn_submit_respiratoryrate.date, pecarn_submit_respiratoryrate.time),
           vitals_datetime = ymd_hms(vitals_datetime))
  data_HR <- data_HR %>%
    mutate(vitals_datetime = paste(pecarn_submit_heartrate.date, pecarn_submit_heartrate.time),
           vitals_datetime = ymd_hms(vitals_datetime))
  data_So2 <- data_So2 %>% 
    mutate(vitals_datetime =pecarn_submit_respiratorysupport.gid,
           vitals_datetime = ymd_hms(vitals_datetime))
  data_temp <- data_temp %>%
    mutate(vitals_datetime = paste(pecarn_submit_tempc.date, pecarn_submit_tempc.time),
           vitals_datetime = ymd_hms(vitals_datetime))
  data_blood_pressure <- data_blood_pressure %>%
    mutate(vitals_datetime = paste(pecarn_submit_bloodpressure.date, pecarn_submit_bloodpressure.time),
           vitals_datetime = ymd_hms(vitals_datetime))
  
  # Create vitals tables list
  vitals_list <- list(data_RR, data_HR, data_So2, data_temp, data_blood_pressure)
  names(vitals_list) <- c("data_RR", "data_HR", "data_So2", "data_temp", "data_blood_pressure")
  vitals_tables <- map(vitals_list, ~ list(data = .x, encounter_col = "encounter_id"))
  
  # Extract earliest vitals time per visit
  triage_times_list <- map(vitals_tables, function(table_info) {
    table_info$data %>%
      filter(!is.na(vitals_datetime)) %>%
      group_by(!!sym(table_info$encounter_col)) %>%
      summarise(earliest_vitals_time = min(vitals_datetime, na.rm = TRUE), .groups = "drop") %>%
      rename(encounter_id = !!sym(table_info$encounter_col))
  })
  
  # Combine all tables and find the overall earliest time per visit
  triage_vitals_times <- bind_rows(triage_times_list) %>%
    group_by(encounter_id) %>%
    summarise(triage_vitals_time = min(earliest_vitals_time, na.rm = TRUE), .groups = "drop")
  
  return(triage_vitals_times)
}

# Get table with triage vital signs
get_triage_vitals_table <- function(data_RR, data_HR, data_So2, data_temp, data_blood_pressure, triage_vitals_times) {
  
  # Rename encounter id columns and format datetime for each dataset
  data_RR <- data_RR %>% 
    rename(encounter_id = pecarn_submit_respiratoryrate.encntr_id) %>%
    mutate(vitals_datetime = ymd_hms(paste(pecarn_submit_respiratoryrate.date, pecarn_submit_respiratoryrate.time)))
  
  data_HR <- data_HR %>% 
    rename(encounter_id = pecarn_submit_heartrate.encntr_id) %>%
    mutate(vitals_datetime = ymd_hms(paste(pecarn_submit_heartrate.date, pecarn_submit_heartrate.time)))
  
  data_So2 <- data_So2 %>% 
    rename(encounter_id = pecarn_submit_respiratorysupport.encntr_id) %>%
    mutate(vitals_datetime = ymd_hms(pecarn_submit_respiratorysupport.gid))
  
  data_temp <- data_temp %>% 
    rename(encounter_id = pecarn_submit_tempc.encntr_id) %>%
    mutate(vitals_datetime = ymd_hms(paste(pecarn_submit_tempc.date, pecarn_submit_tempc.time)))
  
  data_blood_pressure <- data_blood_pressure %>% 
    rename(encounter_id = pecarn_submit_bloodpressure.encntr_id) %>%
    mutate(vitals_datetime = ymd_hms(paste(pecarn_submit_bloodpressure.date, pecarn_submit_bloodpressure.time)))
  
  # Create all_vitals table (combine all vitals with vital_type column)
  all_vitals <- bind_rows(
    data_RR %>% mutate(vital_type = "respiratory_rate") %>% 
      dplyr::select(encounter_id, vitals_datetime, vital_type, vital_value = pecarn_submit_respiratoryrate.respiratoryrate),
    data_HR %>% mutate(vital_type = "heart_rate") %>% 
      dplyr::select(encounter_id, vitals_datetime, vital_type, vital_value = pecarn_submit_heartrate.heartrate),
    data_So2 %>% mutate(vital_type = "oxygen_saturation") %>% 
      dplyr::select(encounter_id, vitals_datetime, vital_type, vital_value = pecarn_submit_respiratorysupport.o2sat),
    data_temp %>% mutate(vital_type = "temperature") %>% 
      dplyr::select(encounter_id, vitals_datetime, vital_type, vital_value = pecarn_submit_tempc.tempc),
    data_blood_pressure %>% mutate(vital_type = "blood_pressure_systolic") %>% 
      dplyr::select(encounter_id, vitals_datetime, vital_type, vital_value = pecarn_submit_bloodpressure.systolicbp),
    data_blood_pressure %>% mutate(vital_type = "blood_pressure_diastolic") %>% 
      dplyr::select(encounter_id, vitals_datetime, vital_type, vital_value = pecarn_submit_bloodpressure.diastolicbp)
  ) %>%
    filter(!is.na(vitals_datetime))
  
  # Create triage_vitals table (one row per encounter, one column per vital)
  table_triage_vitals <- all_vitals %>%
    left_join(triage_vitals_times, by = "encounter_id") %>%
    filter(vitals_datetime == triage_vitals_time) %>%
    group_by(encounter_id, vital_type) %>% summarise(value=mean(vital_value)) %>%
    dplyr::select(encounter_id, vital_type, value) %>%

    pivot_wider(
      names_from = vital_type,
      values_from = value,
      names_sep = "_"
    ) %>%
    # Ensure all encounters are represented
    right_join(
      triage_vitals_times, 
      by = "encounter_id"
    )
  
  # Return both tables
  return(table_triage_vitals)
}

# Get table with all vital signs
get_all_vitals_table <- function(data_RR, data_HR, data_So2, data_temp, data_blood_pressure) {
  
  # Rename encounter id columns and format datetime for each dataset
  data_RR <- data_RR %>% 
    rename(encounter_id = pecarn_submit_respiratoryrate.encntr_id) %>%
    mutate(vitals_datetime = paste(pecarn_submit_respiratoryrate.date, pecarn_submit_respiratoryrate.time),
           vitals_datetime = ymd_hms(vitals_datetime))
  
  data_HR <- data_HR %>% 
    rename(encounter_id = pecarn_submit_heartrate.encntr_id) %>%
    mutate(vitals_datetime = paste(pecarn_submit_heartrate.date, pecarn_submit_heartrate.time),
           vitals_datetime = ymd_hms(vitals_datetime))
  
  data_So2 <- data_So2 %>% 
    rename(encounter_id = pecarn_submit_respiratorysupport.encntr_id) %>%
    mutate(vitals_datetime = ymd_hms(pecarn_submit_respiratorysupport.gid))
  
  data_temp <- data_temp %>% 
    rename(encounter_id = pecarn_submit_tempc.encntr_id) %>%
    mutate(vitals_datetime = paste(pecarn_submit_tempc.date, pecarn_submit_tempc.time),
           vitals_datetime = ymd_hms(vitals_datetime))
  
  data_blood_pressure <- data_blood_pressure %>% 
    rename(encounter_id = pecarn_submit_bloodpressure.encntr_id) %>%
    mutate(vitals_datetime = paste(pecarn_submit_bloodpressure.date, pecarn_submit_bloodpressure.time),
           vitals_datetime = ymd_hms(vitals_datetime))
  
  # Create all_vitals table (combine all vitals with vital_type column)
  table_all_vitals <- bind_rows(
    data_RR %>% mutate(vital_type = "respiratory_rate") %>% 
      dplyr::select(encounter_id, vitals_datetime, vital_type, vital_value = pecarn_submit_respiratoryrate.respiratoryrate),
    data_HR %>% mutate(vital_type = "heart_rate") %>% 
      dplyr::select(encounter_id, vitals_datetime, vital_type, vital_value = pecarn_submit_heartrate.heartrate),
    data_So2 %>% mutate(vital_type = "oxygen_saturation") %>% 
      dplyr::select(encounter_id, vitals_datetime, vital_type, vital_value = pecarn_submit_respiratorysupport.o2sat),
    data_temp %>% mutate(vital_type = "temperature") %>% 
      dplyr::select(encounter_id, vitals_datetime, vital_type, vital_value = pecarn_submit_tempc.tempc),
    data_blood_pressure %>% mutate(vital_type = "blood_pressure_systolic") %>% 
      dplyr::select(encounter_id, vitals_datetime, vital_type, vital_value = pecarn_submit_bloodpressure.systolicbp),
    data_blood_pressure %>% mutate(vital_type = "blood_pressure_diastolic") %>% 
      dplyr::select(encounter_id, vitals_datetime, vital_type, vital_value = pecarn_submit_bloodpressure.diastolicbp)
  ) %>%
    filter(!is.na(vitals_datetime))
  
  #Code used to pivot wider, but no need to do this here- long format is fine.

  return(table_all_vitals)
}

# Add pain scores to vitals
add_pain_scores_to_vitals <- function(data_painscore, triage_vitals_wide, all_vitals) {
  
  # Process pain score data
  data_pain_processed <- data_painscore %>%
    rename(encounter_id = pecarn_submit_painscore.encntr_id) %>%  
    mutate(vitals_datetime = paste(pecarn_submit_painscore.painscore_date, pecarn_submit_painscore.painscore_time), 
           vitals_datetime = ymd_hms(vitals_datetime)) %>%
    dplyr::select(encounter_id, vitals_datetime, pain_score = pecarn_submit_painscore.score) %>% 
    filter(!is.na(vitals_datetime))

   print(head(data_pain_processed))
  
  # Add pain scores to triage vitals table
  triage_vitals_with_pain <- triage_vitals_wide %>%
    left_join(data_pain_processed, by = c("encounter_id", "triage_vitals_time" = "vitals_datetime"))
  
  # Add pain scores to all vitals table (this is long format)
  data_pain_processed <- data_pain_processed %>% rename(vital_value=pain_score) %>% mutate(vital_type="pain")
  all_vitals_with_pain <- rbind(all_vitals, data_pain_processed)
  
  return(list(
    triage_vitals_with_pain = triage_vitals_with_pain,
    all_vitals_with_pain = all_vitals_with_pain
  ))
  
}

# Get diagnoses from diagnosis codes
get_icd_scores_diagnosis <- function(data_diagnoses) {
  
  # Generate ICD prefixes
  generate_icd_prefixes <- function(letter, start_num, end_num, exclude_nums = c()) {
    nums <- start_num:end_num
    nums <- nums[!nums %in% exclude_nums]
    paste0(letter, sprintf("%02d", nums))
  }
  
  # Find condition for a given ICD code
  find_condition <- function(icd_code, code_dict) {
    for (condition in names(code_dict)) {
      if (any(sapply(code_dict[[condition]], function(prefix) startsWith(icd_code, prefix)))) {
        return(condition)
      }
    }
    return(NA)
  }
  
  # Get condition from pre-computed mapping
  get_condition <- function(icd_code, unique_codes, corresponding_conditions) {
    if (icd_code %in% unique_codes) {
      return(corresponding_conditions[icd_code])
    }
    return(NA)
  }
  
  # Rename columns
  diagnoses <- data_diagnoses %>%
    rename(encounter_id = pecarn_submit_ps_diagnoses.encntr_id,
           DIAGNOSIS_CODE = pecarn_submit_ps_diagnoses.dxcode)

  # Define ICD code dictionary
  paed_icd_code_dict <- list(
    "alcohol_abuse" = c("F10", "Z71.41", "K70"),
    "anemia" = c("D50", "D51", "D52", "D53", "D55", "D66", "D57"),
    "anxiety" = c("F06.4", "F40", "F41", "F43.0", "F43.22", "F43.8", "F43.9"),
    "any_malignancy" = c("C00", "C01", "C02", "C03", "C04", "C05", "C06", "C07", "C08", "C09",
                         "C10", "C11", "C12", "C13", "C14", "C15", "C16", "C17", "C18", "C19", 
                         "C20", "C21", "C22", "C23", "C24", "C25", "C26", "C30", "C31", "C32", 
                         "C33", "C34", "C35", "C36", "C37", "C38", "C39", "C40", "C41", "C43", 
                         "C45", "C46", "C47", "C48", "C49", "C50", "C51", "C52", "C53", "C54", 
                         "C55", "C56", "C57", "C58", "C60", "C61", "C62", "C63", "C64", "C65", 
                         "C66", "C67", "C68", "C69", "C70", "C71", "C72", "C73", "C74", "C75",
                         "C76", "C81", "C82", "C84", "C85", "C86", "C87", "C88", "C89", "C90", 
                         "C91", "C92", "C93", "C94.0", "C94.1", "C94.2", "C94.3", "C95", 
                         "C96.0", "C96.2", "C96.4", "C96.9", "C96.A", "C96.Z", "D45"),
    "asthma" = c("J45"),
    "cardiovascular" = generate_icd_prefixes("I", 0, 99, c(3, 4, 17, 18, 19, 29, 53, 54, 55, 56, 57, 58, 59, 90, 91, 92, 93, 94)),
    "chromosomal_anomalies" = generate_icd_prefixes("Q", 90, 99, c(94)),
    "conduct_disorders" = c("F91"),
    "congenital_malformations" = generate_icd_prefixes("Q", 0, 89, c(8, 9, 19, 29, 46, 47, 48, 49, 57, 58, 59)),
    "depression" = c("F32", "F33", "F06.30", "F06.31", "F06.32", "F34.9", "F39", "F43.21", "F43.23"),
    "developmental_delays" = c("F81", "R48.0", "F80", "H93.25", "F82", "F88", "F89", "F70", "F71", "F72", "F78", "F79"),
    "diabetes_mellitus" = c("E08", "E09", "E10", "E11", "E13"),
    "drug_abuse" = c(generate_icd_prefixes("F", 11, 19, c(17)), "F55", "Z71.51"),
    "eating_disorders" = c("F50"),
    "epilepsy" = c("G40", "R56"),
    "gastrointestinal" = c(generate_icd_prefixes("K", 20, 31, c(24)), "K50", "K51", "K52", "K58", "Z87.1", "K92", "K62"),
    "joint_disorders" = c("M21", "M24"),
    "menstrual_disorders" = c("N91", "N92"),
    "nausea_and_vomiting" = c("R11"),
    "pain_conditions" = c("G89", "R52", "R10", "M54", "R07", "M25.5", "F45.4"),
    "psychotic_disorders" = c("F30", "F31", "F06.33", "F20", "F22", "F23", "F24", "F25", "F28", "F29", "R44"),
    "sleep_disorders" = c("F51", "G47.0", "G47.1", "G47.2", "G47.3", "G47.4", "G47.5", "G47.6", "G47.8", "G47.9"),
    "smoking" = c("F17", "T65.2", "Z87.891"),
    "weight_loss" = c(generate_icd_prefixes("E", 40, 46, c()), "E64.0", "R63.4", "R64")
  )
  
  # Get the conditions associated with each diagnosis
  unique_codes <- unique(diagnoses$DIAGNOSIS_CODE)
  corresponding_conditions <- purrr::map_vec(unique_codes, ~find_condition(.x, paed_icd_code_dict), .progress = TRUE)
  codes_with_conditions <- which(!is.na(corresponding_conditions))
  
  unique_codes <- unique_codes[codes_with_conditions]
  corresponding_conditions <- corresponding_conditions[codes_with_conditions]
  names(corresponding_conditions) <- unique_codes
  
  # Map conditions to diagnosis codes
  diagnoses$condition <- 
    purrr::map_vec(diagnoses$DIAGNOSIS_CODE, ~get_condition(.x, unique_codes, corresponding_conditions), .progress = TRUE)
  # 77% of the codes are not associated with a condition
  
  # Filter out diagnoses that don't correspond to any condition
  diagnoses <- diagnoses %>% 
    filter(!is.na(condition))
  
  # Get unique conditions per patient
  patient_conditions <- diagnoses %>% 
    group_by(encounter_id) %>% 
    distinct(condition, .keep_all = TRUE) %>%
    ungroup()
  
  # Create binary indicator variables for each condition
  condition_indicators <- patient_conditions %>%
    mutate(value = 1) %>%
    pivot_wider(
      id_cols = encounter_id,
      names_from = condition,
      values_from = value,
      values_fill = 0,
      names_prefix = "diagnosis_"
    )
  
  # Get all unique encounters to ensure all patients are included
  all_encounters <- data_diagnoses %>%
    select(pecarn_submit_ps_diagnoses.encntr_id) %>%
    rename(encounter_id = pecarn_submit_ps_diagnoses.encntr_id) %>%
    distinct()
  
  # Join to include all patients, filling missing conditions with 0
  result <- all_encounters %>%
    left_join(condition_indicators, by = "encounter_id") %>%
    mutate(across(starts_with("diagnosis_"), ~replace_na(.x, 0)))
  
  return(result)
}

# Get temporal variables
get_temporal_variables <- function(data) {
  
  data <- data %>%
    mutate(
      # Extract year
      arrival_year = year(arrival_datetime),
      
      # Create season based on month
      arrival_season = case_when(
        month(arrival_datetime) %in% c(12, 1, 2) ~ "Winter (Dec-Feb)",
        month(arrival_datetime) %in% c(3, 4, 5) ~ "Spring (Mar-May)",
        month(arrival_datetime) %in% c(6, 7, 8) ~ "Summer (Jun-Aug)",
        month(arrival_datetime) %in% c(9, 10, 11) ~ "Fall (Sep-Nov)",
        TRUE ~ NA_character_
      ),
      
      arrival_day_txfype = case_when(
        wday(arrival_datetime) %in% c(6, 7) ~ "Weekend",
        wday(arrival_datetime) %in% c(1, 2, 3, 4, 5) ~ "Weekday",
        TRUE ~ NA_character_
      ),
      
      # Create 6-hour time blocks
      arrival_time_block = case_when(
        hour(arrival_datetime) %in% 0:5 ~ "00:00-05:59",
        hour(arrival_datetime) %in% 6:11 ~ "06:00-11:59",
        hour(arrival_datetime) %in% 12:17 ~ "12:00-17:59",
        hour(arrival_datetime) %in% 18:23 ~ "18:00-23:59",
        TRUE ~ NA_character_
      )
    )
  
  return(data)
}

# Get crowdedness
get_crowdedness <- function(data) {
 
    #Get crowdedness scores and pseudo-NEDOCS scores: first, create specialised dataframes
    crowdedness_df <- data %>% 
        select(id_visit, arrival_datetime, disposition_datetime, triage_acuity) %>% arrange(arrival_datetime)

    #Make a new dataframe with crowdedness scores
    score_results <- purrr::map(
        1:nrow(data), #Number of rows is the same
        function (i) {
            #Count visits which started earlier than the arrival time, and ended after;
            #we only need to check the departure times of visits which occur before the current one 
            #in the data frame, because of the ordering
            if (i==1) {
                return(list(0, 0))
            } else {
                present_at_arrival <- which(crowdedness_df$disposition_time[1:(i-1)] > crowdedness_df$arrival_datetime[i])
            
                crowdedness_score <- length(present_at_arrival) #no offset, so present-at-arrival also gives indices in the original dataframe
                pseudo_nedocs <-  sum(6-crowdedness_df$triage_acuity[present_at_arrival], na.rm=TRUE)

                return(list(crowdedness_score, pseudo_nedocs)) #Crowdedness is number of patients there when you got to ED
                    #pseudo-NEDOCS weights them by severity, such that a level-1 patient contributes 5 points
            }
            
        }, .progress=TRUE
    )

   #Set crowdedness score- remembering these are not in the same order as the visits dataframe
    crowdedness_df$crowdedness <- purrr::map_dbl(score_results, 1)
    crowdedness_df$pseudo_nedocs <- purrr::map_dbl(score_results, 2)
    crowdedness_df <- crowdedness_df %>% select(id_visit, crowdedness, pseudo_nedocs)
    data <- data %>% left_join(crowdedness_df, by="id_visit")
        return(data)
}

# Get prior visits
get_prior_visits <- function(data) { 
  visits <- data %>%
    arrange(id_patient, minutes_since_first_arrival) %>% 
    group_by(id_patient) %>%
    mutate(
      num_previous_admissions = purrr::map_dbl(row_number(), function(i) {
        current_time <- minutes_since_first_arrival[i]
        thirty_days_ago <- current_time - 24*60*30
        
        sum(minutes_since_first_arrival < current_time &
              minutes_since_first_arrival > thirty_days_ago &
              disposition == "Admitted")
      }),
      num_previous_visits_without_admission = purrr::map_dbl(row_number(), function(i) {
        current_time <- minutes_since_first_arrival[i]
        thirty_days_ago <- current_time - 24*60*30
        
        sum(minutes_since_first_arrival < current_time &
              minutes_since_first_arrival > thirty_days_ago &
              disposition == "Discharge")
      }),
    ) %>% ungroup()
  
  return(visits)
}

# MAIN -------------------------------------------------------------------------

# Load tables
data <- read.table("PATIENTIDENTIFIER_and_DEMOGRAPHICS.txt", sep = "|", header = TRUE)
data_age <- read.table("age_deid.txt", sep = "|", header = TRUE)
data_visit <- read.table("VISITINFORMATION.txt", sep = "|", header = TRUE)
data_weight <- read.table("WeightKg.txt", sep = "|", header = TRUE)
data_disposition <- read.table("EDDISPOSITION.txt", sep = "|", header = TRUE)
data_lab <- read.table("lab.txt", sep = "|", header = TRUE)
data_meds <- read.table("med_administration.txt", sep = "|", header = TRUE)
data_procedures <- read.table("PS_Procedures.txt", sep = "|", header = TRUE)
data_imaging <- read.table("imaging.txt", sep = "|", header = TRUE)
data_diagnoses <- read.table("PS_Diagnoses.txt", sep = "|", header = TRUE)
data_painscore <- read.table("painscore.txt", sep = "|", header = TRUE)
data_reason <- read.table("reason_for_visit.txt", sep = "|", header = TRUE)
# Vital signs
data_RR <- read.table("RespiratoryRate.txt", sep = "|", header = TRUE)
data_HR <- read.table("HeartRate.txt", sep = "|", header = TRUE)
data_So2 <- read.table("respiratorysupport.txt", sep = "|", header = TRUE)
data_temp <- read.table("TempC.txt", sep = "|", header = TRUE)
data_blood_pressure <- read.table("BloodPressure.txt", sep = "|", header = TRUE)

print("Loaded all files")

# Define main function
get_demographics <- function(data, data_age, data_visit, data_weight, data_disposition,
                             data_lab, data_meds, data_procedures, data_imaging,
                             data_diagnoses, data_painscore, data_RR, data_HR,
                             data_So2, data_temp, data_blood_pressure) {
  

  # VISIT ID (do not use edvisitid, use encntr_id) -----------------------------
  names(data)[names(data) == "pecarn_submit_patientidentifier_demographics.encntr_id_hashed"] <- "id_visit"
  # delete visits with duplicated IDs: 280 duplicated IDs
  id_counts <- data %>% count(id_visit, name = "count")
  data <- data %>% left_join(id_counts, by = "id_visit") %>%
    filter(count == 1) %>% dplyr::select(-count)
  
  # PATIENT ID -----------------------------------------------------------------
  names(data)[names(data) == "pecarn_submit_patientidentifier_demographics.medrecnbr_hashed"] <- "id_patient"
  
  # DISPOSITION ----------------------------------------------------------------
  data <- merge(data, data_disposition,  
                by.x = "id_visit", 
                by.y = "pecarn_submit_eddisposition.encntr_id", 
                all.x = TRUE)
  names(data)[names(data) == "pecarn_submit_eddisposition.disposition"] <- "disposition_raw"
  group_disposition <- function(disposition_col) {
    case_when(
      disposition_col %in% c("Admitted", "Discharge & Admit to CHLA Rehab") ~ "Admitted",
      disposition_col %in% c("Transfer to Other Medical Facility", "Other (OP) Medical Facility",
                             "Discharge OP to Psychiatric Facility") ~ "Transfer",
      disposition_col %in% c("Left prior to discharge", "Left prior to seeing MD", 
                             "Left prior to visit", "Against Medical Advice") ~ "Left",
      disposition_col %in% c("Home/Routine", "Discharge/Transfer to Home Health Care",
                             "Discharge/Transfer to other SNF", "Discharge Home", 
                             "Discharge/Transfer to Intermediate Care", "Residential Care Facility") ~ "Discharge",
      disposition_col %in% c("Expired (ER)") ~ "Died",
      TRUE ~ "other/unknown"
    )
  }
  data <- data %>% mutate(disposition = group_disposition(disposition_raw))
  # Drop disposition = "Left" (42,069) ,"Died" (20) & "other/unknown" (272)
  data <- data %>%
    filter(!disposition %in% c("Left", "Died", "other/unknown"))
  
  # DISPOSITION TIME -----------------------------------------------------------
  data <- data %>% mutate(disposition_datetime = ymd_hms(paste(pecarn_submit_eddisposition.eddepartdate,
                                     pecarn_submit_eddisposition.eddeparttime)))
  
  write.csv(data, "intermediate-files/visits-with-disposition-time.csv")
  print("Saved disp. times")

  # ARRIVAL DATE & TIME --------------------------------------------------------
  data <- merge(data, data_visit,  
                by.x = "id_visit", 
                by.y = "pecarn_submit_visitinformation.encntr_id", 
                all.x = TRUE)

  data <- data %>% mutate(arrival_datetime = ymd_hms(paste(pecarn_submit_visitinformation.eddoordate, pecarn_submit_visitinformation.eddoortime)))
  
  # Check visit length
  # 30 visits with departure before arrival
  data <- data[(data$disposition_datetime - data$arrival_datetime) > 0, ]
  # 248 visits with a duration longer than 36h
  data <- data[(data$disposition_datetime - data$arrival_datetime) < 36*60*60, ]
  
  # Minutes since first arrival
  first_arrival <- min(data$arrival_datetime, na.rm = TRUE)
  data <- data %>%
    mutate(
      minutes_since_first_arrival = as.numeric(difftime(arrival_datetime, first_arrival, units = "mins"))
    )
  
  # TRIAGE DATE & TIME ---------------------------------------------------------
  data <- data %>% mutate(triage_datetime = ymd_hms(paste(pecarn_submit_visitinformation.triagedate, pecarn_submit_visitinformation.triagetime)))
  
  # TEMPORAL COARSENING --------------------------------------------------------
  data <- get_temporal_variables(data)
  
  write.csv(data, "intermediate-files/visits-with-temporal-data.csv")
  print("Saved temporal data")

  # AGE (years) ----------------------------------------------------------------
  data_age$encntr_id_hashed <- gsub('^"|"$', '', data_age$encntr_id_hashed)
  data <- merge(data, data_age, 
                     by.x = "id_visit", 
                     by.y = "encntr_id_hashed", 
                     all.x = TRUE)
  # 6 visits with negative age
  data <- data[data$age >= 0, ]
  
  # Assign an age group
  data <- data %>% mutate(age_group = get_age_group(age))
  
  write.csv(data, "intermediate-files/visits-with-age.csv")
  print("Saved age")

  # SEX ------------------------------------------------------------------------
  names(data)[names(data) == "pecarn_submit_patientidentifier_demographics.sexid"] <- "sex"
  unique(data$sex)
  # 12 "unknown", 3 "intersex"
  data <- data %>% filter((sex =="M"| sex =="F")) # keep only M and F
  
  # RACE/ETHNICITY -------------------------------------------------------------
  names(data)[names(data) == "pecarn_submit_patientidentifier_demographics.ethnicity"] <- "ethnicity"
  names(data)[names(data) == "pecarn_submit_patientidentifier_demographics.race"] <- "race"
  
  # Group races
  # There are no NA values
  group_race <- function(race_column) {
    case_when(
      is.na(race_column) ~ "unknown",
      race_column %in% c("White", "Other White") ~ "white",
      race_column %in% c("Alaska Native/Inuit", "First Nation/Indigenous/Native/Indian", 
                         "Other First Nation/Indigenous/Native", "Native Hawaiian") ~ "native",
      race_column %in% c("Asian", "Asian Indian", "Asian/Pacific", "Cambodian", "Chinese", 
                         "Filipino", "Japanese", "Korean", "Laotian", "Other Asian", "South Asian", 
                         "Thai", "Vietnamese") ~ "asian",
      race_column %in% c("Black and/or African American", "African", "Afro Caribbean", 
                         "Other Black and/or African American") ~ "black",
      race_column %in% c("Cuban", "Guatemalan", "Latino/a/x and/or Hispanic", "Mexican/Mexican-American, 
                         Chican(x)", "Other Latin(x) and/or Hispanic", "Puerto Rican", "Salvadorian") ~ "hispanic",
      race_column %in% c("Declines to State") ~ "unknown",
      TRUE ~ "other"
    )
  }
  data <- data %>% mutate(race_groups= group_race(race))
  
  # Group ethnicity " " and "Unknown" 
  data$ethnicity[data$ethnicity == " "] <- "Unknown"
  
  # Create race/ethnicity groups
  group_race_ethnicity <- function(race_group_column, ethnicity_column) {
    case_when(
      is.na(race_group_column) ~ "unknown",
      race_group_column %in% c("asian") ~ "asian",
      race_group_column %in% c("black") & ethnicity_column == "Hispanic"  ~ "hispanic",
      race_group_column %in% c("black") & ethnicity_column == "Non-Hispanic"  ~ "non_hispanic_black",
      race_group_column %in% c("hispanic") ~ "hispanic", 
      race_group_column %in% c("unknown") & ethnicity_column == "Hispanic" ~ "hispanic",
      race_group_column %in% c("unknown") & ethnicity_column == "Non-Hispanic"~ "unknown",
      race_group_column %in% c("unknown") & ethnicity_column == "Unknown"~ "unknown",
      race_group_column %in% c("native") ~ "other",
      race_group_column %in% c("other") & ethnicity_column == "Unknown" ~ "other",
      race_group_column %in% c("other") & ethnicity_column == "Hispanic" ~ "hispanic", 
      race_group_column %in% c("other") & ethnicity_column == "Non-Hispanic" ~ "other",
      race_group_column %in% c("white") & ethnicity_column == "Hispanic" ~ "hispanic_white",
      race_group_column %in% c("white") & ethnicity_column == "Non-Hispanic" ~ "non_hispanic_white",
      .default = "unknown"
    )
  }
  data <- data %>% mutate(race_ethnicity = group_race_ethnicity(race_groups, ethnicity))
  # 15,386 visits with unknown race/ethnicity
  
  write.csv(data, "intermediate-files/visits-with-sex-and-race.csv")
  print("Saved sex and race")

  data <- read.csv("intermediate-files/visits-with-sex-and-race.csv")

  # ZIP CODE -------------------------------------------------------------------
  names(data)[names(data) == "pecarn_submit_patientidentifier_demographics.zip"] <- "zip"
  
  # STATES: extract from ZIP codes
  unique_zip_codes <- unique(data$zip)
  unique_states <- purrr::map_vec(unique_zip_codes, get_state, .progress = TRUE)
  valid_state <- which(!is.na(unique_states$state))
  unique_zip_codes <- unique_zip_codes[valid_state]
  unique_states <- unique_states[valid_state, ] 
  state_lookup <- setNames(unique_states$state, unique_zip_codes)
  data$state <- state_lookup[data$zip]
  
  # MILES TRAVELLED: extract from ZIP codes
  data <- data %>% mutate(miles_travelled= as.numeric(zip_distance(zip, "90027")$distance))
  
  # SOCIAL DEPRIVATION INDEX (SDI): Robert Graham Center's, 2019
  sdi_scores <- read.csv("rgcsdi-2015-2019-zcta.csv")
  sdi_scores$ZCTA5_FIPS <- sprintf("%05d", as.numeric(sdi_scores$ZCTA5_FIPS))
  sdi_scores <- sdi_scores %>% select(ZCTA5_FIPS, SDI_score)
  data <- left_join(data, sdi_scores, by=c("zip"="ZCTA5_FIPS"))
  data$SDI_score <- ifelse(is.na(data$SDI_score), "unknown", data$SDI_score)
                  

  write.csv(data, "intermediate-files/visits-with-socioeconomics.csv")
  print("Saved socioec")

  # TRIAGE ACUITY --------------------------------------------------------------
  names(data)[names(data) == "pecarn_submit_visitinformation.triagecategoryid"] <- "triage_acuity"
  
  # CHIEF COMPLAINT ------------------------------------------------------------
  names(data)[names(data) == "pecarn_submit_visitinformation.complaint"] <- "raw_complaint"
  
  write.csv(data, "intermediate-files/visits-with-raw-complaint.csv")
  print("Saved raw complaint")

  data <- read.csv("intermediate-files/visits-with-raw-complaint.csv")

  # Reason for visit
  data_reason$pecarn_submit_patientidentifier_demographics.encntr_id_hashed <- 
    gsub('^"|"$', '', data_reason$pecarn_submit_patientidentifier_demographics.encntr_id_hashed)

  #Drop visits with no or a non-unique ID in the chief complaints table.
  data_reason <- data_reason %>% group_by(pecarn_submit_patientidentifier_demographics.encntr_id_hashed) %>%
    mutate(num_appearances=n()) %>% filter(num_appearances==1) %>% select(-num_appearances)

   before_join <- nrow(data)

  data <- merge(data, data_reason,  
                by.x = "id_visit", 
                by.y = "pecarn_submit_patientidentifier_demographics.encntr_id_hashed", 
                all.x = FALSE) #We actually don't want visits with no identifiable chief complaint, per BCH
  names(data)[names(data) == "cb.result_val"] <- "raw_reason_for_visit"


  assert(nrow(data)==length(unique(data$id_visit)))
  after_join <- nrow(data)
  print(paste(before_join-after_join, "visits with no unique CSN in the complaint table."))
  
  
  # Grouping reason for visit
  all_complaints <- data$raw_reason_for_visit %>%
    str_split(",") %>%                  # Split by commas
    unlist() %>%                        # Flatten the list
    trimws() %>%                        # Trim white space
    str_to_lower() %>%                  # Convert to lowercase
    table() %>%                         # Count frequencies
    as.data.frame() %>%                 
    rename(ComplaintPhrase = '.', Freq = Freq) %>%
    arrange(desc(Freq))                 # Sort by frequency
  
  # Define pediatric complaints according to PERC clusters.
  perc_complaints <- list(
    "abdominal_pain" = c("abdominal pain", "other: flank pain",
                         "other: epigastric pain", "other: gi complaint",
                         "other: groin pain", "other: abdominal distention"),
    "assault" = c("other: assault"),
    "allergic_reaction" = c("allergic reaction"),
    "altered_mental_status" = c("aloc/behavior changes"),
    "asthma_or_wheezing" = c("other: wheezing"),
    "bites_or_stings" = c("bite", "other: dog bite", "other: bug bites",
                          "other: insect bite", "other: bug bite", 
                          "other: bee sting", "other: insect bites"),
    "burn" = c("burn"),
    "cardiac" = c("chest pain/arrhythmia", "other: tachycardia", "other: palpitations",
                  "other: brue", "other: bradycardia", "other: svt"),
    "chest_pain" = c("other: rib pain", "other: breast pain", "other: chest pain"),
    # "chronic_disease" = c(), # no HIV, 5 sickle, 3 cancer, 6 diabetes
    "congestion" = c("congestion", "other: runny nose"),
    "constipation" = c("constipation", "other: rectal pain", "no bowel movement",
                       "other: dysuria"),
    "cough" = c("cough"),
    # "croup" = c(), # only 9 visits
    "crying_or_colic" = c("crying excessively", "other: fussy", "other: fussiness",
                          "other: increased fussiness", "other: irritability"),
    "dental" = c("dental/mouth pain", "other: mouth sores", "other: jaw pain",
                 "other: mouth pain", "other: tooth pain", "other: mouth injury"),
    "device_complication" = c("g/j tube problem", "cvc problem", "other: ng tube out",
                              "other: ngt out", "other: vp shunt", "other: vps"),
    "diarrhea" = c("diarrhea"),
    "ear_complaint" = c("ear complaint"),
    "epistaxis" = c("other: nose bleed", "other: nosebleed", "other: epistaxis",
                    "other: nose bleeds", "other: nosebleeds", "other: bloody nose",
                    "other: epitaxis"),
    "extremity" = c("lower extremity pain/injury", "upper extremity pain/injury",
                    "other: joint pain", "other: finger injury", "other: ingrown toe nail",
                    "other: ingrown toenail", "other: hip pain", "other: shoulder pain",
                    "other: leg pain", "other: finger pain", "other: toe pain"),
    "eye_complaint" = c("eye complaint", "vision problem"),
    "syncope" = c("syncopal episode", "other: near syncope", "other: syncope"),
    "foreign_body" = c("foreign body in ear/nose", "foreign body ingestion"), 
    "fever" = c("fever", "fever >5 days", "fever-immunocompromised"), 
    "follow_up" = c("abnormal labs", "well child check", "abnormal imaging",
                    "scan", "cast check", "surgical site problem",
                    "other: suture removal",  "other: staple removal",
                    "needs blood product/sedation/imaging", "other: wound check",
                    "other: bili check", "other: stitch removal"),
    "general" = c("pain crisis", "other: body aches", "other: fatigue",
                  "other: weakness", "other: bodyaches", "other: pain",
                  "other: lethargy", "other: chills", "other: numbness", 
                  "other: lethargic", "fatigue", "other: hypothermia",
                  "other: pale", "weakness", "other: body ache", 
                  "other: body pain", "other: generalized weakness",
                  "bleeding"), 
    "gi_bleed" = c("other: blood in stool", "other: bloody stool",
                   "other: bloody stools", "other: hematuria", "other: black stool"),
    "gynecologic" = c("gu complaint", "other: mva", "other: vaginal bleeding",
                      "other: vaginal pain"),
    "head_or_neck" = c("closed head injury", "other: head injury", 
                       "other: facial swelling", "other: facial injury",
                       "other: nose pain", "other: nasal injury",
                       "other: nose complaint", "other: neck swelling"),
    "headache" = c("headache"),
    "laceration" = c("laceration", "other: gsw"),
    "lump_or_mass" = c("swelling/lesion"), 
    "male_genital" = c("testicular complaint", "other: penile pain",
                       "other: penile swelling", "other: penis pain"),
    "mvc" = c("other: mvc", "other: peds vs auto", "other: auto vs peds"),
    "neck_pain" = c("other: neck pain"),
    "neurologic" = c("other: dizziness", "gait disturbance", "other: dizzy",
                     "other: abnormal movements", "other: facial droop",
                     "dizziness", "other: twitching", "other: spasms",
                     "other: abnormal movement", "other: facial numbness",
                     "other: facial drooping", "other: tremors"),
    "poisoning" = c("substance ingestion", "other: ingestion"),
    "poor_feeding" = c("decreased po's", "other: weight loss", "other: ftt",
                       "weight loss", "other: poor weight gain", "other: decreased po",
                       "other: difficulty swallowing", "other: lip swelling"),
    #"pregnancy" = c(),
    "primary_care" = c("needs medication/supplies"),
    "psych" = c("si/hi/depression", "other: anxiety",
                "other: panic attack", "other: anxiety attack"),
    "rash" = c("rash", "other: diaper rash", "other: skin problem", 
               "other: hives", "other: eczema", "other: itching"),
    "other_respiratory" = c("breathing difficulty", "choking episode/color change",
                            "increase in trach. secretions", "other: hypoxia",
                            "other: sob"),
    "seizure" = c("seizure"),
    "sore_throat" = c("throat pain", "other: sore throat"),
    "trauma" = c("back/neck pain", "other: fall", "other: nose injury",
                 "other: bruising", "other: back pain", "other: straddle injury",
                 "other: trauma", "other: abrasion"),
    "urinary" = c("other: painful urination", "other: decreased uop"),
    "vomiting" = c("vomiting", "other: nausea", "nausea")
  )
  
  #The presence of any of these tags defines a complaint
  complaint_groups <- list()
  for (complaint in names(perc_complaints)) {
    complaint_name <- paste0("complaint_contains_", complaint)
    tags <- perc_complaints[[complaint]]
    column <- rep(0, nrow(data))
    for (tag in tags) {
      match <- grepl(paste0("\\b", tag, "\\b"), data$raw_reason_for_visit, ignore.case = TRUE)
      column <- ifelse(match + column > 0, 1, 0)
    }
    complaint_groups[[complaint_name]] <- column
  }

  assert(nrow(data)==length(unique(data$id_visit)))
  data <- cbind(data, as.data.frame(complaint_groups))

  assert(nrow(data)==length(unique(data$id_visit)))

  write.csv(data, "intermediate-files/visits-with-chief-complaint.csv")
  print("Saved chief complaint")
  
  # INSURANCE ------------------------------------------------------------------
  names(data)[names(data) == "pecarn_submit_visitinformation.primarypayer"] <- "raw_insurance"
  group_insurance <- function(raw_insurance) {
    case_when(
      raw_insurance %in% c("MEDICAID OUT OF STATE-NOT FOR PAC", "MEDICAID/WELFARE", 
                           "MEDICARE PART A", "MEDICARE PART B", "CHAMPUS") ~ "Public", 
      raw_insurance %in% c("BLUE CROSS", "COMMERCIAL", "HMO", "OTHER") ~ "Private",
      .default = "unknown"
    )
  }
  data <- data %>% mutate(insurance= group_insurance(raw_insurance))
  
  # ARRIVAL MODE ---------------------------------------------------------------
  names(data)[names(data) == "pecarn_submit_visitinformation.arrivalmode"] <- "raw_arrival_mode"
  group_arrival_mode <- function(raw_arrival_mode) {
    case_when(
      raw_arrival_mode %in% c("Self transport") ~ "self",
      str_detect(tolower(raw_arrival_mode), "bus|uber|taxi|walk") ~ "self",
      raw_arrival_mode %in% c("Ambulance", "Helicopter") ~ "EMS",
      str_detect(tolower(raw_arrival_mode), 
                 "air|transfer|transport|altamed|amb|amr|ems|escort|fire|police|blue|lafd|lapd") ~ "EMS",
      raw_arrival_mode %in% c("") ~ "unknown",
      raw_arrival_mode %in% c("Task Duplication") ~ "task duplication",
      .default = "other"
    )
  }
  data <- data %>% mutate(arrival_mode = group_arrival_mode(raw_arrival_mode))
  
  # PREFERRED LANGUAGE ---------------------------------------------------------
  names(data)[names(data) == "pecarn_submit_visitinformation.preferredlanguage"] <- "raw_preferred_language"
  group_preferred_language <- function(raw_preferred_language) {
    case_when(
      raw_preferred_language %in% c("English") ~ "English",
      raw_preferred_language %in% c("Spanish") ~ "Spanish", 
      raw_preferred_language %in% c("Mandarin") ~ "Mandarin", # 1159
      raw_preferred_language %in% c("Russian") ~ "Russian",   # 1247
      raw_preferred_language %in% c("Armenian (Eastern)") ~ "Armenian", # 2704
      .default = "other_unknown" # only 657 unknown
    )
  }
  data <- data %>% mutate(preferred_language = group_preferred_language(raw_preferred_language))

  write.csv(data, "intermediate-files/visits-with-language.csv")
  print("Saved language")

  data <- read.csv("intermediate-files/visits-with-language.csv")

  # CROWDEDNESS ----------------------------------------------------------------
  data <- get_crowdedness(data)
  
  write.csv(data, "intermediate-files/visits-with-crowdedness.csv")
  print("Saved crowdedness")

  # WEIGHT (normalized by age) -------------------------------------------------
  # Rename columns
  names(data_weight)[names(data_weight) == "pecarn_submit_weightkg.encntr_id"] <- "id_visit"
  names(data_weight)[names(data_weight) == "pecarn_submit_weightkg.weightkg"] <- "weightkg"
  names(data_weight)[names(data_weight) == "pecarn_submit_weightkg.date"] <- "date"
  names(data_weight)[names(data_weight) == "pecarn_submit_weightkg.time"] <- "time"
  data_weight <- data_weight %>% mutate(datetime = ymd_hms(paste(date, time)))
  # Normalize and group weights
  data <- get_weight_normalize(data, data_weight)
  assert(nrow(data)==length(unique(data$id_visit)))

  write.csv(data, "intermediate-files/visits-with-weight.csv")
  print("Saved weight")
  
  # LABS -----------------------------------------------------------------------
  # Filter labs during ED stay only
  data_lab_filtered <- data_lab %>%
    mutate(
      lab_order_datetime = paste(`pecarn_submit_lab.laborderdate`, 
                                 `pecarn_submit_lab.labordertime`),
      lab_order_datetime = ymd_hms(lab_order_datetime)
    ) %>%
    left_join(
      data %>% dplyr::select(id_visit, arrival_datetime, disposition_datetime), 
      by = c("pecarn_submit_lab.encntr_id" = "id_visit")
    ) %>%
    filter(
      lab_order_datetime >= arrival_datetime &
        lab_order_datetime <= disposition_datetime
    )
  # Count number of labs per visit
  lab_counts <- data_lab_filtered %>% count(`pecarn_submit_lab.encntr_id`, name = "num_labs")
  data <- data %>%
    left_join(
      lab_counts, by = c("id_visit" = "pecarn_submit_lab.encntr_id")
    ) %>% 
    mutate(num_labs = ifelse(is.na(num_labs), 0, num_labs))
  data <- data %>%
    mutate(any_labs = ifelse(num_labs > 0, 1, 0))

    assert(nrow(data)==length(unique(data$id_visit)))
    write.csv(data, "intermediate-files/visits-with-labs.csv")
    print("Saved labs")
  
  # MEDICATION -----------------------------------------------------------------
  # Filter medication during ED stay only
  data_med_filtered <- data_meds %>%
    mutate(
      med_order_datetime = ymd_hms(paste(`pecarn_submit_med_administration.medadministeredevent_date`,
                                 `pecarn_submit_med_administration.medadministeredevent_time`)),
    ) %>%
    left_join(
      data %>% dplyr::select(id_visit, arrival_datetime, disposition_datetime), 
      by = c("pecarn_submit_med_administration.encntr_id" = "id_visit")
    ) %>%
    filter(
      med_order_datetime >= arrival_datetime &
        med_order_datetime <= disposition_datetime
    )
  # Count all meds and IV meds
  med_counts <- data_med_filtered %>% 
    count(`pecarn_submit_med_administration.encntr_id`, name = "num_meds")
  IV_med_counts <- data_med_filtered %>%
    filter(str_detect(tolower(`pecarn_submit_med_administration.medroute`), "iv|intravenous")) %>%
    count(`pecarn_submit_med_administration.encntr_id`, name = "num_IV_meds")
  data <- data %>%
    left_join(
      med_counts, by = c("id_visit" = "pecarn_submit_med_administration.encntr_id")
    ) %>% 
    mutate(num_meds = ifelse(is.na(num_meds), 0, num_meds))
  data <- data %>%
    left_join(
      IV_med_counts, by = c("id_visit" = "pecarn_submit_med_administration.encntr_id")
    ) %>% 
    mutate(num_IV_meds = ifelse(is.na(num_IV_meds), 0, num_IV_meds))
  data <- data %>%
    mutate(
      any_meds = ifelse(num_meds > 0, 1, 0),
      any_IV_meds = ifelse(num_IV_meds > 0, 1, 0)
    )
    assert(nrow(data)==length(unique(data$id_visit)))
    write.csv(data, "intermediate-files/visits-with-meds.csv")
    print("Saved meds")
  
# #   IMAGING --------------------------------------------------------------------

#     data <- read.csv("intermediate-files/visits-with-meds.csv")

#   imaging_counts <- data_imaging %>% count(encntr_id, name = "num_imaging")
#   data <- data %>%
#   left_join(
#      imaging_counts, 
#      by = c("id_visit" = "encntr_id")
#    ) %>% 
#    mutate(
#      num_imaging = ifelse(is.na(num_imaging), 0, num_imaging),
#      any_imaging = ifelse(num_imaging > 0, 1, 0)
#    )

#    assert(nrow(data)==length(unique(data$id_visit)))
#     write.csv(data, "intermediate-files/visits-with-imaging.csv")
#     print("Saved imaging")
  
  # DIAGNOSES ------------------------------------------------------------------
  # Extract diagnoses from codes
  diagnoses_indicators <- get_icd_scores_diagnosis(data_diagnoses)
  data <- data %>%
    left_join(diagnoses_indicators, by = c("id_visit" = "encounter_id"))

   assert(nrow(data)==length(unique(data$id_visit)))
   write.csv(data, "intermediate-files/visits-with-diagnoses.csv")
   print("Saved diagnoses")
   data <- read.csv("intermediate-files/visits-with-diagnoses.csv")
  
  # VITAL SIGNS ----------------------------------------------------------------
  # Get triage vital signs time per visit
  triage_vitals_times <- get_vital_signs_triage_time(data_RR, data_HR, data_So2, data_temp, data_blood_pressure)
  data <- data %>%
    left_join(triage_vitals_times, by = c("id_visit" = "encounter_id"))

   assert(nrow(data)==length(unique(data$id_visit)))
   write.csv(data, "intermediate-files/visits-with-triage-vital-signs.csv")
   print("Saved triage-vital-signs")
  
  # Create table with Triage vital signs
  table_triage_vitals <- get_triage_vitals_table(data_RR, data_HR, data_So2, data_temp, data_blood_pressure, triage_vitals_times)
  
  # Create table with all vital signs
  table_all_vitals <- get_all_vitals_table(data_RR, data_HR, data_So2, data_temp, data_blood_pressure)
  
  # PAIN SCORES ----------------------------------------------------------------
  # Add pain scores to vitals tables
  pain_results <- add_pain_scores_to_vitals(data_painscore, table_triage_vitals, table_all_vitals)
  table_triage_vitals <- pain_results$triage_vitals_with_pain
  table_all_vitals <- pain_results$all_vitals_with_pain

  assert(nrow(data)==length(unique(data$id_visit)))
  write.csv(data, "intermediate-files/visits-with-pain.csv")
  print("Saved pain")
  
  # PRIOR VISITS ---------------------------------------------------------------
  data <- get_prior_visits(data)


  assert(nrow(data)==length(unique(data$id_visit)))
  write.csv(data, "intermediate-files/visits-with-prior-visits.csv")
  print("Saved prior visits")
  
  # Keep columns of interest only ----------------------------------------------

  data <- data[, c("id_visit", "id_patient", "disposition", "age", "age_group", 
                   "sex", "race_ethnicity", "zip", "state", "miles_travelled", 
                   "SDI_score", "triage_acuity", "insurance",
                   "disposition_datetime", "arrival_datetime", "triage_datetime", 
                   "minutes_since_first_arrival", "arrival_year", "arrival_season",
                   "arrival_day_txfype", "arrival_time_block",
                   "arrival_mode", "preferred_language", "weight", 
                   "num_labs", "any_labs", "num_meds", "any_meds", "num_IV_meds", 
                   "any_IV_meds", "triage_vitals_time", colnames(data)[startsWith(colnames(data), "complaint") | startsWith(colnames(data), "diagnosis")],
                   "crowdedness", "pseudo_nedocs", "num_previous_admissions", "num_previous_visits_without_admission",
                   "raw_complaint", "raw_reason_for_visit")]
  
  return(list(
    data = data,
    table_triage_vitals = table_triage_vitals,
    table_all_vitals = table_all_vitals
  ))
}
results <- get_demographics(data, data_age, data_visit, data_weight, data_disposition,
                            data_lab, data_meds, data_procedures, data_imaging,
                            data_diagnoses, data_painscore, data_RR, data_HR,
                            data_So2, data_temp, data_blood_pressure)

# Save tables
data <- results$data
table_triage_vitals <- results$table_triage_vitals
table_all_vitals <- results$table_all_vitals

# Join main data with triage vitals table
table_triage_vitals_clean <- table_triage_vitals %>% # extract first element of list
  mutate(
    triage_heart_rate = sapply(heart_rate, function(x) if(length(x) > 0) as.numeric(x[1]) else NA_real_),
    triage_respiratory_rate = sapply(respiratory_rate, function(x) if(length(x) > 0) as.numeric(x[1]) else NA_real_),
    triage_oxygen_saturation = sapply(oxygen_saturation, function(x) if(length(x) > 0) as.numeric(x[1]) else NA_real_),
    triage_temperature = sapply(temperature, function(x) if(length(x) > 0) as.numeric(x[1]) else NA_real_),
    triage_systolic_bp = sapply(blood_pressure_systolic, function(x) if(length(x) > 0) as.numeric(x[1]) else NA_real_),
    triage_diastolic_bp = sapply(blood_pressure_diastolic, function(x) if(length(x) > 0) as.numeric(x[1]) else NA_real_)
  ) 
table_triage_vitals_clean <- 
  table_triage_vitals_clean[, c("encounter_id", "triage_vitals_time", "triage_heart_rate",
                                "triage_respiratory_rate", "triage_oxygen_saturation", 
                                "triage_temperature", "triage_systolic_bp", "triage_diastolic_bp")]
data_with_triage_vitals <- data %>%
  left_join(table_triage_vitals_clean, by = c("id_visit" = "encounter_id"))


# Save all 4 tables as CSV files
write.csv(data_with_triage_vitals, file.path("preprocessed_data_with_triage_vitals.csv"), row.names = FALSE)
write.csv(data, file.path("preprocessed_data.csv"), row.names = FALSE)
write.csv(table_triage_vitals_clean, file.path("triage_vitals.csv"), row.names = FALSE)
write.csv(table_all_vitals, file.path("all_vitals.csv"), row.names = FALSE)


