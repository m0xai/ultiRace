"""Re-encode the CC0 music (see godot/assets/audio/CREDITS.md) to Vorbis ~q3 for the app.

Usage: build/venv/bin/python art/audio/encode_music.py <download dir> godot/assets/audio/music
Needs `soundfile` (libsndfile with Vorbis). Sample-exact length is kept, so the loops stay seamless.
"""
import os
import sys

import soundfile as sf

TRACKS = {
    "menu": "cool_city_bpm124_0.ogg",
    "sunny": "pure_raceway_bpm160_0.ogg",
    "sunny_final": "pure_raceway_climax_bpm175_0.ogg",
    "neon": "neon_sign_circuit_bpm145_0.ogg",
    "neon_final": "neon_sign_circuit_climax_bpm160_0.ogg",
    "frosty": "blossom_mountain_bpm140_0.ogg",
    "frosty_final": "blossom_mountain_climax_bpm155_0.ogg",
    "result_best": "racing_game_result_best_bpm140_0.ogg",
    "result_good": "racing_game_result_good_bpm110_0.ogg",
    "result_bad": "racing_game_result_bad_bpm95_0.ogg",
}

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
for name, fn in TRACKS.items():
    data, sr = sf.read(os.path.join(src, fn), always_2d=True)
    out = os.path.join(dst, name + ".ogg")
    # compression_level 0.6 ≈ Vorbis q3–4 (~110–130 kbps stereo)
    # (written in blocks: libsndfile's Vorbis writer crashes on one huge write)
    with sf.SoundFile(out, "w", sr, data.shape[1], format="OGG", subtype="VORBIS", compression_level=0.6) as fh:
        for i in range(0, len(data), 16384):
            fh.write(data[i:i + 16384])
    print("%-14s %6.1f s  %5.2f MB" % (name, len(data) / sr, os.path.getsize(out) / 1e6))
