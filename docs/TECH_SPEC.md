# SCRIBBLESTEIN — Technical Specification v2.0

## 1. Engine & Project Pins

- **Godot 4.7.x** (pin the exact minor in `project.godot`; do not float on "4.x").
  Raised from 4.4.x by explicit instruction; the whole suite passes unchanged on
  4.7.1, so the pin moved rather than the code.
- **Renderer:** Compatibility (GL) — trivial 2D load, keeps a future web export open.
- **Design resolution:** 1920×1080, `canvas_items` stretch, aspect `keep`.
- **Physics:** 60 Hz fixed tick. Creatures are `CharacterBody2D`.
- **GDScript:** static typing mandatory (`untyped_declaration = error` in project
  settings). One class per file, `class_name` for shared types.
- **Textures:** import filter Nearest, mipmaps off (repo-wide import defaults).

## 2. Repository Layout

```
res://
  data/            # all JSON (this pack's data/ folder drops in here)
  assets/
    parts/{torsos,heads,legs,arms,tails,backs}/
    tiles/  ui/  fx/
    audio/{sfx,music}/
  scenes/
    creature/      # creature.tscn + assembler
    lab/           # hub, editor UI, scratchpad
    levels/        # level_01_margins.tscn ...
    ui/
  scripts/
    core/          # json_loader.gd, save_manager.gd, config.gd
    creature/      # creature.gd, part_assembler.gd, weight_class.gd,
                   # attack_controller.gd, health.gd, player_input.gd, ai_brain.gd
    fx/            # line_boil.gdshader
  tools/           # validate_assets.gd (see ASSET_SPEC.md §5)
```

## 3. Creature Scene Architecture (one scene for player AND enemies)

```
Creature (CharacterBody2D)                 creature.gd
├─ Skeleton2D                              bones per blueprints.json
│   └─ Bone2D* (root/torso/head/...)       part Sprite2Ds bound per slot
├─ HitboxRoot (Node2D)                     part_assembler.gd spawns Area2Ds here,
│   ├─ Hurtbox (Area2D)                    parented to follow their bone transform
│   └─ DamageBox* (Area2D, disabled)       enabled only during active attack phase
├─ Health (Node)                           hp, i-frames, death signal
├─ AttackController (Node)                 windup/active/recovery state machine
├─ WeightClass (Node)                      recompute on assembly, exposes preset
└─ Controller (ONE of:)
    ├─ PlayerInput (Node)                  reads InputMap
    └─ AIBrain (Node)                      FSM per enemies.json ai profile
```

**Assembly flow:** `assemble(loadout: Dictionary)` → clear slots → for each slot:
load part JSON → bind texture to slot's bone (offset from `blueprints.json`
`attach` + part's `pivot`) → spawn hitbox Areas in bone-local space → recompute
weight class, max HP, defense → emit `assembled` (camera re-frames, UI refreshes).
Enemies call the identical function with their `assembly` from `enemies.json`.

**AIBrain FSM (v1):** `PATROL` (walk, flip at edge/wall) → `CHASE` when player within
`aggro_radius` and roughly line-of-sight → `ATTACK` when within `attack_range`
(fires the same AttackController) → `COOLDOWN` → re-evaluate. Fliers substitute
hover-patrol; parameters entirely from `enemies.json`.

## 4. Physics Layers

| # | Name | Notes |
|---|------|-------|
| 1 | `world` | tiles, one-way platforms |
| 2 | `world_cracked` | breakable by Heavy landing (≥ landing speed threshold) |
| 3 | `climbable` | wall regions valid for `can_climb` |
| 4 | `player_body` | body collision only (no damage semantics) |
| 5 | `enemy_body` | bodies push, never hurt (Decision 4) |
| 6 | `player_hurtbox` | receives enemy damage boxes |
| 7 | `enemy_hurtbox` | receives player damage boxes |
| 8 | `player_damage` | active only during player attack windows |
| 9 | `enemy_damage` | active only during enemy attack windows |
| 10 | `pickup` | ink, correction fluid, blueprints, death blob |
| 11 | `hazard` | spikes etc. — always-on env damage (env is exempt from B5) |

## 5. InputMap (exact action names)

`move_left` (A, LS-left) · `move_right` (D, LS-right) · `climb_up` (W, LS-up) ·
`crouch_roll` (S, LS-down) · `jump_glide` (Space, gamepad A) ·
`attack_primary` (LMB, J, gamepad X) · `attack_secondary` (RMB, K, gamepad B) ·
`interact` (E, gamepad Y) · `pause` (Esc, Start).
Full gamepad support ships in v1; no rebinding UI in the slice (post-slice).

## 6. Camera Formula (Mandate A4)

```
bbox   = creature visual bounding box height in px (recomputed on assemble)
target = clamp(REF_HEIGHT / bbox, ZOOM_MIN, ZOOM_MAX)     # REF_HEIGHT = 420
zoom   = lerp(zoom, target, CAMERA_LERP * delta)          # CAMERA_LERP = 3.0
```
Constants live in `game_config.json → camera`. Position smoothing on, drag margins
0.1/0.1, look-ahead 80 px in facing direction.

## 7. Line Boil Shader (Mandate A3)

`line_boil.gdshader` (canvas_item), applied to all sprites & tile layers:
- `uniform boil_fps = 10.0` (clamp 8–12), `uniform amplitude_px = 2.5`,
  `instance uniform seed` (randomized per sprite at ready).
- `t = floor(TIME * boil_fps) / boil_fps` → hash(t, seed) → UV offset within
  ±amplitude. Because `t` is floored, the wobble stutters at boil FPS while
  transforms stay smooth. Amplitude halves on UI text for legibility.

## 8. Save File (`user://save.json`)

```json
{
  "version": 2,
  "ink": 0,
  "unlocked_parts": ["torso_ribby", "legs_scribble_sprint", "head_monster_maw"],
  "blueprints_found": [],
  "kill_counters": { "enemy_scribble_grunt": { "kills": 0, "since_drop": 0 } },
  "loadouts": {
    "biped":     { "torso": "torso_ribby", "legs": "legs_scribble_sprint",
                   "head": "head_monster_maw", "tail": null, "arms": null, "back": null },
    "quadruped": { "torso": null, "legs_front": null, "legs_rear": null,
                   "head": null, "tail": null, "back": null }
  },
  "active_blueprint": "biped",
  "blueprint_unlocked": ["biped"],
  "levels": {
    "level_01_margins": { "completed": false,
                          "death_blob": { "x": 0, "y": 0, "amount": 0 } }
  },
  "settings": { "volume_master": 1.0, "volume_music": 0.8, "volume_sfx": 1.0 }
}
```
`death_blob: null` when none. Save on: level complete, death, unlock, exit-to-lab,
loadout change. Atomic write (write temp → rename).

**Version 2 (M9).** The two body types have different slots, so a single
`loadout` could not hold both: it became `loadouts`, keyed by blueprint id, with
`active_blueprint` naming the one being built and played. `_migrate` folds a
version-1 save's `loadout` into `loadouts.biped` and drops the old key, so no
build is lost. Each stored loadout is rebuilt against its blueprint's current
slots on load — slots the blueprint no longer has are dropped, new ones arrive
null, and a part that no longer exists in `parts_db.json` is cleared — so
assembly can never be handed a shape it cannot build.

Unlocking a blueprint also grants every zero-cost part that fits it
(`Config.free_part_ids`), because a body type whose required slots have no
affordable part would be dead on arrival.

## 8b. Level Files (`data/levels/<id>.json`, `user://levels/<id>.json`)

One file per level, schema in `data/level.schema.json`. A level is data: geometry,
inhabitants, rewards, signage and soundtrack, in world pixels with +Y down, so a
number in the file compares directly against a jump reach.

```json
{
  "schema": 1,
  "id": "level_01_margins",
  "name": "The Margins",
  "order": 1,
  "spawn": [-420, -80],
  "terrain": [{ "kind": "solid", "points": [[0,0], [400,0], [400,200]] }],
  "ropes":   [{ "at": [900, -600], "length": 500 }],
  "enemies": [{ "id": "enemy_scribble_grunt", "at": [620, -120],
                "facing": -1, "patrol": 420 }],
  "pickups": [{ "kind": "ink", "at": [400, -60], "amount": 15 }],
  "doors":   [{ "kind": "exit", "at": [5500, 1420] }],
  "signs":   [{ "at": [0, -300], "text": "mind the gap" }],
  "music":   { "tracks": ["intro.ogg"], "shuffle": false, "crossfade_seconds": 1.5 }
}
```

**Terrain** is free-form polygons, not tiles. `kind` picks the physics layer and
the tile texture in one: `solid` · `oneway` (solid from above only) · `climbable`
(solid, plus a `climbable` marker area) · `cracked` · `hazard` (an area that
hurts, not a body that stops you). The outline you draw is the outline you
collide with.

**Where they live.** `res://data/levels/` ships with the game;
`user://levels/` is what the editor writes in an exported build.
`LevelData.find` prefers the user copy, so an edited level shadows the shipped
one rather than replacing it.

**Loading.** `DataLevel` (a `PlayScene`) builds any of these. `Game.goto_level`
prefers a level file over a hand-coded scene, so porting a level to the editor's
format is a matter of writing the file.

**Proving a level.** Hand-coded levels had their gaps as GDScript constants to
compare against `JumpMath`. Drawn ones do not, so `LevelGeometry` recovers the
same numbers from the polygons — walkable surfaces, gaps and their drops,
head-room, and a conservative walk-and-jump reachability sweep from the spawn to
the exit. That is what keeps DESIGN §9's lock-and-key promise checkable now that
levels are drawn rather than typed.

**Soundtracks.** `music.tracks` are file names inside
`user://music/<level id>/`, capped at five by the schema. The editor copies
whatever the player picks into that folder, so a level file stays small and
portable and the audio stays out of the repository. `MusicDirector` loads them
at runtime (`.ogg` / `.mp3` / `.wav`) — they arrive after the game is built, so
the importer never sees them. A missing track is skipped with a named warning,
never a crash.

## 9. JSON Loading Rules (Mandate B1)

- `json_loader.gd` loads `data/*.json` at boot into a read-only `Config` singleton.
- Debug builds: validate `parts_db.json` against `parts_db.schema.json`; structurally
  check blueprints/enemies (unknown part ids, unknown slots, unknown effects →
  crash with file + path + reason). Release builds: log and refuse to start on error.
- Cross-reference checks: every `effects[]` entry must exist in `effects.json`;
  every enemy assembly part must exist and fit the enemy's blueprint.
