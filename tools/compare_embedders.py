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
"""Compare LAION-CLAP (what Clap Studio uses) with EmbeddingGemma 2 on a sample of your own library.

    mise exec uv@latest -- uv run --default-index https://pypi.org/simple \\
        tools/compare_embedders.py --limit 300

Nothing in the app or its database is changed (the library is opened read-only). For a random sample of the
indexed files it embeds the audio with both models, then writes an HTML report to build/embedder-comparison.html and opens it. Every file in the
lists has a play button that plays the original file:

  * text searches ("punchy kick drum", ...): the ten best matches from each model, side by side
  * find-similar: the five nearest neighbours of some random files, from each model
  * how much the two models agree (overlap of their top results), speed, and vector sizes
  * how much EmbeddingGemma 2 loses when its vectors are cut from 768 to 256 numbers

The numbers only say how much the models agree. Which one is better is for your ears: open the report and judge
the lists. Weights: laion/clap-htsat-unfused (Apache-2.0) and google/embeddinggemma-2 (Apache-2.0), downloaded
from Hugging Face on first use (roughly 2 GB).
"""
from __future__ import annotations

import argparse
import random
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from compare_report import render  # noqa: E402
from embedders import DEFAULT_DB, embed_with_both, load_audio, pick_samples, truncate  # noqa: E402

DEFAULT_QUERIES = [
    "punchy kick drum", "tight closed hi-hat", "snare with a long reverb tail", "deep 808 sub bass",
    "warm analog pad", "vinyl crackle texture", "metallic clang", "short vocal chop", "rising riser sweep",
    "heavy rain", "footsteps on gravel", "glitchy percussion", "dark rumbling drone", "bright pluck",
]


# MARK: comparison

def top_k(scores: np.ndarray, k: int, exclude: int | None = None) -> list[int]:
    order = np.argsort(-scores)
    return [int(i) for i in order if i != exclude][:k]


def overlap(a: list[int], b: list[int]) -> float:
    return len(set(a) & set(b)) / max(1, min(len(a), len(b)))


def main() -> None:
    args = parse_args()
    samples = pick_samples(args.db, args.limit, args.seed, args.seconds)
    if len(samples) < 20:
        raise SystemExit(f"Only {len(samples)} indexed files found in {args.db}; need at least 20.")
    queries = ([line.strip() for line in Path(args.queries_file).read_text().splitlines() if line.strip()]
               if args.queries_file else DEFAULT_QUERIES)

    print(f"Reading {len(samples)} files")
    a48, a16, samples = load_audio(samples, args.seconds)
    print(f"{len(samples)} readable")

    results = embed_with_both(a48, a16, queries)

    clap, gemma = results["CLAP"], results["EmbeddingGemma 2"]
    rng = random.Random(args.seed)
    anchors = rng.sample(range(len(samples)), min(args.anchors, len(samples)))

    facts = [("Numbers per sound", f"CLAP {clap['docs'].shape[1]}, EmbeddingGemma 2 {gemma['docs'].shape[1]} "
                                   f"(768, 512, 256 or 128)"),
             ("Embedding speed", f"CLAP {len(samples) / clap['seconds']:.1f} files/s, "
                                 f"EmbeddingGemma 2 {len(samples) / gemma['seconds']:.1f} files/s")]

    def rows_for(a: list[int], b: list[int], scores_a: np.ndarray, scores_b: np.ndarray) -> list:
        shared = set(a) & set(b)
        return [((samples[i], float(scores_a[i]), i in shared), (samples[j], float(scores_b[j]), j in shared))
                for i, j in zip(a, b)]

    query_overlaps, query_sections = [], []
    for qi, query in enumerate(queries):
        scores_a, scores_b = clap["docs"] @ clap["text"][qi], gemma["docs"] @ gemma["text"][qi]
        a, b = top_k(scores_a, 10), top_k(scores_b, 10)
        query_overlaps.append(overlap(a, b))
        query_sections.append({"title": query, "shared": len(set(a) & set(b)), "total": 10,
                               "rows": rows_for(a, b, scores_a, scores_b)})

    neighbour_overlaps, truncated_overlaps, similar_sections = [], [], []
    sims_clap = clap["docs"] @ clap["docs"].T
    sims_gemma = gemma["docs"] @ gemma["docs"].T
    small = truncate(gemma["docs"], 256)
    sims_small = small @ small.T
    for anchor in anchors:
        a = top_k(sims_clap[anchor], 5, exclude=anchor)
        b = top_k(sims_gemma[anchor], 5, exclude=anchor)
        neighbour_overlaps.append(overlap(a, b))
        truncated_overlaps.append(overlap(top_k(sims_gemma[anchor], 10, exclude=anchor),
                                          top_k(sims_small[anchor], 10, exclude=anchor)))
        similar_sections.append({"anchor": samples[anchor], "rows": rows_for(a, b, sims_clap[anchor], sims_gemma[anchor])})

    html = render(
        intro=f"{len(samples)} random indexed files, each cut at {args.seconds:g} s. Both models ran on this machine "
              f"({'GPU' if _has_gpu() else 'CPU'}).",
        facts=facts,
        agreement=[
            f"Text searches: on average {np.mean(query_overlaps) * 10:.1f} of the top 10 are shared.",
            f"Find similar: on average {np.mean(neighbour_overlaps) * 5:.1f} of the top 5 are shared.",
            f"EmbeddingGemma 2 cut to 256 numbers keeps {np.mean(truncated_overlaps) * 10:.1f} of its own top 10 "
            f"neighbours (the model card says quality is close to lossless down to 256).",
        ],
        queries=query_sections, similar=similar_sections)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html)
    print(f"Wrote {out}")
    if not args.no_open:
        subprocess.run(["open", str(out)], check=False)


def _has_gpu() -> bool:
    import torch
    return torch.cuda.is_available() or getattr(torch.backends, "mps", None) is not None and torch.backends.mps.is_available()


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--db", default=DEFAULT_DB, help="Clap Studio library database (opened read-only)")
    p.add_argument("--limit", type=int, default=300, help="how many random files to embed")
    p.add_argument("--seconds", type=float, default=10.0, help="use at most this much of each file (CLAP reads 10 s)")
    p.add_argument("--anchors", type=int, default=15, help="how many find-similar examples to list")
    p.add_argument("--queries-file", help="text file with one search per line (default: a built-in list)")
    p.add_argument("--seed", type=int, default=1, help="makes the random sample repeatable")
    p.add_argument("--out", default="build/embedder-comparison.html")
    p.add_argument("--no-open", action="store_true", help="do not open the report in the browser when done")
    return p.parse_args()


if __name__ == "__main__":
    main()
