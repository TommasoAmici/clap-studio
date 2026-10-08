#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "numpy",
#   "scikit-learn",
#   "torch",
#   "torchaudio",
#   "transformers>=4.45,<5",
#   "librosa>=0.10",
#   "soundfile",
# ]
# ///
"""Compare MERT (https://github.com/yizhilll/MERT) with the CLAP model Clap Studio uses, on your own library.

    mise exec uv@latest -- uv run --default-index https://pypi.org/simple \\
        tools/compare_mert.py --limit 500

Models (Hugging Face): laion/clap-htsat-unfused (the app today, the baseline) and m-a-p/MERT-v1-95M (~0.4 GB on first
use). Add the larger one with  --mert "MERT-330M=m-a-p/MERT-v1-330M"  (repeatable; --mert replaces the default).

MERT is a music model with no text side: it can compare sounds with each other, but it cannot search by a phrase or
sort sounds into the app's categories and moods by itself. So this script compares what both can do, which is
"find similar" and, with a little training, categories:

  * Name labels: file names that say what the sound is ("Kick1", "Open Hat", "Perc") give labels that neither model
    produced. For every model: how often the 5 nearest sounds are of the same kind (precision@5), how often the
    nearest one is, and how well a simple classifier trained on the embeddings (5-fold cross-validation) does.
    CLAP's zero-shot categories, exactly as the app decides them, are shown next to it.
  * MERT layers: it has no single embedding; each transformer layer is one, and they differ a lot. The script tries
    every layer and uses the best one by precision@5. (Picked on the same labels, so slightly flattering to MERT.)
    MERT's embeddings are centred on your library's average before comparing, which helps them a lot.
  * Find similar: the nearest sounds to random files, side by side, playable, and the files where the models agree
    least. These are for your ears; the numbers only say how different the models are.

Your library is opened read-only and nothing in the app changes. MERT's weights are CC-BY-NC 4.0: free for
research and personal use, not for a commercial product. Its model code is run from Hugging Face
(trust_remote_code), pinned to a reviewed commit for the two official models; the harmless "nnAudio" warning is
about a feature the v1 models do not use.
"""
from __future__ import annotations

import argparse
import random
import re
import subprocess
import time
from collections import defaultdict
from html import escape
from pathlib import Path

import numpy as np

from compare_common import (CLAP_MODEL, DEFAULT_DB, Clap, category_vectors, classify, load_audio, pick_samples,
                            read_app_categories, unit)
from compare_report import SCRIPT, STYLE, _player, _ranked, _table

MERT_RATE = 24_000
CLAP_RATE = 48_000
MIN_PER_CATEGORY = 5          # categories with fewer name-labelled files are left out of the numbers
DEFAULT_MERT = {"MERT-95M": "m-a-p/MERT-v1-95M"}
# MERT's model code is downloaded from Hugging Face and run (trust_remote_code), so the known repos are pinned to the
# commit that was read. Any other repo you pass runs whatever is current there: read it first.
PINNED_REVISIONS = {
    "m-a-p/MERT-v1-95M": "12af15fef9d0ac838c3f475bfbbf26d2060dd4f5",
    "m-a-p/MERT-v1-330M": "5240c2708a5acaee1007f43fb9735c7dcd0b78c9",
}

# What a file name says about the sound. Checked against the lower-cased name without digits; a name matching more
# than one category is ambiguous and gets no label. Only categories the app has are used.
NAME_PATTERNS = {
    "Kick": r"kick|kik|bass ?drum",
    "Snare": r"snare|snr|rimshot",
    "Clap": r"clap|klap",
    "Hi-hat": r"hi ?hat|hat|\bhh|hihat",
    "Cymbal": r"cymbal|crash|\bride\b",
    "Tom": r"(?<![a-z])tom(?![a-z])|hitom|lotom",
    "Percussion": r"perc|conga|bongo|shaker|tambourine|cowbell|clave",
    "Bass": r"bass(?! ?drum)|808|sub ?bass",
    "Synth": r"synth|saw|supersaw",
    "Lead": r"lead",
    "Pluck": r"pluck",
    "Keys": r"piano|keys|rhodes|organ|epiano",
    "Guitar": r"guitar|gtr",
    "Strings": r"strings?|violin|cello",
    "Vocal": r"vocal|vox|voice|choir|chant",
    "FX": r"\bfx\b|riser|sweep|impact|laser|zap",
    "Ambience": r"atmos|ambien|texture|drone",
}


# MARK: labels

def name_labels(samples: list[dict], categories: set[str]) -> list[str | None]:
    """A category for each file whose name clearly says one (None otherwise)."""
    patterns = {name: re.compile(pattern) for name, pattern in NAME_PATTERNS.items() if name in categories}
    labels = []
    for sample in samples:
        text = re.sub(r"\d+", " ", sample["name"].lower().replace("_", " ").replace("-", " "))
        hits = [name for name, pattern in patterns.items() if pattern.search(text)]
        labels.append(hits[0] if len(hits) == 1 else None)
    counts = defaultdict(int)
    for label in labels:
        counts[label] += 1
    return [label if label and counts[label] >= MIN_PER_CATEGORY else None for label in labels]


# MARK: MERT

def embed_mert(repo: str, arrays: list[np.ndarray], device: str) -> tuple[np.ndarray, float]:
    """Time-averaged hidden states of every layer: (files, layers + 1, dimension), and seconds spent."""
    import torch
    from transformers import AutoModel, Wav2Vec2FeatureExtractor

    revision = PINNED_REVISIONS.get(repo)
    if revision is None:
        print(f"  WARNING: {repo} is not pinned; the code currently on Hugging Face will run on this machine")
    model = AutoModel.from_pretrained(repo, trust_remote_code=True, revision=revision).eval().to(device)
    processor = Wav2Vec2FeatureExtractor.from_pretrained(repo, trust_remote_code=True, revision=revision)
    out, start = [], time.time()
    with torch.no_grad():
        for i, y in enumerate(arrays):
            y = np.pad(y, (0, max(0, 2400 - y.size)))          # the feature extractor needs a few frames of audio
            inputs = processor(y, sampling_rate=MERT_RATE, return_tensors="pt")
            # One file at a time and no attention mask: the model normalises over the whole input, so padding would
            # change the result.
            hidden = model(inputs["input_values"].to(device), output_hidden_states=True).hidden_states
            out.append(torch.stack(hidden).squeeze(1).mean(dim=1).cpu().numpy())     # (layers + 1, dimension)
            if (i + 1) % 100 == 0:
                print(f"  {i + 1}/{len(arrays)}")
    seconds = time.time() - start
    del model
    return np.stack(out).astype(np.float32), seconds


def centred(x: np.ndarray) -> np.ndarray:
    """Unit vectors after removing the library's average: raw hidden states share a big common component."""
    return unit(x - x.mean(axis=0, keepdims=True))


# MARK: metrics

def precision_at_k(emb: np.ndarray, labelled: np.ndarray, labels: np.ndarray, k: int = 5) -> tuple[float, float, dict]:
    """Among the name-labelled files: mean share of the k nearest that have the same label, the share whose single
    nearest has it, and the first number per category."""
    e = emb[labelled]
    sims = e @ e.T
    np.fill_diagonal(sims, -np.inf)
    order = np.argsort(-sims, axis=1)[:, :k]
    same = labels[order] == labels[:, None]
    per_category = {label: float(same[labels == label].mean()) for label in sorted(set(labels))}
    return float(same.mean()), float(same[:, 0].mean()), per_category


def probe_accuracy(emb: np.ndarray, labelled: np.ndarray, labels: np.ndarray, seed: int) -> float:
    """5-fold cross-validated accuracy of a logistic regression on the embeddings (name labels)."""
    from sklearn.linear_model import LogisticRegression
    from sklearn.model_selection import StratifiedKFold, cross_val_score
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import StandardScaler

    folds = min(5, int(min(np.unique(labels, return_counts=True)[1])))
    if folds < 2:
        return float("nan")
    model = make_pipeline(StandardScaler(), LogisticRegression(max_iter=3000, C=0.5))
    cv = StratifiedKFold(n_splits=folds, shuffle=True, random_state=seed)
    return float(cross_val_score(model, emb[labelled], labels, cv=cv).mean())


def top_k(scores: np.ndarray, k: int, exclude: int | None = None) -> list[int]:
    return [int(i) for i in np.argsort(-scores) if i != exclude][:k]


def overlap(a: list[int], b: list[int]) -> float:
    return len(set(a) & set(b)) / max(1, min(len(a), len(b)))


# MARK: report

def pct(value: float) -> str:
    return "–" if value != value else f"{value:.0%}"


def build_report(*, intro: str, facts: list[tuple[str, str]], metrics: list[list[str]], metric_labels: list[str],
                 per_category: tuple[list[str], list[list[str]]] | None, layers: list[tuple[str, list[list[str]]]],
                 agreement: list[str], labels: list[str], similar: list[dict], disagreements: list[dict]) -> str:
    baseline = labels[0]
    parts = [f"<!doctype html><meta charset=utf-8><title>MERT vs CLAP</title><style>{STYLE}</style>",
             "<h1>MERT vs CLAP on your library</h1>", f"<p>{escape(intro)}</p>", '<table class="facts">',
             *[f"<tr><td>{escape(k)}</td><td>{escape(v)}</td></tr>" for k, v in facts], "</table>",
             "<h2>Does the nearest sound have the same name label?</h2>",
             "<p class=muted>Higher is better. Labels come from file names, so they cover only the files whose name "
             "says what they are. “Zero-shot” is CLAP deciding from the app's phrases, which MERT cannot do.</p>",
             _table(metric_labels, ["".join(f"<td>{escape(cell)}</td>" for cell in row) for row in metrics])]
    if per_category:
        header, rows = per_category
        parts += ["<h3>Precision@5 per category</h3>",
                  _table(header, ["".join(f"<td>{escape(cell)}</td>" for cell in row) for row in rows])]
    for title, rows in layers:
        parts += [f"<h3>{escape(title)}: layer by layer</h3><p class=muted>Precision@5 and nearest-sound accuracy "
                  "using only that layer. Layer 0 is the input; the last layer is the output.</p>",
                  _table(["Layer", "Precision@5", "Nearest"], ["".join(f"<td>{escape(c)}</td>" for c in row) for row in rows])]
    parts += ["<h2>How much they agree</h2><ul>", *[f"<li>{escape(line)}</li>" for line in agreement], "</ul>",
              "<h2>Find similar</h2><p class=muted>Play the reference, then compare what each model considers "
              f"closest. A highlighted cell was also found by <b>{escape(baseline)}</b>.</p>"]
    for item in similar:
        parts += ["<h3>Like this sound</h3>", f'<div class="anchor">{_player(item["anchor"])}</div>',
                  _ranked(labels, item["rows"])]
    parts += ["<h2>Where they disagree most</h2><p class=muted>Sounds whose five nearest neighbours have nothing in "
              "common between the models. Which list sounds more right?</p>"]
    for item in disagreements:
        parts += ["<h3>Like this sound</h3>", f'<div class="anchor">{_player(item["anchor"])}</div>',
                  _ranked(labels, item["rows"])]
    parts.append(f"<script>{SCRIPT}</script>")
    return "\n".join(parts)


def ranked_rows(samples: list[dict], lists: list[list[int]], scores: list[np.ndarray]) -> list[list[tuple]]:
    baseline = set(lists[0])
    return [[(samples[found[rank]], float(score[found[rank]]), column > 0 and found[rank] in baseline)
             for column, (found, score) in enumerate(zip(lists, scores))] for rank in range(len(lists[0]))]


# MARK: main

def parse_models(specs: list[str] | None) -> dict[str, str]:
    if not specs:
        return DEFAULT_MERT
    models = {}
    for spec in specs:
        label, _, repo = spec.partition("=")
        if not repo:
            raise SystemExit(f'--mert wants "Label=repo/name", got {spec!r}')
        models[label] = repo
    return models


def main() -> None:
    args = parse_args()
    mert_models = parse_models(args.mert)
    categories = read_app_categories()
    names = [name for name, _ in categories]
    phrases = [phrase for _, group in categories for phrase in group]

    samples = pick_samples(args.db, args.limit, args.seed)
    if len(samples) < 20:
        raise SystemExit(f"Only {len(samples)} indexed files found in {args.db}; need at least 20.")
    print(f"Reading {len(samples)} files")
    import librosa
    audio48, samples = load_audio(samples, max(args.seconds, args.mert_seconds), CLAP_RATE)
    print(f"{len(samples)} readable")
    clap_audio = [y[:int(args.seconds * CLAP_RATE)] for y in audio48]
    mert_audio = [librosa.resample(y[:int(args.mert_seconds * CLAP_RATE)], orig_sr=CLAP_RATE, target_sr=MERT_RATE)
                  for y in audio48]
    del audio48

    print(f"Loading CLAP ({CLAP_MODEL})")
    clap = Clap()
    start = time.time()
    clap_docs = clap.embed_audio(clap_audio)
    clap_seconds = time.time() - start
    zero_shot = classify(clap_docs @ category_vectors(clap.embed_text(phrases), categories).T, names)
    del clap

    labels_by_name = name_labels(samples, set(names))
    labelled = np.array([i for i, label in enumerate(labels_by_name) if label])
    label_array = np.array([labels_by_name[i] for i in labelled])
    print(f"{len(labelled)} of {len(samples)} files have a name label "
          f"({len(set(label_array))} categories: {', '.join(sorted(set(label_array)))})")

    embeddings: dict[str, np.ndarray] = {"CLAP": clap_docs}      # the vectors each model is judged by
    seconds = {"CLAP": clap_seconds}
    layer_tables: list[tuple[str, list[list[str]]]] = []
    facts = [("CLAP", f"{CLAP_MODEL}, 512 numbers, 48 kHz, first {args.seconds:g} s"), ]
    for label, repo in mert_models.items():
        print(f"Loading {label} ({repo})")
        per_layer, seconds[label] = embed_mert(repo, mert_audio, args.device)
        layers = per_layer.shape[1]
        sweep = []
        for layer in range(layers):
            if len(labelled):
                p5, nearest, _ = precision_at_k(centred(per_layer[:, layer]), labelled, label_array)
            else:
                p5 = nearest = float("nan")
            sweep.append((layer, p5, nearest))
        if args.layer == "best" and len(labelled):
            chosen = max(sweep, key=lambda row: row[1])[0]
        elif args.layer in ("best", "mean"):
            chosen = None
        else:
            chosen = int(args.layer)
        if chosen is None:
            embeddings[label] = centred(per_layer.mean(axis=1))
            used = "average of all layers"
        else:
            embeddings[label] = centred(per_layer[:, chosen])
            used = f"layer {chosen} of {layers - 1}"
        embeddings[f"{label} + CLAP"] = unit(np.concatenate([clap_docs, embeddings[label]], axis=1))
        layer_tables.append((label, [[str(layer), pct(p5), pct(nearest)] for layer, p5, nearest in sweep]))
        facts.append((label, f"{repo}, {per_layer.shape[2]} numbers ({used}), 24 kHz, first {args.mert_seconds:g} s"))
        del per_layer

    labels = [name for name in embeddings if "+" not in name]            # models shown side by side in the lists
    metric_labels = ["Embedding", "Precision@5", "Nearest sound", "Classifier (5-fold)"]
    metrics, per_category_rows = [], {}
    for name, emb in embeddings.items():
        if len(labelled):
            p5, nearest, per_category_rows[name] = precision_at_k(emb, labelled, label_array)
            metrics.append([name, pct(p5), pct(nearest), pct(probe_accuracy(emb, labelled, label_array, args.seed))])
    if len(labelled):
        hits = np.mean([zero_shot[i] == labels_by_name[i] for i in labelled])
        metrics.append(["CLAP zero-shot (the app)", "", "", pct(float(hits))])
    per_category = None
    if per_category_rows:
        shown = [name for name in embeddings if "+" not in name]
        per_category = (["Category", "Files", *shown],
                        [[category, str(int((label_array == category).sum())),
                          *[pct(per_category_rows[name][category]) for name in shown]]
                         for category in sorted(set(label_array))])

    sims = {name: embeddings[name] @ embeddings[name].T for name in labels}
    found_all = {name: np.argsort(-(sims[name] - 2 * np.eye(len(samples))), axis=1)[:, :5] for name in labels}
    agreement = []
    for name in labels[1:]:
        shared = np.mean([overlap(list(found_all[labels[0]][i]), list(found_all[name][i])) for i in range(len(samples))])
        agreement.append(f"{name}: {shared * 5:.1f} of the 5 nearest sounds are shared with {labels[0]} on average.")
    agreement.append("Speed: " + ", ".join(f"{name} {len(samples) / seconds[name]:.1f} files/s" for name in labels))

    rng = random.Random(args.seed)
    similar = []
    for anchor in rng.sample(range(len(samples)), min(args.anchors, len(samples))):
        found = [top_k(sims[name][anchor], 5, exclude=anchor) for name in labels]
        similar.append({"anchor": samples[anchor], "rows": ranked_rows(samples, found, [sims[n][anchor] for n in labels])})
    # Files where the first MERT shares nothing with CLAP (picked at random among them).
    mert_name = labels[1]
    lonely = [i for i in range(len(samples)) if not set(found_all[labels[0]][i]) & set(found_all[mert_name][i])]
    rng.shuffle(lonely)
    disagreements = []
    for anchor in lonely[:args.anchors]:
        found = [top_k(sims[name][anchor], 5, exclude=anchor) for name in labels]
        disagreements.append({"anchor": samples[anchor],
                              "rows": ranked_rows(samples, found, [sims[n][anchor] for n in labels])})
    agreement.append(f"{len(lonely)} of {len(samples)} sounds have no neighbour in common between {labels[0]} and "
                     f"{mert_name}.")

    html = build_report(
        intro=f"{len(samples)} random indexed files; {len(labelled)} of them have a file name that says what they are.",
        facts=[*facts, ("Licence", "MERT weights are CC-BY-NC 4.0 (no commercial use); CLAP is Apache-2.0"),
               ("Text", "MERT has no text side: no search by phrase, no zero-shot categories or moods")],
        metrics=metrics, metric_labels=metric_labels, per_category=per_category, layers=layer_tables,
        agreement=agreement, labels=labels, similar=similar, disagreements=disagreements)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html)
    print(f"Wrote {out}")
    for row in metrics:
        print("  " + "  ".join(f"{cell:>26}" if i == 0 else f"{cell:>12}" for i, cell in enumerate(row)))
    if not args.no_open:
        subprocess.run(["open", str(out)], check=False)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--db", default=DEFAULT_DB, help="Clap Studio library database (opened read-only)")
    p.add_argument("--limit", type=int, default=500, help="how many random files to embed")
    p.add_argument("--seconds", type=float, default=10.0, help="CLAP reads at most this much of each file")
    p.add_argument("--mert-seconds", type=float, default=5.0, help="MERT reads at most this much (it was trained on 5 s)")
    p.add_argument("--anchors", type=int, default=15, help="how many find-similar examples to list")
    p.add_argument("--mert", action="append", help='"Label=huggingface/name", repeatable (default: MERT-v1-95M)')
    p.add_argument("--layer", default="best", help='MERT layer to use: a number, "best" (by precision@5) or "mean"')
    p.add_argument("--device", default="cpu", help="torch device for MERT: cpu, mps or cuda")
    p.add_argument("--seed", type=int, default=1, help="makes the random sample repeatable")
    p.add_argument("--out", default="build/mert-vs-clap.html")
    p.add_argument("--no-open", action="store_true", help="do not open the report in the browser when done")
    return p.parse_args()


if __name__ == "__main__":
    main()
