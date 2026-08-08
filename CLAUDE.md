# CLAUDE.md — Scribblestein Agent Operating Manual

You are building **Scribblestein**: a 2D creature-builder platformer in **Godot 4.4**,
monochrome hand-sketched aesthetic. The design phase is COMPLETE. Do not redesign;
implement.

## Session start (every time)
1. Read `docs/MANDATES.md` — non-negotiable rules. If a task conflicts with a
   mandate, the mandate wins.
2. Read the Decision Log in `docs/DESIGN.md` §0 — these 12 questions are settled.
   Do not reopen them.
3. Check `docs/MILESTONES.md` for the current milestone and its acceptance criteria.

## Repository layout
- **Repo root = Godot project root.** Create `project.godot` here in Milestone 0.
- `data/` = `res://data/` — the single source of truth for every gameplay number
  (parts, enemies, tuning, blueprints, effects). NEVER hardcode a balance value in
  GDScript; if you need a number, it lives in `data/game_config.json` or a data file.
- `docs/` — full spec: DESIGN, MANDATES, TECH_SPEC, MILESTONES, ASSET_SPEC.
- `assets/`, `scenes/`, `scripts/`, `tools/` — create per `docs/TECH_SPEC.md` §2.

## Workflow rules
- Execute milestones **M0 → M7 strictly in order**. A milestone is DONE only when
  every acceptance criterion in `docs/MILESTONES.md` demonstrably passes. Write the
  checks as runnable headless scripts or tests wherever possible; manual-only ACs
  get a written verification note in the PR/commit description.
- Commit in milestone-scoped chunks, messages prefixed `M{n}: `.
- Required validations (from M0 onward, and in CI):
  - `godot --headless --import` completes clean.
  - `godot --headless -s tools/validate_assets.gd` exits 0 (palette / canvas /
    naming / import-settings checks per `docs/ASSET_SPEC.md` §5).
  - Debug boot performs JSON schema + cross-reference validation
    (`docs/TECH_SPEC.md` §9) — crashing loudly on bad data is REQUIRED behavior,
    not a bug.
- **Spec conflicts:** precedence is MANDATES > `data/*.json` > TECH_SPEC > DESIGN >
  MILESTONES. Never resolve a contradiction silently — record it in a root-level
  `DECISIONS_NEEDED.md` and pause that thread for a human.

## Code style
- GDScript with static typing everywhere; set `untyped_declaration = error`.
- One class per file; `class_name` for shared types. Signals over polling.
- All textures import with `filter = Nearest`, `mipmaps = off` (set repo-wide
  import defaults in M0).
- Placeholder art must already pass the asset validator (pure black + transparent
  only) — see `docs/ASSET_SPEC.md` §4. No colored dev textures, ever.

## Hard "never" list (abridged — full text in docs/MANDATES.md)
- Never anti-alias, never use grays/gradients in gameplay pixels.
- Never quantize physics/transform motion — only the boil shader stutters (8–12 FPS).
- Never fork a separate enemy implementation — one creature scene, controller-swapped.
- Never frame-by-frame sprite-swap body animation — Skeleton2D/Bone2D only.
- Never hardcode stats, hitboxes, timings, costs — JSON only.
- Never enable a `damage` hitbox outside an attack's active window.

## Out of scope unless explicitly asked
Everything under "Backlog" at the end of `docs/MILESTONES.md` (asymmetric arms,
mid-level rebuild stations, checkpoints, rebinding UI, pre-baked boil, third
blueprint, contact-damage parts, NG+).
