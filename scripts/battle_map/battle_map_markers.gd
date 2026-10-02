extends RefCounted

## Who the map draws at each semantic level.
##
## Zooming out is not supposed to shrink the contacts, it is supposed to say
## less about more ground: at tactical range the pilot flies against individual
## tracks, at regional range against groups of them, and at theatre range the
## merges are wide enough that mostly groups are left. A track with nothing
## beside it stays itself at every one of those, because a report about one
## thing is not a group. So this clusters the tracker's own contacts into pooled
## group records. The contacts keep their handles and a group carries the
## handles inside it, which is what lets a tap on a group fly the camera in and
## hand the same target back to the existing targeting system -- there is no
## second, map-only identity anywhere in here.
##
## Nothing is recomputed unless the camera or the contact set has actually
## changed, and the records are reused rather than reallocated, because the map
## may be looking at hundreds of tracks with a glide running.

const LEVELS := preload("res://scripts/battle_map/battle_map_layers.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

## Ground metres per cluster cell, indexed by level. World-aligned, so a group
## keeps its identity while the map pans and only a level change re-cells it.
## Zero at tactical range, where every track is drawn as itself.
const CELL_METRES := [16000.0, 7000.0, 0.0]
## Cells whose centroids are this fraction of a cell apart are the same
## formation, split by a cell line that means nothing on the ground.
const MERGE_FRACTION := 0.5
## Two tracks make a group, at every density. A lone track stays itself: the
## alternative is a report reading "GROUND GROUP 1 · 1" over a single SAM site
## that has a name, and a group is a statement about multiplicity that a
## singleton cannot support. Nothing disappears either way -- an individual is
## drawn as its own symbol at theatre range just as it is at tactical.
const MIN_GROUP := 2
## A marker that has grown past this is two markers, however close it is: one
## symbol swallowing the whole screen is the failure mode of a naive merge.
const MAX_GROUP := 12
## Bound on the merge passes. Cells are merged in canonical order, so this is
## only ever reached by a line of cells longer than the loop runs.
const MAX_PASSES := 6
## Placeholder for a draw item that is an individual track, not a group. A const
## so the common tactical case allocates nothing per item.
const NO_GROUP := {}

var _pool := []
var _items := []
var _live := []
var _labels := {}
var _signature := -1
var _computed := []
var _cursor := 0


## Returns what to draw for the contacts layer at this density. The records
## belong to this object and are valid until the next call, which is what lets
## hundreds of tracks be folded into a dozen markers without allocating anything
## per frame.
func markers(contacts: Array, level: int) -> Array:
	var signature := _signature_for(contacts, level)
	if signature == _signature:
		return _computed
	_rebuild(contacts, level)
	_signature = signature
	return _computed


## Cheap, exact enough, and it allocates nothing: a rebuild happens when the
## contact set changes or when a track genuinely moves -- not on every pixel of a
## camera glide, because the cells are world-aligned and the caller re-projects
## the markers itself. The handle sum catches a track dying and another appearing
## in the same frame, which a bare count would not, and the quantised positions
## matter because the tracker hands this object the sources' dictionaries, which
## are replaced wholesale every frame: a cached contact that was not refreshed
## would freeze a marker in place.
func _signature_for(contacts: Array, level: int) -> int:
	var hash := int(level) * 1000003 + contacts.size()
	for contact in contacts:
		var at: Vector3 = contact["position"]
		var velocity: Vector3 = contact["velocity"]
		hash = _mix(hash, int(contact["handle"]))
		hash = _mix(hash, int(round(at.x)))
		hash = _mix(hash, int(round(at.z)))
		hash = _mix(hash, int(round(velocity.x)))
		hash = _mix(hash, int(round(velocity.z)))
	return hash


static func _mix(into: int, value: int) -> int:
	return into * 8191 + value


func _rebuild(contacts: Array, level: int) -> void:
	_cursor = 0
	for record in _live:
		record["count"] = 0
	_live.clear()
	var cell := float(CELL_METRES[level])
	if cell <= 0.0:
		for contact in contacts:
			_emit(true, contact, NO_GROUP)
		_publish()
		return
	var buckets := {}
	for contact in contacts:
		var at: Vector3 = contact["position"]
		var key := Vector2i(int(floor(at.x / cell)), int(floor(at.z / cell)))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(contact)
	var clusters := _clusters(buckets, cell * MERGE_FRACTION)
	var alive := {}
	for cluster in clusters:
		var key: Vector2i = cluster["key"]
		var members: Array = cluster["members"]
		alive[key] = true
		if members.size() >= MIN_GROUP:
			var group := _group_for(key, members)
			_live.append(group)
			_emit(false, null, group)
		else:
			for contact in members:
				_emit(true, contact, NO_GROUP)
	_retire(alive)
	_publish()


## Grid cells are what keep a group's identity steady while the camera moves, and
## their price is that a formation sitting on a cell line arrives as two buckets,
## which on a phone is two markers nearly on top of one another. So cells whose
## centroids are within half a cell of each other are unioned into one cluster,
## and the survivor is always the canonically lowest cell: the answer is a
## property of the ground, not of the order the tracker handed the contacts over
## in, and it does not change while the same formation sits on the same ground.
func _clusters(buckets: Dictionary, merge: float) -> Array:
	var keys: Array = buckets.keys()
	keys.sort_custom(_cells_ascending)
	var size := keys.size()
	var parent := []
	var lists := []
	var centres := []
	var counts := []
	for index in range(size):
		var members: Array = buckets[keys[index]]
		parent.append(index)
		lists.append(members)
		counts.append(members.size())
		var total := Vector2.ZERO
		for contact in members:
			var at: Vector3 = contact["position"]
			total += Vector2(at.x, at.z)
		centres.append(total / float(members.size()))
	var changed := true
	var passes := 0
	while changed and passes < MAX_PASSES:
		changed = false
		passes += 1
		for left in range(size):
			var root := _root(parent, left)
			for right in range(left + 1, size):
				var other := _root(parent, right)
				if root == other or counts[root] + counts[other] > MAX_GROUP:
					continue
				if centres[root].distance_to(centres[other]) > merge:
					continue
				parent[other] = root
				var together := int(counts[root]) + int(counts[other])
				centres[root] = (
					(centres[root] as Vector2) * float(counts[root])
					+ (centres[other] as Vector2) * float(counts[other])
				) / float(together)
				counts[root] = together
				lists[root].append_array(lists[other])
				changed = true
	var result := []
	var claimed := {}
	for index in range(size):
		var root := _root(parent, index)
		if claimed.has(root):
			continue
		claimed[root] = true
		result.append({"key": keys[root], "members": lists[root]})
	return result


static func _root(parent: Array, index: int) -> int:
	var at := index
	while int(parent[at]) != at:
		parent[at] = parent[parent[at]]
		at = int(parent[at])
	return at


static func _cells_ascending(a: Vector2i, b: Vector2i) -> bool:
	return _before(a, b)


static func _before(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


## Item records are pooled the same way group records are: the array handed to
## the canvas keeps its identity and its dictionaries are written, not rebuilt.
func _emit(individual: bool, contact, group: Dictionary) -> void:
	if _cursor >= _items.size():
		_items.append({"individual": false, "contact": null, "group": {}})
	var item: Dictionary = _items[_cursor]
	item["individual"] = individual
	item["contact"] = contact
	item["group"] = group
	_cursor += 1


func _publish() -> void:
	_computed.resize(_cursor)
	for i in range(_cursor):
		_computed[i] = _items[i]
	_computed.sort_custom(_paint_order)


## Groups are pooled by their cell key, so the same patch of ground keeps the
## same record and a label cannot jump around while the map is moving.
func _group_for(key: Vector2i, members: Array) -> Dictionary:
	var group: Dictionary = _labels.get(key, {})
	var fresh := group.is_empty()
	var air := _is_air(members)
	if fresh:
		group = _take_from_pool()
		group["registered"] = true
		_labels[key] = group
	# The cell keeps its record, and so keeps its number, while it holds the same
	# sort of thing. A formation that turns from armour into aircraft is a
	# different report and earns a new number.
	if fresh or bool(group["air"]) != air:
		group["key"] = key
		group["air"] = air
		group["label"] = _label_for(air)
	var total := Vector3.ZERO
	var ceiling := 0.0
	for contact in members:
		var at: Vector3 = contact["position"]
		total += at
		ceiling = maxf(ceiling, at.y)
	group["centroid"] = total / float(members.size())
	group["altitude_m"] = ceiling
	# A theatre cell can hold a launcher battery and a flight over it. The report
	# is titled by anything airborne inside it and coloured to match, because the
	# air threat is the one that changes the pilot's plan.
	var kind := int(members[0]["kind"])
	if air:
		for contact in members:
			if _kind_air(int(contact["kind"])):
				kind = int(contact["kind"])
				break
	group["kind"] = kind
	group["count"] = members.size()
	group["members"] = members
	group["heading"] = _heading_of(members)
	return group


## The heading of the group as a whole: the mean track of its moving members,
## or NAN when nothing in it is moving, because a stationary group has no
## heading to claim and the card must be able to say so.
func _heading_of(members: Array) -> float:
	var east := 0.0
	var north := 0.0
	var moving := 0
	for contact in members:
		var velocity: Vector3 = contact["velocity"]
		if velocity.length_squared() < 1.0:
			continue
		east += velocity.x
		north -= velocity.z
		moving += 1
	if moving == 0:
		return NAN
	return fposmod(atan2(east, north), TAU)


func _take_from_pool() -> Dictionary:
	for record in _pool:
		# A record is free only when it holds nothing *and* no cell is still
		# registered to it. `count` alone is not enough: every live record is
		# zeroed at the top of a rebuild, so a cell the loop has not reached yet
		# looks exactly like a cell that has gone away -- and handing its record
		# out early gives two markers for one formation.
		if int(record["count"]) == 0 and not bool(record["registered"]):
			return record
	var fresh := {
		"key": Vector2i.ZERO, "label": "", "air": false, "members": [], "count": 0,
		"centroid": Vector3.ZERO, "altitude_m": 0.0, "heading": NAN, "kind": 0,
		"registered": false,
	}
	_pool.append(fresh)
	return fresh


## A cell that no longer holds anything gives its number back, so the numbering
## does not climb forever as the map sweeps across a theatre.
func _retire(buckets: Dictionary) -> void:
	for key in _labels.keys():
		if buckets.has(key):
			continue
		var group: Dictionary = _labels[key]
		# Registration is one key per record: `_take_from_pool` will not hand out
		# a record a cell still owns, so a registered record cannot have been
		# re-keyed under another cell within this rebuild.
		group["count"] = 0
		group["registered"] = false
		_labels.erase(key)


func _label_for(air: bool) -> String:
	var prefix := "AIR GROUP" if air else "GROUND GROUP"
	var index := 1
	while _taken(prefix, index):
		index += 1
	return "%s %d" % [prefix, index]


func _taken(prefix: String, index: int) -> bool:
	var wanted := "%s %d" % [prefix, index]
	for key in _labels:
		if String(_labels[key]["label"]) == wanted:
			return true
	return false


static func _kind_air(kind: int) -> bool:
	return kind == TRACKER.Kind.AIR_JET or kind == TRACKER.Kind.AIR_DRONE


static func _is_air(members: Array) -> bool:
	for contact in members:
		if _kind_air(int(contact["kind"])):
			return true
	return false


## Paint order, because the canvas draws the array in order and the last thing it
## draws is on top: groups under individuals (a group is a summary of a patch of
## ground, a lone track is the thing you shoot at), ground under air, and the
## bigger group on top of the smaller within those.
static func _paint_order(a: Dictionary, b: Dictionary) -> bool:
	var mine := bool(a["individual"])
	var theirs := bool(b["individual"])
	if mine != theirs:
		return not mine
	if mine:
		return not _kind_air(int(a["contact"]["kind"]))
	var group: Dictionary = a["group"]
	var other: Dictionary = b["group"]
	if bool(group["air"]) != bool(other["air"]):
		return not bool(group["air"])
	return int(group["count"]) < int(other["count"])


## The live group whose marker is nearest this screen point, or an empty
## Dictionary. `pixels` is how close is close enough and `project` is how the
## caller turns ground into screen, because this module owns no camera.
func group_at(point: Vector2, project: Callable, pixels: float) -> Dictionary:
	var nearest := {}
	var distance := pixels
	for group in _live:
		if int(group["count"]) <= 0:
			continue
		var at: Vector2 = project.call(
			Vector2(group["centroid"].x, group["centroid"].z))
		if not at.is_finite():
			continue
		var separation := at.distance_to(point)
		if separation < distance:
			distance = separation
			nearest = group
	return nearest


## The handles inside a group, in the tracker's own numbering.
func handles_of(group: Dictionary) -> Array:
	var result := []
	for contact in group.get("members", []):
		result.append(int(contact["handle"]))
	return result


func live_groups() -> Array:
	return _live
