extends RefCounted

## The campaign, in a file.
##
## §28's acceptance is a specific story: destroy airbase assets, quit, reload, and find the
## damage and its consequences still there. Everything that story needs is already computed by
## the four modules this writes between -- the war owns the ground, the air and the facilities;
## the two commanders own the decisions and the memory those decisions were made from; the two
## staffs own the cards the pilot was offered and what came of them. None of them is asked to
## explain itself here: each is handed to through `export_state`/`import_state`, which is where
## its own idea of what is worth remembering lives. That is the only reason this file can survive
## the phases still to come -- a new module with a save pair of its own is one more line here,
## not a rewrite of the format.
##
## What is deliberately not here: anything the flying world owns. No aircraft in the air, no
## weapon on a rail, no particle, no node path, and no position that the theatre's own data does
## not put back. §25 counts a second copy of a fact as a bug even when both copies agree, and the
## registry re-authors every airfield, launcher site and tower from the region the map loads --
## so a save carrying coordinates would be a save that can disagree with the ground it is applied
## to. A `Vector2` cannot even be written by the JSON the telemetry server already uses, which is
## the same boundary arriving from the other side.
##
## The file is versioned because §28 says so, and because the honest alternative -- reading an
## unknown shape and hoping the keys line up -- is how a campaign gets quietly restored half
## applied. A version this build does not know is refused with the reason kept for the overlay to
## print, and the current version is refused too if it names a theatre other than the one seated:
## the corridor's war reloaded onto the islands would move ground nobody can see.

## The shape this build writes. Bump it when a field changes meaning, not merely when one is
## added: a save that is missing a term the loader requires is refused by the modules themselves,
## which is the same guard with less bookkeeping.
const VERSION := 1

const PATH := "user://campaign_save.json"

var _refusal := ""


## ------------------------------------------------------------------------ the file

func path() -> String:
	return PATH


func exists() -> bool:
	return FileAccess.file_exists(PATH)


func refusal() -> String:
	return _refusal


func erase() -> bool:
	_refusal = ""
	if not exists():
		return true
	var removed := DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	if removed != OK:
		_refusal = "the save file would not come off the disk"
	return removed == OK


## Write a campaign out. Returns false with a reason rather than a half-written file: a capture
## taken while the modules were unseated would save an empty war over the good one, which is the
## one way to lose a campaign by saving it.
func write(state: Dictionary) -> bool:
	_refusal = ""
	if state.is_empty() or int(state.get("version", 0)) != VERSION:
		_refusal = "nothing here is a campaign this build understands"
		return false
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		_refusal = "the save file could not be opened (%d)" % FileAccess.get_open_error()
		return false
	file.store_string(JSON.stringify(state, "\t"))
	file.flush()
	file.close()
	return true


## Read it back. An absent file is not an error -- a first run has no campaign -- but anything
## else that comes off the disk is checked against the version before the modules are asked to
## trust it, so a save from a later build cannot be talked into a partial application.
func read() -> Dictionary:
	_refusal = ""
	if not exists():
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		_refusal = "the save file could not be opened"
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_refusal = "the save file is not a JSON object"
		return {}
	var state := parsed as Dictionary
	if int(state.get("version", 0)) != VERSION:
		_refusal = "the save file is version %d, this build writes version %d" \
			% [int(state.get("version", 0)), VERSION]
		return {}
	return state


## -------------------------------------------------------------------- capture / apply

## Assemble the whole campaign from the five modules that hold it. The theatre name comes from
## the registry -- it is the region the map loaded, and the only identifier both the war and the
## boards agree on.
func capture(
		theatre: String, war: RefCounted, own: RefCounted, foe: RefCounted,
		own_board: RefCounted, foe_board: RefCounted) -> Dictionary:
	_refusal = ""
	var parts := {
		"war": war,
		"own": own,
		"foe": foe,
		"own_board": own_board,
		"foe_board": foe_board,
	}
	for name in parts:
		if not _exports(parts[name]):
			_refusal = "%s cannot be written out" % name
			return {}
	if theatre.is_empty():
		_refusal = "no theatre is loaded"
		return {}
	return {
		"version": VERSION,
		"theatre": theatre,
		"saved_at": int(Time.get_unix_time_from_system()),
		"war": war.export_state(),
		"own": own.export_state(),
		"foe": foe.export_state(),
		"own_board": own_board.export_state(),
		"foe_board": foe_board.export_state(),
	}


## Hand each part back to the module that authored it, in the order the campaign is built: the
## war first, because the commanders read their districts off it and the boards read their cards
## off them. One refusal stops the whole thing -- a campaign restored except for the red
## commander is a campaign where the enemy has forgotten why it was attacking.
func apply(
		state: Dictionary, war: RefCounted, own: RefCounted, foe: RefCounted,
		own_board: RefCounted, foe_board: RefCounted) -> bool:
	_refusal = ""
	if state.is_empty():
		_refusal = "there is no campaign to restore"
		return false
	if int(state.get("version", 0)) != VERSION:
		_refusal = "the state is version %d, this build writes version %d" \
			% [int(state.get("version", 0)), VERSION]
		return false
	var seated := String(war.call("theatre")) if war != null and war.has_method("theatre") else ""
	if seated.is_empty():
		_refusal = "nothing is seated to restore onto"
		return false
	var saved := String(state.get("theatre", ""))
	if saved != seated:
		_refusal = "the save is %s, the loaded theatre is %s" % [saved, seated]
		return false
	var order := [
		["war", state.get("war", {}), war],
		["own", state.get("own", {}), own],
		["foe", state.get("foe", {}), foe],
		["own_board", state.get("own_board", {}), own_board],
		["foe_board", state.get("foe_board", {}), foe_board],
	]
	# Five modules restored in a row is five chances to stop halfway, and a campaign made of two
	# wars is the failure this layer exists to prevent. Each module is asked for its own state
	# before it is overwritten, and a later refusal puts those back in reverse order: the same
	# `import_state` that restored the campaign is what un-restores it, so a rollback cannot
	# disagree with the module it is rolling back.
	var undo := []
	for step in order:
		var label := String(step[0])
		var module: RefCounted = step[2]
		if not _imports(module):
			_refusal = "%s cannot be restored" % label
			_rewind(undo)
			return false
		var part: Variant = step[1]
		if not (part is Dictionary):
			_refusal = "%s's part of the file is not a table" % label
			_rewind(undo)
			return false
		undo.append([module, module.call("export_state")])
		if not bool(module.import_state(part as Dictionary)):
			_refusal = "%s refused the saved state" % label
			_rewind(undo)
			return false
	return true


## Put the modules that already took the new state back on the old one, newest first.
func _rewind(undo: Array) -> void:
	for index in range(undo.size() - 1, -1, -1):
		var entry: Array = undo[index]
		(entry[0] as RefCounted).call("import_state", entry[1])


func _exports(module: RefCounted) -> bool:
	return module != null and module.has_method("export_state") \
		and bool(module.call("is_ready"))


func _imports(module: RefCounted) -> bool:
	return module != null and module.has_method("import_state")
