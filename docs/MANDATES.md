# SCRIBBLESTEIN — STRICT AGENT MANDATES v2.0

These rules are NON-NEGOTIABLE. Any implementation, refactor, or asset that violates
them is wrong even if it "works" or "looks better". When a mandate and convenience
conflict, the mandate wins. NEVER implement clean, standard, or modern game aesthetics.

## A. Aesthetics & Audio

### A1. Rule of Color (Monochrome Only)
- Gameplay pixels are ONLY pure black `#000000` and paper white/off-white
  (background `#F4F0E6`, see `ASSET_SPEC.md`).
- No grayscale, no gradients, no anti-aliasing, no partial alpha.
- Enforcement is **asset discipline, automated**: the asset validator
  (`ASSET_SPEC.md §5`) MUST pass in CI and MUST be run before any texture is
  committed. A sprite with a single gray or semi-transparent pixel is a build failure.
- Texture import settings: `filter = Nearest`, `mipmaps = off`, everywhere.

### A2. Rule of Linework ("Ignorant Style")
- All sprites and environment tiles must look hand-drawn, jagged, uneven, and
  slightly wrong. Wobbly outlines, inconsistent stroke weight, visible construction
  lines are features. Never vector-clean, never symmetric.

### A3. Rule of Animation ("The Line Boil")
- A Godot `CanvasItem` shader jitters UVs of static textures, with the jitter value
  **snapped to 8–12 FPS steps** (default 10). Parameters in `TECH_SPEC.md §7`.
- Each sprite instance gets a **random phase seed** so parts never boil in sync.
- The boil is strictly visual: **underlying transforms, physics, and camera remain
  perfectly smooth at full frame rate.** Never quantize positions or physics.

### A4. Rule of Camera (Dynamic Framing)
- `Camera2D` zoom is driven by the assembled creature's bounding box
  (formula in `TECH_SPEC.md §6`). Big creature → wide view; tiny creature → tight.
- Zoom changes are smoothed (lerp), never snapped, never quantized by the boil.

### A5. Rule of Audio (Raw & Diegetic)
- SFX are literal, organic, human: pencil scratches and paper tears for UI, rhythmic
  scribbling for footsteps, pitch-shifted mouth noises (beatbox pops, grunts) for
  creatures. Music: heavy, minimalist analog synth beats (Bla Bla Bla homage).
- FORBIDDEN: generic royalty-free weapon clangs, standard RPG UI chirps, orchestral
  or "epic" music, realistic foley. Full required SFX list: `ASSET_SPEC.md §6`.

## B. Gameplay, Logic & Rigging

### B1. Rule of Data (The JSON Mandate)
- ALL stats, parts, hitboxes, attacks, enemies, blueprints, tuning values, and drop
  tables live in legible JSON under `res://data/`. No gameplay numbers hardcoded in
  GDScript. If you find yourself typing a balance number in code, move it to JSON.
- JSON is validated against `data/parts_db.schema.json` (and structural checks for
  the other files) **at boot in debug builds**; validation failure must crash loudly
  with the offending file, key, and reason. Silent defaults are forbidden.

### B2. Rule of Universal Entities (Player = Enemy)
- One creature scene, one assembly pipeline. Player and enemies differ ONLY in the
  controller component attached (PlayerInput vs AIBrain). Damage, hitboxes, weight
  class, effects — identical code paths. Never fork a special enemy implementation.

### B3. Rule of Rigging (Skeleton2D / Bone2D)
- Every creature is a `Skeleton2D` with `Bone2D` nodes per `data/blueprints.json`.
  Part sprites bind to bones. Animation = bone rotation/position via `AnimationPlayer`
  or procedural code. NEVER frame-by-frame sprite-sheet swapping for body movement.

### B4. Rule of Modularity
- Abilities, stats, and hitboxes come exclusively from equipped parts' JSON.
  Hitbox shapes are generated at assembly time from part data, in **bone-local
  space** (they rotate with the bone). Nothing about a creature's capability is
  hardcoded in a scene.

### B5. Rule of Combat Timing (Decision 4)
- `damage` hitboxes are instantiated dormant and enabled ONLY during the attack's
  active window. `hurtbox` hitboxes are always live (minus i-frames).

### B6. Rule of Feel
- Input → movement response within 1 physics tick. Coyote time and jump buffering
  are mandatory (values in `game_config.json`). The sketchy look must never make
  controls feel sketchy.
