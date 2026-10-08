"""Shared by the comparison scripts: reading a random sample of the library, and the two embedding models.

CLAP is laion/clap-htsat-unfused (what Clap Studio uses); EmbeddingGemma 2 is google/embeddinggemma-2. Both are
Apache-2.0 and download from Hugging Face on first use (roughly 2 GB).
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

CLAP_NAME = "laion/clap-htsat-unfused"
GEMMA_NAME = "google/embeddinggemma-2"
DEFAULT_DB = os.path.expanduser("~/Library/Application Support/ClapStudio/library.sqlite")

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


def embed_with_both(audio_48k: list[np.ndarray], audio_16k: list[np.ndarray], texts: list[str]) -> dict[str, dict]:
    """Audio and text vectors from each model: {model name: {"docs", "text", "seconds"}} (seconds = audio time)."""
    results = {}
    for model_class, audio in ((Clap, audio_48k), (Gemma, audio_16k)):
        print(f"Loading {model_class.name}")
        model = model_class()
        start = time.time()
        docs = model.embed_audio(audio)
        seconds = time.time() - start
        text = model.embed_text(texts)
        print(f"  {model_class.name}: {docs.shape[1]} numbers per sound, {len(audio) / seconds:.1f} files/s")
        results[model_class.name] = {"docs": docs, "text": text, "seconds": seconds}
        del model
    return results
