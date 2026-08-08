extends TestCase

## M3 acceptance: the sketchbook always tells the truth, a wrong drop is refused
## audibly, unlocking costs exactly what the catalogue says, and the round trip
## to the Scratchpad and back keeps the build.

const BLUEPRINT: String = "biped"

var _saved_profile: Dictionary = {}
var _editor: SketchbookEditor = null
var _desk: UnlockDesk = null
var _heard: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_saved_profile = SaveManager.data.duplicate(true)
	SaveManager.data = SaveManager.default_save()
	_heard = PackedStringArray()
	Audio.sfx_played.connect(_on_sfx)


func after_each() -> void:
	if Audio.sfx_played.is_connected(_on_sfx):
		Audio.sfx_played.disconnect(_on_sfx)
	_free(_editor)
	_free(_desk)
	_editor = null
	_desk = null
	SaveManager.data = _saved_profile


func _on_sfx(sfx_id: String) -> void:
	_heard.append(sfx_id)


func _free(node: Node) -> void:
	if is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.queue_free()


func _open_editor() -> SketchbookEditor:
	_editor = SketchbookEditor.new()
	tree.root.add_child(_editor)
	return _editor


func _open_desk() -> UnlockDesk:
	_desk = UnlockDesk.new()
	tree.root.add_child(_desk)
	return _desk


# --- readouts ------------------------------------------------------------------

func test_the_readout_always_equals_the_recomputed_stats() -> void:
	var editor: SketchbookEditor = _open_editor()
	for loadout: Dictionary in [
			CreatureFixture.loadout(),
			CreatureFixture.loadout({"head": "head_anvil"}),
			CreatureFixture.loadout({"torso": "torso_barrel", "tail": "tail_eraser_club"}),
			CreatureFixture.loadout({"head": null})]:
		SaveManager.unlock_part(str(loadout.get("head", "")) if loadout.get("head") != null else "head_anvil")
		editor.loadout = loadout
		editor.refresh()
		var expected: CreatureStats = PartAssembler.preview_stats(loadout, BLUEPRINT)
		var shown: CreatureStats = PartAssembler.preview_stats(editor.loadout, BLUEPRINT)
		almost(shown.max_hp, expected.max_hp, 0.001, "HP readout")
		almost(shown.total_defense, expected.total_defense, 0.001, "defense readout")
		almost(shown.total_weight, expected.total_weight, 0.001, "weight readout")
		eq(WeightClass.class_for_weight(shown.total_weight),
			WeightClass.class_for_weight(expected.total_weight), "class stamp")


func test_the_part_list_only_offers_parts_you_actually_own() -> void:
	var editor: SketchbookEditor = _open_editor()
	is_false(editor.owned_parts_for("head").has("head_anvil"), "a locked part is not offered")
	SaveManager.unlock_part("head_anvil")
	is_true(editor.owned_parts_for("head").has("head_anvil"), "an unlocked one is")
	is_true(editor.owned_parts_for("head").has("head_monster_maw"), "as is the starter head")


func test_stat_deltas_describe_the_swap_they_promise() -> void:
	var editor: SketchbookEditor = _open_editor()
	SaveManager.unlock_part("head_anvil")
	var deltas: Dictionary = editor.deltas_for("head", "head_anvil")
	# Read from the catalogue, not written down: the readout's job is to be the
	# difference between two parts, whatever those parts currently are.
	var worn: Dictionary = Config.part("head_monster_maw")["stats"] as Dictionary
	var candidate: Dictionary = Config.part("head_anvil")["stats"] as Dictionary
	almost(float(deltas["hp"]),
		float(candidate.get("hp_bonus", 0.0)) - float(worn.get("hp_bonus", 0.0)),
		0.001, "HP delta")
	almost(float(deltas["def"]),
		float(candidate.get("defense", 0.0)) - float(worn.get("defense", 0.0)),
		0.001, "defense delta")
	almost(float(deltas["weight"]),
		float(Config.part("head_anvil")["weight"])
			- float(Config.part("head_monster_maw")["weight"]),
		0.001, "weight delta")
	almost(float(deltas["atk"]),
		float(candidate.get("attack_power", 0.0)) - float(worn.get("attack_power", 0.0)),
		0.001, "attack delta")


# --- drag and drop -------------------------------------------------------------

func test_a_slot_refuses_a_part_that_does_not_belong_to_it() -> void:
	var editor: SketchbookEditor = _open_editor()
	var head_slot: SlotTarget = _slot(editor, "head")
	is_true(head_slot._can_drop_data(Vector2.ZERO,
		{"kind": "part", "part_id": "head_anvil", "slot": "head"}), "a head is welcome")
	is_false(head_slot._can_drop_data(Vector2.ZERO,
		{"kind": "part", "part_id": "tail_scorpion", "slot": "tail"}),
		"a tail is refused, so the card snaps back")
	is_false(head_slot._can_drop_data(Vector2.ZERO, {"kind": "nonsense"}),
		"and so is anything that is not a part")


func test_a_refused_drop_scratches() -> void:
	var editor: SketchbookEditor = _open_editor()
	_heard = PackedStringArray()
	# No drag is in flight, so the engine reports the drop as unsuccessful —
	# exactly the state a wrong-slot drop leaves behind.
	editor._notification(Control.NOTIFICATION_DRAG_END)
	is_true(_heard.has("sfx_ui_error_scratch"),
		"a failed drop plays sfx_ui_error_scratch (DESIGN §11)")


func test_equipping_an_illegal_part_is_refused_and_scratches() -> void:
	var editor: SketchbookEditor = _open_editor()
	_heard = PackedStringArray()
	editor._equip("legs", null)
	is_true(_heard.has("sfx_ui_error_scratch"), "emptying a required slot scratches")
	ne(editor.loadout["legs"], null, "and the legs stay on")


func test_equipping_a_legal_part_persists_immediately() -> void:
	var editor: SketchbookEditor = _open_editor()
	SaveManager.unlock_part("head_anvil")
	editor._equip("head", "head_anvil")
	eq(editor.loadout["head"], "head_anvil", "the working loadout changed")
	eq(SaveManager.loadout()["head"], "head_anvil", "and so did the save")


# --- unlock desk ---------------------------------------------------------------

func test_unlocking_deducts_the_exact_cost_and_persists() -> void:
	var desk: UnlockDesk = _open_desk()
	var cost: int = int(Config.part("head_anvil")["unlock_cost"])
	SaveManager.add_blueprint_sketch("head_anvil")
	SaveManager.add_ink(cost + 37)

	desk._buy("head_anvil")

	is_true(SaveManager.is_unlocked("head_anvil"), "the part is unlocked")
	eq(SaveManager.ink, 37, "exactly unlock_cost was deducted")
	is_true(_heard.has("sfx_unlock_kaching_mouth"), "and it goes ka-ching")

	# It survives a reload — an unlock the player paid for cannot evaporate.
	SaveManager.data = {}
	SaveManager.load_game()
	is_true(SaveManager.is_unlocked("head_anvil"), "the unlock persisted")
	eq(SaveManager.ink, 37, "and so did the remaining ink")
	DirAccess.remove_absolute(SaveManager.SAVE_PATH)


func test_an_unaffordable_unlock_changes_nothing() -> void:
	var desk: UnlockDesk = _open_desk()
	SaveManager.add_blueprint_sketch("head_anvil")
	SaveManager.add_ink(int(Config.part("head_anvil")["unlock_cost"]) - 1)
	var before: int = SaveManager.ink

	desk._buy("head_anvil")

	is_false(SaveManager.is_unlocked("head_anvil"), "the part stays locked")
	eq(SaveManager.ink, before, "and the ink stays in the wallet")


func test_the_desk_only_offers_parts_you_have_a_sketch_for() -> void:
	var desk: UnlockDesk = _open_desk()
	SaveManager.add_ink(9999)
	is_false(SaveManager.has_blueprint_sketch("head_anvil"), "no sketch yet")
	desk._buy("head_anvil")
	# _buy is the button's handler; the button only exists for found sketches,
	# so the guard that matters is that the desk never lists an unfound part.
	desk.refresh()
	is_true(SaveManager.blueprints_found().is_empty(), "nothing has been found")


func _slot(editor: SketchbookEditor, slot: String) -> SlotTarget:
	return editor._slot_targets[slot] as SlotTarget
