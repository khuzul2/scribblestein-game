# SCRIBBLESTEIN — Design Document v2.0 (Ready-to-Code)

Supersedes the v1 Google Doc GDD. All open design questions are resolved.
Read together with: `MANDATES.md`, `TECH_SPEC.md`, `MILESTONES.md`, `ASSET_SPEC.md`, `data/*`.

## 0. Decision Log (locked 2026-08-08)

| # | Question | Decision |
|---|----------|----------|
| 1 | World structure | **Hub + level select** (The Lab is the hub) |
| 2 | Weight mechanic | **Weight classes** — Light / Medium / Heavy presets |
| 3 | Blueprints in v1 | **Biped + 1 unlockable** (quadruped, post-slice) |
| 4 | Hitbox activation | **Attack windows only** (damage boxes dormant otherwise) |
| 5 | Damage math | **Attack vs defense**: `dmg = max(1, attack_power − total_defense)` |
| 6 | Passive parts in attack slots | **Separate utility slots** (see §4 slot map) |
| 7 | Death penalty | **Corpse run** (ink blob persists across level restart) |
| 8 | Blueprint drops | **RNG + pity timer** (per-enemy-type kill counter) |
| 9 | Healing | **Health pickups** — "Correction Fluid" blobs |
| 10 | Render resolution | **High-res crisp** (native 1920×1080 design res) |
| 11 | Line boil | **Shader UV-jitter** (8–12 FPS snap) |
| 12 | Monochrome enforcement | **Asset discipline** + mandatory automated validator |

## 1. Overview

**Scribblestein** is a 2D platformer / creature-creator / metroidvania-lite for **Godot 4.4**.
The player assembles a Frankenstein creature from badly drawn, hand-sketched body
parts. The assembly IS the character sheet: parts carry stats, hitboxes, attacks and
abilities. Visual identity: stark black-and-white "ignorant style" pencil sketch
(see `MANDATES.md` — non-negotiable).

**Core fantasy:** "I am a walking doodle, stitched from stolen anatomy."

## 2. Core Loop

1. **Build** a creature in The Lab (hub) by slotting parts onto a skeleton blueprint.
2. **Test** it instantly in the whitebox Scratchpad room ("Play in Lab").
3. **Select a level** from the sketchbook world map and clear its lock-and-key obstacles.
4. **Fight** enemies (built from the same part system), harvest **DNA Ink** and
   **Blueprint Sketches**.
5. **Return / die trying**, spend Ink in The Lab to unlock blueprinted parts.
6. Repeat with a stronger anatomy toolbox.

## 3. World Structure (Decision 1)

- **The Lab** is the hub scene: part editor + Scratchpad test room + world map table.
- Levels are **handcrafted, self-contained scenes** selected from the map. No open
  world, no streaming.
- Rebuilding the creature is possible **only in The Lab**. Entering a level is a
  loadout commitment (this is the puzzle).
- Levels unlock linearly at first, then branch (2–3 available at once) so a player
  blocked by a missing "anatomical key" always has an alternative.
- Exiting a level mid-run (pause menu → "Return to Lab") is always allowed; it keeps
  banked state and any death blob (see §7), but abandons level progress.

## 4. Creature Assembly & Slots (Decisions 3, 6)

### 4.1 Slot model
Slots are split into **attack slots** (wired to attack buttons) and **utility/movement
slots** (passive or context abilities). This resolves the v1 bat-wing conflict: passive
parts never occupy an attack slot.

### 4.2 Blueprint: "Misshapen Biped" (v1, default)

| Slot | Kind | Required | Wired to | Examples |
|------|------|----------|----------|----------|
| `torso` | core | YES | — (base HP, anchor) | Ribby Torso, Barrel Torso |
| `legs` | movement | YES | S = roll or crouch (per part) | Scribble Sprinters, Tree Trunks |
| `head` | attack | no | **Primary Attack** | Monster Maw (bite) |
| `tail` | attack | no | **Secondary Attack** | Scorpion Tail (sting) |
| `arm_l`, `arm_r` | utility | no | W = climb (if climbing arms) | Climber Claws |
| `back` | utility | no | Space (air) = glide / double jump | Bat Wing Scraps |

- A creature with an empty attack slot simply has an inert button. Empty utility
  slots remove the ability. `torso` + `legs` are the only hard requirements.
- Arms are equipped **as a pair** (one part fills both `arm_l`/`arm_r` bones).
  Same for legs. Asymmetry is a post-v1 stretch goal.

### 4.3 Blueprint: "Crooked Quadruped" (unlockable)
Slots: `torso`, `legs_front`, `legs_rear`, `head`, `tail`, `back`. No arms, so
`can_climb` parts cannot be equipped — a quadruped crosses vertical ground by
pouncing, not climbing. Parts declare compatibility via `fits_blueprints`.

Implemented in M9. Front and rear legs are **separate slots** with their own parts
(`DECISIONS_NEEDED.md` D2), so a build can pair sprinter forelegs with heavy
haunches. Bought at the Unlock Desk for `blueprints.json → quadruped.unlock_cost`;
buying it also grants every zero-cost part that fits it, because a body whose
required slots have no affordable part would be dead on arrival. Each body type
keeps its own loadout in the save, so switching never costs you a build.

**Pounce** (`game_config.json → movement.profiles.pounce`): four legs run faster
and leap flatter. A jump keeps `jump_velocity_mult` of the class' height but
commits the body forward at `launch_speed_mult` of running speed, bleeding back
down at `launch_decay`; steering mid-pounce is poor (`air_control_mult`). The
burst is only spent by the launch — knockback still decays at the weight class'
normal deceleration.

## 5. Weight Classes (Decision 2)

`total_weight = Σ part.weight`. The total buckets the creature into a class that
selects a full movement preset (exact numbers in `data/game_config.json`):

| Class | Total weight | Identity |
|-------|-------------|----------|
| **Light** | 0–25 | Fast, floaty, high jump, weak knockback resistance |
| **Medium** | 26–60 | Baseline platforming feel |
| **Heavy** | 61+ | Slow, short jump, high knockback resistance, breaks `cracked` floors |

- Class is recomputed on every assembly change and displayed in the Lab UI
  (a scribbled L / M / H stamp).
- Heavy's floor-breaking is a level-design key (see §9).
- Camera zoom keys off the creature's **bounding box**, not the class (mandate
  preserved) — formula in `TECH_SPEC.md §6`.

## 6. Combat (Decisions 4, 5)

- **Activation:** `damage`-type hitboxes exist only during the **active phase** of an
  attack. Every attack defines `windup / active / recovery / cooldown` seconds in its
  part JSON. Outside active frames, touching an enemy deals no damage in either
  direction (body contact only pushes).
- **Damage:** `damage = max(1, attacker.attack_power − defender.total_defense)`.
  `attack_power` comes from the attacking part; `total_defense = Σ part.defense`.
- **HP:** `max_hp = torso.base_hp + Σ part.hp_bonus`.
- **Hit response:** defender gets `hitstun` (attacker's attack def) + knockback impulse
  (attack's `knockback` value, direction from attacker); player gets 0.5 s i-frames
  after taking a hit, enemies 0.2 s (values in `game_config.json`).
- **Player = Enemy mandate holds:** enemies are creature assemblies with an AI brain
  instead of input (see `data/enemies.json`); identical damage rules apply.

## 7. Death & Corpse Run (Decision 7)

- All carried DNA Ink is the "wallet"; there is **no separate banking step**. Spending
  happens only in The Lab.
- On death, the **entire wallet** drops as a single splattered **Ink Blob** at the death
  position. The player respawns at the level entrance with full HP.
- **The blob persists across the level restart** and across returning to the hub —
  it is saved per-level in the save file (`death_blob: {x, y, amount}`).
- Touching the blob recovers 100% of it. **Dying again before recovery overwrites**
  the old blob with the new one (old ink is gone forever).
- One blob max exists globally? **No — one blob max per level.** Blobs in other
  levels remain waiting.

## 8. Economy (Decisions 8, 9)

- **DNA Ink:** enemies splatter 8–20 ink on death by tier (values in
  `data/enemies.json`); auto-collected on contact.
- **Blueprint Sketches:** each enemy type has `{drop_chance: 0.15, pity_kills: 6}`
  (tunable per enemy). A per-enemy-type kill counter lives in the save; the drop is
  guaranteed on the `pity_kills`-th kill if RNG hasn't fired. Counter resets on drop.
  If the blueprint is **already found or the part unlocked**, the drop converts to a
  +15 ink bonus (no duplicates).
- **Unlocking:** Blueprint Sketch + Ink cost paid in The Lab permanently unlocks the
  part (costs per part in `data/parts_db.json → unlock_cost`).
- **Correction Fluid (healing):** white blobs, 20% drop chance per kill, heal 25 HP on
  contact, despawn after 10 s. Skinned as white-out: damage scribbles your linework,
  Correction Fluid restores it.
- Starting kit (always unlocked): Ribby Torso, Scribble Sprinters, Monster Maw.

## 9. Level Design (Lock & Key)

- Levels are handcrafted obstacle courses testing specific anatomies. Geometry must
  read instantly despite the chaotic linework (mandate).
- **Canonical locks → keys (v1):**
  - Tall smooth shaft → `can_climb` (Climber Claws) or `double_jump`
  - Wide chasm → `can_glide` (Bat Wing Scraps)
  - `cracked` floor tiles → Heavy class stomps through
  - Low crawl tunnel → `crouch` legs (or Light class + roll)
  - Sting-target switches behind grates → `sting_attack` reach
- Every level's intro sightline telegraphs its required keys (a scribbled "warning
  sketch" sign showing the needed anatomy).
- Vertical slice ships **Level 1: "The Margins"** — teaches glide + climb gates,
  contains all 3 enemy types, ~6–8 min clear time.

## 10. Controls (final)

Godot InputMap actions (bindings incl. gamepad in `TECH_SPEC.md §5`):

| Action | KB/M | Effect |
|--------|------|--------|
| `move_left` / `move_right` | A / D | Run |
| `jump_glide` | Space | Grounded: jump · Airborne (held): glide, or double jump (tap) if equipped |
| `climb_up` | W | Climb while on wall with climbing arms |
| `crouch_roll` | S | Roll or crouch, per equipped legs |
| `attack_primary` | LMB / J | Head-slot attack |
| `attack_secondary` | RMB / K | Tail-slot attack |
| `interact` | E | Pickups requiring confirm, Lab stations, level doors |
| `pause` | Esc | Pause / Return to Lab |

## 11. The Lab (hub) — functional spec

- **Editor:** messy-sketchbook UI. Left page: unlocked part list filtered by slot,
  with scribbled stat deltas. Right page: the blueprint with drop targets per slot.
  Drag-and-drop; invalid slot drops snap back with a pencil-scratch error sound.
- Always-visible readouts: HP, weight total + class stamp, attack power per button,
  defense, active abilities (tiny icons).
- **Play in Lab:** one button → Scratchpad room (platform stairs, wall, gap,
  crawl tunnel, cracked floor, dummy enemy with visible HP). Instant, no fade > 0.3 s.
- **Unlock desk:** shows found Blueprint Sketches; pay ink to unlock.
- **World map table:** level select with completion checkmarks and a blob icon on any
  level holding an unrecovered death blob.
