"""PANNs CNN14 (Kong et al., 2020) trunk, without the spectrogram front end.

The log-mel front end runs in Swift (Accelerate); this module is the convolutional part
that is converted to Core ML. Layer names match the official `Cnn14_mAP=0.431.pth`
checkpoint so the weights load directly.
"""
import torch
import torch.nn as nn
import torch.nn.functional as F


class ConvBlock(nn.Module):
    def __init__(self, in_channels, out_channels):
        super().__init__()
        self.conv1 = nn.Conv2d(in_channels, out_channels, 3, 1, 1, bias=False)
        self.conv2 = nn.Conv2d(out_channels, out_channels, 3, 1, 1, bias=False)
        self.bn1 = nn.BatchNorm2d(out_channels)
        self.bn2 = nn.BatchNorm2d(out_channels)

    def forward(self, x, pool):
        x = F.relu_(self.bn1(self.conv1(x)))
        x = F.relu_(self.bn2(self.conv2(x)))
        return F.avg_pool2d(x, kernel_size=pool) if pool != (1, 1) else x


class Cnn14Trunk(nn.Module):
    """log-mel (B, 1, T, 64) -> frame features (B, 2048, T // 32)."""

    def __init__(self):
        super().__init__()
        self.bn0 = nn.BatchNorm2d(64)
        sizes = [(1, 64), (64, 128), (128, 256), (256, 512), (512, 1024), (1024, 2048)]
        for i, (cin, cout) in enumerate(sizes, start=1):
            setattr(self, f"conv_block{i}", ConvBlock(cin, cout))

    def forward(self, mel):
        x = mel.transpose(1, 3)
        x = self.bn0(x)
        x = x.transpose(1, 3)
        for i in range(1, 6):
            x = getattr(self, f"conv_block{i}")(x, (2, 2))
        x = self.conv_block6(x, (1, 1))
        return torch.mean(x, dim=3)          # average over the mel axis -> (B, 2048, T')
