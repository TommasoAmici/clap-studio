#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = [
#   "tensorflow>=2.16,<2.20",
#   "numpy<2.2",
#   "coremltools>=8.3",
#   "requests",
#   "tqdm",
# ]
# ///
"""Convert BirdNET V2.4 (bird species detector) to Core ML for Clap Studio.

    mise exec uv@latest -- uv run --python 3.12 --default-index https://pypi.org/simple tools/export_birdnet.py

Output, in ~/Library/Application Support/ClapStudio/Models/ (or --out):
    BirdNET.mlpackage       3 s of 48 kHz mono audio (1, 144000) -> 6522 species logits (apply a sigmoid)
    birdnet_labels.txt      "Scientific name_Common name" per output, in model order

BirdNET's own spectrogram layers use a complex FFT, which Core ML cannot run. The layers keep only the real part
of the FFT (a `Cast` from complex64 to float32), and the real part of a real FFT is a matrix product with a cosine
matrix, so the FFT nodes are swapped for that product in the frozen graph. The rest of the network is unchanged.
The converted model is checked against the original SavedModel before it is written.

Weights: BirdNET V2.4, Cornell Lab of Ornithology and Chemnitz University of Technology, CC BY-NC-SA 4.0
(https://github.com/birdnet-team/BirdNET-Analyzer). Personal and research use only: do not redistribute the output
or ship it in a commercial product.
"""
import argparse
import os
import shutil
import zipfile
from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow.python.framework.convert_to_constants import convert_variables_to_constants_v2

URL = "https://tuc.cloud/index.php/s/886x39f5N3sdsAM/download/V2.4.zip"
CACHE = Path(__file__).resolve().parent / ".cache" / "birdnet"
DEFAULT_OUT = os.path.expanduser("~/Library/Application Support/ClapStudio/Models")
SAMPLES = 144_000                      # 3 s at 48 kHz
MODEL_SCOPE = "StatefulPartitionedCall/model/"
SPECTROGRAMS = (("MEL_SPEC1", 2048), ("MEL_SPEC2", 1024))   # layer name, FFT length
TOLERANCE = 2e-3                       # largest allowed logit difference from the SavedModel


def download(destination: Path) -> Path:
    import requests
    from tqdm import tqdm

    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / "V2.4.zip"
    response = requests.get(URL, stream=True, timeout=30)
    response.raise_for_status()
    total = int(response.headers.get("content-length", 0))
    with open(archive, "wb") as file, tqdm(total=total, unit="iB", unit_scale=True, desc="BirdNET V2.4") as bar:
        for chunk in response.iter_content(1 << 16):
            file.write(chunk)
            bar.update(len(chunk))
    with zipfile.ZipFile(archive) as zipped:
        zipped.extractall(destination)
    archive.unlink()
    return find_model_dir(destination)


def find_model_dir(root: Path) -> Path:
    for path in root.rglob("saved_model.pb"):
        if path.parent.name == "BirdNET_GLOBAL_6K_V2.4_Model":
            return path.parent.parent
    raise SystemExit(f"No BirdNET_GLOBAL_6K_V2.4_Model folder found under {root}")


def cosine_matrix(n: int) -> np.ndarray:
    """Real part of the rfft: Re X[k] = sum_i x[i] cos(2 pi k i / n), k = 0...n/2."""
    k = np.arange(n // 2 + 1)[None, :]
    i = np.arange(n)[:, None]
    return np.cos(2 * np.pi * ((i * k) % n) / n).astype(np.float32)


def without_complex_fft(graph: "tf.compat.v1.GraphDef") -> "tf.compat.v1.GraphDef":
    """The same graph with each spectrogram layer's RFFT + Cast replaced by a cosine matrix product."""
    edited = tf.compat.v1.GraphDef()
    edited.versions.CopyFrom(graph.versions)
    edited.library.CopyFrom(graph.library)
    removed = {MODEL_SCOPE + layer + "/stft/rfft" for layer, _ in SPECTROGRAMS}
    casts = {MODEL_SCOPE + layer + "/Cast": layer for layer, _ in SPECTROGRAMS}
    found = 0
    for node in graph.node:
        if node.name in removed:
            continue
        copy = edited.node.add()
        copy.CopyFrom(node)
        if node.name in casts:
            layer = casts[node.name]
            copy.op = "BatchMatMulV2"
            copy.attr.clear()
            del copy.input[:]
            copy.input.extend([MODEL_SCOPE + layer + "/stft/mul", MODEL_SCOPE + layer + "/cosine"])
            copy.attr["T"].type = tf.float32.as_datatype_enum
            copy.attr["adj_x"].b = False
            copy.attr["adj_y"].b = False
            found += 1
    if found != len(SPECTROGRAMS):
        raise SystemExit("This is not the BirdNET V2.4 graph the exporter expects (spectrogram layers not found).")
    for layer, n in SPECTROGRAMS:
        const = edited.node.add()
        const.name = MODEL_SCOPE + layer + "/cosine"
        const.op = "Const"
        const.attr["dtype"].type = tf.float32.as_datatype_enum
        const.attr["value"].tensor.CopyFrom(tf.make_tensor_proto(cosine_matrix(n)))
    return edited


def runnable(graph: "tf.compat.v1.GraphDef"):
    # The argument name becomes the Core ML input name.
    @tf.function(input_signature=[tf.TensorSpec([1, SAMPLES], tf.float32)])
    def run(inputs):
        out, = tf.graph_util.import_graph_def(graph, input_map={"inputs:0": inputs},
                                              return_elements=["Identity:0"], name="")
        return out

    return run


def test_clips() -> np.ndarray:
    """Deterministic audio: chirps over noise, with different loudness, so every layer is exercised."""
    rng = np.random.default_rng(7)
    t = np.arange(SAMPLES) / 48_000
    clips = []
    for base, rate in ((2500, 900), (4000, 1500), (6500, 400), (1200, 2500)):
        sweep = np.sin(2 * np.pi * (base * t + rate * t * t))
        envelope = np.clip(np.sin(2 * np.pi * 2.5 * t), 0, 1)
        clips.append(0.5 * sweep * envelope + 0.05 * rng.standard_normal(SAMPLES))
    return np.stack(clips).astype(np.float32)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", help="folder holding BirdNET_GLOBAL_6K_V2.4_Model (default: download V2.4.zip)")
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args()

    source = find_model_dir(Path(args.source)) if args.source else (
        find_model_dir(CACHE) if CACHE.exists() and any(CACHE.rglob("saved_model.pb")) else download(CACHE))
    print(f"Model files: {source}")

    import coremltools as ct

    saved = tf.saved_model.load(str(source / "BirdNET_GLOBAL_6K_V2.4_Model"))
    frozen = convert_variables_to_constants_v2(saved.signatures["basic"]).graph.as_graph_def()
    original = runnable(frozen)
    edited = runnable(without_complex_fft(frozen))

    clips = test_clips()
    expected = np.concatenate([original(tf.constant(c[None])).numpy() for c in clips])
    rewritten = np.concatenate([edited(tf.constant(c[None])).numpy() for c in clips])
    print(f"Cosine-matrix spectrograms vs original: largest logit difference {np.abs(rewritten - expected).max():.2e}")

    model = ct.convert([edited.get_concrete_function()], source="tensorflow", convert_to="mlprogram",
                       minimum_deployment_target=ct.target.macOS14, compute_precision=ct.precision.FLOAT32,
                       inputs=[ct.TensorType(name="inputs", shape=(1, SAMPLES), dtype=np.float32)])
    spec_outputs = list(model.get_spec().description.output)
    output_name = spec_outputs[0].name
    converted = np.concatenate([model.predict({"inputs": c[None]})[output_name] for c in clips])
    difference = float(np.abs(converted - expected).max())
    print(f"Core ML vs original SavedModel: largest logit difference {difference:.2e}")
    if difference > TOLERANCE:
        raise SystemExit(f"Core ML output differs from the original by {difference:.2e} (limit {TOLERANCE:.0e}); not written.")

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    package = out / "BirdNET.mlpackage"
    if package.exists():
        shutil.rmtree(package)
    model.short_description = "BirdNET V2.4: 3 s of 48 kHz audio to 6522 species logits (CC BY-NC-SA 4.0)"
    model.save(str(package))
    shutil.copy(source / "BirdNET_GLOBAL_6K_V2.4_Labels.txt", out / "birdnet_labels.txt")
    print(f"Wrote {package} and birdnet_labels.txt")


if __name__ == "__main__":
    main()
