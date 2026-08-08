# DECISIONS_NEEDED

Contradictions between spec sources that the agent must not resolve silently
(`CLAUDE.md` → *Spec conflicts*). Each entry states the conflict, the sources,
the options, and the ruling.

Precedence when resolving: MANDATES > `data/*.json` > TECH_SPEC > DESIGN > MILESTONES.

**Status: all eight entries are resolved.** D1-D6 were ruled on by a human
before M8; D7 and D8 were found by the tests when the M10 catalogue landed and
fixed in that milestone. `data/validation_waivers.json` is empty and boot
validation raises zero issues. `tests/test_decisions.gd`,
`tests/test_catalogue.gd` and `tests/test_loadout_space.gd` pin every ruling so
none of them can quietly come back.

---

## D1 — `arms_noodle_hookers` carries `speed_boost`, an effect declared movement-only

- **Status:** RESOLVED in M8 — option 1.

**Conflict.** `data/parts_db.json → parts.arms_noodle_hookers` sits in slot `arms`,
which `data/blueprints.json → blueprints.biped.slots.arms` declares as
`kind: "utility"`. Its `effects` list contained `speed_boost`, and
`data/effects.json → effects.speed_boost.slot_kinds` was `["movement"]`, so a
strict reading made a working part illegal.

**Ruling.** `speed_boost` and `jump_boost` are now legal in every slot kind
(`core`, `movement`, `attack`, `utility`). They are UI icon flags for a `stats`
multiplier that `WeightClass` applies from any slot, so the slot restriction was
describing a mechanic that never existed. The waiver that downgraded this to a
warning has been deleted and the check is enforced at full strength again.

---

## D2 — `legs_tree_trunks` declared `fits_blueprints: ["biped", "quadruped"]` but quadruped has no `legs` slot

- **Status:** RESOLVED in M8 — option 1.

**Conflict.** The quadruped's slots are `torso, legs_front, legs_rear, head, tail,
back`. There is no `legs` slot, so a `legs` part could never be equipped there
despite declaring it fit.

**Ruling.** `legs_tree_trunks` is biped-only. The quadruped gets **dedicated
`legs_front` / `legs_rear` parts** in the M10 catalogue, so front and rear legs
can differ — a four-legged creature with sprinter forelegs and heavy haunches is
a build, not a rounding error. `tests/test_decisions.gd` now asserts that no part
anywhere claims a blueprint that has no slot for it, so the class of bug is
closed rather than the instance.

---

## D3 — "import filter Nearest, mipmaps off" is not a texture import option in Godot 4

- **Status:** RESOLVED — an engine-mechanics mapping, logged for visibility.

`ASSET_SPEC.md §5.4` and `MANDATES.md A1` require textures to import with
`filter = Nearest, mipmaps = off`. In Godot 3 both were import options; in
Godot 4 texture filtering moved off the importer and onto the project setting
`rendering/textures/canvas_textures/default_texture_filter` plus a per-CanvasItem
override. The intent is fully achievable, so this is a mapping, not a conflict:

- **Nearest:** `project.godot → rendering/textures/canvas_textures/default_texture_filter=0`,
  with every sprite left on `texture_filter = 0` (inherit).
- **Mipmaps off + no lossy compression:** `project.godot → [importer_defaults] texture`
  sets `mipmaps/generate=false`, `compress/mode=0` (lossless) and
  `detect_3d/compress_to=0`, so no pixel is ever resampled or block-compressed.

`tools/validate_assets.gd` checks all three, per-file and project-wide.

---

## D4 — the Light weight class was unreachable with the shipped part catalogue

- **Status:** RESOLVED in M8 — option 2.

**Conflict.** Light is `0–25` total weight, but `torso` and `legs` are both
required and the lightest legal pair was `torso_ribby` (20) +
`legs_scribble_sprint` (8) **= 28**. No player could ever be Light, so the whole
preset — `max_speed 340`, `jump_velocity -880`, `knockback_taken_mult 1.3` — was
dead content.

**Ruling.** A new light torso, **`torso_paper_husk`** (weight 15, 70 HP,
`jump_mod 1.05`, 60 ink), makes the lightest legal biped **23**. The starter build
stays Medium, so the opening feel is unchanged and Light is something you *build
towards* — which is the point of the part economy. `tests/test_decisions.gd`
asserts every weight class is reachable by some legal loadout, so adding a class
without a build that reaches it now fails the suite.

---

## D5 — the starter bite could not reach a grounded Stinger

- **Status:** RESOLVED in M8 — option 1.

**Conflict.** The Jagged Monster Maw's damage circle spans y **−455 … −365**.
`enemy_stinger` has no head, so its highest hurtbox — the torso — topped out at
**−360**. The two missed by 5 px, and the starter kit's only attack could not
damage a grounded Stinger at all.

**Ruling.** `back_bat_scraps` gained a hurtbox at the `back` bone
(`extents [50, 45]`, spanning −375 … −285), which closes the gap and reads
correctly: you bite the wings. Auditing for the same shape found
`back_sketch_thrusters` had **no hurtbox either** — both wing parts were
untouchable by anything in the game. It now has one too
(`extents [42, 38]`). `tests/test_decisions.gd` asserts that *every* part in the
catalogue has at least one hurtbox, and the boot validator's reach check keeps
proving that every starter attack can touch every enemy.

---

## D6 — a dodge roll could not fit through any crawl tunnel

- **Status:** RESOLVED in M8 — option 1. **Read the consequence below.**

**Conflict.** `DESIGN.md §9` lists the key for a low crawl tunnel as *"`crouch`
legs (or Light class + roll)"* and `effects.json → dodge_roll` promises a roll
*"fits under crawl tunnels only while rolling"*. Neither worked: a roll covers
190 px over 0.32 s with a 0.5 s cooldown, and a creature is 110–150 px wide, so
one roll clears at most ~80 px of overhang before the creature stands up inside
the ceiling with the cooldown ticking.

**Ruling.** Under an overhang the roll cooldown is suspended and *holding* crouch
keeps the roll going, so a roll traverses a tunnel of any length. A creature that
is already ducked also stays ducked while a ceiling is overhead, so a roll that
expires mid-tunnel crouch-walks out instead of wedging. `Locomotion` decides this
with a shape query of the creature's own **standing** body box at its current
position (`Creature.standing_body_box()`), inset 4 px so the floor underfoot and
a brushed wall never read as an overhang.

The gate is still a gate: a creature that can neither roll nor crouch walks into
the overhang and stops, which `tests/test_decisions.gd` proves.

**Consequence, recorded rather than hidden.** With the v1 catalogue, *all three*
`legs` parts granted `dodge_roll` or `crouch`, so once rolling actually worked a
crawl tunnel gated nothing. That was a property of having only three legs parts,
not of the ruling. **Closed in M10:** Ink Stilts, Pogo Nib and Anvil Boots grant
neither, so the tunnel is a real lock again — asserted by
`tests/test_catalogue.gd`.

---

## D7 — a glide gate is only a gate below a certain ledge height

- **Waiver id:** none — found by `tests/test_loadout_space.gd` when the M10
  catalogue landed, and fixed in the same milestone. Recorded because it changes
  how every future glide gate must be placed.
- **Status:** RESOLVED in M10.

**What went wrong.** Level 01's glide ledge sat 380 px below its launch lip, and
the gate was proved by "the worst glide build out-reaches the best non-glide
build". With 14 parts that held. With 61 it does not: the catalogue's best light
double-jumper reaches **513 px** at that drop, while the *worst* glide build — a
heavy creature wearing wings — manages only **465 px**. The gate silently became
passable by exactly the builds it was meant to exclude.

**Why.** Gliding is not "further than jumping"; it is *slower falling*. A glide
converts a drop into time at a fixed fall speed, so its reach grows **linearly**
with the drop, while a jump's grows with the **square root** of it. Below the
crossing point a fast jumper wins; above it, every glider beats every
non-glider. The crossing depends on the catalogue, so it moves whenever parts
are added.

**Ruling.** A glide gate must hang below the crossing. Level 01's ledge moved to
a drop of 800 px with a 750 px gap, where the best non-glide build reaches 612 px
and the worst glide build 892 px — daylight of 138 px and 142 px either side.
`tests/test_loadout_space.gd` now asserts that a crossing exists at all, and that
Level 01's own ledge hangs below it, so adding parts can never quietly reopen
this.

---

## D8 — a creature's body collider did not turn around with it

- **Waiver id:** none — a plain bug, found by the Level 01 autopilot in M10 and
  fixed there. Recorded because it was invisible for four milestones and its
  symptom looked like a level-design problem.
- **Status:** RESOLVED in M10.

**What went wrong.** The body collider is fitted to the union of the equipped
hurtboxes, which for anything with a tail is not symmetric — a Stinger's box
extends about 175 px further behind it than in front. The collider is a sibling
of the `Skeleton2D`, so the `scale.x` flip that turns a creature around never
reached it: the box stayed pointing whichever way the creature was first built.

A Stinger that turned to face the player therefore carried a slab of collider
sticking out of its **chest**, 120 px in front of any of its hurtboxes. It walled
off the chasm corridor in Level 01 and held the player outside its own attack
reach — an enemy that could neither be passed nor hit. The autopilot wedged
against it and the level became uncompletable.

**Fix.** `Creature` re-fits the collider whenever `facing` changes, reading the
already-flipped hurtboxes, so the box always describes where the creature
actually is. `tests/test_assembly.gd` asserts that a tailed creature's box
mirrors on turning and still contains every hurtbox.
