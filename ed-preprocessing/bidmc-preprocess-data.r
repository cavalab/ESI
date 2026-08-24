library(lubridate)
library(ggsurvfit)
library(gtsummary)
library(tidycmprsk)
library(testit)
library(httpgd)
library(broom)
library(stringr)
library(patchwork)
library(forcats)
library(pROC)
library(ggsignif)
hgd()

library(knitr)
library(dplyr)
library(survival)
library(ggplot2)
library(tibble)
library(janitor)
library(MatchIt)
library(data.table)
library(exact2x2)
library(cobalt)
library(zipcodeR)
library(xgboost)
library(glmnet)
library(cowplot)
library(yardstick)
library(ggridges)
library(comorbidity)

# Preprocess the BIDMC data. Usage: Rscript bidmc-preprocess-data.r RAW_DATA_DIR OUTPUT_DIR
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) stop("Usage: Rscript bidmc-preprocess-data.r RAW_DATA_DIR OUTPUT_DIR")
setwd(normalizePath(args[[1]]))
dir.create("intermediate-files", recursive=TRUE, showWarnings=FALSE)
outputpath <- normalizePath(args[[2]], mustWork=FALSE)
dir.create(outputpath, recursive=TRUE, showWarnings=FALSE)

# pyxis <- read.csv("pyxis.csv") %>% group_by(name) %>%
#     summarise(count=n()) %>% arrange(desc(count))
# write.csv(pyxis, "common-drugs.csv")



#Load the database of ED stays.
visits <- read.csv("edstays.csv") %>% rename(csn=stay_id, mrn=subject_id, 
    arrival_time=intime, checkout_time=outtime, sex=gender, 
    ed_arrival_mode=arrival_transport) %>% select(csn, mrn, arrival_time,
    checkout_time, sex, race, ed_arrival_mode, disposition)

#Link age and year group from the patient database.
patients <- read.csv("patients.csv") %>% rename(mrn=subject_id) %>%
    select(mrn, anchor_year, anchor_age, anchor_year_group)

#To impute age, we assume that:
#All patients have a birth-time of midnight on 1 January in their anchor year.

print(paste("Before linking anchor timepoints, we have", length(unique(visits$csn)), 
    "visits from", length(unique(visits$mrn)), "unique patients."))

#Link visits to their anchor timepoints.
visits <- visits %>% inner_join(patients, by="mrn")

print(paste("After linking anchor timepoints, we have", length(unique(visits$csn)), 
    "visits from", length(unique(visits$mrn)), "unique patients."))

#Impute the patient's age at the time of the visit.
visits <- visits %>% 
    mutate(imputed_birth_time = paste0(anchor_year-anchor_age, "-01-01 00:00:00")) %>%
    mutate(age = floor(as.numeric(difftime(lubridate::ymd_hms(arrival_time), lubridate::ymd_hms(imputed_birth_time), units="weeks"))/52.1429))

print(paste("After imputing age, the youngest patient is", min(visits$age),
    "and the oldest is", max(visits$age)))

#AGE GROUP: move into groups. Case_when picks the first match for each element.
visits$age_group <- case_when(
    visits$age < 30 ~ "18-29",
    visits$age < 40 ~ "30-39",
    visits$age < 50 ~ "40-49",
    visits$age < 60 ~ "50-59",
    visits$age < 70 ~ "60-69",
    visits$age < 80 ~ "70-79",
    visits$age >= 80 ~ "80+",
    .default = NA
)

assert(!any(is.na(visits$age_group)))
assert(nrow(visits)==length(unique(visits$csn)))


#We also create new anchor year groups where years are shifted: i.e. if a patient has
#an anchor year of 2100, an anchor year group of 2008-2011, and a visit in 2101, then
#that visit is assigned a year group 2009-2012.

split_years <- str_split(visits$anchor_year_group, " - ")
visits$lower_anchor_year_limit <- as.numeric(purrr::map(split_years, ~ .x[1])) #Extracts the earliest year from the anchor year group, e.g. 2008.
visits$upper_anchor_year_limit <- as.numeric(purrr::map(split_years, ~ .x[2])) #Extracts the latest year from the anchor year group, e.g. 2011.

visits <- visits %>% mutate(year_of_visit=lubridate::year(arrival_time),
    earliest_year_of_visit= lower_anchor_year_limit + (year_of_visit-anchor_year),
    latest_year_of_visit= upper_anchor_year_limit + (year_of_visit-anchor_year),
    year_group=paste0(earliest_year_of_visit, "-", latest_year_of_visit))

# print(table(visits$year_group)) 
# Imputed year groups run continuously from 2008-2011 to 2020-2022.

# print(sum(is.na(visits$race))) #There are no NAs, so 'other' is a reasonable default.

#Group together race categories.
visits$race <- case_when(
    grepl("ASIAN", visits$race) ~ "Asian",
    grepl("BLACK", visits$race) ~  "Black",
    grepl("HISPANIC", visits$race) ~ "Hispanic", #There is no category which incorporates Black and Hispanic, or White and Hispanic.
    grepl("WHITE", visits$race) ~ "White",
    visits$race %in% c("UNKNOWN", "UNABLE TO OBTAIN", "PATIENT DECLINED TO ANSWER", "", " ") | is.na(visits$race) ~ "Unknown",
    .default = "Other"
)

#All patients have a sex of either M or F, and there are no NAs, so sex is fine without processing.

#Group together ED ARRIVAL MODES.
visits$ed_arrival_mode <- case_when(
    visits$ed_arrival_mode %in% c("AMBULANCE", "HELICOPTER") ~ "EMS",
    visits$ed_arrival_mode == "WALK IN" ~ "Walk-in",
    .default = "Other/Unknown" #no NA values, so this is fine.
)

#Filter out all whose disposition is not ADMITTED or HOME, i.e. those who eloped, died, LWBS, LAMA, or whose dispositions are 'transfer' or 'other'.
visits <- visits %>% filter(disposition %in% c("ADMITTED", "HOME")) %>% mutate(is_admitted=ifelse(disposition=="ADMITTED", 1, 0))

print(paste("After filtering out those not admitted or discharged, we have", length(unique(visits$csn)), 
    "visits from", length(unique(visits$mrn)), "unique patients."))

#Work out the length of each stay in minutes.
#Visits increase more or less continuously up to a week in duration (7.6 days), and then 2 visits
#which are longer than 14 days; I will filter those out, as they seem obvious outliers.

visits <- visits %>% 
    mutate(ed_los=as.numeric(difftime(lubridate::ymd_hms(checkout_time), lubridate::ymd_hms(arrival_time), units="mins"))) %>%
    filter(!is.na(ymd_hms(arrival_time)), !is.na(ymd_hms(checkout_time)), !is.na(ed_los), ed_los < 14*24*60)

print(paste("After filtering outliers in ED LOS (those longer than 2 weeks, following inspection, and those with no legible duration), we have", length(unique(visits$csn)), 
    "visits from", length(unique(visits$mrn)), "unique patients."))

#Assign each visit a timestamp: the difference in minutes between its arrival time and midnight on 1 Jan 2100; this will allow us to order visits relative to each other.
visits <- visits %>% 
    mutate(arbitrary_timestamp=as.numeric(difftime(lubridate::ymd_hms(arrival_time), lubridate::ymd_hms("2100-01-01 00:00:00"), units="mins")))


#Now we can work out whether patients have previous visits without admission, or any admissions, in the last thirty days.
visits <- visits %>%
    arrange(mrn, arbitrary_timestamp) %>% group_by(mrn) %>%
    mutate(
        num_previous_admissions = purrr::map_dbl(row_number(), function(i) {
            current_time <- arbitrary_timestamp[i]
            thirty_days_ago <- current_time - 24*60*30

            sum(arbitrary_timestamp < current_time &
                arbitrary_timestamp > thirty_days_ago &
                is_admitted==1)
        }
            ),
        num_previous_visits_without_admission = purrr::map_dbl(row_number(), function(i) {
            current_time <- arbitrary_timestamp[i]
            thirty_days_ago <- current_time - 24*60*30

            sum(arbitrary_timestamp < current_time &
                arbitrary_timestamp > thirty_days_ago &
                is_admitted==0
            )}),
    
    ) %>% ungroup() 


#Discard unnecessary columns.
visits <- visits %>% select(csn, mrn, arrival_time, sex, race, age_group, ed_arrival_mode,
    year_group, is_admitted, ed_los, num_previous_admissions, num_previous_visits_without_admission)

write.csv(visits, "intermediate-files/visits-after-edstays-and-patients.csv")
visits <- read.csv("intermediate-files/visits-after-edstays-and-patients.csv")

#Load the table containing triage vitals, chief complaint and acuity.
triage <- read.csv("triage.csv") %>% rename(csn=stay_id, Triage_Temp=temperature,
    Triage_HR=heartrate, Triage_RR=resprate, Triage_SpO2=o2sat, 
    Triage_SBP=sbp, Triage_DBP=dbp, Triage_Pain=pain, Triage_acuity=acuity) %>%
    mutate(CC=toupper(chiefcomplaint)) %>%
    select(-c(subject_id, chiefcomplaint))

visits <- visits %>% inner_join(triage, by="csn")

print(paste("After linking complaint and triage acuity, we have", length(unique(visits$csn)), 
    "visits from", length(unique(visits$mrn)), "unique patients."))

#Categorise chief complaint, using same categories as Stanford.

#First, look at the distribution of complaints, breaking complaints out by frequency
all_complaints <- as.data.frame(table(sub("^ ", "", unlist(str_split(visits$CC, ","))))) %>% #remove leading spaces
    rename(ComplaintPhrase=Var1) %>% arrange(desc(Freq))
write.csv(all_complaints, "complaint-phrases-by-freq.csv")


#Categorise them, using the Stanford database and adding common categories not present in Stanford data (at least not in the top ~200 complaints.)
complaint_dict <- list(
    "abdominal_pain" = c("ABDOMINAL PAIN", "ABD PAIN", "RUQ ABDOMINAL PAIN", "LLQ ABDOMINAL PAIN",
        "LUQ ABD PAIN", "UPPER ABDOMINAL PAIN"),
    "pelvic_pain" = c("PELVIC PAIN"),
    "chest_pain" = c("CHEST PAIN", "CHEST PRESSURE", "CHEST TIGHTNESS", "CP",
        "CHEST PAIN (CARDIAC FEATURES)"),
    "shortness_of_breath" = c("SHORTNESS OF BREATH", "BREATHING PROBLEM", 
        "RESPIRATORY DISTRESS", "HYPERVENTILATING", "WHEEZING", "DYSPNEA",
        "DYSPNEA ON EXERTION", "SOB", "ASTHMA EXACERBATION", "RESPIRATORY DISTRESS"),
    "headache" = c("HEADACHE", 'HA'),
    "fever" = c("FEVER", "CHILLS"),
    "fall" = c("S/P FALL", "FALL"),
    "ortho" = c("BACK PAIN", "LEG PAIN", "KNEE PAIN", "ARM PAIN", "FOOT PAIN",
            "SHOULDER PAIN", "HIP PAIN", "LEG SWELLING", "ANKLE PAIN",
            "TRAUMA", "HAND PAIN", "TOE PAIN", "ANKLE INJURY", "WRIST PAIN", "FINGER PAIN",
            "FOOT INJURY", "LEG INJURY", "LOW BACK PAIN", "ELBOW PAIN", "KNEE INJURY",
            "WRIST INJURY", "CALF PAIN", "HIP INJURY", "BACK INJURY", 'LOWER BACK PAIN', 
            "L LEG PAIN", "R LEG PAIN", "R KNEE PAIN", "L KNEE PAIN", "R FOOT PAIN",
            "R SHOULDER PAIN", "L ARM PAIN", "L FOOT PAIN", "L SHOULDER PAIN",
            "R HIP PAIN", "L HIP PAIN", "R ARM PAIN", "R ANKLE PAIN", "L ANKLE PAIN",
            "R ANKLE INJURY", "L LEG SWELLING", "R LEG SWELLING", "BODY ACHES", "L ANKLE INJURY",
            "R WRIST PAIN", "B LEG SWELLING", "R HAND INJURY", 'R HAND PAIN', 'L HAND PAIN', 
            "L WRIST PAIN", "L HAND INJURY", 'L CALF PAIN', "FOOT PAIN", "LOWER EXTREMITY PAIN",
            "L ELBOW PAIN", "L HAND PAIN", "R CALF PAIN", "R ELBOW PAIN", "B LEG PAIN", "L WRIST INJURY"),
    "dizziness" = c("DIZZINESS", "LIGHTHEADED", "DIZZY", "VERTIGO"),
    "weakness" = c("GENERAL WEAKNESS", "FATIGUE", "LETHARGY", "L WEAKNESS", 'R WEAKNESS', "LEG WEAKNESS"),
    "other_abdomen_complaint" = c("EMESIS", "NAUSEA", "DIARRHEA", "MELENA", "VOMITING",
        "RECTAL PAIN", "BLOOD IN VOMIT", "RECTAL BLEEDING", "BRBPR", "ANAL PAIN", "N/V", "N/V/D",
        "HEMATEMESIS", 'GI BLEED', "SBO", "EPIGASTRIC PAIN", 'R RIB PAIN', "L RIB PAIN", "VOMITING AND/OR NAUSEA"),
    "cough" = c("COUGH", "HEMOPTYSIS", "PRODUCTIVE COUGH"),
    "chest" = c("BREAST PAIN"),
    "flank_pain" = c("FLANK PAIN", "R FLANK PAIN", "L FLANK PAIN"),
    "neuro" = c("ACUTE NEUROLOGICAL PROBLEM", "ALTERED MENTAL STATUS", "NEUROLOGIC PROBLEM", "STROKE",
            "FACIAL DROOP", "APHASIA", "CONFUSION", "UNABLE TO AMBULATE", "SLURRED SPEECH", "UNSTEADY GAIT",
            "CVA", "TREMOR"),
    "psych" = c("PROBLEM PSYCH", "ANXIETY", "SUICIDAL", "PANIC ATTACK", "MENTAL HEALTH DISORDER",
        "HALLUCINATIONS", "DEPRESSION", "ANOREXIA", "SUICIDAL IDEATION", "SI", "PSYCH EVAL", "AGITATION", "PSYCH"),
    "seizure" = c("SEIZURE"),
    "crash" = c("MOTOR VEHICLE CRASH", "BICYCLE CRASH", "MOTORCYCLE CRASH", "AUTOMOBILE VERSUS PEDESTRIAN", "MVC", 
        "PED STRUCK", "S/P MVC", "BICYCLE ACCIDENT"),
    "vaginal" = c("VAGINAL BLEEDING", "FEMALE GENITAL PROBLEM", "VAGINAL PAIN", "VAGINAL DISCHARGE", 
        "VAGINAL PAIN"),
    "cardiac" = c("PALPITATIONS", "IRREGULAR HEART BEAT", "RAPID HEART RATE",
        "SLOW HEART RATE", "CARDIAC ARREST", "ABNORMAL EKG", "TACHYCARDIA", "BRADYCARDIA",
        "ATRIAL FIBRILLATION", "NSTEMI"),
    "syncope" = c("FAINTING", "NEAR SYNCOPE", "PRESYNCOPE"),
    "head_and_neck" = c("EYE PROBLEM", "SORE THROAT", "NECK PAIN", "EYE PAIN", "EAR PAIN", "HEAD INJURY",
        "THROAT PAIN", "EPISTAXIS", "DENTAL PAIN", "BLURRED VISION", "VISION CHANGE", "JAW PAIN", "FACIAL PAIN",
        "NASAL PAIN", "HEAD LACERATION", "EYE INJURY", "FACIAL SWELLING", "MIGRAINE", "PAIN TOOTH", "FACIAL INJURY",
        "HEARING LOSS", "LIP LACERATION", "VISUAL DISTURBANCE", "FOREIGN BODY IN EYE", "HEAD PAIN", "VISUAL PROBLEMS",
        "HEAD INJURY", "VISUAL CHANGES", "R EYE PAIN", "L EYE PAIN", "L EAR PAIN", "R EAR PAIN", "HEAD LAC",
        "THROAT FOREIGN BODY SENSATION", "VISION CHANGES"), 
    "hypertension" = c("HYPERTENSION"),
    "skin" = c("RASH", "WOUND CHECK", "ALLERGIC REACTION", "FINGER LAC", "WOUND INFECTION",
        "HAND INJURY", "SKIN ABSCESS", "FINGER INJURY", "SKIN PROBLEM", "HAND LACERATION", "DOG BITE",
        "LAC OTHER", "ABCESS", "INSECT BITE", "BURN", "JAUNDICE", "ARM LACERATION", "LEG LACERATION",
         "ANIMAL BITE (OTHER)", "ABRASION", "PUNCTURE WOUND", "STAB WOUND", "FOREIGN BODY", "FOREIGN BODY SWALLOWED",
         "CAT BITE", "ABSCESS", "WOUND EVAL", "LACERATION", "FINGER LACERATION"),
    "genitourinary" = c("URINARY COMPLAINT", "BLOOD IN URINE", "URINARY RETENTION", "URINARY FREQUENCY",
        "MALE GENITAL PROBLEM", "GROIN PAIN", "URINARY CATHETER PROBLEM", "URINARY PROBLEM", "SCROTAL PAIN", "INCONTINENCE",
        "URINARY TRACT INFECTION", "BLADDER INFECTION", "DYSURIA", 'HEMATURIA', "CONSTIPATION", "URINARY FREQUENCY",
        "TESTICULAR PAIN", "UTI"),
    "assault" = c("ASSAULT VICTIM", "ASSAULT"),
    "pregnancy" = c("PREGNANCY RELATED", "R/O ECTOPIC", "PREGNANT"),
    "shingles" = c("SHINGLES"),
    ##categories common in BIDMC but not Stanford-- major so do not fall into 'other'
    "transfer" = c("TRANSFER"),
    "substance_use" = c("ETOH", "OVERDOSE", "SUBSTANCE USE", "SUBSTANCE MISUSE/INTOXICATION", "DETOX"),
    "influenza" = c("ILI", "INFLUENZA LIKE ILLNESS"),
    "abnormal_test" = c("ABNORMAL LABS", "ABNORMAL CT", "HYPOXIA", "HYPOGLYCEMIA", "HYPERGLYCEMIA", 
        "ABNORMAL MRI", "HYPERKALEMIA", "ELEVATED TROPONIN", "ABNORMAL SODIUM LEVEL"),
    "suspected_appendicitis" = c("RLQ ABDOMINAL PAIN", 'LOWER ABDOMINAL PAIN', "RIGHT SIDED ABDOMINAL PAIN"),
    "hypotension" = c("HYPOTENSION"),
    "brain_bleed" = c("SDH", "ICH", "SAH"),
    "unresponsive" = c("UNRESPONSIVE", "FOUND DOWN")

)



#Because abbreviations are more common here, split string by commas and identify individual sub-complaints rather than testing for presence of string anywhere in complaint.
#Tag each visit (each visit can be described by more than 1 complaint variable)

#Pre-split the complaints for efficiency.
split_complaints <- lapply(visits$CC, function(x) trimws(strsplit(x, ",")[[1]]))

for (complaint in names(complaint_dict)) {
    complaint_name <- paste0("complaint_contains_", complaint)
    tags <- complaint_dict[[complaint]]
    #Check whether any of the tags appear in the split complaint.
    visits[[complaint_name]] <- purrr::map_vec(split_complaints, function(string) ifelse(any(tags %in% string), 1, 0), .progress=TRUE)
}


#Categorise triage vitals.

#Triage vitals: categorise respiratory rate according to NIH guidelines
visits$Triage_RR <- case_when(
    visits$Triage_RR < 12 ~ "low",
    visits$Triage_RR > 20 ~ "high",
    visits$Triage_RR >= 12 & visits$Triage_RR <= 20 ~ "normal",
    .default = NA
)

#Triage vitals: categorise heart rate according to Nursing Skills textbook
visits$Triage_HR <- case_when(
    visits$Triage_HR < 60 ~ "low",
    visits$Triage_HR >= 60 & visits$Triage_HR <= 100 ~ "normal",
    visits$Triage_HR > 100 & visits$Triage_HR <= 150 ~ "high",
    visits$Triage_HR > 150 ~ "very_high",
    .default = NA
)

#Categorise temperature as a fever above 100.4F or 38C
visits$Triage_Temp <- case_when(
    visits$Triage_Temp > 100.4 ~ "fever",
    visits$Triage_Temp <= 100.4 ~ "normal",
    .default = NA
)

#Categorise O2 saturation
visits$Triage_SpO2 <- case_when(
    visits$Triage_SpO2 < 85 ~ "very_low",
    visits$Triage_SpO2 >= 85 & visits$Triage_SpO2 <= 95 ~ "low",
    visits$Triage_SpO2 > 95 ~ "normal",
    .default = NA
)

#Categorise pain on the 0-11 NRS scale.
visits$Triage_Pain <- case_when(
    visits$Triage_Pain == 0 ~ "normal",
    visits$Triage_Pain < 4 ~ "mild",
    visits$Triage_Pain < 8 ~ "moderate",
    visits$Triage_SpO2 <=10 ~ "severe", 
    .default = NA
)

#Categorise triage blood pressure.
visits$Triage_BP <- case_when(
    (visits$Triage_SBP >= 180) | (visits$Triage_DBP > 120)  ~ "Hypertensive Crisis",
    (visits$Triage_SBP >= 140) | (visits$Triage_DBP > 90)  ~ "Stage 2 Hypertension",
    (visits$Triage_SBP >= 130 & visits$Triage_SBP < 140) | (visits$Triage_DBP >= 80 & visits$Triage_DBP < 90)  ~ "Stage 1 Hypertension",
    visits$Triage_SBP >= 120 & visits$Triage_SBP < 130 & visits$Triage_DBP < 80 ~ "Elevated",
    visits$Triage_SBP < 120 & visits$Triage_DBP < 80 ~ "Normal",
    .default = NA
)


#Save visits.
write.csv(visits, "intermediate-files/visits-after-triage-information.csv")
visits <- read.csv("intermediate-files/visits-after-triage-information.csv")

#Now link diagnoses as a result of the visit.
diagnoses <- read.csv("diagnosis.csv") %>% rename(mrn=subject_id, csn=stay_id)
print(head(diagnoses))

#Divide stays into those recorded with ICD-9 codes and those recorded with ICD-10 codes.
diagnoses_with_icd9 <- diagnoses %>% filter(icd_version==9)
diagnoses_with_icd10 <- diagnoses %>% filter(icd_version==10)

#Check there is no overlap
diagnoses_with_both_icd_codes <- diagnoses %>% 
    group_by(csn, icd_version) %>%
    summarise(count=1) %>%
    group_by(csn) %>%
    summarise(num_code_types=sum(count)) %>%
    filter(num_code_types > 1)

print(paste("Number of visits recorded with overlapping codes:", nrow(diagnoses_with_both_icd_codes))) #0

#Calculate comorbidity scores RESULTING FROM THE ED VISIT, from both sets of visits
comorb9 <- comorbidity(diagnoses_with_icd9, id="csn", code="icd_code", map="charlson_icd9_quan", assign0=TRUE)
comorb10 <- comorbidity(diagnoses_with_icd10, id="csn", code="icd_code", map="charlson_icd10_quan", assign0=TRUE)

cci_arising_from_visit <- rbind(
    data.frame(csn=comorb9$csn, diagnosis_severity=comorbidity::score(comorb9, w="quan", assign0=TRUE)),
    data.frame(csn=comorb10$csn, diagnosis_severity=comorbidity::score(comorb10, w="quan", assign0=TRUE)))

#Also attach the comorbidities arising from the visit as individual variables.
comorbs <- colnames(comorb9)
comorbs <- comorbs[!(comorbs=="csn")]

all_comorbidities <- rbind(comorb9, comorb10) %>%  
    rename_with(~paste0("current_diagnosis_", .x), .cols=all_of(comorbs))

print(paste("Before linking diagnoses from ED stay, we have", length(unique(visits$csn)), 
  "visits from", length(unique(visits$mrn)), "unique patients."))

#Link to visits
visits <- visits %>% inner_join(cci_arising_from_visit, by="csn") %>%
    inner_join(all_comorbidities, by="csn")

print(paste("After linking diagnoses from ED stay, we have", length(unique(visits$csn)), 
  "visits from", length(unique(visits$mrn)), "unique patients."))

#Save visits.
write.csv(visits, "intermediate-files/visits-after-diagnoses.csv")
visits <- as.data.frame(fread("intermediate-files/visits-after-diagnoses.csv"))

#Now load in the medication each patient was taking prior to their ED stay.
medrecon <- as.data.frame(fread("medrecon.csv")) %>% rename(mrn=subject_id, csn=stay_id)


#We can map drugs to predicted disease risk with the RxRisk tool. First, we have to map NDC codes to ATC-4 codes using the FDA's drug database:
drug_codes <- read.csv("drug-codes.csv") 

# # Convert NDC codes to standard 11-digit format. https://www.fda.gov/media/173715/download

convert_ndc_codes <- function(code) {
    split <- str_split(code, "-")[[1]]
    #print(split)
    result <- NA
    #Format 1: 5-4-1
    if (nchar(split[1])==5 & nchar(split[2])==4 & nchar(split[3])==1) {
        result <- paste0(split[1], split[2], "0", split[3])
    } else {
        #Format 2: 5-3-2
        if (nchar(split[1])==5 & nchar(split[2])==3 & nchar(split[3])==2) {
            result <- paste0(split[1], "0", split[2], split[3])
        }
     else { #Format 3: 4-4-2
        if (nchar(split[1])==4 & nchar(split[2])==4 & nchar(split[3])==2) {
            result <- paste0("0", split[1], split[2], split[3])
        }}}
    return(as.character(result))
}

drug_codes$NDC <- purrr::map_chr(drug_codes$NDC, convert_ndc_codes, .progress=TRUE)

drug_codes <- drug_codes %>% filter(!is.na(NDC)) %>% 
    rename(ndc=NDC) %>%
    mutate(atc_code=substr(ATC_class, start=1, stop=3)) #We are interested in the first two levels of classification, which is the therapeutic use

#Map second-level ATC codes to their descriptions
#using the table scraped from the WHO database
#(https://github.com/fabkury/atcd/blob/master/WHO%20ATC-DDD%202024-07-31.csv)

atc_codes <- read.csv("atc-codes.csv")
drug_codes <- drug_codes %>% 
    inner_join(atc_codes, by="atc_code") %>% #Link to therapeutic description
    select(ndc, atc_name)



#Link to medication table.
medrecon$ndc <- as.character(medrecon$ndc)
medrecon <- medrecon %>% inner_join(drug_codes, by="ndc", relationship="many-to-many") #As a single drug may have many ATC classifications
 
write.csv(medrecon, "intermediate-files/medrecon-with-atc.csv")

#Load in medications with their linked ATC descriptions. 
medrecon <- as.data.frame(fread("intermediate-files/medrecon-with-atc.csv"))

#How many distinct therapeutic categories do we have?
print(paste("We have", length(unique(medrecon$atc_name)), "unique ATC descriptions."))
#"We have 85 unique ATC descriptions."-- 85 different kinds of drugs is fine! 
#Let's transform these into variables as a proxy for medical history.

#Recode each medication as a binary variable.
medrecon <- medrecon %>% select(csn, atc_name) %>%
    group_by(csn, atc_name) %>% summarise(count=1) %>% 
    ungroup() %>% 
    tidyr::pivot_wider(names_from=atc_name,
         names_prefix="medrecon_", values_from=count, values_fill=0) %>%
    clean_names()


visits <- as.data.frame(fread("intermediate-files/visits-after-diagnoses.csv")) %>% 
    left_join(medrecon, by="csn")

#Set all medication columns with NA to 0-- the person was not taking it at admission.
medication_names <- colnames(medrecon)[startsWith(colnames(medrecon), "medrecon")]

for (col in medication_names) {
    visits[[col]] <- ifelse(is.na(visits[[col]]), 0, visits[[col]])
}

#Discard unnecessary columns
visits <- visits %>% select(-c(X.1, V1)) %>% clean_names()

#Save visits
write.csv(visits, file.path(outputpath, "BIDMC-visits.csv"))

 
#Link VITAL SIGNS
visits <- read.csv(file.path(outputpath, "BIDMC-visits.csv"))
vitals <- read.csv("vitalsign.csv") %>% rename(mrn=subject_id, csn=stay_id)

#For some reason the system struggles to read arrival times back out, so link to the original dataframe for these.
arrival_times <- read.csv("edstays.csv") %>% 
    rename(csn=stay_id) %>% mutate(arrival_time=ymd_hms(intime)) %>%
    select(csn, arrival_time)

#Link ED LOS from the preprocessed data, and make sure that we only have
#visits from the preprocessed dataframe.
ed_los <- visits %>% select(csn, ed_los) %>% inner_join(arrival_times, by="csn")

#Convert dates to appropriate format.
vitals$charttime <- lubridate::ymd_hms(vitals$charttime)

#Convert all non-numeric and blank readings to NA.
for (col in c("temperature", "heartrate", "resprate", "o2sat", "sbp", "dbp", "pain")) {
    vitals[[col]] <- as.numeric(vitals[[col]])
    vitals[[col]] <- ifelse(vitals[[col]]=="", NA, vitals[[col]])
}

#Filter out vitals outside timeframe of visit, and pivot table.
vitals <- vitals %>% inner_join(ed_los, by="csn") %>%
    mutate(timestamp = as.numeric(difftime(charttime, arrival_time, units="mins"))) %>%
    filter(!is.na(timestamp), timestamp >= 0, timestamp <= ed_los) %>% #Make sure vitals are taken during ED visit
    select(csn, timestamp, temperature, heartrate, resprate, o2sat, sbp, dbp, pain) %>%
    rename(temp=temperature, hr=heartrate, rr=resprate, spo2=o2sat) %>%
    tidyr::pivot_longer(!c(csn, timestamp), names_to="Measure", values_to="Value") %>%
    filter(!is.na(Value))

#Add triage vitals. (Rates of missing CSNs in the vitals table are higher than rates of missing CSNs in corresponding columns of the triage_vitals table, suggesting
#that triage vitals are not included in this table. The PhysioNet documentation is unclear on this point.)
triage_vitals <- read.csv("triage.csv") %>%
     rename(csn=stay_id) %>% clean_names() %>%
     select(csn, temperature, heartrate, resprate, o2sat, sbp, dbp, pain)

# The binarization step consumes the source triage table (including stay_id),
# so place that companion artifact beside the preprocessed visits table.
file.copy("triage.csv", file.path(outputpath, "BIDMC-triage.csv"), overwrite=TRUE)


#Convert all non-numeric and blank readings to NA.
for (col in c("temperature", "heartrate", "resprate", "o2sat", "sbp", "dbp", "pain")) {
    triage_vitals[[col]] <- as.numeric(triage_vitals[[col]])
    triage_vitals[[col]] <- ifelse(triage_vitals[[col]]=="", NA, triage_vitals[[col]])
}

triage_vitals <- triage_vitals %>%
     rename(temp=temperature, hr=heartrate, rr=resprate, spo2=o2sat) %>%
     mutate(timestamp=0) %>% #Assume all timestamps are taken at the point of arrival.
    tidyr::pivot_longer(!c(csn, timestamp), names_to="Measure", values_to="Value") %>%
    filter(!is.na(Value))

vitals <- rbind(vitals, triage_vitals)


write.csv(vitals, "intermediate-files/preprocessed-vitals.csv")
