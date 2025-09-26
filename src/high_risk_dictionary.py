
from pathlib import Path
import pandas as pd
import re
from nltk.corpus import words
from rapidfuzz import process
import matplotlib.pyplot as plt

# download database
import nltk
nltk.download('words') 

# Global variables: Handbook Acuity Keywords
simple_keywords = [
    "chest pain", "chest pressure", "pressure in chest", "cardiac problem", "heart problem", "heart racing", "palpitations",
    "fatigue", "chest tightness", "syncope", "dizzy", "weak", "cardiac device problem", "heart failure",
    "tachypnea", "tachycardia", "tripoding", "audible stridor",
    "stroke", "aphasia", "apraxia", "agnosia", "dysarthria", "slurred speech", "paralysis",
    "severe headache", "thunderclap headache",  "severe headache",
    "altered mental status", "confused", "disorientation", "lethargy", "seizure", "post-seizure", "somnolence",
    "respiratory distress", "respiratory problem", "shortness of breath", "tripoding", "wheezing", "grunting", "congestion", "apneic",
    "belly breathing", "retractions", "hypoxia", "hypoglycemia", "hyponatremia", "underperfusion", "pneumonia", "hyperglycemia",
    "suicidal", "attempt", "intentional", "abuse",
    "psychotic", "psychosis", "psych", "acute grief", "neuro problem", "neurologic problem", "combativeness", "aggressive",
    "aggression", "agitated", "agitation", "emotional distress", "prenatal loss",
    "urosepsis", "appendicitis", "sepsis", "diverticulitis", "sickle cell",
    "ejection", "gunshot", "amputation",
    "overdose", "poisoning", "vision loss", "diplopia", "anisocoria", "exophthalmos", "assault",
    "severe stomach pain", "lower belly pain", "gtube", "tube",
    "testicular pain", "testicle pain","genitourinary problem", "uti", "urinary tract infection", "flank pain",
    "acute", "complication"]

pattern_simple = '|'.join(re.escape(kw) for kw in simple_keywords)

and_keywords = [
    "pregnant + vaginal bleeding", "pregnant + headache", "fever + chemo", "fever + transplant", "fever + immune",
    "headache + fever", "belly pain + vomiting", "fever + abdominal pain", "fever + seizure"]

# Define English dictionary
english_words = set(w.lower() for w in words.words())


def _is_english_word(word):
    return word.lower() in english_words


def load_data_filter_acuity_2_3(path_bin_data: Path, triage_col: str):

    # Load data
    data = pd.read_csv(path_bin_data)

    # Filter triage acuity 2 & 3 patients
    data_acuity = data[data[triage_col].isin([2, 3])]
    print(f"Acuity level 2 and 3: {len(data_acuity)}")

    return data_acuity, data


def _check_simple_keywords(text):
    if pd.isna(text):
        return False
    parts = re.split(r'[;,/]', str(text))
    return any(re.search(pattern_simple, p.strip(), flags=re.IGNORECASE) for p in parts)


def _check_and_keywords(text, terms):
    if pd.isna(text):
        return False
    parts = [p.strip().lower() for p in re.split(r'[;,/]', str(text))]
    return all(any(term.lower() in part for part in parts) for term in terms)


def _correct_words(text, vocab, correction_stats, threshold=85, max_letter_diff=1):
    items = str(text).split()
    corrected = []
    for word in items:
        word_lower = word.lower()

        # Skip correction if word is valid English
        if _is_english_word(word):
            corrected.append(word)
            continue

        # Fuzzy match
        match, score, _ = process.extractOne(word, vocab)
        length_diff = abs(len(match) - len(word))
        correction_stats.append({
            'original_word': word,
            'matched_word': match,
            'score': score,
            'length_difference': length_diff})

        # Skip hypo/hyper swaps
        match_lower = match.lower()
        if ((word_lower.startswith("hypo") and match_lower.startswith("hyper")) or
                (word_lower.startswith("hyper") and match_lower.startswith("hypo"))):
            corrected.append(word)
        elif score >= threshold and length_diff <= max_letter_diff:
            corrected.append(match)
        else:
            corrected.append(word)
    return " ".join(corrected)


def keyword_detection_and_misspelling_correction(data_acuity: pd.DataFrame, complaint_col: str):

    data_acuity = data_acuity.copy()
    data_acuity[complaint_col] = data_acuity[complaint_col].str.lower()  # convert to lower case

    # Apply keyword masks (check if complaints in keywords)
    mask_simple = data_acuity[complaint_col].apply(_check_simple_keywords)

    mask_and = pd.Series(False, index=data_acuity.index)
    for key in and_keywords:
        terms = [term.strip() for term in key.split('+')]
        mask = data_acuity[complaint_col].apply(lambda x: _check_and_keywords(x, terms))
        mask_and |= mask

    final_mask = mask_simple | mask_and

    # Spelling correction
    single_keywords = [kw for kw in simple_keywords if len(kw.split()) == 1]
    multi_keywords = [kw for kw in simple_keywords if len(kw.split()) > 1]

    vocab = set(single_keywords)
    correction_stats = []  # initialize result variable

    # Filter unmatched complaints only
    data_acuity.loc[:, 'corrected_complaint'] = data_acuity[complaint_col]
    unmatched_mask = ~final_mask
    unmatched_texts = data_acuity.loc[unmatched_mask, complaint_col].unique()

    # Apply correction
    corrected_lookup = {text: _correct_words(text, vocab, correction_stats) for text in unmatched_texts}
    data_acuity.loc[unmatched_mask, 'corrected_complaint'] = data_acuity.loc[
        unmatched_mask, complaint_col].map(corrected_lookup)

    # Check for keywords again after correction
    pattern_all = '|'.join(re.escape(kw) for kw in (multi_keywords + single_keywords))
    final_mask_corrected = data_acuity['corrected_complaint'].str.contains(pattern_all, na=False)
    data_acuity.loc[:, 'final_mask_corrected'] = final_mask_corrected

    return data_acuity, correction_stats


def view_statistics_high_risk_keywords(correction_stats):
    # Explore Correction Stats
    correction_stats_df = pd.DataFrame(correction_stats)

    # Print stats summary
    correction_stats_df.describe()

    # Plot: All letter differences
    plt.figure(figsize=(12, 5))
    plt.hist(
        correction_stats_df['length_difference'],
        bins=range(0, correction_stats_df['length_difference'].max() + 2),  # include all differences
        edgecolor='black',
        color='steelblue')
    plt.xticks(range(0, correction_stats_df['length_difference'].max() + 1))
    plt.title("Distribution of Letter Differences")
    plt.xlabel("Letter Difference")
    plt.ylabel("Count")
    plt.grid(axis="y", linestyle="--", alpha=0.7)
    plt.tight_layout()
    plt.show()

    # Filter: Only score >85
    high_score_df = correction_stats_df[correction_stats_df['score'] > 85]

    # Plot: Letter difference distribution with score >85
    plt.figure(figsize=(12, 5))
    plt.hist(
        high_score_df['length_difference'],
        bins=range(0, high_score_df['length_difference'].max() + 2),
        edgecolor='black',
        color='mediumseagreen')
    plt.xticks(range(0, high_score_df['length_difference'].max() + 1))
    plt.title("Distribution of Letter Differences (Score >85)")
    plt.xlabel("Letter Difference")
    plt.ylabel("Count")
    plt.grid(axis="y", linestyle="--", alpha=0.7)
    plt.tight_layout()
    plt.show()

    # Show correction examples
    max_diff = correction_stats_df['length_difference'].max()

    for diff in range(0, max_diff + 1):
        subset = correction_stats_df[
            (correction_stats_df['length_difference'] == diff) &
            (correction_stats_df['score'] > 85)]
        if not subset.empty:
            print(f"\nLetter Difference = {diff} ({len(subset)} corrections with score >85):")
            display_df = subset[['original_word', 'matched_word', 'score']].head(10)
            print(display_df.to_string(index=False))
