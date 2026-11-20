# iPhone 11 emulation on the Mac (`make iphone11`)

There is no way to run this Godot build on an iPhone 11 simulator here (the official Godot
4.7.2 iOS template ships an x86_64-only simulator library and the iOS 27 simulator refuses
Intel apps), and a simulator would use the Mac's GPU anyway. Instead the game runs on the Mac
**as an iPhone 11** and projects its frame times to the A13 from published benchmarks.

## What is emulated

| | iPhone 11 | How |
|---|---|---|
| Screen | 1792 × 828 px landscape (896 × 414 pt @2x), 60 Hz | window 1792×828, `Config.refresh_rate()` = 60 |
| Safe area | 48 pt left/right (notch / home-indicator column), 21 pt bottom → 96, 0, 96, 42 px | `Config.safe_area_override()` → `Ui.safe_insets()` |
| Model | `iPhone12,1` → Quality picks the **low tier** exactly like on the device | `Config.model_name()` |
| GPU | A13 ≈ 1/5.8 of this Mac's M2 Pro 16-core GPU | GFXBench 5 Aztec Ruins High offscreen: A13 ≈ 31 fps, M2 Pro 16-core ≈ 181 fps |
| Thermal | sustained GPU ≈ 52–72 % of peak (3DMark Wild Life stress: iPhone 11 Pro 51.7 %, UL database iPhone 11 72 %) | sustained = peak ÷ 0.62 |
| CPU | ≈ 1.6 × slower single-core (estimate) | game-logic time × 1.6 |

Measurement: vsync and the fps cap are off, so each frame shows its real cost; game logic is
timed from frame start to render start (×1.6), the rest of the frame counts as GPU work (×5.8).
Fixed per-frame costs of the Mac (present, compositor) are scaled too, so the projection is on
the **pessimistic** side. `FEEL=1` caps the frame rate to the projected sustained value so the
race can be watched at iPhone 11 speed; `SCALE=0.7` forces the render scale adaptive quality
would pick on a hot phone.

```bash
make iphone11                 # 20 s practice race, prints IP11 lines + IP11_SUMMARY, screenshot build/iphone11.png
make iphone11 FEEL=1          # play/watch at the projected iPhone 11 frame rate
make iphone11 SCALE=0.7 SECONDS=40
```

## Results (2026-11-20, cars v5, low tier: own car mid ≈ 40 k, others light ≈ 5 k)

- Projected A13 GPU 12–14 ms per frame → **60 fps** while the phone is cool.
- Throttled (long session): 19–23 ms → **≈ 44–50 fps** (target §8: no drop below 50 fps after
  15 min). Render scale 0.8 → 0.7 does not change it: the low tier is not fill-rate bound, so
  the lever is geometry/draw calls (or it is the pessimistic fixed-cost scaling). To confirm on
  a real iPhone 11 before release.
- CPU (scripts, prediction, physics): ≈ 1.8 ms projected — not a bottleneck.
- Layout: HUD, steering buttons and minimap stay inside the safe area.
- Found and fixed with it: a road block next to the wall could pin a car outside the road.

## Sources

- GFXBench Aztec Ruins (A13): https://www.notebookcheck.net/Apple-A13-Bionic-GPU.434833.0.html
- GFXBench Aztec Ruins (M2 Pro 16-core): https://www.notebookcheck.net/Apple-M2-Pro-16-Core-GPU.773571.0.html
- A13 GPU review (sustained vs peak): https://at-web1.www.anandtech.com/show/14892/the-apple-iphone-11-pro-and-max-review/6
- 3DMark Wild Life stress (iPhone 11 Pro 51.7 %): https://hothardware.com/news/ul-benchmarks-3dmark-wildlife-stress-test-benchmark-iphone-android
- UL iPhone 11 (Wild Life stability 72 %): https://benchmarks.ul.com/hardware/phone/Apple+iPhone+11+review
- Screen geometry (414 × 896 pt @2x): https://useyourloaf.com/blog/iphone-17-screen-sizes/
