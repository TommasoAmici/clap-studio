#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "numpy",
#   "torch",
#   "transformers>=5",
#   "librosa>=0.10",
#   "soundfile",
# ]
# ///
"""Compare the CLAP model Clap Studio uses with the larger LAION-CLAP variants on a sample of your own library.

    mise exec uv@latest -- uv run --default-index https://pypi.org/simple \\
        tools/compare_clap_variants.py --limit 500

Models (Hugging Face, Apache-2.0, roughly 0.7 GB each on first use): laion/clap-htsat-unfused (the app today, the
baseline), laion/larger_clap_music_and_speech and laion/larger_clap_general. Change them with --model "Label=repo/name"
(repeatable; the first one is the baseline).

For a random sample of indexed files it writes build/clap-variants.html and opens it. Every file has a play button
that plays the original. The report has:

  * text searches: the ten best matches per model side by side; cells also found by the baseline are highlighted,
    unhighlighted ones are what a variant adds
  * find similar: the five nearest sounds to a few random files, per model
  * categories, decided exactly as the app does it (phrases read from Sources/ClapCore/Categories/Categorizer.swift,
    same sharpness and "clear winner" threshold): every sound a variant categorises differently from the baseline

Agreement numbers only say how different the models are, not which is better: judge the lists by ear. The library is
opened read-only and nothing in the app changes.
"""
from __future__ import annotations

import argparse
import random
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from clap_variants import DEFAULT_DB, DEFAULT_MODELS, embed_with_each, load_audio, pick_samples  # noqa: E402
from compare_report import render  # noqa: E402

SWIFT_SOURCE = Path(__file__).resolve().parent.parent / "Sources/ClapCore/Categories/Categorizer.swift"
TEMPERATURE = 100.0           # Categorizer.temperature
MINIMUM_CONFIDENCE = 0.25     # Categorizer.minimumConfidence
UNCATEGORISED = "Uncategorised"

DEFAULT_QUERIES = [
    "punchy kick drum", "tight closed hi-hat", "snare with a long reverb tail", "deep 808 sub bass",
    "warm analog pad", "vinyl crackle texture", "metallic clang", "short vocal chop", "rising riser sweep",
    "heavy rain", "footsteps on gravel", "glitchy percussion", "dark rumbling drone", "bright pluck",
]


# MARK: categories (the app's method)

def read_app_categories() -> list[tuple[str, list[str]]]:
    """The (name, phrases) pairs from the app's SoundCategories.all."""
    found = re.findall(r'\(\s*"([^"]+)"\s*,\s*\[((?:\s*"[^"]*"\s*,?)+)\s*\]\s*\)', SWIFT_SOURCE.read_text())
    categories = [(name, re.findall(r'"([^"]*)"', phrases)) for name, phrases in found]
    if not categories:
        raise SystemExit(f"Could not read the categories from {SWIFT_SOURCE}")
    return categories


def category_vectors(phrase_vectors: np.ndarray, categories: list[tuple[str, list[str]]]) -> np.ndarray:
    """One normalised vector per category: the mean of its phrases' vectors, like the app."""
    rows, start = [], 0
    for _, phrases in categories:
        mean = phrase_vectors[start:start + len(phrases)].mean(axis=0)
        rows.append(mean / max(np.linalg.norm(mean), 1e-9))
        start += len(phrases)
    return np.stack(rows)


def classify(similarities: np.ndarray, names: list[str]) -> list[dict]:
    """Per sound: category (None without a clear winner), its confidence, and the runner-up."""
    logits = similarities * TEMPERATURE
    exps = np.exp(logits - logits.max(axis=1, keepdims=True))
    probabilities = exps / exps.sum(axis=1, keepdims=True)
    results = []
    for row in probabilities:
        order = np.argsort(-row)
        best, second = int(order[0]), int(order[1])
        results.append({"category": names[best] if row[best] >= MINIMUM_CONFIDENCE else None,
                        "best": names[best], "confidence": float(row[best]),
                        "runner_up": names[second], "runner_up_confidence": float(row[second])})
    return results


# MARK: comparison

def top_k(scores: np.ndarray, k: int, exclude: int | None = None) -> list[int]:
    return [int(i) for i in np.argsort(-scores) if i != exclude][:k]


def overlap(a: list[int], b: list[int]) -> float:
    return len(set(a) & set(b)) / max(1, min(len(a), len(b)))


def ranked_rows(samples: list[dict], lists: list[list[int]], scores: list[np.ndarray]) -> list[list[tuple]]:
    """For each rank, one (sample, score, found by the baseline too) per model; the baseline column has no highlight."""
    baseline = set(lists[0])
    return [[(samples[found[rank]], float(score[found[rank]]), column > 0 and found[rank] in baseline)
             for column, (found, score) in enumerate(zip(lists, scores))] for rank in range(len(lists[0]))]


def parse_models(specs: list[str] | None) -> dict[str, str]:
    if not specs:
        return DEFAULT_MODELS
    models = {}
    for spec in specs:
        label, _, name = spec.partition("=")
        if not name:
            raise SystemExit(f'--model wants "Label=repo/name", got {spec!r}')
        models[label] = name
    if len(models) < 2:
        raise SystemExit("Give at least two --model values (the first is the baseline).")
    return models


def main() -> None:
    args = parse_args()
    models = parse_models(args.model)
    labels = list(models)
    categories = read_app_categories()
    names = [name for name, _ in categories]
    phrases = [phrase for _, group in categories for phrase in group]
    queries = ([line.strip() for line in Path(args.queries_file).read_text().splitlines() if line.strip()]
               if args.queries_file else DEFAULT_QUERIES)

    samples = pick_samples(args.db, args.limit, args.seed)
    if len(samples) < 20:
        raise SystemExit(f"Only {len(samples)} indexed files found in {args.db}; need at least 20.")
    print(f"Reading {len(samples)} files")
    audio, samples = load_audio(samples, args.seconds)
    print(f"{len(samples)} readable")

    results = embed_with_each(models, audio, queries + phrases)
    docs = {label: r["docs"] for label, r in results.items()}
    text = {label: r["text"][:len(queries)] for label, r in results.items()}
    phrase_vectors = {label: r["text"][len(queries):] for label, r in results.items()}

    query_overlaps = {label: [] for label in labels[1:]}
    query_sections = []
    for qi, query in enumerate(queries):
        scores = [docs[label] @ text[label][qi] for label in labels]
        found = [top_k(s, 10) for s in scores]
        for label, other in zip(labels[1:], found[1:]):
            query_overlaps[label].append(overlap(found[0], other))
        query_sections.append({"title": query, "shared": [len(set(found[0]) & set(other)) for other in found[1:]],
                               "rows": ranked_rows(samples, found, scores)})

    anchors = random.Random(args.seed).sample(range(len(samples)), min(args.anchors, len(samples)))
    sims = {label: docs[label] @ docs[label].T for label in labels}
    neighbour_overlaps = {label: [] for label in labels[1:]}
    similar_sections = []
    for anchor in anchors:
        scores = [sims[label][anchor] for label in labels]
        found = [top_k(s, 5, exclude=anchor) for s in scores]
        for label, other in zip(labels[1:], found[1:]):
            neighbour_overlaps[label].append(overlap(found[0], other))
        similar_sections.append({"anchor": samples[anchor], "rows": ranked_rows(samples, found, scores)})

    verdicts = {label: classify(docs[label] @ category_vectors(phrase_vectors[label], categories).T, names)
                for label in labels}
    name_of = lambda verdict: verdict["category"] or UNCATEGORISED  # noqa: E731
    distribution = [(name, *[sum(name_of(v) == name for v in verdicts[label]) for label in labels])
                    for name in [*names, UNCATEGORISED]]
    category_sections, same_category = [], {}
    for label in labels[1:]:
        groups = defaultdict(list)
        for sample, base, other in zip(samples, verdicts[labels[0]], verdicts[label]):
            if name_of(base) != name_of(other):
                groups[(name_of(base), name_of(other))].append((sample, base, other))
        same_category[label] = 1 - sum(len(g) for g in groups.values()) / len(samples)
        ordered = sorted(groups.items(), key=lambda item: (-len(item[1]), item[0]))
        category_sections.append({"label": label, "groups": [
            {"current": a, "other": b, "items": items} for (a, b), items in ordered]})

    agreement = []
    for label in labels[1:]:
        agreement.append(f"{label}: {np.mean(query_overlaps[label]) * 10:.1f} of the top 10 text results and "
                         f"{np.mean(neighbour_overlaps[label]) * 5:.1f} of the top 5 similar sounds are shared with "
                         f"{labels[0]}; {same_category[label]:.0%} of sounds get the same category.")
    html = render(
        intro=f"{len(samples)} random indexed files, each cut at {args.seconds:g} s.",
        facts=[*[("Warning", f"{label}: embeddings look collapsed (every sound nearly identical), results are meaningless")
                 for label in labels if results[label]["collapsed"]],
               ("Models", ", ".join(f"{label} = {name}" for label, name in models.items())),
               ("Embedding speed", ", ".join(f"{label} {len(samples) / results[label]['seconds']:.1f} files/s"
                                             for label in labels))],
        agreement=agreement, labels=labels, queries=query_sections, similar=similar_sections,
        distribution=distribution, categories=category_sections)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html)
    print(f"Wrote {out}")
    if not args.no_open:
        subprocess.run(["open", str(out)], check=False)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--db", default=DEFAULT_DB, help="Clap Studio library database (opened read-only)")
    p.add_argument("--limit", type=int, default=500, help="how many random files to embed")
    p.add_argument("--seconds", type=float, default=10.0, help="use at most this much of each file (CLAP reads 10 s)")
    p.add_argument("--anchors", type=int, default=15, help="how many find-similar examples to list")
    p.add_argument("--queries-file", help="text file with one search per line (default: a built-in list)")
    p.add_argument("--model", action="append", help='"Label=huggingface/name", repeatable; the first is the baseline')
    p.add_argument("--seed", type=int, default=1, help="makes the random sample repeatable")
    p.add_argument("--out", default="build/clap-variants.html")
    p.add_argument("--no-open", action="store_true", help="do not open the report in the browser when done")
    return p.parse_args()


if __name__ == "__main__":
    main()
