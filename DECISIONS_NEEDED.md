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

---

## D5 — the starter bite cannot reach a grounded Stinger

- **Waiver id:** none — reported as a boot warning
  (`attack_reach:head_monster_maw:enemy_stinger`), which disappears by itself
  once the data lets the two touch.
- **Status:** OPEN — the slice is playable (see *Current behaviour*), but one
  enemy is immune to the starter attack while it stands on the ground.

**Conflict.** Hitbox offsets are bone-local and the biped bone tree is fixed, so
whether an attack can ever touch a target is decided entirely by the data. The
Jagged Monster Maw's damage circle sits at the `head` bone, `offset [60, -10]`,
`radius 45` — a vertical span of **y −455 … −365**. `enemy_stinger` has no head
(deliberately: *"its primary attack is simply absent"*), so its hurtboxes are
torso −360 … −180, legs −150 … +6 and tail −197 … −153.

The nearest pair, the bite's bottom edge and the torso's top edge, **miss by
5 px**. The starter kit's only attack therefore cannot damage a grounded Stinger
at all, and the Stinger is one of the three enemies the vertical slice ships.

**Options.**
1. Give `back_bat_scraps` a hurtbox. It is currently the only equipped part in
   the game with `"hitboxes": []`, so the wings cannot be hit at all; a box at
   the `back` bone (y −330) with a half-height of ~45 would span −375 … −285 and
   close the gap. *Agent's recommendation* — it fixes a second latent gap at the
   same time and reads correctly: you bite the wings.
2. Lower or enlarge the maw's damage box (e.g. `offset [60, 10]`). One number,
   but it changes the reach of the starter attack against everything.
3. Accept it as designed: the Stinger is a tail-only target, teaching "kill what
   you want to become" by forcing the player towards the Scorpion Tail. If this
   is the intent it should be said out loud in DESIGN §9, because nothing
   currently signals it and a player will read it as a bug.

**Current behaviour.** Nothing is blocked and the slice is completable. The
Stinger's `glide_harasser` profile has it hop off ledges and glide at the player,
and while it is **airborne above** the player its legs and torso rise into the
bite's band, so it can be hit out of the air. On the ground it cannot be bitten.
The tail (`sting_attack`, damage box at torso height) hits it in either case.

The reach check that found this now runs at boot for every starter attack
against every enemy, so this class of silent immunity cannot reappear unnoticed.

---

## D6 — a dodge roll cannot fit through any crawl tunnel

- **Waiver id:** none — this is a level-design consequence, not a validation
  failure, so it is recorded here rather than enforced by a check.
- **Status:** OPEN — worked around in Level 01; the alternative key does not work.

**Conflict.** `DESIGN.md §9` lists the canonical key for a low crawl tunnel as
*"`crouch` legs (or Light class + roll)"*, and `effects.json → dodge_roll` says a
roll *"fits under crawl tunnels only while rolling"*. Neither is achievable with
the shipped numbers:

- **Light class is unreachable** at all (see D4), so "Light class + roll" cannot
  happen to anyone.
- **A roll is too short to traverse a tunnel.** `game_config.json → movement.roll`
  gives `distance 190` over `duration 0.32`, with a `cooldown` of 0.5 s. A
  creature is 110–150 px wide, so clearing an overhang of length *L* needs
  `L + width` of travel while ducked — at most **80 px** of overhang for the
  narrowest build. Anything longer leaves the creature standing up underneath
  the ceiling mid-tunnel, where it is stuck. Rolls cannot be chained through
  either: the 0.5 s cooldown is spent standing.

So in practice a crawl tunnel is a **`crouch`-only gate**, and `crouch` comes
from exactly one part, `legs_tree_trunks` (100 ink).

**Options.**
1. Let a roll be held or chained — remove the standing beat between rolls while
   a ceiling is overhead. *Agent's recommendation*: it is the smallest change
   that makes the documented key real, and rolling through a gap feels good.
2. Raise `roll.distance` to ~400 and drop the cooldown, so one roll clears a real
   tunnel. Changes dodge combat as a side effect.
3. Accept crouch as the only key and delete "(or Light class + roll)" from
   DESIGN §9 and the promise from `effects.json → dodge_roll`.

**Current behaviour.** Level 01 puts its crawl tunnel on an optional branch — on
the chasm floor, to the *left* of where the player lands, so the way onward is
never behind it. It is signposted "duck (ink back there)" and rewards a
`crouch` build with an ink cache. The level stays completable with the starter
kit, which has no crouch.
