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
indexed files it embeds the audio with both models, then writes a Markdown report to build/embedder-comparison.md:

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
import os
import random
import sqlite3
import time
import warnings
from pathlib import Path

import numpy as np

warnings.filterwarnings("ignore")

CLAP_NAME = "laion/clap-htsat-unfused"
GEMMA_NAME = "google/embeddinggemma-2"
DEFAULT_DB = os.path.expanduser("~/Library/Application Support/ClapStudio/library.sqlite")

DEFAULT_QUERIES = [
    "punchy kick drum", "tight closed hi-hat", "snare with a long reverb tail", "deep 808 sub bass",
    "warm analog pad", "vinyl crackle texture", "metallic clang", "short vocal chop", "rising riser sweep",
    "heavy rain", "footsteps on gravel", "glitchy percussion", "dark rumbling drone", "bright pluck",
]


# MARK: data

def pick_samples(db_path: str, limit: int, seed: int, max_seconds: float) -> list[dict]:
    """A random sample of readable, indexed library files (never a temporary USB root)."""
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    columns = {row[1] for row in con.execute("PRAGMA table_info(roots)")}
    transient = "AND r.transient = 0" if "transient" in columns else ""
    rows = con.execute(
        f"""SELECT s.id, r.path, s.rel_path, s.name, s.duration FROM samples s JOIN roots r ON r.id = s.root_id
            WHERE s.status = 'ok' AND s.duration > 0.05 {transient}"""
    ).fetchall()
    con.close()
    random.Random(seed).shuffle(rows)
    found = []
    for sample_id, root, rel, name, duration in rows:
        path = Path(root) / rel
        if path.is_file():
            found.append({"id": sample_id, "path": str(path), "rel": rel, "name": name, "duration": duration})
        if len(found) >= limit:
            break
    return found


def load_audio(samples: list[dict], seconds: float) -> tuple[list[np.ndarray], list[np.ndarray], list[dict]]:
    """Each file once at 48 kHz (CLAP) and 16 kHz (EmbeddingGemma), mono, cut at `seconds`."""
    import librosa

    a48, a16, kept = [], [], []
    for sample in samples:
        try:
            y, _ = librosa.load(sample["path"], sr=48_000, mono=True, duration=seconds)
        except Exception as error:  # unreadable or unsupported file: leave it out of both models
            print(f"  skipped {sample['rel']}: {error}")
            continue
        if y.size < 480:
            continue
        a48.append(y.astype(np.float32))
        a16.append(librosa.resample(y, orig_sr=48_000, target_sr=16_000).astype(np.float32))
        kept.append(sample)
    return a48, a16, kept


# MARK: models

def unit(x: np.ndarray) -> np.ndarray:
    x = np.asarray(x, dtype=np.float32)
    return x / np.maximum(np.linalg.norm(x, axis=-1, keepdims=True), 1e-9)


class Clap:
    name = "CLAP"

    def __init__(self) -> None:
        import torch
        from transformers import ClapModel, ClapProcessor

        self.torch = torch
        self.model = ClapModel.from_pretrained(CLAP_NAME).eval()
        self.processor = ClapProcessor.from_pretrained(CLAP_NAME)

    @staticmethod
    def _features(result) -> np.ndarray:
        # Newer transformers return an output object whose pooled vector is the projected embedding.
        tensor = result if hasattr(result, "cpu") else result.pooler_output
        vectors = tensor.cpu().numpy()
        if vectors.shape[-1] != 512:
            raise RuntimeError(f"expected CLAP's 512-number embedding, got {vectors.shape}")
        return vectors

    def embed_audio(self, arrays: list[np.ndarray], batch: int = 16) -> np.ndarray:
        out = []
        with self.torch.no_grad():
            for i in range(0, len(arrays), batch):
                chunk = arrays[i:i + batch]
                try:
                    inputs = self.processor(audio=chunk, sampling_rate=48_000, return_tensors="pt")
                except (TypeError, ValueError):  # older transformers call the argument `audios`
                    inputs = self.processor(audios=chunk, sampling_rate=48_000, return_tensors="pt")
                out.append(self._features(self.model.get_audio_features(**inputs)))
        return unit(np.concatenate(out))

    def embed_text(self, texts: list[str]) -> np.ndarray:
        with self.torch.no_grad():
            inputs = self.processor(text=texts, return_tensors="pt", padding=True)
            return unit(self._features(self.model.get_text_features(**inputs)))


class Gemma:
    name = "EmbeddingGemma 2"

    def __init__(self) -> None:
        import torch
        from sentence_transformers import SentenceTransformer

        # Text and audio only; float32 because the model overflows float16 (see its model card).
        self.model = SentenceTransformer(GEMMA_NAME, config_kwargs={"vision_config": None},
                                         model_kwargs={"torch_dtype": torch.float32})
        self.audio_format = None

    def embed_audio(self, arrays: list[np.ndarray], batch: int = 8) -> np.ndarray:
        # The model card does not spell out how to pass raw audio, so try the plausible forms once and remember
        # the one that works.
        forms = {
            "dict with array": lambda a: {"audio": a},
            "dict with sampling rate": lambda a: {"audio": {"array": a, "sampling_rate": 16_000}},
            "bare array": lambda a: a,
        }
        order = [self.audio_format] if self.audio_format else list(forms)
        last_error = None
        for form in order:
            try:
                vectors = self.model.encode([forms[form](a) for a in arrays], batch_size=batch,
                                            convert_to_numpy=True, normalize_embeddings=True)
                self.audio_format = form
                return np.asarray(vectors, dtype=np.float32)
            except Exception as error:
                last_error = error
        raise RuntimeError(f"could not embed audio with EmbeddingGemma 2 ({last_error}); see the model card for the "
                           f"current audio input format and adjust Gemma.embed_audio")

    def embed_text(self, texts: list[str]) -> np.ndarray:
        return np.asarray(self.model.encode(texts, prompt_name="SearchQuery", convert_to_numpy=True,
                                            normalize_embeddings=True), dtype=np.float32)


def truncate(x: np.ndarray, dim: int) -> np.ndarray:
    return unit(x[:, :dim])


# MARK: comparison

def top_k(scores: np.ndarray, k: int, exclude: int | None = None) -> list[int]:
    order = np.argsort(-scores)
    return [int(i) for i in order if i != exclude][:k]


def overlap(a: list[int], b: list[int]) -> float:
    return len(set(a) & set(b)) / max(1, min(len(a), len(b)))


def label(sample: dict) -> str:
    return f"{sample['name']} ({sample['duration']:.1f}s)"


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

    results = {}
    for model_class, audio in ((Clap, a48), (Gemma, a16)):
        print(f"Loading {model_class.name}")
        model = model_class()
        start = time.time()
        docs = model.embed_audio(audio)
        seconds = time.time() - start
        text = model.embed_text(queries)
        print(f"  {model_class.name}: {docs.shape[1]} numbers per sound, {len(audio) / seconds:.1f} files/s")
        results[model_class.name] = {"docs": docs, "text": text, "seconds": seconds}
        del model

    clap, gemma = results["CLAP"], results["EmbeddingGemma 2"]
    rng = random.Random(args.seed)
    anchors = rng.sample(range(len(samples)), min(args.anchors, len(samples)))

    lines = ["# CLAP and EmbeddingGemma 2 on your library", "",
             f"{len(samples)} random indexed files, each cut at {args.seconds:g} s. Both models ran on this machine "
             f"({'CPU' if not _has_gpu() else 'GPU'}).", "",
             "| | CLAP | EmbeddingGemma 2 |", "|---|---|---|",
             f"| Numbers per sound | {clap['docs'].shape[1]} | {gemma['docs'].shape[1]} (768, 512, 256 or 128) |",
             f"| Embedding speed | {len(samples) / clap['seconds']:.1f} files/s | {len(samples) / gemma['seconds']:.1f} files/s |",
             ""]

    query_overlaps = []
    lines += ["## Text searches", "",
              "Ten best matches per model. Where both models list the same file it appears in both columns.", ""]
    for qi, query in enumerate(queries):
        a = top_k(clap["docs"] @ clap["text"][qi], 10)
        b = top_k(gemma["docs"] @ gemma["text"][qi], 10)
        query_overlaps.append(overlap(a, b))
        shared = set(a) & set(b)
        lines += [f"### “{query}”  (agree on {len(shared)} of 10)", "", "| # | CLAP | EmbeddingGemma 2 |", "|---|---|---|"]
        for rank in range(10):
            mark = lambda i: f"**{label(samples[i])}**" if i in shared else label(samples[i])
            lines.append(f"| {rank + 1} | {mark(a[rank])} | {mark(b[rank])} |")
        lines.append("")

    neighbour_overlaps, truncated_overlaps = [], []
    lines += ["## Find similar", "", "Five nearest sounds to a few random files, per model.", ""]
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
        lines += [f"### Like {label(samples[anchor])}", "", "| # | CLAP | EmbeddingGemma 2 |", "|---|---|---|"]
        for rank in range(5):
            lines.append(f"| {rank + 1} | {label(samples[a[rank]])} | {label(samples[b[rank]])} |")
        lines.append("")

    summary = [
        "## How much they agree", "",
        f"* Text searches: on average {np.mean(query_overlaps) * 10:.1f} of the top 10 are shared.",
        f"* Find similar: on average {np.mean(neighbour_overlaps) * 5:.1f} of the top 5 are shared.",
        f"* EmbeddingGemma 2 cut to 256 numbers keeps {np.mean(truncated_overlaps) * 10:.1f} of its own top 10 neighbours "
        f"(the model card says quality is close to lossless down to 256).",
        "", "Low agreement is expected and is not a verdict: two good models can rank differently. "
        "Read the lists below and decide which one you would rather browse.", ""]
    lines[4:4] = summary  # right after the intro

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines))
    print(f"Wrote {out}")


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
    p.add_argument("--out", default="build/embedder-comparison.md")
    return p.parse_args()


if __name__ == "__main__":
    main()
