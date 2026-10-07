#!/usr/bin/env python3
"""Writes tools/reference/logmel_reference.json: a librosa log-mel of a deterministic signal.

The Swift test `LogMelParityTests` compares LogMelExtractor against it, proving the Swift
front end matches the one the CNN14 weights were trained with (n_fft 1024, hop 320, 64 Slaney
mels, 50-14000 Hz, power -> dB with amin 1e-10, centered reflect padding).
"""
import json
import os

import librosa
import numpy as np

SR, N = 32000, 128000


def signal():
    t = np.arange(24000) / SR                       # 0.75 s of audio, rest is zero padding
    rng = np.random.default_rng(5)
    x = 0.5 * np.sin(2 * np.pi * 440 * t) * np.exp(-t * 3) + 0.05 * rng.standard_normal(t.size)
    return np.pad(x.astype(np.float32), (0, N - t.size))


def main():
    x = signal()
    stft = librosa.stft(x, n_fft=1024, hop_length=320, win_length=1024, window="hann", center=True, pad_mode="reflect")
    power = np.abs(stft) ** 2
    mel = librosa.filters.mel(sr=SR, n_fft=1024, n_mels=64, fmin=50, fmax=14000)
    logmel = 10 * np.log10(np.maximum(mel @ power, 1e-10)).T          # (frames, mels)
    out = os.path.join(os.path.dirname(__file__), "reference")
    os.makedirs(out, exist_ok=True)
    rows = [0, 10, 50, 100, 200]
    with open(os.path.join(out, "logmel_reference.json"), "w") as f:
        json.dump({"frames": int(logmel.shape[0]), "rows": rows,
                   "values": {str(r): logmel[r].round(4).tolist() for r in rows}}, f)
    print("frames", logmel.shape)


if __name__ == "__main__":
    main()
