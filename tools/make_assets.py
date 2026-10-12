#!/usr/bin/env python3
"""Generates the app logo, launcher icons and alarm sounds.

Usage (from the safety_system folder):  python3 tools/make_assets.py

To use your own logo instead, replace phone/assets/logo.png (square, 512 px or
larger) and run:  python3 tools/make_assets.py --icons-from phone/assets/logo.png
"""
import math
import sys
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
PHONE_RES = ROOT / "phone/android_overlay/res"
WEAR_RES = ROOT / "wear_os/app/src/main/res"
ASSETS = ROOT / "phone/assets"

DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

CRIMSON_TOP = (190, 22, 52)
CRIMSON_BOTTOM = (112, 14, 62)
PIN = (196, 32, 47)
WHITE = (255, 255, 255)


# ---------------------------------------------------------------- logo
def bezier(p0, p1, p2, n=40):
    pts = []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t**2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t**2 * p2[1]
        pts.append((x, y))
    return pts


def heart(cx, cy, half_width, n=200):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts.append((cx + x / 16 * half_width, cy + y / 16 * half_width))
    return pts


def draw_logo(size=1024):
    s = size * 4  # supersample for smooth edges
    img = Image.new("RGB", (s, s))
    px = ImageDraw.Draw(img)
    for y in range(s):  # vertical gradient background
        k = y / (s - 1)
        px.line(
            [(0, y), (s, y)],
            fill=tuple(int(CRIMSON_TOP[i] + (CRIMSON_BOTTOM[i] - CRIMSON_TOP[i]) * k) for i in range(3)),
        )

    def P(x, y):  # normalised (-1..1) to pixels
        return (s / 2 + x * s * 0.5, s / 2 + y * s * 0.5)

    # shield, kept inside the safe zone so round launcher masks do not clip it
    k = 0.66
    outline = (
        bezier(P(-0.80 * k, -0.52 * k), P(-0.45 * k, -0.62 * k), P(0, -0.98 * k))
        + bezier(P(0, -0.98 * k), P(0.45 * k, -0.62 * k), P(0.80 * k, -0.52 * k))[1:]
        + [P(0.80 * k, 0.06 * k)]
        + bezier(P(0.80 * k, 0.06 * k), P(0.62 * k, 0.62 * k), P(0, 1.02 * k))[1:]
        + bezier(P(0, 1.02 * k), P(-0.62 * k, 0.62 * k), P(-0.80 * k, 0.06 * k))[1:]
    )
    px.polygon(outline, fill=WHITE)

    # location pin
    cx, cy = P(0, -0.13 * k * 1.0)
    r = s * 0.5 * 0.40 * k
    tip = (cx, cy + r * 2.15)
    ang = math.acos(r / (tip[1] - cy))
    t1 = (cx + r * math.sin(ang), cy + r * math.cos(ang))
    t2 = (cx - r * math.sin(ang), cy + r * math.cos(ang))
    px.ellipse([cx - r, cy - r, cx + r, cy + r], fill=PIN)
    px.polygon([tip, t1, (cx, cy), t2], fill=PIN)

    # heart in the pin
    px.polygon(heart(cx, cy - r * 0.04, r * 0.50), fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)


def write_icons(master: Image.Image):
    for res_dir in (PHONE_RES, WEAR_RES):
        for name, px in DENSITIES.items():
            out = res_dir / f"mipmap-{name}"
            out.mkdir(parents=True, exist_ok=True)
            master.resize((px, px), Image.LANCZOS).save(out / "ic_launcher.png")
    ASSETS.mkdir(parents=True, exist_ok=True)
    master.resize((512, 512), Image.LANCZOS).save(ASSETS / "logo.png")


# --------------------------------------------------------------- sounds
SR = 22050


def _save_wav(path: Path, data: np.ndarray):
    data = data / max(1e-9, np.max(np.abs(data))) * 0.95
    n_fade = int(SR * 0.004)
    fade = np.linspace(0, 1, n_fade)
    data[:n_fade] *= fade
    data[-n_fade:] *= fade[::-1]
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((data * 32767).astype("<i2").tobytes())


def make_siren() -> np.ndarray:
    """Rising and falling wail, 700-1500 Hz, two sweeps, loops cleanly."""
    dur, sweep = 3.2, 1.6
    t = np.arange(int(SR * dur)) / SR
    freq = 700 + 800 * (0.5 - 0.5 * np.cos(2 * math.pi * t / sweep))
    phase = 2 * math.pi * np.cumsum(freq) / SR
    return np.sin(phase) + 0.35 * np.sin(2 * phase) + 0.18 * np.sin(3 * phase)


def make_pulse() -> np.ndarray:
    """Sharp triple beep at 2.9 kHz, then a pause. Cuts through noise on small speakers."""
    beep, gap, rest = 0.16, 0.10, 0.50
    parts = []
    for _ in range(3):
        n = int(SR * beep)
        t = np.arange(n) / SR
        tone = np.sign(np.sin(2 * math.pi * 2900 * t)) * 0.6 + np.sin(2 * math.pi * 2900 * t) * 0.4
        env = np.minimum(1, np.minimum(np.arange(n), n - np.arange(n)) / (SR * 0.006))
        parts.append(tone * env)
        parts.append(np.zeros(int(SR * gap)))
    parts.append(np.zeros(int(SR * rest)))
    return np.concatenate(parts)


def main():
    args = sys.argv[1:]
    if args[:1] == ["--icons-from"] and len(args) == 2:
        master = Image.open(args[1]).convert("RGB")
        write_icons(master)
        print("Icons rebuilt from", args[1])
        return
    master = draw_logo(1024)
    write_icons(master)
    master.save(ROOT / "logo_preview.png")
    _save_wav(PHONE_RES / "raw/alarm_siren.wav", make_siren())
    _save_wav(PHONE_RES / "raw/alarm_pulse.wav", make_pulse())
    print("Logo, icons and alarm sounds written.")


if __name__ == "__main__":
    main()
