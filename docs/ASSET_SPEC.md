# SCRIBBLESTEIN — Asset Specification v2.0

High-res crisp direction (Decision 10): assets are drawn large and clean-of-pixels
but filthy-of-line. Think scanned pencil on paper, not pixel art.

## 1. Canvas Sizes & Pivots (creature parts)

All parts: PNG, RGBA. Design scale: 1 px = 1 screen px at 1080p, creature stands
roughly 380–520 px tall depending on build.

| Slot | Canvas | Pivot convention |
|------|--------|------------------|
| torso | 384×512 | center of mass; bone `torso` origin |
| head | 256×256 | neck joint at bottom-center |
| legs (pair, one file) | 384×384 | hip line at top-center |
| arms (pair, one file) | 256×384 | shoulder at top-center |
| tail | 320×256 | tail root at left-center (drawn facing right) |
| back | 384×384 | spine mount at bottom-center |

Each part JSON carries `pivot: {x, y}` (px from canvas top-left) = the point glued
to the bone origin. All creatures are authored facing RIGHT; the engine flips X.
Hitbox offsets in part JSON are relative to the pivot, in bone-local space.

## 2. Color Rules (Mandate A1 — asset discipline)

- Allowed pixel values in ANY gameplay texture: `#000000FF` (ink) and `#00000000`
  (fully transparent). Nothing else. No gray, no partial alpha, no off-black.
- Paper white lives ONLY in the dedicated background texture(s):
  `assets/tiles/paper_bg.png` may use `#F4F0E6FF` plus `#000000FF` grain flecks.
- UI may additionally use `#F4F0E6FF` for white-on-black panels. The validator has
  an allowlist per folder for this.
- Correction Fluid pickup is the one gameplay sprite allowed `#F4F0E6FF` (it is
  literally white-out) — folder-allowlisted.
- Export from art tools with anti-aliasing OFF / threshold at 50%.

## 3. Naming

`{slot}_{name}.png` → `head_monster_maw.png`, `tail_scorpion.png`.
Tiles: `tile_{name}.png`. UI: `ui_{name}.png`. FX: `fx_{name}.png`.
Matches `texture_path` in `parts_db.json` exactly; validator cross-checks that every
referenced path exists and every part texture is referenced.

## 4. Placeholder Strategy (for the agent, pre-art)

Until final art exists, the agent generates programmatic placeholders that PASS the
validator: pure-black jagged polygon blobs per canvas size with 2–3 px wobbly
outlines and the part name scrawled inside. Never use colored/gray dev textures —
placeholders obey the palette from day one.

## 5. Asset Validator (`tools/validate_assets.gd`) — REQUIRED (M0)

Headless-runnable (`godot --headless -s tools/validate_assets.gd`) and in CI:
1. Every PNG under `assets/`: all pixels ∈ folder's allowlist
   (default: {#000000FF, #00000000}). Report file + first offending pixel coords.
2. Canvas size matches the slot table for `assets/parts/**`.
3. Every `texture_path` in `parts_db.json` exists; orphan textures warn.
4. Import settings: filter Nearest, mipmaps off.
Exit non-zero on any violation. This is what makes Decision 12 ("asset discipline")
safe: the discipline is a machine, not a hope.

## 6. Audio Asset List (Mandate A5)

Format: OGG Vorbis, 44.1 kHz. Sources: recorded mouth noises, pencil on paper,
paper handling; synth loops from a single analog-style mono synth.

**UI:** `sfx_ui_click_scratch` · `sfx_ui_error_scratch` · `sfx_ui_page_turn` ·
`sfx_ui_stamp` (class stamp / unlock)
**Movement:** `sfx_step_scribble_01..04` · `sfx_jump_mouthpop` ·
`sfx_land_thud_light/med/heavy` · `sfx_glide_flapflap` · `sfx_climb_scratch_loop` ·
`sfx_roll_swish` · `sfx_crack_floor_break` (paper rip + crunch)
**Combat:** `sfx_attack_windup_inhale` · `sfx_bite_chomp` (mouth) ·
`sfx_sting_thwip` · `sfx_hit_beatbox_thud` · `sfx_hurt_grunt_01..03` ·
`sfx_death_paper_tear`
**Economy:** `sfx_ink_slurp` · `sfx_blob_recover_bigslurp` ·
`sfx_blueprint_found_gasp` · `sfx_correction_squeak` · `sfx_unlock_kaching_mouth`
(a human saying "ka-ching", pitched)
**Creature voice:** per enemy type one idle + one aggro mouth-noise loop.
**Music:** `mus_lab_loop` (~70 BPM sketchy synth) ·
`mus_level01_loop` (~124 BPM heavy minimal beat, Bla Bla Bla energy) — 60–90 s
seamless loops.

FORBIDDEN: any stock fantasy/sci-fi SFX pack sounds, orchestral stingers, chiptune.
