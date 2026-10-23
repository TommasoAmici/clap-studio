#!/usr/bin/env python3
"""Convert LAION-CLAP (laion/clap-htsat-unfused) to Core ML for Clap Studio.

    scripts/setup.sh --model-tools
    tools/.venv/bin/python tools/export_clap.py

Output, in ~/Library/Application Support/ClapStudio/Models/:
    CLAPAudio.mlpackage   log-mel (1,1,1001,64) -> 512-d unit embedding
    CLAPText.mlpackage    token ids + mask (1,48) -> 512-d unit embedding
    clap_vocab.json, clap_merges.txt   RoBERTa BPE tokenizer files (used by the Swift tokenizer)

Weights: LAION-CLAP, Apache-2.0 (https://huggingface.co/laion/clap-htsat-unfused).
"""
import argparse
import json
import os
import shutil
import types
import warnings

import numpy as np
import torch
import torch.nn.functional as F

warnings.filterwarnings("ignore")

NAME = "laion/clap-htsat-unfused"
FRAMES, MELS = 1001, 64          # 10 s at 48 kHz, hop 480 (must match LogMelExtractor.clap)
TEXT_LEN = 48                    # tokens, padded with <pad> (must match CLAPTextEncoder)
DEFAULT_OUT = os.path.expanduser("~/Library/Application Support/ClapStudio/Models")


class AudioTower(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.m = model
        self.register_buffer("longer", torch.zeros(1, 1, dtype=torch.bool))

    def forward(self, mel):
        return self.m.get_audio_features(input_features=mel, is_longer=self.longer)


def patch_bicubic(model):
    """Core ML has no bicubic upsample. The resize (1001 -> 1024 frames along time) is linear,
    so capture it exactly as a matrix and apply it with a matmul."""
    enc = model.audio_model.audio_encoder
    width = int(enc.spec_size * enc.freq_ratio)
    with torch.no_grad():
        basis = torch.eye(FRAMES).reshape(FRAMES, 1, FRAMES, 1)
        matrix = F.interpolate(basis, (width, 1), mode="bicubic", align_corners=True)[:, 0, :, 0].T.contiguous()
    enc.register_buffer("resize_m", matrix)

    def reshape_mel2img(self, x):
        b, c, _, f = x.shape
        x = torch.einsum("wt,bctf->bcwf", self.resize_m, x)
        x = x.reshape(b, c * self.freq_ratio, width // self.freq_ratio, f)
        x = x.permute(0, 1, 3, 2).contiguous()
        return x.reshape(b, c, f * self.freq_ratio, width // self.freq_ratio)

    enc.reshape_mel2img = types.MethodType(reshape_mel2img, enc)


class TextTower(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.m = model

    def forward(self, ids, mask):
        positions = torch.cumsum(mask, 1) * mask + 1       # RoBERTa positions; padding_idx = 1
        pooled = self.m.text_model(input_ids=ids, attention_mask=mask, position_ids=positions).pooler_output
        return F.normalize(self.m.text_projection(pooled), dim=-1)


def cosine(a, b):
    a, b = a.ravel(), b.ravel()
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9))


def replace(path, build):
    if os.path.exists(path):
        shutil.rmtree(path)
    build(path)
    print(f"Saved {path}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    import coremltools as ct
    from huggingface_hub import hf_hub_download
    from transformers import ClapModel, ClapProcessor

    original = ClapModel.from_pretrained(NAME).eval()
    model = ClapModel.from_pretrained(NAME).eval()
    processor = ClapProcessor.from_pretrained(NAME)
    os.makedirs(args.out, exist_ok=True)

    # ---- audio tower
    patch_bicubic(model)
    audio = AudioTower(model).eval()
    rng = np.random.default_rng(0)
    xs = [torch.from_numpy((rng.standard_normal((1, 1, FRAMES, MELS)) * 10 - 35).astype(np.float32)) for _ in range(3)]
    with torch.no_grad():
        traced = torch.jit.trace(audio, xs[0], check_trace=False)
    audio_ml = ct.convert(
        traced, inputs=[ct.TensorType(name="mel", shape=(1, 1, FRAMES, MELS), dtype=np.float32)],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)], convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16, minimum_deployment_target=ct.target.macOS14)
    worst = 1.0
    for x in xs:
        with torch.no_grad():
            expected = original.get_audio_features(input_features=x, is_longer=torch.zeros(1, 1, dtype=torch.bool)).numpy()
        got = audio_ml.predict({"mel": x.numpy()})["embedding"]
        worst = min(worst, cosine(expected, got))
    print(f"audio tower: worst cosine vs PyTorch {worst:.6f}")
    if worst < 0.99:
        raise SystemExit("audio tower deviates from PyTorch; refusing to save")
    audio_ml.short_description = "LAION-CLAP HTSAT audio encoder (log-mel -> 512-d embedding)"
    audio_ml.license = "Apache-2.0"
    replace(os.path.join(args.out, "CLAPAudio.mlpackage"), audio_ml.save)

    # ---- text tower (fp16 only for matmuls: a full fp16 conversion overflows in attention/layer-norm)
    text = TextTower(model).eval()
    probe = processor.tokenizer(["a punchy kick drum"], padding="max_length", max_length=TEXT_LEN, return_tensors="pt")
    with torch.no_grad():
        traced = torch.jit.trace(text, (probe["input_ids"], probe["attention_mask"]), check_trace=False)
    text_ml = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input_ids", shape=(1, TEXT_LEN), dtype=np.int32),
                ct.TensorType(name="attention_mask", shape=(1, TEXT_LEN), dtype=np.int32)],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)], convert_to="mlprogram",
        compute_precision=ct.transform.FP16ComputePrecision(op_selector=lambda op: op.op_type in ("linear", "matmul", "gelu")),
        minimum_deployment_target=ct.target.macOS14)
    worst = 1.0
    for q in ["a punchy kick drum", "closed hi hat", "warm analog pad", "808"]:
        e = processor.tokenizer([q], padding="max_length", max_length=TEXT_LEN, return_tensors="pt")
        with torch.no_grad():
            expected = original.get_text_features(input_ids=e["input_ids"], attention_mask=e["attention_mask"]).numpy()
        got = text_ml.predict({"input_ids": e["input_ids"].int().numpy(),
                               "attention_mask": e["attention_mask"].int().numpy()})["embedding"]
        worst = min(worst, cosine(expected, got))
    print(f"text tower: worst cosine vs PyTorch {worst:.6f}")
    if worst < 0.99:
        raise SystemExit("text tower deviates from PyTorch; refusing to save")
    text_ml.short_description = "LAION-CLAP text encoder (tokens -> 512-d embedding)"
    text_ml.license = "Apache-2.0"
    replace(os.path.join(args.out, "CLAPText.mlpackage"), text_ml.save)

    for src, dst in [("vocab.json", "clap_vocab.json"), ("merges.txt", "clap_merges.txt")]:
        shutil.copyfile(hf_hub_download(NAME, src), os.path.join(args.out, dst))
    print("Copied tokenizer files")


if __name__ == "__main__":
    main()
