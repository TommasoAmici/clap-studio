"""Shared by compare_clap_variants.py: a random sample of the library, and LAION-CLAP checkpoints from Hugging Face.

All variants are Apache-2.0, produce 512-number embeddings and read 10 s of 48 kHz audio, like the model in the app.
"""
from __future__ import annotations

import os
import random
import sqlite3
import time
import warnings
from pathlib import Path

import numpy as np

warnings.filterwarnings("ignore")

DEFAULT_DB = os.path.expanduser("~/Library/Application Support/ClapStudio/library.sqlite")

# laion/larger_clap_music is left out on purpose: its Hugging Face weights give nearly identical embeddings for every
# sound (average cosine 0.98 between different sounds), so it cannot be compared fairly.

# Short label shown in the report -> Hugging Face model. The first one is what Clap Studio uses today.
DEFAULT_MODELS = {
    "Current (htsat-unfused)": "laion/clap-htsat-unfused",
    "Larger, music + speech": "laion/larger_clap_music_and_speech",
    "Larger, general": "laion/larger_clap_general",
}


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


def load_audio(samples: list[dict], seconds: float) -> tuple[list[np.ndarray], list[dict]]:
    """Each file once, mono, 48 kHz, cut at `seconds`; unreadable files are left out."""
    import librosa

    audio, kept = [], []
    for sample in samples:
        try:
            y, _ = librosa.load(sample["path"], sr=48_000, mono=True, duration=seconds)
        except Exception as error:
            print(f"  skipped {sample['rel']}: {error}")
            continue
        if y.size < 480:
            continue
        audio.append(y.astype(np.float32))
        kept.append(sample)
    return audio, kept


def unit(x: np.ndarray) -> np.ndarray:
    x = np.asarray(x, dtype=np.float32)
    return x / np.maximum(np.linalg.norm(x, axis=-1, keepdims=True), 1e-9)


class Clap:
    def __init__(self, name: str) -> None:
        import torch
        from transformers import ClapModel, ClapProcessor

        self.torch = torch
        self.model = ClapModel.from_pretrained(name).eval()
        self.processor = ClapProcessor.from_pretrained(name)

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


def embed_with_each(models: dict[str, str], audio: list[np.ndarray], texts: list[str]) -> dict[str, dict]:
    """{label: {"docs", "text", "seconds"}} for every model; seconds is the time spent on the audio."""
    results = {}
    for label, name in models.items():
        print(f"Loading {label} ({name})")
        model = Clap(name)
        start = time.time()
        docs = model.embed_audio(audio)
        seconds = time.time() - start
        print(f"  {len(audio) / seconds:.1f} files/s")
        pairwise = float(((docs @ docs.T).sum() - len(docs)) / max(1, len(docs) * (len(docs) - 1)))
        if pairwise > 0.95:
            print(f"  WARNING: different sounds average {pairwise:.2f} cosine; this model's embeddings look collapsed")
        results[label] = {"docs": docs, "text": model.embed_text(texts), "seconds": seconds,
                          "collapsed": pairwise > 0.95}
        del model
    return results
