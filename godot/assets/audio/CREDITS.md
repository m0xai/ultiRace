# Audio credits

All audio in this folder is **generated procedurally** by `art/audio/gen_audio.py`
(sfxr-style synthesis: oscillators + filtered noise, fixed seeds). No third-party samples are
used. Licence: **CC0** (created for UltiRace). Regenerate with
`python3 art/audio/gen_audio.py godot/assets/audio`.

| Files | Source | Licence |
|---|---|---|
| `sfx_*.wav` | gen_audio.py `sfx()` | CC0, own work |
| `engine_<class>_<layer>.wav` | gen_audio.py `engine_loop()` | CC0, own work |
| `music_*.wav` | gen_audio.py `music()` | CC0, own work |
