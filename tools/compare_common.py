"""Shared by the model comparison scripts: a random sample of the library, the app's CLAP model, and the app's
way of turning CLAP embeddings into categories."""
from __future__ import annotations

import os
import random
import re
import sqlite3
import warnings
from pathlib import Path

import numpy as np

warnings.filterwarnings("ignore")

DEFAULT_DB = os.path.expanduser("~/Library/Application Support/ClapStudio/library.sqlite")
CATEGORIZER_SOURCE = Path(__file__).resolve().parent.parent / "Sources/ClapCore/Categories/Categorizer.swift"
CLAP_MODEL = "laion/clap-htsat-unfused"
TEMPERATURE = 100.0           # Categorizer.temperature
MINIMUM_CONFIDENCE = 0.25     # Categorizer.minimumConfidence


def pick_samples(db_path: str, limit: int, seed: int) -> list[dict]:
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


def load_audio(samples: list[dict], seconds: float, sample_rate: int = 48_000) -> tuple[list[np.ndarray], list[dict]]:
    """Each file once, mono, at `sample_rate`, cut at `seconds`; unreadable files are left out."""
    import librosa

    audio, kept = [], []
    for sample in samples:
        try:
            y, _ = librosa.load(sample["path"], sr=sample_rate, mono=True, duration=seconds)
        except Exception as error:
            print(f"  skipped {sample['rel']}: {error}")
            continue
        if y.size < sample_rate // 100:
            continue
        audio.append(y.astype(np.float32))
        kept.append(sample)
    return audio, kept


def unit(x: np.ndarray) -> np.ndarray:
    x = np.asarray(x, dtype=np.float32)
    return x / np.maximum(np.linalg.norm(x, axis=-1, keepdims=True), 1e-9)


class Clap:
    """The model the app uses (LAION-CLAP HTSAT, 512-number embeddings, 48 kHz, 10 s) through Hugging Face."""

    def __init__(self, name: str = CLAP_MODEL) -> None:
        import torch
        from transformers import ClapModel, ClapProcessor

        self.torch = torch
        self.model = ClapModel.from_pretrained(name).eval()
        self.processor = ClapProcessor.from_pretrained(name)

    @staticmethod
    def _features(result) -> np.ndarray:
        # Newer transformers return an output object whose pooled vector is the projected embedding.
        tensor = result if hasattr(result, "cpu") else result.pooler_output
        return tensor.cpu().numpy()

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


# MARK: the app's categories

def read_app_categories() -> list[tuple[str, list[str]]]:
    """The (name, phrases) pairs from the app's SoundCategories.all."""
    found = re.findall(r'\(\s*"([^"]+)"\s*,\s*\[((?:\s*"[^"]*"\s*,?)+)\s*\]\s*\)', CATEGORIZER_SOURCE.read_text())
    categories = [(name, re.findall(r'"([^"]*)"', phrases)) for name, phrases in found]
    if not categories:
        raise SystemExit(f"Could not read the categories from {CATEGORIZER_SOURCE}")
    return categories


def category_vectors(phrase_vectors: np.ndarray, categories: list[tuple[str, list[str]]]) -> np.ndarray:
    """One normalised vector per category: the mean of its phrases' vectors, like the app."""
    rows, start = [], 0
    for _, phrases in categories:
        mean = phrase_vectors[start:start + len(phrases)].mean(axis=0)
        rows.append(mean / max(np.linalg.norm(mean), 1e-9))
        start += len(phrases)
    return np.stack(rows)


def classify(similarities: np.ndarray, names: list[str]) -> list[str | None]:
    """Per sound: its category, or None without a clear winner (the app's softmax and threshold)."""
    logits = similarities * TEMPERATURE
    exps = np.exp(logits - logits.max(axis=1, keepdims=True))
    probabilities = exps / exps.sum(axis=1, keepdims=True)
    return [names[int(row.argmax())] if row.max() >= MINIMUM_CONFIDENCE else None for row in probabilities]
