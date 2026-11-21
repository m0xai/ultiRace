"""Re-encode the CC0 music (see godot/assets/audio/CREDITS.md) to Vorbis ~q3 for the app.

Usage: build/venv/bin/python art/audio/encode_music.py <download dir> godot/assets/audio/music
Needs `soundfile` (libsndfile with Vorbis). Sample-exact length is kept, so the loops stay seamless.
"""
import os
import sys

import numpy as np
import soundfile as sf

# name → source file (see CREDITS.md). Race tracks (2026-11-21, human: "fast pace, motivating"):
# Sunny = Hyper Ultra-Racing (cynicmusic, DnB), Desert night ("neon" id) = Darkness Road
# (MintoDog, techno) + its climax mix, Frosty = Black Diamond (Joth, DnB with icy textures).
TRACKS = {
    "menu": "cool_city_bpm124_0.ogg",
    "sunny": "hyper_ultra_racing.wav",
    "neon": "darkness_road_bpm165_0.ogg",
    "neon_final": "darkness_road_climax_bpm180_0.ogg",
    "frosty": "black_diamond.mp3",
    "result_best": "racing_game_result_best_bpm140_0.ogg",
    "result_good": "racing_game_result_good_bpm110_0.ogg",
    "result_bad": "racing_game_result_bad_bpm95_0.ogg",
}

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
for name, fn in TRACKS.items():
    data, sr = sf.read(os.path.join(src, fn), always_2d=True)
    if not fn.endswith("_0.ogg"):
        # songs / MP3s are not made to loop sample-exactly: short edge fades avoid a click
        n = int(0.04 * sr)
        ramp = (np.arange(n) / n)[:, None]
        data[:n] *= ramp
        data[-n:] *= ramp[::-1]
    out = os.path.join(dst, name + ".ogg")
    # compression_level 0.6 ≈ Vorbis q3–4 (~110–130 kbps stereo)
    # (written in blocks: libsndfile's Vorbis writer crashes on one huge write)
    with sf.SoundFile(out, "w", sr, data.shape[1], format="OGG", subtype="VORBIS", compression_level=0.6) as fh:
        for i in range(0, len(data), 16384):
            fh.write(data[i:i + 16384])
    print("%-14s %6.1f s  %5.2f MB" % (name, len(data) / sr, os.path.getsize(out) / 1e6))
