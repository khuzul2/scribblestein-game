# Scribblestein

A 2D modular platformer / creature-creator (metroidvania-lite) for **Godot 4.7**.
Build a Frankenstein creature from badly drawn body parts — the assembly IS the
character sheet. Stark black-and-white "ignorant style" pencil-sketch aesthetic
with a line-boil shader over perfectly smooth physics.

**Status:** vertical slice playable. Milestones M0–M7 are implemented and their
acceptance criteria pass; the art and audio are validator-compliant
*placeholders* awaiting a human pass (see **What is and is not finished**).

## For the coding agent
Start with [`CLAUDE.md`](CLAUDE.md). Then build `docs/MILESTONES.md` M0 → M7 in
order; every milestone ends with acceptance criteria that must demonstrably pass.

## For humans
- Game design (all decisions resolved): [`docs/DESIGN.md`](docs/DESIGN.md)
- Non-negotiable rules: [`docs/MANDATES.md`](docs/MANDATES.md)
- Architecture & pins: [`docs/TECH_SPEC.md`](docs/TECH_SPEC.md)
- Build order + acceptance criteria: [`docs/MILESTONES.md`](docs/MILESTONES.md)
- Art & audio spec: [`docs/ASSET_SPEC.md`](docs/ASSET_SPEC.md)

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
```

## What is and is not finished

**Finished:** every system the vertical slice needs — assembly, locomotion, the
camera, combat, the enemy FSM, the economy and corpse run, save/load, the Lab,
the Scratchpad and Level 01 — with the acceptance criteria of M0–M7 checked by
`tools/acceptance.sh`.

**Placeholder:** the art and the audio. `tools/generate_placeholders.gd` and
`tools/generate_placeholder_audio.gd` produce every texture and sound the game
references, palette-exact and named per `ASSET_SPEC.md`, but they are generated
stand-ins for hand-drawn linework and recorded mouth noises. Replacing a file
requires no code change; the validator will tell you if a replacement breaks the
palette, the canvas size or the naming.

**Spec contradictions:** six contradictions inside the spec pack were written up
in [`DECISIONS_NEEDED.md`](DECISIONS_NEEDED.md) rather than resolved silently,
and all six were ruled on before M8 — the Light weight class is now reachable, the
starter bite can hit every enemy, and a dodge roll traverses a crawl tunnel. Boot
validation raises zero issues, `data/validation_waivers.json` is empty, and
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
