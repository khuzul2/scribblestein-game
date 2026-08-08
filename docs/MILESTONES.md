# SCRIBBLESTEIN — Milestones & Acceptance Criteria v2.0

## Vertical Slice Definition ("done" for phase one)

One playable build containing: Misshapen Biped blueprint · all 14 v1 parts ·
3 enemy types · The Lab (editor + Scratchpad + unlock desk + map table) ·
Level 01 "The Margins" · full loop (build → test → level → fight → ink/blueprints →
corpse run → unlock → rebuild) · line boil + monochrome + core SFX set · save/load.
Quadruped blueprint is explicitly OUT of the slice (it lands in M9).

Each milestone below is agent-executable and ends with testable acceptance criteria
(AC). Do not start milestone N+1 with failing AC in milestone N.

## M0 — Project Bootstrap
Godot 4.4 project per `TECH_SPEC.md` §1–2; JSON loader + boot validation; asset
validator tool; CI (headless import + validator + boot smoke test).
**AC:** corrupting any value in `parts_db.json` (e.g. `"weight": "heavy"`) makes a
debug boot crash naming file, JSON path, and reason. A test PNG containing one gray
pixel fails `tools/validate_assets.gd`. Clean repo boots to an empty scene.

## M1 — Skeleton & Assembly
Biped `Skeleton2D` per `blueprints.json`; `part_assembler.gd`; placeholder part
textures (validator-compliant scribbles are fine); hitboxes spawned from JSON in
bone-local space; debug overlay drawing all hitboxes.
**AC:** changing `loadout.head` in save JSON changes sprite, hitboxes, HP and weight
with zero scene edits. Debug overlay shows hitboxes within 1 px of JSON offsets and
rotating with their bones. Removing `legs` from a loadout is rejected with a clear
error (required slot).

## M2 — Locomotion & Camera
Movement per weight-class presets in `game_config.json`; coyote time; jump buffer;
glide; climb; roll/crouch; cracked-floor break for Heavy; camera formula.
**AC:** measured jump apex per class within 5% of
`jump_velocity²/(2·gravity)`. Jump pressed ≤ `coyote_time` after leaving a ledge
still fires. Glide caps fall speed at `glide_fall_cap` only while `jump_glide` held
with a glide part. Heavy landing on `world_cracked` from ≥ threshold breaks it;
Light/Medium never do. Camera zoom hits the §6 formula target for a min-size and
max-size creature.

## M3 — The Lab & Scratchpad
Sketchbook editor UI (drag-drop, filtered part list, stat readouts, class stamp);
Play in Lab ↔ editor round trip; Scratchpad room with dummy enemy and one of each
lock type; unlock desk (spend ink); world map table.
**AC:** editor→Scratchpad→editor round trip ≤ 3 s, loadout intact. Dropping a part
on a wrong slot snaps back with `sfx_ui_error_scratch`. Stat readouts always equal
recomputed values. Unlocking deducts the exact `unlock_cost` and persists.

## M4 — Combat
AttackController phase machine (windup/active/recovery/cooldown from part JSON);
damage formula; hitstun/knockback/i-frames; AIBrain FSM; all 3 enemies assembled
from `enemies.json`.
**AC:** DamageBox areas are enabled only during active phase (verifiable in debug
overlay). Bite (35 atk) vs Grunt (0 def, 60 hp) kills in exactly 2 hits; vs a
5-defense target in exactly 2 hits (30 dmg each); formula floor holds
(atk ≤ def deals 1). Player i-frames 0.5 s: overlapping enemy re-hits only after.
Each enemy patrols, chases within `aggro_radius`, attacks within `attack_range`.

## M5 — Economy, Death & Save
Ink pickups + wallet; corpse-run blob (persist per level across restarts and hub
trips, overwrite on second death); pity-timer blueprint drops; duplicate→ink
conversion; Correction Fluid; full save/load per `TECH_SPEC.md` §8.
**AC:** die with 47 ink → blob(47) at death spot; quit to Lab, relaunch game,
re-enter level → blob still there; die again elsewhere before recovery → only new
blob exists. Killing 6 Grunts with forced-fail RNG yields the blueprint on kill 6
and resets the counter. Blueprint drop when already unlocked grants +15 ink and no
sketch. Correction Fluid heals 25, despawns at 10 s.

## M6 — Aesthetics & Audio
Line boil shader on all sprites/tiles with per-instance seeds; paper background;
core SFX set + 2 synth loops wired (`ASSET_SPEC.md` §6); final art pass on the 14
parts, tiles, and UI.
**AC:** boil visibly steps at 8–12 FPS while a moving creature's transform is
smooth (record 1 s at 60 fps: sprite position changes every frame, UV wobble ~6
times… i.e. every 6th frame at 10 fps). Every shipped texture passes the validator.
A fullscreen screenshot contains only palette colors from `ASSET_SPEC.md` §2.
All UI interactions and creature actions have their mapped SFX.

## M7 — Level 01 "The Margins" + Slice Polish
Handcrafted level using glide + climb gates, a cracked-floor secret, a crawl
tunnel, all 3 enemies, warning-sketch signage; level select flow; pause/return;
difficulty & economy tuning pass.
**AC:** completable with the intended loadouts; the glide gate is provably
impassable without a glide part (jump math check); a first-time playtester finishes
in 5–10 min; clearing marks completion on the map and persists.

---

# Phase two — post-slice

Scope set by the project owner after the vertical slice shipped: move to Godot
4.7, settle every open decision, build the full part catalogue for both body
types, add an interactive level editor, and give each level its own soundtrack.
The rulings behind these milestones are in `/DECISIONS_NEEDED.md`; the ones that
shaped the work are noted inline.

## M8 — Engine 4.7.1 + decision resolutions
Pin **Godot 4.7.1** (`project.godot`, CI, TECH_SPEC §1, README); resolve D1, D2,
D4, D5, D6 per the owner's rulings; empty `validation_waivers.json`; add
`tests/test_decisions.gd` so no ruling can silently regress.
**AC:** the whole suite, the asset validator and every acceptance check pass on
4.7.1. Boot validation reports **zero** issues — no errors and no warnings. The
Light weight class is reachable, every part has a hurtbox, every part fits a
blueprint that has its slot, and a rolling creature crosses a 900 px crawl tunnel
while a non-ducking one is stopped by it.

## M9 — Crooked Quadruped, full parity
Real second `Skeleton2D` rig (the `STUB` marker comes off `blueprints.json`);
pounce movement profile; blueprint unlock flow; `fits_blueprints` filtering in
the Lab; active blueprint persisted in the save.
**AC:** switching blueprints in the Lab re-rigs correctly; biped-only parts are
hidden for the quadruped and vice versa; the save round-trips the active
blueprint; every quadruped required slot has at least one part that fills it.

## M10 — The part catalogue
`docs/PARTS_TREE.md`: the full list/tree of every part and every art file for
both body types. ~60 parts across legible archetypes (heavy/brawler,
light/agile, ranged, utility/traversal, glass-cannon), each carrying a distinct
effect or attack rather than only a stat delta. Dedicated `legs_front` /
`legs_rear` parts for the quadruped (D2). Validator-clean placeholder art for
every one.
**AC:** every slot of both blueprints offers at least four legal parts; every
archetype is reachable; every weight class is reachable on both blueprints; the
asset validator passes on the whole catalogue; boot validation stays at zero
issues; a crawl tunnel is a real lock again — at least one `legs` part grants
neither `dodge_roll` nor `crouch` (D6's recorded consequence).

## M11 — Interactive level editor
In-game editor scene in the sketchbook aesthetic, reached from the main menu.
Free-form polygon terrain drawing; one-way platforms; climbable walls; ropes;
spawn and exit door; enemy placement with per-instance facing and patrol range;
pickups, ink caches and cracked floors; hazards; warning sketches. Pan/zoom,
undo/redo, and a Playtest button that enters the level with the current build.
Levels are one JSON file each under `res://data/levels/`, with editor saves in
`user://levels/`; a runtime loader builds any level from that file, and a
geometry analyser measures gaps, ceilings and clearances from the polygon soup
so `JumpMath` gate proofs keep working without hand-coded rectangles.
**AC:** a level drawn in the editor saves, reloads and plays identically; the
loader reproduces the geometry within a pixel; the analyser's measured gap for a
known level matches the drawn one; undo/redo round-trips every tool; an editor
level with an unreachable exit is reported before it can be played.

## M12 — Soundtrack system
Up to five tracks per level. A file picker copies `.ogg` / `.mp3` / `.wav` into
`user://music/<level_id>/`; the level JSON references them by name. Ordered
playlist with crossfade at track end, plus a per-level shuffle toggle. Editor UI
for adding, reordering and removing tracks.
**AC:** five tracks attach to a level, survive a save/reload, and play in the
authored order; shuffle changes the order without repeating a track inside a
cycle; a missing or unreadable file degrades to silence with a named warning
rather than crashing; a sixth track is refused with a clear message.

## M13 — Integration and final verification
Level 01 ported to the editor's format; full acceptance run on 4.7.1; docs
updated.
**AC:** every earlier milestone's AC still passes; Level 01 plays identically
from data; the autopilot clears it.

## Backlog (explicitly not scheduled)
Asymmetric arm slots · mid-level rebuild stations · checkpoints inside levels ·
input rebinding UI · pre-baked boil frames for hero parts · third blueprint ·
contact-damage part effect ("Spiky Hide") · NG+ modifiers.
