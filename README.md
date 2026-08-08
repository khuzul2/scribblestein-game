# Scribblestein

A 2D modular platformer / creature-creator (metroidvania-lite) for **Godot 4.4**.
Build a Frankenstein creature from badly drawn body parts — the assembly IS the
character sheet. Stark black-and-white "ignorant style" pencil-sketch aesthetic
with a line-boil shader over perfectly smooth physics.

**Status:** design complete & locked · implementation starts at Milestone 0.

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

## Requirements
Godot **4.4.x** (Compatibility renderer). Validate data + assets headlessly:
`godot --headless -s tools/validate_assets.gd` (available after M0).

## Building & checking locally

Requires Godot **4.4.1** on `PATH` as `godot`.

```bash
godot --headless --import                       # import assets (run twice on a clean clone)
godot --headless -s tools/validate_assets.gd    # palette / canvas / naming / import settings
godot --headless -s tools/generate_placeholders.gd  # regenerate placeholder art (deterministic)
godot --headless -s tools/run_tests.gd          # unit tests
./tools/acceptance.sh                           # milestone acceptance criteria
godot --headless --quit                         # boot smoke test
```

CI (`.github/workflows/ci.yml`) runs all of the above on every push.

Unresolved contradictions between spec sources are recorded in
[`DECISIONS_NEEDED.md`](DECISIONS_NEEDED.md); any that are waived to keep the
build moving are listed in `data/validation_waivers.json` and printed on every boot.
