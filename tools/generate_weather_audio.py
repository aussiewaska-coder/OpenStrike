#!/usr/bin/env python3
"""Generate OpenStrike's original weather sounds. Requires ffmpeg with Vorbis.

No recordings or third-party samples. Offline generation keeps noise synthesis
off the game's frame loop. Run: python3 tools/generate_weather_audio.py
"""
import array
import math
from pathlib import Path
import random
import subprocess
import tempfile
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets/audio"


def noise(seconds, thunder=False):
    rng = random.Random(913 if thunder else 217)
    low = bass = 0.0
    samples = []
    for i in range(int(seconds * RATE)):
        t = i / RATE
        white = rng.uniform(-1, 1)
        low += (0.09 if thunder else 0.55) * (white - low)
        bass += 0.014 * (white - bass)
        if thunder:
            roll = (0.72 + 0.2 * math.sin(t * 5.3) + 0.08 * math.sin(t * 13.7))
            envelope = min(t / 0.04, 1) * math.exp(-t / 1.7) * min((seconds - t) / 0.8, 1)
            crack = math.exp(-t / 0.08) + 0.4 * math.exp(-abs(t - 0.23) / 0.035)
            value = envelope * (bass * 6.0 + low * 0.7) * roll + low * crack * 0.5
        else:
            value = low * (0.7 + 0.04 * math.sin(t * 1.7)) + bass * 0.4
        samples.append(value)
    if not thunder:
        # Equal-power overlap joins the tail to the head, then starts after
        # that join. Both the splice and the exported loop boundary are continuous.
        overlap = RATE
        join = [samples[-overlap + i] * math.cos(i / (overlap - 1) * math.pi / 2)
                + samples[i] * math.sin(i / (overlap - 1) * math.pi / 2)
                for i in range(overlap)]
        samples = samples[overlap:-overlap] + join
    peak = max(abs(v) for v in samples)
    return array.array("h", (round(v / peak * 26000) for v in samples))


def main():
    OUT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="openstrike-weather-audio-") as folder:
        for name, seconds, thunder in [("rain_loop", 10, False), ("thunder", 6, True)]:
            wav = Path(folder) / f"{name}.wav"
            with wave.open(str(wav), "wb") as output:
                output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
                output.writeframes(noise(seconds, thunder).tobytes())
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav),
                            "-c:a", "libvorbis", "-q:a", "3", str(OUT / f"{name}.ogg")], check=True)


if __name__ == "__main__":
    main()
