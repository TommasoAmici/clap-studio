#!/usr/bin/env python3
"""Convert the PANNs CNN14 audio-tagging network to a Core ML model for Clap Studio.

    mise exec uv@latest -- uv venv --python 3.12 tools/.venv
    mise exec uv@latest -- uv pip install --python tools/.venv/bin/python \\
        --default-index https://pypi.org/simple -r tools/requirements.txt
    tools/.venv/bin/python tools/export_model.py

Output: ~/Library/Application Support/ClapStudio/Models/CNN14Trunk.mlpackage
(the app compiles it on first launch). Weights: Kong et al., "PANNs: Large-Scale Pretrained
Audio Neural Networks for Audio Pattern Recognition" (CC BY 4.0, https://zenodo.org/records/3987831).
"""
import argparse
import hashlib
import os
import sys
import urllib.request

import numpy as np
import torch

sys.path.insert(0, os.path.dirname(__file__))
from cnn14 import Cnn14Trunk  # noqa: E402

CHECKPOINT_URL = "https://zenodo.org/records/3987831/files/Cnn14_mAP%3D0.431.pth?download=1"
FRAMES, MELS = 401, 64            # 4 s at 32 kHz, hop 320 (must match LogMelExtractor)
DEFAULT_OUT = os.path.expanduser("~/Library/Application Support/ClapStudio/Models/CNN14Trunk.mlpackage")


def download(path):
    if os.path.exists(path):
        return
    print(f"Downloading checkpoint to {path} ...")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    urllib.request.urlretrieve(CHECKPOINT_URL, path)


def load_trunk(checkpoint):
    state = torch.load(checkpoint, map_location="cpu", weights_only=False)["model"]
    model = Cnn14Trunk()
    own = model.state_dict()
    filtered = {k: v for k, v in state.items() if k in own}
    missing = set(own) - set(filtered)
    if missing:
        raise SystemExit(f"checkpoint is missing layers: {sorted(missing)[:5]}")
    model.load_state_dict(filtered)
    return model.eval()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", default=os.path.join(os.path.dirname(__file__), ".cache", "Cnn14_mAP=0.431.pth"))
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    import coremltools as ct

    download(args.checkpoint)
    model = load_trunk(args.checkpoint)

    example = torch.randn(1, 1, FRAMES, MELS)
    traced = torch.jit.trace(model, example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="mel", shape=(1, 1, FRAMES, MELS), dtype=np.float32)],
        outputs=[ct.TensorType(name="features", dtype=np.float32)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
    )
    mlmodel.short_description = "PANNs CNN14 convolutional trunk (log-mel -> frame features)"
    mlmodel.author = "Kong et al. (PANNs), converted for Clap Studio"
    mlmodel.license = "Weights: CC BY 4.0"

    # Verify the converted model against PyTorch on realistic inputs.
    worst = 0.0
    for seed in range(3):
        rng = np.random.default_rng(seed)
        x = (rng.standard_normal((1, 1, FRAMES, MELS)).astype(np.float32) * 12) - 40   # dB-like range
        with torch.no_grad():
            expected = model(torch.from_numpy(x)).numpy()
        got = mlmodel.predict({"mel": x})["features"]
        cos = float((expected.ravel() @ got.ravel()) / (np.linalg.norm(expected) * np.linalg.norm(got) + 1e-9))
        worst = max(worst, 1 - cos)
        print(f"seed {seed}: output shape {got.shape}, cosine {cos:.5f}")
    if worst > 0.01:
        raise SystemExit(f"Core ML output deviates from PyTorch (1 - cos = {worst:.4f}); refusing to save")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    if os.path.exists(args.out):
        import shutil
        shutil.rmtree(args.out)
    mlmodel.save(args.out)
    print(f"Saved {args.out}")


if __name__ == "__main__":
    main()
