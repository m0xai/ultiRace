# Audio credits

Sound effects and engines are **generated procedurally** (own work, CC0); the music is
third-party **CC0** (no attribution required; credited anyway). Regenerate the generated part
with `make audio`.

| Files | Source | Licence |
|---|---|---|
| `sfx_*.wav` | gen_audio.py `sfx()` | CC0, own work |
| `eng_<car>_<k>_<on|off>.wav`, `engines.json`, `road_roll.wav`, `wind.wav` | `art/audio/gen_engines.py` (physical engine model, numpy) | CC0, own work |
| `engine_<class>_<layer>.wav`, `music_*.wav` | old gen_audio.py output, unused (excluded from export; HUMAN_TODO #29) | CC0, own work |

### Music (`music/*.ogg`, re-encoded by `art/audio/encode_music.py`)

All by **MintoDog** on OpenGameArt, licence **CC0 1.0** (checked on each page 2026-11-21).

| File | Track | Source |
|---|---|---|
| `menu.ogg` | Cool City (124 BPM) | https://opengameart.org/content/cool-city |
| `sunny.ogg`, `sunny_final.ogg` | Pure Raceway (160 BPM) + Climax (175 BPM) | https://opengameart.org/content/pure-raceway |
| `neon.ogg`, `neon_final.ogg` | Neon Sign Circuit (145 BPM) + Climax (160 BPM) | https://opengameart.org/content/neon-sign-circuit |
| `frosty.ogg`, `frosty_final.ogg` | Blossom Mountain (140 BPM) + Climax (155 BPM) | https://opengameart.org/content/blossom-mountain |
| `result_best.ogg`, `result_good.ogg`, `result_bad.ogg` | Racing Game Result Best / Good / Bad | https://opengameart.org/content/racing-game-result |

## Fonts

- `godot/assets/fonts/LilitaOne-Regular.ttf` — Lilita One by Juan Montoreano, SIL Open Font
  License 1.1 (`godot/assets/fonts/OFL.txt`), from github.com/google/fonts (ofl/lilitaone).
