class_name EditorHistory
extends RefCounted

## Undo and redo for the level editor, by snapshot.
##
## Every edit is recorded as the whole level's serialised form rather than as a
## reversible operation. That is the unglamorous choice and the right one here: a
## level is a few kilobytes of JSON, so a snapshot costs nothing, and it is
## impossible for an undo to be subtly wrong — which is exactly the failure mode
## a hand-written inverse operation has, and exactly the one that loses somebody's
## work. Adding a new tool needs no undo code at all.

## How many steps back the editor can go before the oldest is dropped.
const DEPTH: int = 100

var _past: Array[Dictionary] = []
var _future: Array[Dictionary] = []
var _current: Dictionary = {}
## Human-readable label per past state, for the editor's status line.
var _labels: Array[String] = []


## Start a history at `level`'s current state. Nothing to undo yet.
func begin(level: LevelData) -> void:
	_past.clear()
	_future.clear()
	_labels.clear()
	_current = level.to_dictionary()


## Record that `level` has just been changed, with a short description of what
## the change was ("draw solid", "move enemy"). Call this *after* the edit.
func record(level: LevelData, label: String) -> void:
	var snapshot: Dictionary = level.to_dictionary()
	if JSON.stringify(snapshot) == JSON.stringify(_current):
		return  # a no-op edit (a click that moved nothing) is not a step
	_past.append(_current)
	_labels.append(label)
	_current = snapshot
	_future.clear()
	if _past.size() > DEPTH:
		_past.pop_front()
		_labels.pop_front()


func can_undo() -> bool:
	return not _past.is_empty()


func can_redo() -> bool:
	return not _future.is_empty()


## Step back. Returns the level to restore, or null when there is nothing to undo.
func undo() -> LevelData:
	if _past.is_empty():
		return null
	_future.push_back(_current)
	_current = _past.pop_back()
	_labels.pop_back()
	return LevelData.from_dictionary(_current)


func redo() -> LevelData:
	if _future.is_empty():
		return null
	_past.append(_current)
	_labels.append("redo")
	_current = _future.pop_back()
	return LevelData.from_dictionary(_current)


## What undoing would take back, for the status line.
func next_undo_label() -> String:
	return "" if _labels.is_empty() else _labels[_labels.size() - 1]


func depth() -> int:
	return _past.size()
