#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "numpy",
#   "torch",
#   "transformers>=5",
#   "sentence-transformers>=5",
#   "librosa>=0.10",
#   "soundfile",
#   "pillow",
#   "torchvision",
# ]
# ///
"""Compare how CLAP and EmbeddingGemma 2 categorise your samples, and list every sample they disagree on.

    mise exec uv@latest -- uv run --default-index https://pypi.org/simple \\
        tools/compare_categories.py --limit 500

It does what the app does (Sources/ClapCore/Categories/Categorizer.swift): each category is described by a few
phrases, a sound gets the category whose phrases are closest, and sounds without a clear winner stay uncategorised.
The phrases are read from that Swift file, so the script never drifts from the app. Both models use the same
phrases. The library is opened read-only; nothing in the app changes.

The report (build/category-comparison.html, opened when done) lists every sample that EmbeddingGemma 2 categorises
differently from CLAP, grouped by the change (for example "CLAP: Snare, EmbeddingGemma 2: Clap"), each with a play
button. CLAP's way of judging "clear winner" does not transfer to another model as is, so EmbeddingGemma 2's
sharpness is calibrated to leave the same share of sounds uncategorised as CLAP does (override: --gemma-temperature),
and its scores are centred per category on the sample (--no-centering turns that off) because EmbeddingGemma 2's
text-to-audio scores carry a large per-category offset.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from compare_report import render_categories  # noqa: E402
from embedders import DEFAULT_DB, embed_with_both, load_audio, pick_samples  # noqa: E402

SWIFT_SOURCE = Path(__file__).resolve().parent.parent / "Sources/ClapCore/Categories/Categorizer.swift"
APP_TEMPERATURE = 100.0       # Categorizer.temperature
MINIMUM_CONFIDENCE = 0.25     # Categorizer.minimumConfidence
UNCATEGORISED = "Uncategorised"


def read_app_categories() -> list[tuple[str, list[str]]]:
    """The (name, phrases) pairs from the app's SoundCategories.all."""
    source = SWIFT_SOURCE.read_text()
    found = re.findall(r'\(\s*"([^"]+)"\s*,\s*\[((?:\s*"[^"]*"\s*,?)+)\s*\]\s*\)', source)
    categories = [(name, re.findall(r'"([^"]*)"', phrases)) for name, phrases in found]
    if not categories:
        raise SystemExit(f"Could not read the categories from {SWIFT_SOURCE}")
    return categories


def category_vectors(phrase_vectors: np.ndarray, categories: list[tuple[str, list[str]]]) -> np.ndarray:
    """One normalised vector per category: the mean of its phrases' (normalised) vectors, like the app."""
    rows, start = [], 0
    for _, phrases in categories:
        mean = phrase_vectors[start:start + len(phrases)].mean(axis=0)
        rows.append(mean / max(np.linalg.norm(mean), 1e-9))
        start += len(phrases)
    return np.stack(rows)


def softmax_confidence(similarities: np.ndarray, temperature: float) -> np.ndarray:
    logits = similarities * temperature
    exps = np.exp(logits - logits.max(axis=1, keepdims=True))
    return exps / exps.sum(axis=1, keepdims=True)


def unsure_share(similarities: np.ndarray, temperature: float) -> float:
    return float((softmax_confidence(similarities, temperature).max(axis=1) < MINIMUM_CONFIDENCE).mean())


def calibrate(similarities: np.ndarray, target_share: float) -> float:
    """The softmax temperature at which the share of unsure sounds matches `target_share` (bisection)."""
    low, high = 1.0, 2000.0     # a sharper softmax means fewer unsure sounds
    for _ in range(40):
        middle = (low * high) ** 0.5
        if unsure_share(similarities, middle) > target_share:
            low = middle
        else:
            high = middle
    return high


def classify(similarities: np.ndarray, names: list[str], temperature: float) -> list[dict]:
    """Per sound: category (None if unsure), confidence of the best, and the runner-up."""
    probabilities = softmax_confidence(similarities, temperature)
    results = []
    for row in probabilities:
        order = np.argsort(-row)
        best, second = int(order[0]), int(order[1])
        results.append({"category": names[best] if row[best] >= MINIMUM_CONFIDENCE else None,
                        "best": names[best], "confidence": float(row[best]),
                        "runner_up": names[second], "runner_up_confidence": float(row[second])})
    return results


def main() -> None:
    args = parse_args()
    categories = read_app_categories()
    names = [name for name, _ in categories]
    phrases = [phrase for _, group in categories for phrase in group]

    samples = pick_samples(args.db, args.limit, args.seed, args.seconds)
    if len(samples) < 20:
        raise SystemExit(f"Only {len(samples)} indexed files found in {args.db}; need at least 20.")
    print(f"Reading {len(samples)} files ({len(names)} categories, {len(phrases)} phrases)")
    a48, a16, samples = load_audio(samples, args.seconds)
    print(f"{len(samples)} readable")

    results = embed_with_both(a48, a16, phrases)
    sims = {model: r["docs"] @ category_vectors(r["text"], categories).T for model, r in results.items()}

    gemma_sims = sims["EmbeddingGemma 2"]
    if not args.no_centering:
        # Its text-to-audio cosines carry a large offset per category (about 0.75 for "FX", 0.66 for "Hi-hat" for
        # every sound), so without this nearly everything lands in one category. CLAP does not need it.
        gemma_sims = gemma_sims - gemma_sims.mean(axis=0)
    clap = classify(sims["CLAP"], names, APP_TEMPERATURE)
    target = unsure_share(sims["CLAP"], APP_TEMPERATURE)
    temperature = args.gemma_temperature or calibrate(gemma_sims, target)
    gemma = classify(gemma_sims, names, temperature)
    print(f"EmbeddingGemma 2 sharpness {temperature:.0f} (CLAP: {APP_TEMPERATURE:.0f}), "
          f"uncategorised: CLAP {target:.0%}, EmbeddingGemma 2 {np.mean([g['category'] is None for g in gemma]):.0%}")

    different = [(sample, c, g) for sample, c, g in zip(samples, clap, gemma) if c["category"] != g["category"]]
    groups: dict[tuple[str, str], list] = defaultdict(list)
    for sample, c, g in different:
        groups[(c["category"] or UNCATEGORISED, g["category"] or UNCATEGORISED)].append((sample, c, g))
    ordered = sorted(groups.items(), key=lambda item: (-len(item[1]), item[0]))

    clap_counts = Counter(c["category"] or UNCATEGORISED for c in clap)
    gemma_counts = Counter(g["category"] or UNCATEGORISED for g in gemma)
    html = render_categories(
        intro=f"{len(samples)} random indexed files, each cut at {args.seconds:g} s, categorised with the app's "
              f"{len(names)} categories and phrases.",
        agreement=[
            f"Same category: {len(samples) - len(different)} of {len(samples)} "
            f"({1 - len(different) / len(samples):.0%}). Different: {len(different)}.",
            f"Left uncategorised: CLAP {clap_counts[UNCATEGORISED]}, EmbeddingGemma 2 {gemma_counts[UNCATEGORISED]}.",
            f"EmbeddingGemma 2's sharpness was set to {temperature:.0f} to match CLAP's share of uncategorised sounds "
            f"(CLAP uses the app's {APP_TEMPERATURE:.0f}).",
            ("EmbeddingGemma 2's scores for each category were centred on this sample (its scores have a large "
             "per-category offset that otherwise puts almost every sound in one category)."
             if not args.no_centering else "EmbeddingGemma 2's scores were used as they are (no centring)."),
        ],
        distribution=[(name, clap_counts[name], gemma_counts[name]) for name in [*names, UNCATEGORISED]],
        changes=[(c, g, len(items)) for (c, g), items in ordered],
        groups=[{"clap": c, "gemma": g, "items": items} for (c, g), items in ordered])

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html)
    print(f"Wrote {out}")
    if not args.no_open:
        subprocess.run(["open", str(out)], check=False)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--db", default=DEFAULT_DB, help="Clap Studio library database (opened read-only)")
    p.add_argument("--limit", type=int, default=500, help="how many random files to categorise")
    p.add_argument("--seconds", type=float, default=10.0, help="use at most this much of each file (CLAP reads 10 s)")
    p.add_argument("--seed", type=int, default=1, help="makes the random sample repeatable")
    p.add_argument("--gemma-temperature", type=float, help="softmax sharpness for EmbeddingGemma 2 (default: calibrated)")
    p.add_argument("--no-centering", action="store_true",
                   help="use EmbeddingGemma 2's raw scores instead of centring each category on the sample")
    p.add_argument("--out", default="build/category-comparison.html")
    p.add_argument("--no-open", action="store_true", help="do not open the report in the browser when done")
    return p.parse_args()


if __name__ == "__main__":
    main()
