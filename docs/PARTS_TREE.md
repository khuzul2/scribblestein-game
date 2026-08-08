# SCRIBBLESTEIN — Part & Artwork Tree

Every part the finished game ships, every art file it needs, and why each one
exists. This is the authority on **what** the catalogue contains; the numbers
live in `data/parts_db.json`, which is the authority on **how much** (Mandate B1
— no balance value is ever written in GDScript).

- **61 parts** across **8 slots** and **2 body types**.
- Every slot on both blueprints offers **at least four** legal parts.
- Every part carries a distinct **effect or attack**, not merely a stat delta —
  part choice should read as a playstyle, not as a slider.

---

## 1. The slot tree

```
Misshapen Biped                        Crooked Quadruped
├── torso       core     required  8   ├── torso        core     required  8   (shared)
├── legs        movement required  8   ├── legs_front   movement required  8
├── head        attack   optional  9   ├── legs_rear    movement required  8
├── tail        attack   optional  7   ├── head         attack   optional  9   (shared)
├── arms        utility  optional  6   ├── tail         attack   optional  7   (shared)
└── back        utility  optional  7   └── back         utility  optional  7   (shared)
        45 parts fit a biped                   47 parts fit a quadruped
```

`torso`, `head`, `tail` and `back` parts fit **both** bodies — they mount on
bones both rigs have. `legs` is biped-only and `legs_front` / `legs_rear` are
quadruped-only, which is what makes a quadruped a different animal rather than a
biped on all fours (`DECISIONS_NEEDED.md` D2).

## 2. Archetypes

Every part belongs to one, and the five are legible at a glance in the Lab:

| Archetype | Reads as | Carries |
|---|---|---|
| **Brute** | heavy, armoured, unbudgeable | `thick_hide`, `heavy_landing`, high defense, weight 20–45 |
| **Skitter** | light, quick, fragile | `speed_boost`, `jump_boost`, `dodge_roll`, weight 3–14 |
| **Reach** | hits from further than it looks | `long_reach`, `spit_attack`, `quick_strike` |
| **Rigger** | goes where others cannot | `can_climb`, `can_glide`, `double_jump`, `air_dash`, `wall_cling`, `crouch` |
| **Glass** | enormous damage, nothing to absorb one | very high `attack_power`, very low HP and weight |

A build is normally two archetypes in conversation — a Brute torso on Skitter
legs, a Glass head on a Rigger back. That conversation is the game.

## 3. Effects

Ten shipped before M10; eight are added with the catalogue. Each is declared in
`data/effects.json` with the slot kinds it is legal in, and the boot validator
enforces that declaration.

| Effect | Category | What it does |
|---|---|---|
| `bite_attack` | attack | primary attack, damage box at the head bone |
| `sting_attack` | attack | secondary attack, damage box at the tail bone |
| `club_attack` | attack | secondary attack, slower and heavier than a sting |
| `spit_attack` | attack | **new** — fires a projectile instead of swinging |
| `can_climb` | movement | scale a `climbable` surface |
| `can_glide` | movement | cap fall speed while the jump button is held |
| `double_jump` | movement | one extra jump in the air |
| `dodge_roll` | movement | committed roll with i-frames; chains under an overhang |
| `crouch` | movement | duck to fit a crawl tunnel |
| `air_dash` | movement | **new** — one horizontal burst per airtime |
| `wall_cling` | movement | **new** — hold a climbable face without ascending |
| `speed_boost` | passive | UI flag for a `speed_mod` |
| `jump_boost` | passive | UI flag for a `jump_mod` |
| `thick_hide` | passive | **new** — multiplies knockback taken |
| `heavy_landing` | passive | **new** — breaks cracked floors at any weight class |
| `ink_magnet` | passive | **new** — widens the ink pickup radius |
| `quick_strike` | passive | **new** — shortens attack windup and cooldown |
| `long_reach` | passive | **new** — scales up damage boxes |

## 4. The catalogue

Weight is the number that decides your class (Light 0–25 · Medium 26–60 ·
Heavy 61+), so it is listed first — it is the real cost of every part.

### 4.1 `torso` — core, required, both bodies (8)

| Part | W | HP | Def | Mods | Effects | Archetype |
|---|---|---|---|---|---|---|
| Wire Cage | 12 | 55 | — | spd ×1.10 | `speed_boost` | Skitter |
| Paper Husk | 15 | 70 | — | jmp ×1.05 | `jump_boost` | Skitter |
| Ribby Torso ★ | 20 | 100 | — | — | — | baseline |
| Burst Seams | 22 | 60 | — | spd ×1.05, jmp ×1.05 | `speed_boost`, `jump_boost` | Skitter |
| Inkwell Belly | 26 | 110 | 1 | — | `ink_magnet` | Rigger |
| Stitched Sack | 30 | 130 | 2 | spd ×0.97 | `thick_hide` | Brute |
| Slab of Card | 38 | 160 | 4 | spd ×0.92 | `thick_hide`, `heavy_landing` | Brute |
| Barrel Chest | 45 | 150 | 3 | — | — | baseline |

### 4.2 `legs` — movement, required, biped (8)

| Part | W | HP+ | Def | Mods | Effects | Archetype |
|---|---|---|---|---|---|---|
| Scribble Sprinters ★ | 8 | — | — | spd ×1.15 | `dodge_roll`, `speed_boost` | Skitter |
| Ink Stilts | 10 | — | — | spd ×1.05, jmp ×1.15 | `jump_boost` | Skitter |
| Spring Coils | 12 | — | — | jmp ×1.30 | `dodge_roll`, `jump_boost` | Skitter |
| Pogo Nib | 14 | 5 | — | spd ×0.95, jmp ×1.25 | `jump_boost`, `double_jump` | Skitter |
| Dash Scratches | 18 | — | — | spd ×1.08 | `air_dash`, `dodge_roll` | Rigger |
| Hoofed Scrawl | 26 | 15 | 1 | — | `crouch` | Rigger |
| Tree Trunks | 35 | 20 | 2 | spd ×0.90, jmp ×0.90 | `crouch` | Rigger |
| Anvil Boots | 42 | 30 | 3 | spd ×0.85, jmp ×0.80 | `heavy_landing`, `thick_hide` | Brute |

Three of these — Ink Stilts, Pogo Nib and Anvil Boots — grant **neither**
`crouch` nor `dodge_roll`. That is deliberate: the D6 ruling made rolling through
a crawl tunnel actually work, which with only three legs parts (all of which
rolled or crouched) left the tunnel gating nothing. These three put the lock back.

### 4.3 `arms` — utility, optional, biped only (6)

| Part | W | HP+ | Def | Effects | Archetype |
|---|---|---|---|---|---|
| Pocket Lint | 3 | — | — | `ink_magnet` | Rigger |
| Noodle Hookers | 5 | — | — | `speed_boost` | Skitter |
| Scribble Whips | 8 | — | — | `long_reach` | Reach |
| Climber Claws | 10 | — | — | `can_climb` | Rigger |
| Grapple Hooks | 14 | 5 | 1 | `can_climb`, `wall_cling` | Rigger |
| Shield Flaps | 20 | 10 | 3 | `thick_hide` | Brute |

### 4.4 `head` — attack, optional, both bodies (9)

| Part | W | HP+ | Def | Atk | Effects | Archetype |
|---|---|---|---|---|---|---|
| Thumbtack Skull | 5 | — | — | 50 | `bite_attack` | Glass |
| Pencil Stub Head | 6 | — | — | 20 | `bite_attack` | baseline |
| Needle Beak | 9 | — | — | 28 | `bite_attack`, `quick_strike` | Reach |
| Spit Gland | 12 | 5 | — | 18 | `spit_attack` | Reach |
| Jagged Monster Maw ★ | 15 | 20 | — | 35 | `bite_attack` | baseline |
| Lantern Jaw | 22 | 15 | 1 | 44 | `bite_attack`, `long_reach` | Reach |
| Two Bad Faces | 26 | 20 | 1 | 34 | `bite_attack`, `quick_strike` | Reach |
| Rusted Bucket | 30 | 35 | 3 | 30 | `bite_attack`, `thick_hide` | Brute |
| Anvil Noggin | 40 | 30 | 2 | 50 | `bite_attack` | baseline |

### 4.5 `tail` — attack, optional, both bodies (7)

| Part | W | HP+ | Atk | Effects | Archetype |
|---|---|---|---|---|---|
| Ink Dribble | 6 | — | 12 | `sting_attack`, `ink_magnet` | Rigger |
| Rudder Fin | 8 | — | 10 | `sting_attack`, `can_glide` | Rigger |
| Whip Line | 10 | — | 16 | `sting_attack`, `long_reach` | Reach |
| Scorpion Tail | 12 | — | 25 | `sting_attack` | baseline |
| Kick Spring | 14 | 5 | 20 | `club_attack`, `jump_boost` | Skitter |
| Eraser Club | 20 | 10 | 30 | `club_attack` | baseline |
| Counterweight | 28 | 20 | 34 | `club_attack`, `thick_hide` | Brute |

### 4.6 `back` — utility, optional, both bodies (7)

| Part | W | HP+ | Def | Effects | Archetype |
|---|---|---|---|---|---|
| Bat Wing Scraps | 4 | — | — | `can_glide` | Rigger |
| Kite Sail | 7 | — | — | `can_glide`, `air_dash` | Rigger |
| Ink Bladder | 9 | 5 | — | `ink_magnet`, `quick_strike` | Rigger |
| Sketch Thrusters | 10 | — | — | `double_jump` | Rigger |
| Grapple Spool | 12 | 5 | 1 | `wall_cling` | Rigger |
| Scrap Shell | 24 | 25 | 4 | `thick_hide` | Brute |
| Lead Weight | 32 | 15 | 2 | `heavy_landing`, `thick_hide` | Brute |

### 4.7 `legs_front` — movement, required, quadruped only (8)

| Part | W | HP+ | Def | Mods | Effects | Archetype |
|---|---|---|---|---|---|---|
| Scuttler Forelegs | 5 | — | — | spd ×1.20 | `speed_boost` | Skitter |
| Stub Pegs | 8 | — | — | spd ×0.95, jmp ×1.10 | `jump_boost` | Skitter |
| Reaching Arms | 12 | — | — | spd ×1.05 | `long_reach` | Reach |
| Dash Pads | 16 | — | — | spd ×1.10 | `air_dash` | Rigger |
| Wheelbarrow Wheels | 18 | 5 | — | spd ×1.15, jmp ×0.90 | `speed_boost`, `dodge_roll` | Skitter |
| Shovel Claws | 22 | 10 | 1 | spd ×0.95 | `crouch` | Rigger |
| Paw Hammers | 28 | 15 | 3 | spd ×0.90, jmp ×0.95 | — | baseline |
| Iron Pistons | 36 | 25 | 4 | spd ×0.85, jmp ×0.85 | `thick_hide`, `heavy_landing` | Brute |

### 4.8 `legs_rear` — movement, required, quadruped only (8)

| Part | W | HP+ | Def | Mods | Effects | Archetype |
|---|---|---|---|---|---|---|
| Spring Haunches | 5 | — | — | jmp ×1.20 | `jump_boost` | Skitter |
| Scuttle Pair | 9 | — | — | spd ×1.12 | `speed_boost` | Skitter |
| Glider Flaps | 12 | — | — | jmp ×1.05 | `can_glide` | Rigger |
| Kicker Pair | 14 | — | — | spd ×1.05 | `dodge_roll` | Skitter |
| Coiled Springs | 18 | 5 | — | spd ×0.98, jmp ×1.30 | `jump_boost`, `double_jump` | Skitter |
| Stiff Planks | 24 | 10 | 2 | spd ×0.92 | `thick_hide` | Brute |
| Dragging Stumps | 30 | 25 | 3 | spd ×0.85, jmp ×0.85 | `crouch` | Rigger |
| Ballast Sacks | 34 | 30 | 4 | spd ×0.85, jmp ×0.80 | `thick_hide`, `heavy_landing` | Brute |

## 5. Coverage the catalogue has to have

These are asserted by `tests/test_catalogue.gd`, not merely intended:

- **Every slot on both bodies offers ≥ 4 legal parts**, so no slot is a
  foregone conclusion.
- **Every weight class is reachable on both bodies.** Lightest legal biped is
  Wire Cage (12) + Scribble Sprinters (8) = **20**; lightest quadruped is
  Wire Cage (12) + Scuttler Forelegs (5) + Spring Haunches (5) = **22**. Both
  sit under the Light ceiling of 25.
- **Parts that already shipped keep their numbers.** Growing the roster is not a
  balance pass: re-tuning the starter kit while adding parts changes the opening
  of the game for reasons unrelated to variety. The 19 parts that predate this
  catalogue are byte-for-byte what they were.
- **Every archetype is reachable on both bodies** — a build can be wholly Brute,
  wholly Skitter, and so on.
- **Every effect is carried by at least one part that fits each body**, except
  `can_climb`, which is deliberately biped-only: the quadruped has no arms and
  crosses vertical ground by pouncing (DESIGN §4.3).
- **Every part has at least one hurtbox**, so nothing in the game is
  untouchable (`DECISIONS_NEEDED.md` D5).
- **Every part is reachable in play** — it is either a starter, granted with a
  blueprint, or has a positive `unlock_cost` and appears at the Unlock Desk.

## 6. Artwork manifest

One PNG per part, plus the shared set. All are **pure black ink on full
transparency** — no greys, no anti-aliasing, no partial alpha (Mandate A1,
`ASSET_SPEC.md` §2). `tools/validate_assets.gd` rejects anything else, per file,
with the coordinates of the first offending pixel.

### 6.1 Canvas sizes and pivots

From `data/asset_spec.json → canvas_sizes`. The pivot is the point that is glued
to the bone origin, in texture pixels.

| Slot | Canvas | Folder | Typical pivot |
|---|---|---|---|
| `torso` | 384 × 512 | `assets/parts/torsos/` | (192, 256) |
| `head` | 256 × 256 | `assets/parts/heads/` | (128, 128) |
| `legs`, `legs_front`, `legs_rear` | 384 × 384 | `assets/parts/legs/` | (192, 40) |
| `arms` | 256 × 384 | `assets/parts/arms/` | (128, 40) |
| `tail` | 320 × 256 | `assets/parts/tails/` | (160, 128) |
| `back` | 384 × 384 | `assets/parts/backs/` | (192, 192) |

### 6.2 File list

61 part textures, named `<slot>_<name>.png` in the folder for their slot — the
naming pattern is enforced by the validator. The full list is exactly the
`texture_path` of every entry in `data/parts_db.json`; that file is the manifest,
so it cannot drift from what the game loads.

Beyond the parts:

| Group | Files |
|---|---|
| Tiles | `tile_ground`, `tile_climbable`, `tile_cracked`, `tile_oneway`, `tile_hazard`, `tile_rope`, `paper_bg` |
| FX | `fx_ink_blob`, `fx_ink_drop`, `fx_blueprint_sketch`, `fx_correction_fluid`, `fx_spit` |
| UI | door and marker glyphs used by the level editor and the exit |

### 6.3 What "placeholder" means here

Every file listed above exists today, generated by
`tools/generate_placeholders.gd`, and every one passes the validator. They are
honest stand-ins, not final art: each silhouette is derived from that part's own
hurtbox in `parts_db.json`, so a placeholder is exactly as big as the thing it
represents and the camera framing, the collider fitting and the reach maths are
all already correct.

Replacing one is a file swap with no code change. The validator will tell you if
a replacement breaks the palette, the canvas size, the naming or the import
settings. What the hand-drawn pass owes each part is character — ASSET_SPEC §3's
wobbling, over-confident line — not different dimensions.
