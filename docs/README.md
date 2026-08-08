# Scribblestein — Specification Index (v2.0, decisions locked 2026-08-08)

Agent reading order:
1. `MANDATES.md` — non-negotiable rules. In context for EVERY task.
2. `DESIGN.md` — the game, with the 12-entry Decision Log resolving all open
   questions. Do not reopen decided items.
3. `TECH_SPEC.md` — engine pins, creature architecture, physics layers, InputMap,
   camera formula, save schema, JSON loading rules.
4. `MILESTONES.md` — build order M0→M7 (+M8 post-slice), each with acceptance
   criteria.
5. `ASSET_SPEC.md` — before touching any texture or sound.

Gameplay data lives at the repo root in `../data/` (= `res://data/` once
`project.godot` exists): `parts_db.json` (+ schema), `blueprints.json`,
`effects.json`, `enemies.json`, `game_config.json`.

Conflict precedence: MANDATES > data JSON > TECH_SPEC > DESIGN > MILESTONES —
and contradictions get flagged to a human in `/DECISIONS_NEEDED.md`, never
silently resolved. This spec supersedes the original Google-Doc GDD entirely.
