# UI style (A2)

Goal (human, 2026-11-20): menus and text must feel like a **game, not an app** — joyful, bold,
tactile. All screens build their widgets through `godot/src/app/screens/Ui.gd`, so the style lives
in one place.

## References

- Casual/arcade mobile games (Beach Buggy Racing, Mario Kart Tour, Brawl Stars-style menus):
  chunky "toy" buttons with a darker lip underneath, saturated primaries, heavy rounded display type
  with dark outlines, everything bounces when touched.
- Racing UI write-ups: bold display faces convey speed/energy
  ([Contra: racing game UI](https://contra.com/p/FgcAeElX-uiux-design-for-mobile-racing-game));
  less screen space on mobile → fewer, bigger elements
  ([Tubik Studio](https://blog.tubikstudio.com/?p=4690));
  large touch targets and one consistent font
  ([Unity: mobile UI best practices](https://blog.unity.com/en/games/mobile-ui-design-best-practices-part-1)).

## Rules

| Element | Rule |
|---|---|
| Font | **Lilita One** (OFL, `godot/assets/fonts/`) everywhere, set as the project default font |
| Text | white with a dark navy outline (≈ size/5); titles ≥ 40 px also get a drop shadow |
| Primary button | yellow `ACCENT`, UPPERCASE label, 8 px darker lip, soft shadow |
| Secondary button | vivid blue `SECONDARY`, same lip/shadow |
| Press feedback | lip shrinks to 2 px (face "moves down"), squash 0.94 → overshoot 1.05 → 1.0 |
| Screens | gradient background deep blue → purple with faint diagonal speed stripes (`Ui.background`) |
| Entrances | panels/columns pop in (fade + back-eased scale, staggered ~0.1 s, `Ui.pop_in`) |
| Panels | navy, 26 px radius, thin light border, drop shadow |
| Touch | every control ≥ 80 units high (44 pt) |

## Next (A2 backlog)

- Settings: chunky custom toggles, rows on panels.
- 3D car showroom on Home and Vehicle Select (turntable of the real car models).
- Juicier countdown and results (scale punches, confetti for the podium).
