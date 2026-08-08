# Scribblestein

A 2D modular platformer / creature-creator (metroidvania-lite) for **Godot 4.7**.
Build a Frankenstein creature from badly drawn body parts — the assembly IS the
character sheet. Stark black-and-white "ignorant style" pencil-sketch aesthetic
with a line-boil shader over perfectly smooth physics.

**Status:** playable. Milestones M0–M13 are implemented and their acceptance
criteria pass; the art and audio are validator-compliant *placeholders* awaiting
a human pass (see **What is and is not finished**).

## For the coding agent
Start with [`CLAUDE.md`](CLAUDE.md). Then build `docs/MILESTONES.md` M0 → M13 in
order; every milestone ends with acceptance criteria that must demonstrably pass.

## For humans
- Game design (all decisions resolved): [`docs/DESIGN.md`](docs/DESIGN.md)
- Non-negotiable rules: [`docs/MANDATES.md`](docs/MANDATES.md)
- Architecture & pins: [`docs/TECH_SPEC.md`](docs/TECH_SPEC.md)
- Build order + acceptance criteria: [`docs/MILESTONES.md`](docs/MILESTONES.md)
- Art & audio spec: [`docs/ASSET_SPEC.md`](docs/ASSET_SPEC.md)
- Every part and every art file: [`docs/PARTS_TREE.md`](docs/PARTS_TREE.md)

## Layout
The repo root is the Godot project root (`project.godot` lands here in M0), so
`data/` is `res://data/` — the single source of truth for every gameplay number:
parts, blueprints, effects, enemies, and all tuning values. No balance numbers in
code, ever.

## Playing it

```bash
godot --headless --import          # once, on a fresh clone (run twice)
godot                              # boots into The Lab
```

The loop: build a creature in the sketchbook, **PLAY IN LAB** to try it in the
Scratchpad, **WORLD MAP** to enter *The Margins*, kill things for DNA Ink and
Blueprint Sketches, come back, spend the ink at the **UNLOCK DESK**, rebuild.

| Action | Keys |
|---|---|
| Move | `A` / `D` |
| Jump · glide (hold) · double jump (tap in air) | `Space` |
| Climb | `W` |
| Roll / crouch | `S` |
| Attack primary (head) · secondary (tail) | `LMB` / `J` · `RMB` / `K` |
| Interact · pause | `E` · `Esc` |

Gamepad is bound throughout. Dying drops your whole wallet as an ink blob where
you fell; it waits there until you fetch it, and dying again loses the old one.

Useful development entry points:

```bash
godot -- --scene=lab                 # straight to the hub
godot -- --scene=level_01_margins    # straight into the level
godot -- --scene=rig_preview --hitboxes   # inspect a rig and its hitboxes
godot -- --scene=editor --level=level_01_margins   # the level editor
```

## What is and is not finished

**Finished:** every system the vertical slice needs — assembly, locomotion, the
camera, combat, the enemy FSM, the economy and corpse run, save/load, the Lab,
the Scratchpad and Level 01 — with the acceptance criteria of M0-M7 checked by
`tools/acceptance.sh`.

Since the slice (M8–M13, all checked by the same script): Godot 4.7.1 · both
body types playable, with the quadruped's own pounce profile · the full
**61-part catalogue** across 18 effects ([`docs/PARTS_TREE.md`](docs/PARTS_TREE.md))
· **levels as data**, with an in-game level editor that draws free-form terrain,
platforms, climbable walls, ropes, enemies, rewards, hazards and signage · and a
**per-level soundtrack** of up to five songs.

### The level editor

Reached from the Lab's world map (or `godot -- --scene=editor`). Draw terrain as
free-form polygons, place everything else by clicking, drag vertices to reshape,
undo anything. **Playtest** enters the level for real with the build currently in
the Lab and comes back to the editor; **Check** reports what is wrong before you
find out the hard way.

Levels are one JSON file each — `data/levels/` for the shipped ones,
`user://levels/` for yours, described in [`docs/TECH_SPEC.md`](docs/TECH_SPEC.md)
§8b. The editor writes exactly what the game reads, so a level that saves is a
level that plays. Songs are copied into `user://music/<level id>/` when you add
them, so a level file stays small and portable.

**Placeholder:** the art and the audio. `tools/generate_placeholders.gd` and
`tools/generate_placeholder_audio.gd` produce every texture and sound the game
references, palette-exact and named per `ASSET_SPEC.md`, but they are generated
stand-ins for hand-drawn linework and recorded mouth noises. Replacing a file
requires no code change; the validator will tell you if a replacement breaks the
palette, the canvas size or the naming.

**Spec contradictions:** eight are written up in
[`DECISIONS_NEEDED.md`](DECISIONS_NEEDED.md) rather than resolved silently. Six
came from the original spec pack and were ruled on by a human before M8; two more
(D7, D8) were found by the tests when the catalogue grew and were fixed in M10.
Boot validation raises zero issues, `data/validation_waivers.json` is empty, and
`tests/test_decisions.gd` pins every ruling.

## Requirements
Godot **4.7.x** (Compatibility renderer). Validate data + assets headlessly:
`godot --headless -s tools/validate_assets.gd` (available after M0).

## Building & checking locally

Requires Godot **4.7.1** on `PATH` as `godot`.

```bash
godot --headless --import                       # import assets (run twice on a clean clone)
godot --headless -s tools/validate_assets.gd    # palette / canvas / naming / import settings
godot --headless -s tools/generate_placeholders.gd  # regenerate placeholder art (deterministic)
godot --headless -s tools/run_tests.gd          # unit tests
./tools/acceptance.sh                           # milestone acceptance criteria
godot --headless --quit                         # boot smoke test
```

CI (`.github/workflows/ci.yml`) runs all of the above on every push.

Contradictions between spec sources are recorded in
[`DECISIONS_NEEDED.md`](DECISIONS_NEEDED.md) with their rulings; any that are
waived to keep the build moving are listed in `data/validation_waivers.json` and
printed on every boot. That file is currently empty — nothing is being waived.
