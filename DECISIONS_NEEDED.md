# DECISIONS_NEEDED

Contradictions between spec sources that the agent must not resolve silently
(`CLAUDE.md` → *Spec conflicts*). Each entry states the conflict, the sources,
the options, and what the build is doing **in the meantime** so nothing is
hidden. Entries with a waiver id are listed in `data/validation_waivers.json`
and re-printed by the boot validator on **every** run.

Precedence when resolving: MANDATES > `data/*.json` > TECH_SPEC > DESIGN > MILESTONES.

---

## D1 — `arms_noodle_hookers` carries `speed_boost`, an effect declared movement-only

- **Waiver id:** `part_effect_slot_kind:arms_noodle_hookers:speed_boost`
- **Status:** WAIVED — non-blocking, awaiting a human decision.

**Conflict.** `data/parts_db.json → parts.arms_noodle_hookers` sits in slot `arms`,
which `data/blueprints.json → blueprints.biped.slots.arms` declares as
`kind: "utility"`. Its `effects` list contains `speed_boost`, and
`data/effects.json → effects.speed_boost.slot_kinds` is `["movement"]`.
`effects.json → notes` says *"slot_kinds documents where the effect is legal; the
boot validator enforces it"*, so a strict reading makes the part illegal.

**Why it is not obviously a data bug.** `speed_boost` is documented as a *UI icon
flag* — "math applied by WeightClass". The part's actual speed change comes from
`stats.speed_mod: 1.05`, which `WeightClass` multiplies across **all** equipped
parts regardless of slot kind. So the part functions correctly either way; only
the legality declaration disagrees.

**Options.**
1. Add `"utility"` to `speed_boost.slot_kinds` (and, for symmetry, `jump_boost`).
   Any slot may flag a passive stat modifier. *Agent's recommendation.*
2. Drop `speed_boost` from `arms_noodle_hookers.effects` and keep `speed_mod`.
   The part still speeds you up but shows no icon in the Lab readout.
3. Move the part to a movement slot — rejected: it is an arms part, DESIGN §4.2
   lists arms as utility.

**Current behaviour.** Waived to a warning. The part is equippable, its
`speed_mod` applies, and the Lab shows its speed icon.

---

## D2 — `legs_tree_trunks` declares `fits_blueprints: ["biped", "quadruped"]` but quadruped has no `legs` slot

- **Waiver id:** none needed — auto-downgraded (see below).
- **Status:** OPEN — out of scope for the vertical slice.

**Conflict.** `data/blueprints.json → blueprints.quadruped.slots` are
`torso, legs_front, legs_rear, head, tail, back`. There is no `legs` slot, so
`legs_tree_trunks` (slot `legs`) can never be equipped on a quadruped despite
declaring that it fits one. `parts_db.schema.json` permits `legs_front` and
`legs_rear` as slot values, so the vocabulary exists; no part uses them yet.

**Options.**
1. Remove `"quadruped"` from `legs_tree_trunks.fits_blueprints`, and author the
   quadruped's leg parts in M8 with slots `legs_front` / `legs_rear`.
   *Agent's recommendation* — matches MILESTONES M8 ("4+ quadruped-compatible parts").
2. Let a `legs` part fill both quadruped leg slots, which needs a rule in
   `blueprints.json` (e.g. `"accepts_slot": "legs"` on each) rather than code.

**Current behaviour.** The validator automatically downgrades cross-reference
failures against a blueprint marked `"status": "STUB…"` to warnings, because the
rig it refers to does not exist yet. The warning prints on every boot. It becomes
a hard error the moment the quadruped stub is implemented in M8.

---

## D3 — "import filter Nearest, mipmaps off" is not a texture import option in Godot 4

- **Waiver id:** none — resolved by the agent as an engine-mechanics mapping,
  logged here for visibility rather than as an open question.
- **Status:** RESOLVED (no design change).

`ASSET_SPEC.md §5.4` and `MANDATES.md A1` require textures to import with
`filter = Nearest, mipmaps = off`. In Godot 3 both were import options; in
Godot 4 texture filtering moved off the importer and onto the project setting
`rendering/textures/canvas_textures/default_texture_filter` plus a per-CanvasItem
override. The intent is fully achievable, so this is a mapping, not a conflict:

- **Nearest:** `project.godot → rendering/textures/canvas_textures/default_texture_filter=0`,
  with every sprite left on `texture_filter = 0` (inherit).
- **Mipmaps off + no lossy compression:** `project.godot → [importer_defaults] texture`
  sets `mipmaps/generate=false`, `compress/mode=0` (lossless) and
  `detect_3d/compress_to=0`, so no pixel is ever resampled or block-compressed.

`tools/validate_assets.gd` checks all three, per-file and project-wide.

---

## D4 — the Light weight class is unreachable with the shipped part catalogue

- **Waiver id:** none — reported as a boot warning
  (`weight_class_unreachable:biped:light`), which disappears the moment the data
  makes Light reachable.
- **Status:** OPEN — playable, but one third of DESIGN §5 is currently dead content.

**Conflict.** `DESIGN.md §5` and `game_config.json → movement.weight_classes.light`
define Light as `0–25` total weight: *"Fast, floaty, high jump, weak knockback
resistance"*. But `torso` and `legs` are both required slots, and the lightest
legal pair in `parts_db.json` is `torso_ribby` (20) + `legs_scribble_sprint` (8)
**= 28**. No legal biped can weigh 25 or less, so no player will ever be Light,
and `light`'s whole preset — `max_speed 340`, `jump_velocity -880`,
`knockback_taken_mult 1.3` — is unreachable.

**Options.**
1. Raise `light.max_total_weight` from 25 to ~30. One number, no part churn; the
   starter build immediately becomes Light, which changes the game's opening feel
   from "baseline" to "fast and floaty".
2. Add a light torso (weight ≤ 17) to the catalogue. *Agent's recommendation* —
   it keeps the starter build Medium as DESIGN §5 implies ("Medium: baseline
   platforming feel") and makes Light something you *build towards*, which is the
   point of the part economy. Costs one new part + art.
3. Cut `torso_ribby` from 20 to 17. Cheapest, but it re-tunes the default build
   rather than adding a choice.

**Current behaviour.** Nothing is blocked — the class boundaries, presets and
movement code all work; `tests/test_movement.gd` proves the Light preset drives
the jump apex correctly by forcing the class. The boot warning names the lightest
legal build and the ceiling it misses, so the fix is a one-line data edit
whenever a human picks an option.

---
