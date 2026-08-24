
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

# Preprocess the Stanford data. Usage: Rscript stanford-preprocess-data.r RAW_DATA_DIR OUTPUT_DIR
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) stop("Usage: Rscript stanford-preprocess-data.r RAW_DATA_DIR OUTPUT_DIR")
setwd(normalizePath(args[[1]]))
dir.create("intermediate-files", recursive=TRUE, showWarnings=FALSE)
outputpath <- normalizePath(args[[2]], mustWork=FALSE)
dir.create(outputpath, recursive=TRUE, showWarnings=FALSE)



#Load raw file.
visits <- read.csv("visits.csv")

#First, check that no visits are registered twice
assert(nrow(visits)==length(unique(visits$CSN)))

#Count visits.
print(paste("Initially we have", length(unique(visits$CSN)), "visits from", length(unique(visits$MRN)), "unique patients."))


#Just filter out all patients under 18 and make sure ages are sensible (no one over 120 etc).
#The youngest is 18 and the oldest is 90. (Age values are randomly perturbed by up to 2 years.)

print(paste("The youngest patient is", min(visits$Age), "and the oldest is", max(visits$Age)))

#AGE GROUP: move into groups. Case_when picks the first match for each element.
visits$age_group <- case_when(
    visits$Age < 30 ~ "18-29",
    visits$Age < 40 ~ "30-39",
    visits$Age < 50 ~ "40-49",
    visits$Age < 60 ~ "50-59",
    visits$Age < 70 ~ "60-69",
    visits$Age < 80 ~ "70-79",
    visits$Age >= 80 ~ "80+",
    .default = NA
)

visits <- visits %>% select(-Age)

#GENDER: filter out 36 patients with unknown gender.
visits <- visits %>% filter(Gender=="M" | Gender=="F")

print(paste("After filtering for known gender, we have", length(unique(visits$CSN)), "visits from", length(unique(visits$MRN)), "unique patients."))


#RACE: group together blank, declines to state and unknown; group together Native and Other.

visits$Race <- case_when(
    (visits$Race == "") | (visits$Race == "Declines to State") ~ "Unknown",
    (visits$Race == "American Indian or Alaska Native") | (visits$Race == "Native Hawaiian or Other Pacific Islander") ~ "Other",
    visits$Race == "Black or African American" ~ "Black",
    .default = visits$Race
)

#ETHNICITY fields is just Hispanic, Non-Hispanic, Declines to State, Unknown, ""
# WGL: Any patient reporting Hispanic is labelled as such
# assume that any white/black person who does not mark their ethnicity as Hispanic is Non-Hispanic
# assume Asian is also non-Hispanic Asian

visits$Race <- case_when(
    visits$Ethnicity=="Hispanic/Latino" ~ "Hispanic",
    (!(visits$Ethnicity=="Hispanic/Latino")) & (visits$Race=="Black") ~ "Non-Hispanic Black",
    (!(visits$Ethnicity=="Hispanic/Latino")) & (visits$Race=="White") ~ "Non-Hispanic White",
    .default = visits$Race
)

#now drop Ethnicity
visits <- visits %>% select(-Ethnicity)



print(paste("After sorting race, we have", length(unique(visits$CSN)), "visits from", length(unique(visits$MRN)), "unique patients."))


#Leave means of arrival: EMS, Self, and ~100 people who are unknown

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
    visits$Triage_Temp > 38 ~ "fever",
    visits$Triage_Temp <= 38 ~ "normal",
    .default = NA
)

#Categorise O2 saturation
visits$Triage_SpO2 <- case_when(
    visits$Triage_SpO2 < 85 ~ "very_low",
    visits$Triage_SpO2 >= 85 & visits$Triage_SpO2 <= 95 ~ "low",
    visits$Triage_SpO2 > 95 ~ "normal",
    .default = NA
)


# print("Range of  temperatures") - Triage temp between 23.1C and 41.4C. 23.1C is very low but possible, due to hypothermia (Lino Moehrmann)
# print(table(visits$Triage_Temp))

# print("Range of O2")- 50-100, all plausible
# print(table(visits$Triage_SpO2))

#Categorise triage blood pressure (using the UptoDate definitions, as well as the definition of 'significantly elevated', which I am calling a hypertensive crisis here)
#First case-match wins.
visits$Triage_BP <- case_when(
    (visits$Triage_SBP >= 180) | (visits$Triage_DBP > 120)  ~ "Hypertensive Crisis",
    (visits$Triage_SBP >= 140) | (visits$Triage_DBP > 90)  ~ "Stage 2 Hypertension",
    (visits$Triage_SBP >= 130 & visits$Triage_SBP < 140) | (visits$Triage_DBP >= 80 & visits$Triage_DBP < 90)  ~ "Stage 1 Hypertension",
    visits$Triage_SBP >= 120 & visits$Triage_SBP < 130 & visits$Triage_DBP < 80 ~ "Elevated",
    visits$Triage_SBP < 120 & visits$Triage_DBP < 80 ~ "Normal",
    .default = NA
)

#Blood pressure readings not otherwise needed, so we discard
visits <- visits %>% select(-c(Triage_SBP, Triage_DBP))

print(paste("After sorting triage vitals, we have", length(unique(visits$CSN)), "visits from", length(unique(visits$MRN)), "unique patients."))



#condense triage acuity to numeric values
visits$Triage_acuity <- case_when(
    visits$Triage_acuity == "1-Resuscitation" ~ 1,
    visits$Triage_acuity == "2-Emergent" ~ 2,
    visits$Triage_acuity == "3-Urgent" ~ 3,
    visits$Triage_acuity == "4-Semi-Urgent" ~ 4,
    visits$Triage_acuity == "5-Non-Urgent" ~ 5,
    .default = NA
)
print(paste("After sorting triage acuity, we have", length(unique(visits$CSN)), "visits from", length(unique(visits$MRN)), "unique patients."))



#Create separate flags for admission, observation, and ICU admission-- only 4 outcomes (and Inpatient)
visits$is_admitted <- ifelse(visits$ED_dispo=="Discharge" | visits$ED_dispo=="Observation", 0, 1) #includes both ICU in inpatient
visits$is_admitted_to_ICU <- ifelse(visits$ED_dispo=="ICU", 1, 0)
visits$is_admitted_for_obs <- ifelse(visits$ED_dispo=="Observation", 1, 0)

#Disposition can be discarded after this
visits <- visits %>% select(-ED_dispo)

#check complaints are not a free-text field

all_complaints <- as.data.frame(table(unlist(str_split(visits$CC, ",")))) %>% 
    rename(ComplaintPhrase=Var1) %>% arrange(desc(Freq))
write.csv(all_complaints, "complaint-phrases-by-freq.csv")


#Create a complaint dictionary based on Arya 2013. All their major complaints are treated as own categories;
#all their minor complaints are grouped according to scheme provided.
#Sort the first 250 complaints (not counting the blank field, "") into categories roughly corresponding to 
#their 'intake' and 'do not intake' list. We do not create categories for the list they call 'other' 
#(as everything not flagged automatically becomes 'other') and we do not use the oncology/transplant categories 
#or differentiate on age-- everything that WOULD be a major complaint depending on age is treated as its own category here.

complaint_dict <- list(
    "abdominal_pain" = c("ABDOMINAL PAIN"),
    "pelvic_pain" = c("PELVIC PAIN"),
    "chest_pain" = c("CHEST PAIN", "CHEST PRESSURE", "CHEST TIGHTNESS"),
    "shortness_of_breath" = c("SHORTNESS OF BREATH", "BREATHING PROBLEM", 
        "RESPIRATORY DISTRESS", "HYPERVENTILATING", "WHEEZING"),
    "headache" = c("HEADACHE"),
    "fever" = c("FEVER"),
    "fall" = c("FALL"),
    "ortho" = c("BACK PAIN", "LEG PAIN", "KNEE PAIN", "ARM PAIN", "FOOT PAIN",
            "SHOULDER PAIN", "HIP PAIN", "LEG SWELLING", "ANKLE PAIN",
            "TRAUMA", "HAND PAIN", "TOE PAIN", "ANKLE INJURY", "WRIST PAIN", "FINGER PAIN",
            "FOOT INJURY", "LEG INJURY", "LOW BACK PAIN", "ELBOW PAIN", "KNEE INJURY",
            "WRIST INJURY", "CALF PAIN", "HIP INJURY", "BACK INJURY"),
    "dizziness" = c("DIZZINESS"),
    "weakness" = c("GENERAL WEAKNESS", "FATIGUE"),
    "other_abdomen_complaint" = c("EMESIS", "NAUSEA", "DIARRHEA", "MELENA", "VOMITING",
        "RECTAL PAIN", "BLOOD IN VOMIT", "RECTAL BLEEDING", "ANAL PAIN"),
    "cough" = c("COUGH"),
    "chest" = c("BREAST PAIN"),
    "flank_pain" = c("FLANK PAIN"),
    "neuro" = c("ACUTE NEUROLOGICAL PROBLEM", "ALTERED MENTAL STATUS", "NEUROLOGIC PROBLEM", "R/O STROKE",
            "FACIAL DROOP", "APHASIA"),
    "psych" = c("PROBLEM PSYCH", "ANXIETY", "SUICIDAL", "PANIC ATTACK", "MENTAL HEALTH DISORDER",
        "HALLUCINATIONS", "DEPRESSION", "ANOREXIA", "SUICIDAL IDEATION"),
    "seizure" = c("SEIZURE"),
    "crash" = c("MOTOR VEHICLE CRASH", "BICYCLE CRASH", "MOTORCYCLE CRASH", "AUTOMOBILE VERSUS PEDESTRIAN"),
    "vaginal" = c("VAGINAL BLEEDING", "FEMALE GENITAL PROBLEM", "VAGINAL PAIN", "VAGINAL DISCHARGE"),
    "cardiac" = c("PALPITATIONS", "IRREGULAR HEART BEAT", "RAPID HEART RATE",
        "SLOW HEART RATE", "CARDIAC ARREST", "ABNORMAL EKG"),
    "syncope" = c("FAINTING", "NEAR SYNCOPE"),
    "head_and_neck" = c("EYE PROBLEM", "SORE THROAT", "NECK PAIN", "EYE PAIN", "EAR PAIN", "HEAD INJURY",
        "THROAT PAIN", "EPISTAXIS", "DENTAL PAIN", "BLURRED VISION", "VISION CHANGE", "JAW PAIN", "FACIAL PAIN",
        "NASAL PAIN", "HEAD LACERATION", "EYE INJURY", "FACIAL SWELLING", "MIGRAINE", "PAIN TOOTH", "FACIAL INJURY",
        "HEARING LOSS", "LIP LACERATION", "VISUAL DISTURBANCE", "FOREIGN BODY IN EYE", "HEAD PAIN", "VISUAL PROBLEMS"), 
    "hypertension" = c("HYPERTENSION"),
    "skin" = c("RASH", "WOUND CHECK", "ALLERGIC REACTION", "FINGER LAC", "WOUND INFECTION",
        "HAND INJURY", "SKIN ABSCESS", "FINGER INJURY", "SKIN PROBLEM", "HAND LACERATION", "DOG BITE",
        "LAC OTHER", "ABCESS", "INSECT BITE", "BURN", "JAUNDICE", "ARM LACERATION", "LEG LACERATION",
         "ANIMAL BITE (OTHER)", "ABRASION", "PUNCTURE WOUND", "STAB WOUND", "FOREIGN BODY", "FOREIGN BODY SWALLOWED",
         "CAT BITE", "ABSCESS"),
    "genitourinary" = c("URINARY COMPLAINT", "BLOOD IN URINE", "URINARY RETENTION", "URINARY FREQUENCY",
        "MALE GENITAL PROBLEM", "GROIN PAIN", "URINARY CATHETER PROBLEM", "URINARY PROBLEM", "SCROTAL PAIN", "INCONTINENCE",
        "URINARY TRACT INFECTION", "BLADDER INFECTION"),
    "assault" = c("ASSAULT VICTIM"),
    "pregnancy" = c("PREGNANCY RELATED", "R/O ECTOPIC"),
    "shingles" = c("SHINGLES")

)

#Tag each visit (each visit can be described by more than 1 complaint variable)
for (complaint in names(complaint_dict)) {
    complaint_name <- paste0("complaint_contains_", complaint)
    tags <- complaint_dict[[complaint]]
    visits[[complaint_name]] <- 0
    for (tag in tags) {
        visits[[complaint_name]] <- ifelse(grepl(tag, visits$CC) | visits[[complaint_name]]==1, 1, 0)
    }
}


write.csv(visits, "intermediate-files/after-chief-complaints.csv")
visits <- read.csv("intermediate-files/after-chief-complaints.csv")

#Now deal with history of previous visits.
#Extract previous visits/admissions within 30 days; discard everything else.
#We may need to return to this in order to extract information about next visits/hospital stay--
#but can do that in a separate file, and then link.

#First, identify the time at which a patient first arrives at the ED.
#Shifting only happens within patients, so this should work.
first_arrival_timestamps <- visits %>% filter(Visit_no==1) %>% 
    select(MRN, Arrival_time) %>% rename(FirstArrivalTimestamp=Arrival_time)

#Create a timestamp for all patients: the time of their first arrival is 0, all other visits 
#are marked by the number of minutes of separating the relevant arrival from the first arrival.
visits <- visits %>% 
    inner_join(first_arrival_timestamps, by="MRN") %>%
    mutate(minutes_since_first_arrival=as.numeric(difftime(ymd_hms(Arrival_time), ymd_hms(FirstArrivalTimestamp), units="mins"))) %>%
    select(-FirstArrivalTimestamp) 


print(paste("After assigning first timestamps, we have", length(unique(visits$CSN)), "visits from", length(unique(visits$MRN)), "unique patients."))


# assert(min(visits$minutes_since_first_arrival)>=0) #Passes


#Now we can easily count how far each visit is from the next, and count previous admissions within 30 days,
#as well as visits without admission.
visits <- visits %>%
    arrange(MRN, minutes_since_first_arrival) %>% group_by(MRN) %>%
    mutate(
        num_previous_admissions = purrr::map_dbl(row_number(), function(i) {
            current_time <- minutes_since_first_arrival[i]
            thirty_days_ago <- current_time - 24*60*30

            sum(minutes_since_first_arrival < current_time &
                minutes_since_first_arrival > thirty_days_ago &
                is_admitted==1)
        }
            ),
        num_previous_visits_without_admission = purrr::map_dbl(row_number(), function(i) {
            current_time <- minutes_since_first_arrival[i]
            thirty_days_ago <- current_time - 24*60*30

            sum(minutes_since_first_arrival < current_time &
                minutes_since_first_arrival > thirty_days_ago &
                is_admitted==0
            )}),
    
    ) %>% ungroup() %>% #Now discard all temporal information (for now), except the arrival time, by which we mean all information relevant to the rest of the visit or to next/previous visits.
    select(-c(minutes_since_first_arrival, Hours_to_next_visit, 
        Dispo_class_next_visit, Admit_service, Hosp_LOS,
         DC_dispo))


write.csv(visits, "intermediate-files/after-visit-history.csv")
visits <- read.csv("intermediate-files/after-visit-history.csv")

#Get insurance status: there are 3 classes, Medicaid, Medicare and blank, which is assumed to be commercial (72k visits.)
visits$Payor_class <- ifelse(visits$Payor_class=="", "Other", visits$Payor_class)
visits <- visits %>% rename(Insurance=Payor_class)

#Now get Charlson comorbidity score, both BEFORE and AFTER a patient's visit

#Load in past medical history.
pmh <- read.csv("pmh.csv")

#First, calculate the past medical history before each visit. Each diagnosis has has a noted time
#So we attach the medical history known about each patient and filter out those known only after that arrival

pmh_before_visit <- visits %>% select(CSN, MRN, Arrival_time) %>%
    inner_join(pmh, by="MRN", relationship="many-to-many") %>% filter(as.numeric(difftime(ymd_hms(Noted_date), ymd_hms(Arrival_time), units="mins")) < 0) %>%
    filter(CodeType=="Dx10") %>% #You can't convert ICD-9 to ICD-10 codes, or combine them when making CCI scores, so we have to just take ICD-10 codes.
    select(CSN, MRN, Code)

#There are 2758 visits whose history are described by ICD-9 codes, 
#and 2581 also have corresponding ICD-10 codes.

#Now bind the ICD-10 codes corresponding to diagnoses attached to the visit.
diagnoses_of_visit <- visits %>% select(CSN, MRN, Dx_ICD10) %>% rename(Code=Dx_ICD10)

#Handle multiple diagnoses
separate_diagnoses <- function(i, diagnoses) {
    csn <- diagnoses$CSN[i]
    codes <- trimws(unlist(strsplit(diagnoses$Code[i], ",")))
    if (length(codes)>0) {
        return(data.frame(CSN=csn, Code=codes))
    } else {
        return(data.frame(CSN=csn, Code=NA))
    }
}

diagnoses_of_visit <- purrr::map_df(1:nrow(diagnoses_of_visit), ~separate_diagnoses(.x, diagnoses_of_visit), .progress=TRUE)


#Calculate scores for each visit, assigning a hierarchy so that only the most severe form of each comorb. is counted. Use Quan mapping.

comorb_before <- comorbidity(pmh_before_visit, id="CSN", code="Code", map="charlson_icd10_quan", assign0=TRUE)
comorb_of <- comorbidity(diagnoses_of_visit, id="CSN", code="Code", map="charlson_icd10_quan", assign0=TRUE)

#Transform these into matrices that we can link to the visit matrix itself, where each variable is a complaint.
comorbs <- colnames(comorb_before)
comorbs <- comorbs[!(comorbs=="CSN")]

pre_visit_diagnoses <- comorb_before %>%
    rename_with(~paste0("pre_diagnosis_", .x), .cols=all_of(comorbs))

current_visit_diagnoses <- comorb_of %>%
    rename_with(~paste0("current_diagnosis_", .x), .cols=all_of(comorbs))

cci_before_visit <- data.frame(CSN=comorb_before$CSN, cci_before_visit=comorbidity::score(comorb_before, w="quan", assign0=TRUE))
cci_of_visit <- data.frame(CSN=comorb_of$CSN, cci_of_visit=comorbidity::score(comorb_of, w="quan", assign0=TRUE))

#Now join to original dataframe.
visits <- visits %>% left_join(cci_before_visit, by="CSN") %>% 
        left_join(cci_of_visit, by="CSN") %>%
        left_join(pre_visit_diagnoses, by="CSN") %>%
        left_join(current_visit_diagnoses, by="CSN") %>%
        select(-c(Dx_ICD9, Dx_ICD10, Dx_name))

#Correct NAs to 0s (no NAS in scores after visit, and the absence of any diagnoses indicates the absence of comorbidities)
visits$cci_before_visit <- ifelse(is.na(visits$cci_before_visit), 0, visits$cci_before_visit)
visits$cci_of_visit <- ifelse(is.na(visits$cci_of_visit), 0, visits$cci_of_visit)

for (col in c(paste0("pre_diagnosis_", comorbs), paste0("current_diagnosis_", comorbs))) {
    visits[[col]] <- ifelse(is.na(visits[[col]]), 0, visits[[col]])
}

write.csv(visits, "intermediate-files/after-comorbidity-scores.csv")
visits <- read.csv("intermediate-files/after-comorbidity-scores.csv")


#Because only the seasonality of the patient's first visit is preserved, and 
#time shifts are measured in seconds, we don't have any temporal information 
#(hour, day, month, year aren't preserved).

#But we can extract time to rooming, decision, and thus the time between decision and checkout.
#Length of stay is already there for us, but it's measured in hours, so let's calculated in minutes.
#We have Arrival_time, Roomed_time, Admit_time, Dispo_time, Departure_time


# #What is the differences between Admit_time and Departure_time/Dispo_time?
# admitted_visits <- visits %>% filter(is_admitted==1)

# #print(table(difftime(admitted_visits$Admit_time, admitted_visits$Departure_time, units="mins"))) Produces a variety of differences
# #print(table(difftime(admitted_visits$Admit_time, admitted_visits$Dispo_time, units="mins"))) Produces all 0s

# discharged_visits <- visits %>% filter(is_admitted==0)
# print(table(discharged_visits$Admit_time))

#Admit time can be discarded; it is absent for non-admitted patients and Dispo_time for admitted patients.

visits$ed_los <- as.numeric(difftime(ymd_hms(visits$Departure_time), ymd_hms(visits$Arrival_time), units="mins"))
visits$time_to_rooming <- as.numeric(difftime(ymd_hms(visits$Roomed_time), ymd_hms(visits$Arrival_time), units="mins"))
visits$time_to_decision <- as.numeric(difftime(ymd_hms(visits$Dispo_time), ymd_hms(visits$Arrival_time), units="mins"))
visits$time_between_decision_and_departure <- visits$ed_los - visits$time_to_decision

#Check we have no repeating CSNs.
print(paste("Before filtering, we have", nrow(visits), "visits from", length(unique(visits$MRN)), "unique patients."))

visits <- visits %>% group_by(CSN) %>% mutate(num_visits_per_csn=n()) %>% ungroup() %>%
    filter(num_visits_per_csn==1) %>% select(-num_visits_per_csn)

print(paste("After filtering duplicate CSNs, we have", nrow(visits), "visits from", length(unique(visits$MRN)), "unique patients.")) #No duplicate CSNs.

#Exclude visits with nonsensical times. 
#(We do not filter out visits longer than 24 hours here, because they seem to be about 30% of the dataset-- we end up with 88k visits of 117k if we filter them.)

# adm_rate_after_24_hours <- visits %>% mutate(longer_than_24_hours=ifelse(ed_los > 24*60, 1, 0)) %>%
#     group_by(longer_than_24_hours) %>% summarise(count=n(), adm_rate=sum(is_admitted)/count)

# print(head(adm_rate_after_24_hours))

#Visit times seem fairly evenly distributed; there is 1 7-day visit, but there are also a few 5 and 6 day visits, so it's not clear there are any obvious outliers. 
#I just won't filter here.

#Exclude visits with nonsensical rooming times.
visits <- visits %>% filter(time_to_rooming >=0) #Filters out 14 visits.

print(paste("After filtering rooming times, we have", nrow(visits), "visits from", length(unique(visits$MRN)), "unique patients."))

#Exclude visits with nonsensical decision times.
visits <- visits %>% filter(time_to_decision >=0) #Filters out 518 visits.

print(paste("After filtering decision times, we have", nrow(visits), "visits from", length(unique(visits$MRN)), "unique patients.")) 


#Exclude visits with nonsensical gaps between decision and departure.
visits <- visits %>% filter(time_between_decision_and_departure >=0) #Filters out 574 visits.

print(paste("After filtering decision to departure times, we have", nrow(visits), "visits from", length(unique(visits$MRN)), "unique patients."))

#"After filtering decision to departure times, we have 114887 visits from 68955 unique patients."

#Save a table linking raw arrival/departure times to visits.
visits_to_arrival_times <- visits %>% select(CSN, Arrival_time, Departure_time)
write.csv(visits_to_arrival_times, "arrival-timestamps-per-visit.csv")

#Now finally filter out all the unnecessary columns.

visits <- visits %>% select(-c(X.1, X.2, Visit_no, Visits, MRN, ED_LOS, Admit_time, Arrival_time, Roomed_time, Dispo_time, Departure_time)) %>% clean_names()
write.csv(visits, "preprocessed-visits.csv")



#For Blanca (triage analysis): drop processed triage vitals and attach raw complaint.

raw_visits <- read.csv("visits.csv") %>% 
    select(CSN, Triage_SBP, Triage_DBP, Triage_HR, Triage_RR, Triage_Temp, Triage_SpO2, CC) %>%
    rename(raw_triage_sbp=Triage_SBP,
        raw_triage_dbp=Triage_DBP,
        raw_triage_hr=Triage_HR,
        raw_triage_rr=Triage_RR,
        raw_triage_temp=Triage_Temp,
        raw_triage_ox_sat=Triage_SpO2,
        raw_chief_complaint=CC) %>% clean_names()


# %>% select(-c(all_of(c(colnames(visits)[startsWith(colnames(visits), "complaint_contains_")])))) 
visits <- visits %>% inner_join(raw_visits, by="csn")

write.csv(visits, file.path(outputpath, "stanford.csv"))
