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

All from OpenGameArt, licence **CC0 1.0** (checked on each page 2026-11-21).

| File | Track (author) | Source |
|---|---|---|
| `menu.ogg` | Cool City (124 BPM) (MintoDog) | https://opengameart.org/content/cool-city |
| `sunny.ogg` | Hyper Ultra-Racing, drum and bass (cynicmusic) | https://opengameart.org/content/hyper-ultra-racing |
| `neon.ogg`, `neon_final.ogg` | Darkness Road (165 BPM) + Climax (180 BPM), techno (MintoDog) | https://opengameart.org/content/darkness-road |
| `frosty.ogg` | Black Diamond, 143 BPM drum and bass (Joth) | https://opengameart.org/content/black-diamond |
| `sunny_final.ogg`, `frosty_final.ogg` | unused (old Pure Raceway / Blossom Mountain climax mixes, MintoDog; excluded from export, HUMAN_TODO #29) | opengameart.org/content/pure-raceway, …/blossom-mountain |
| `result_best.ogg`, `result_good.ogg`, `result_bad.ogg` | Racing Game Result Best / Good / Bad (MintoDog) | https://opengameart.org/content/racing-game-result |

## Fonts

- `godot/assets/fonts/LilitaOne-Regular.ttf` — Lilita One by Juan Montoreano, SIL Open Font
  License 1.1 (`godot/assets/fonts/OFL.txt`), from github.com/google/fonts (ofl/lilitaone).
