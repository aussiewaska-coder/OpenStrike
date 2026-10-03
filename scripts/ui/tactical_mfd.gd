extends Control

signal open_changed(is_open: bool)
signal contact_selected(handle: int)
signal waypoint_requested(position: Vector2)
signal route_skip_requested
signal route_clear_requested
const CANVAS := preload("res://scripts/ui/tactical_map_canvas.gd")
const SETTINGS := preload("res://scripts/ui/settings_panel.gd")
const HUD := preload("res://scripts/ui/helmet_hud.gd")
const NAV := preload("res://scripts/ui/tactical_navigation.gd")
const LEVELS := preload("res://scripts/battle_map/battle_map_layers.gd")
const WAR := preload("res://scripts/war/war_objects.gd")
const MISSIONS := preload("res://scripts/war/mission_director.gd")
const RANGES := [1000.0, 2000.0, 5000.0, 10000.0, 20000.0, 40000.0]
## A selection card is a readout of moving tracks, so it is refreshed on an
## interval rather than every frame: faster than a pilot can read it, and cheap
## enough to run beside the flight on a phone.
const CARD_SECONDS := 0.25
const GREEN := Color(0.40, 0.91, 0.73)
const AMBER := Color(1, 0.78, 0.32)
var map: Control
var _close: Button
var _status: Label
var _range_buttons: Array[Button] = []
var _style_buttons: Array[Button] = []
var _waypoint: Button
var _rail: ScrollContainer
var _margin: MarginContainer
var _header: Label
var _density_label: Label
var _card: HBoxContainer
var _card_lines: Label
var _assign: Button
var _fly: Button
var _objective: Button
## §19's third key on a tasking: the route is planned to the ground the job is about, through
## the same waypoint seam a tap in Add WP mode uses, so a planned leg and a tasking are one
## navigation solution rather than two.
var _route: Button
## The staff's table, when this theatre has a war being run. The card reads its fields out of
## here and the two buttons write back into it, which is the only way a tasking on the map can
## be accepted by the person it was offered to.
var _tasks: RefCounted
var _layer_buttons := {}
var _subject := {}
var _card_elapsed := 0.0
var _density := "TACTICAL"
var pause_flight := true

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 30
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var styling := SETTINGS.new()
	theme = styling._menu_theme()
	styling.free()
	var background := ColorRect.new()
	background.color = Color(0.014, 0.028, 0.031)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	_margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	_header = Label.new()
	_header.text = "BATTLE MAP"
	_header.add_theme_color_override("font_color", Color(0.40, 0.91, 0.73))
	header.add_child(_header)
	_density_label = Label.new()
	_density_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_density_label.clip_text = true
	_density_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_density_label.add_theme_color_override("font_color", Color(0.42, 0.62, 0.58))
	header.add_child(_density_label)
	_close = _button("Close · Y", close_panel)
	header.add_child(_close)
	var ranges := HBoxContainer.new()
	ranges.add_theme_constant_override("separation", 4)
	layout.add_child(ranges)
	for metres in RANGES:
		var button := _button("%d km" % int(metres / 1000), func(): map.animate_range(metres))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ranges.add_child(button)
		_range_buttons.append(button)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	layout.add_child(body)
	map = CANVAS.new()
	body.add_child(map)
	map.contact_selected.connect(_contact_selected)
	map.group_selected.connect(_group_selected)
	map.strategic_selected.connect(_strategic_selected)
	map.mission_selected.connect(_mission_selected)
	map.waypoint_requested.connect(func(point: Vector2): waypoint_requested.emit(point))
	map.range_changed.connect(_range_changed)
	map.level_changed.connect(_level_changed)
	# A theatre gaining or losing its regions changes which rows of the rail are
	# switchable at all, which is a question the panel cannot answer on a timer.
	map.war_changed.connect(_refresh_layers)
	_rail = ScrollContainer.new()
	_rail.custom_minimum_size.x = 116
	_rail.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rail.follow_focus = true
	body.add_child(_rail)
	var buttons := VBoxContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_theme_constant_override("separation", 6)
	_rail.add_child(buttons)
	# Layers go at the head of the rail because they are the section the map
	# cannot be read without: a phone landscape shows two of the twenty-odd rows,
	# and what is on screen when the map is cluttered should be the fix for it.
	buttons.add_child(_section("Layers"))
	for id in map.semantic.ids():
		var toggle := _button(_layer_text(id), _toggle_layer.bind(id))
		toggle.toggle_mode = true
		buttons.add_child(toggle)
		_layer_buttons[id] = toggle
	_refresh_layers()
	buttons.add_child(_section("View"))
	for style in ["Satellite", "Simple", "Terrain"]:
		var index := _style_buttons.size()
		var button := _button(style, _set_style.bind(index))
		button.toggle_mode = true
		buttons.add_child(button)
		_style_buttons.append(button)
	buttons.add_child(_button("Ownship", func(): map.recenter()))
	buttons.add_child(_button("North up", func(): map.reset_view()))
	buttons.add_child(_section("Route"))
	_waypoint = _button("Add WP", _toggle_waypoint)
	_waypoint.toggle_mode = true
	buttons.add_child(_waypoint)
	buttons.add_child(_button("Next WP", func(): route_skip_requested.emit()))
	buttons.add_child(_button("Clear route", func(): route_clear_requested.emit()))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.57, 0.76, 0.71))
	_card = _build_card()
	layout.add_child(_card)
	layout.add_child(_status)
	resized.connect(_resize_layout)
	_resize_layout()
	_set_style(1)
	_range_changed(map.range_m)
	_level_changed(map.semantic.level())
	_status.text = "Drag: pan · Pinch: zoom · Two fingers: tilt and swing · Tap: select · Double tap: fly to it"


func _process(delta: float) -> void:
	if _subject.is_empty() or not visible:
		return
	_card_elapsed += delta
	if _card_elapsed < CARD_SECONDS:
		return
	_card_elapsed = 0.0
	_show_subject()


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(callback)
	return button


func _section(title: String) -> Label:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.42, 0.62, 0.58))
	return label


## The selection card: what the map says is under the finger, in numbers the
## world actually has. A field the tracker cannot answer is not printed at all,
## because an MFD that guesses is worse than one that says nothing. The keys sit
## beside the readout rather than under it: on a phone in landscape, vertical
## space belongs to the map.
func _build_card() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.visible = false
	_card_lines = Label.new()
	_card_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_lines.add_theme_font_size_override("font_size", 13)
	_card_lines.add_theme_color_override("font_color", GREEN)
	row.add_child(_card_lines)
	_assign = _button("Assign", _assign_target)
	_fly = _button("Fly to", _fly_to)
	# §19's third key. A tasking names an object, and the pilot who wants the target's own
	# intelligence should not have to find it on the map again with a second, more careful tap.
	_objective = _button("Target", _open_objective)
	_objective.visible = false
	_route = _button("Route", _plan_route)
	_route.visible = false
	_assign.custom_minimum_size.x = 62
	_fly.custom_minimum_size.x = 62
	_objective.custom_minimum_size.x = 62
	_route.custom_minimum_size.x = 62
	row.add_child(_assign)
	row.add_child(_fly)
	row.add_child(_route)
	row.add_child(_objective)
	return row


## The staff's board, or null for a theatre with no war being run. The map is told so it can
## draw the marks, and the panel is told so the card has something to write a decision back
## into; both read the same table rather than a copy of it.
func set_tasks(source: RefCounted) -> void:
	_tasks = source
	map.set_missions(source)


func _contact_selected(handle: int) -> void:
	_subject = {"handles": [handle], "title": "", "group": false}
	_show_subject()
	# A tap on one track is the same request the map has always made: main.gd
	# decides whether the weapon can actually have it.
	contact_selected.emit(handle)


func _group_selected(handles: Array, title: String, _centroid: Vector3) -> void:
	# A formation is not a target. The card is what the tap buys, and ASSIGN on
	# the card is what reaches the weapon.
	_subject = {"handles": handles, "title": title, "group": true}
	_show_subject()


## A site, a field or a structure: the subject is the registry id rather than the
## record, because the record is live and the card is read again every quarter second
## while the map is open. What stands at a SAM site changes between refreshes, and a
## card that printed the launcher count at the moment of the tap would be a report
## about the tap.
func _strategic_selected(id: int) -> void:
	_subject = {"object": id}
	_show_subject()


## A tasking, held by its id for the same reason an object is: the record is live, and the job
## may have been taken, flown or settled by the campaign between one refresh of the card and
## the next.
func _mission_selected(id: String) -> void:
	_subject = {"mission": id}
	_show_subject()


func _mission() -> Dictionary:
	return map.mission_object(String(_subject.get("mission", "")))


func _clear_subject() -> void:
	_subject = {}
	_card.visible = false


## The formation this card was opened on, if the map still draws one under that
## call sign; otherwise the tracks the tap reported. Group records are pooled and
## a member can have flown away or been shot down since.
func _live_handles(handles: Array) -> Array:
	var title := String(_subject.get("title", ""))
	if title.is_empty():
		return handles
	map.markers()
	for group in map.cluster.live_groups():
		if int(group["count"]) <= 0 or String(group["label"]) != title:
			continue
		var live: Array = map.cluster.handles_of(group)
		if not live.is_empty():
			return live
	return handles


func _subject_tracks() -> Array:
	var handles: Array = _subject.get("handles", [])
	if bool(_subject.get("group", false)):
		handles = _live_handles(handles)
	var tracks := []
	for handle in handles:
		for contact in map.contacts:
			if int(contact["handle"]) == int(handle):
				tracks.append(contact)
				break
	return tracks


func _assign_target() -> void:
	if _subject.has("mission"):
		_accept_mission()
		return
	if _subject.has("object"):
		_assign_object()
		return
	var tracks := _subject_tracks()
	if tracks.is_empty():
		_clear_subject()
		return
	contact_selected.emit(int(_nearest(tracks, map.player)["handle"]))


## Assigning a site means assigning the launcher standing at it, and the tracker's own
## handle is what the weapons already answer to -- the same lock the visor would have
## given for that track, reached from the map. An airfield or a tower has no track of
## its own, and a card that pretended otherwise would hand the pilot a lock that goes
## nowhere.
func _assign_object() -> void:
	var object: Dictionary = map.strategic_object(int(_subject["object"]))
	if object.is_empty():
		_clear_subject()
		return
	var nearest := -1
	var distance := INF
	for handle in object.get("handles", []):
		for contact in map.contacts:
			if int(contact["handle"]) != int(handle):
				continue
			var at: Vector3 = contact["position"]
			var separation := Vector2(at.x - map.player.x, at.z - map.player.z).length()
			if separation < distance:
				distance = separation
				nearest = int(handle)
	if nearest < 0:
		_status.text = "%s · NO LIVE TRACK AT THIS OBJECT · ASSIGN needs a contact" % String(object["name"])
		return
	contact_selected.emit(nearest)


func _fly_to() -> void:
	if _subject.has("mission"):
		_fly_mission()
		return
	if _subject.has("object"):
		var object: Dictionary = map.strategic_object(int(_subject["object"]))
		if object.is_empty():
			_clear_subject()
			return
		map.focus_object(object["world_position"])
		return
	var tracks := _subject_tracks()
	if tracks.is_empty():
		_clear_subject()
		return
	var middle := _mean(tracks)
	if bool(_subject.get("group", false)) and tracks.size() > 1:
		# Flying onto a formation means arriving close enough to fly against the
		# tracks inside it, which is the same contract a double tap has.
		map.focus_group(middle)
		return
	map.focus_contact(int(tracks[0]["handle"]))


func _show_subject() -> void:
	# The keys mean different things on a tasking and on a target, and a card that had kept the
	# word off the last one opened would be a button doing something other than what it says.
	_assign.text = "Assign"
	_assign.disabled = false
	_fly.text = "Fly to"
	_objective.visible = false
	_route.visible = false
	if _subject.has("mission"):
		_show_mission()
		return
	if _subject.has("object"):
		_show_object()
		return
	var tracks := _subject_tracks()
	if tracks.is_empty():
		_clear_subject()
		return
	var own: Vector3 = map.player
	var middle := _mean(tracks)
	# Ground range, not slant range: this is a map, and the altitude the track is
	# wasting is printed beside it rather than hidden inside the number.
	var kilometres := Vector2(middle.x - own.x, middle.z - own.z).length() / 1000.0
	var lines := [
		"RNG %5.1f km · BRG %03d°" % [kilometres, roundi(NAV.bearing(own, middle))],
	]
	var title := String(_subject.get("title", ""))
	if title.is_empty():
		var track: Dictionary = tracks[0]
		var velocity: Vector3 = track["velocity"]
		title = "%s · %s · %s" % [
			track["name"], HUD.kind_label(int(track["kind"])),
			"LOCKED" if int(map.locked) == int(track["handle"]) else "UNLOCKED",
		]
		lines.append("ALT %s m · %s" % [_metres((track["position"] as Vector3).y), _speed(velocity)])
		# A parked track has no course to report, and "TRACK HELD" under
		# "STATIONARY" is the same fact twice taking up a line the map wanted.
		if velocity.length_squared() >= 1.0:
			lines.append(_course(velocity))
	else:
		var ceiling := -INF
		for candidate in tracks:
			ceiling = maxf(ceiling, float((candidate["position"] as Vector3).y))
		var moving := 0
		for candidate in tracks:
			if (candidate["velocity"] as Vector3).length_squared() > 1.0:
				moving += 1
		title = "%s · %d %s" % [title, tracks.size(), "TRACKS" if tracks.size() > 1 else "TRACK"]
		lines.append("CEILING %s m · MOVING %d/%d" % [_metres(ceiling), moving, tracks.size()])
		lines.append("%s · ASSIGN %s" % [
			_track_line(tracks), String(_nearest(tracks, own)["name"])])
	_card_lines.text = "\n".join([title] + lines)
	_card.visible = true


## §19's card: the job, what it is aimed at, and the two decisions anybody can give the staff
## about it. Every line is a field the table published, because a card that re-narrated the
## campaign in its own words would be a second opinion on the war, and the war has one already.
func _show_mission() -> void:
	var mission := _mission()
	if mission.is_empty() or _tasks == null:
		_clear_subject()
		return
	var id := String(mission["id"])
	var status := String(mission["status"])
	var entity := int(_tasks.primary_entity(id))
	var lines := [
		"%s · %s · P%d · %s" % [
			String(mission["callsign"]), String(mission["type"]),
			int(mission["priority"]), status],
		String(mission["briefing"]),
		"PRIMARY %s · REGION %s · THREAT %s" % [
			String(mission["target_name"]) if not String(mission["target_name"]).is_empty()
				else "GROUND",
			String(mission["region_name"]), String(mission["threat_level"])],
		"%sEFFECT %s" % [
			"" if entity < 0 else "TRACK %d · " % entity,
			String(mission["strategic_effect"])],
	]
	# The window is part of the decision rather than a footnote to it: an offer with two ticks
	# left on it is not the same card as one that was raised this tick, and the pilot is the one
	# who has to say which is worth leaving the formation for.
	if status in MISSIONS.OPEN:
		lines.append("SECONDARY %d · WINDOW %d ticks" % [
			(mission["secondary_targets"] as Array).size(),
			maxi(0, int(mission["expires_at"]) - int(_tasks.tick_number()))])
	else:
		lines.append("OUTCOME %s · %s" % [status, String(mission.get("reason", ""))])
	_assign.text = {"AVAILABLE": "Accept", "ASSIGNED": "Taken", "ACTIVE": "Flying"} \
		.get(status, "Closed")
	_assign.disabled = status != MISSIONS.AVAILABLE
	_fly.text = "Fly"
	_objective.visible = int(mission["primary_target"]) >= 0
	_route.visible = status in MISSIONS.OPEN
	_card_lines.text = "\n".join(lines)
	_card.visible = true


## Taking a job is the player's answer to the staff, and nothing more: the campaign goes on
## whether or not anybody flies it, and the mission's own expiry is what makes that true.
func _accept_mission() -> void:
	var mission := _mission()
	if mission.is_empty():
		_clear_subject()
		return
	if _tasks != null and _tasks.accept(String(mission["id"])):
		_show_subject()
		return
	_status.text = "%s · NOT RELEASED · the board no longer has this as an offer" \
		% String(mission["callsign"])


## FLY is one decision rather than three. The pilot who means to work a job has taken it, is
## committed to it, and wants the thing itself shot at -- so the key accepts if it has to,
## commits the sortie, hands the weapon the launcher standing at the objective when the world
## has one, and points the camera at the ground it is all about. What it does not do is invent
## a target the registry does not have in order to complete the gesture.
func _fly_mission() -> void:
	var mission := _mission()
	if mission.is_empty() or _tasks == null:
		_clear_subject()
		return
	var id := String(mission["id"])
	if String(mission["status"]) == MISSIONS.AVAILABLE and not _tasks.accept(id):
		_status.text = "%s · NOT RELEASED · take it from the board first" \
			% String(mission["callsign"])
		return
	if not _tasks.launch(id):
		_status.text = "%s · ALREADY FLOWN · the sortie is committed" \
			% String(mission["callsign"])
		return
	var entity := int(_tasks.primary_entity(id))
	if entity >= 0:
		contact_selected.emit(entity)
	var at: Vector2 = _tasks.position_of(id)
	if at.is_finite():
		map.focus_object(at)
	_show_subject()


## The target, as the intelligence card rather than as a name on a tasking: §20 asks for the
## primary to be reachable from the mission, and the map is where both of them live.
func _open_objective() -> void:
	var mission := _mission()
	if mission.is_empty():
		_clear_subject()
		return
	var target := int(mission["primary_target"])
	if target < 0:
		_status.text = "%s · NO OBJECTIVE · this job is over ground rather than a point on it" \
			% String(mission["callsign"])
		return
	_strategic_selected(target)


## PLAN ROUTE, §19's middle key. The leg is laid onto the ground the job is about -- the
## objective itself when there is one, the middle of the district when the tasking is over
## ground rather than a point on it -- and it goes in through the waypoint seam a tap in Add WP
## mode already uses, so there is one route on the map rather than a planning copy of it.
func _plan_route() -> void:
	var mission := _mission()
	if mission.is_empty() or _tasks == null:
		_clear_subject()
		return
	var at: Vector2 = _tasks.position_of(String(mission["id"]))
	if not at.is_finite():
		_status.text = "%s · NO GROUND · the board has dropped this job" % String(mission["callsign"])
		return
	waypoint_requested.emit(at)


## The strategic card. Every number on it came out of the registry and the registry
## got it out of the world: the strip is the length the airport has, the launcher count
## is what the SAM field reports standing at that site, and the structure line is the
## damage the collision index has accumulated under the footprint the tower's model
## sits on. A field the sources cannot answer is not printed at all.
func _show_object() -> void:
	var object: Dictionary = map.strategic_object(int(_subject["object"]))
	if object.is_empty():
		_clear_subject()
		return
	var at: Vector2 = object["world_position"]
	var own: Vector3 = map.player
	var area := String(map.territory.region_at(at).get("name", ""))
	var holder := String(map.territory.holder_at(at))
	var lines := [
		"%s · %s · %s" % [String(object["name"]), WAR.type_name(object), String(object["faction"])],
		"RNG %5.1f km · BRG %03d° · LAT %.4f · LON %.4f" % [
			Vector2(at.x - own.x, at.y - own.z).length() / 1000.0,
			roundi(NAV.bearing(own, Vector3(at.x, own.y, at.y))),
			float(object["latitude"]), float(object["longitude"])],
		"AREA %s · HELD %s · STATE %s · INTEL %d%%" % [
			area if not area.is_empty() else "UNMAPPED",
			holder if not holder.is_empty() else "UNREPORTED",
			String(object["operational_state"]),
			int(round(float(object["intel_confidence"]) * 100.0))],
		_object_report(object),
		"VALUE %.2f · FROM %s" % [float(object["strategic_value"]), String(object["source"])],
	]
	_card_lines.text = "\n".join(lines)
	_card.visible = true


## What the object's own sort of thing is measured in. An airfield is a strip of a
## certain length; a site is a number of launchers; a tower is a footprint the guns can
## already hit. Where the same object also has a tracker handle, the card says so,
## because that is the line between looking at a target and being able to shoot it.
func _object_report(object: Dictionary) -> String:
	var detail: Dictionary = object["detail"]
	var state := String(object["operational_state"])
	if int(object["type"]) == WAR.Type.AIRBASE:
		var strips: Array = detail.get("strips", [])
		if strips.is_empty():
			return "NO PAVED STRIP"
		# Every strip would not fit the card and only one of them is the reason a
		# flight lands there, so the longest is the one printed.
		var longest: Dictionary = strips[0]
		for strip in strips:
			if float(strip["length_m"]) > float(longest["length_m"]):
				longest = strip
		return "%d STRIP%s · %s %d m · HDG %03d°" % [
			strips.size(), "S" if strips.size() > 1 else "", String(longest["id"]),
			int(round(float(longest["length_m"]))), int(round(float(longest["heading_deg"])))]
	if int(object["type"]) == WAR.Type.SAM_SITE:
		var handles: Array = object.get("handles", [])
		if not handles.is_empty():
			# Measured against the strongest the site has ever been seen at, which is
			# what "one launcher of two" means to a pilot deciding whether to go in.
			var yardstick := maxi(int(detail.get("strongest", 0)), maxi(int(detail.get("planned", 1)), 1))
			return "%d LAUNCHER%s OF %d · TRACK %d" % [
				handles.size(), "S" if handles.size() > 1 else "", yardstick, int(handles[0])]
		if state == WAR.DESTROYED:
			return "NOTHING LEFT AT THIS SITE"
		if state == WAR.UNCONFIRMED:
			return "NOTHING SEEN HERE · POSITION FROM THE LAYOUT"
		return "STATE %s" % state
	if int(object["type"]) == WAR.Type.INFRASTRUCTURE:
		if not bool(detail.get("streamed", false)):
			return "FOOTPRINT NOT STREAMED · NO DAMAGE READ"
		return "FOOTPRINT %d · DAMAGE %d · STANDING %d%%" % [
			int(detail.get("building_id", -1)), int(round(float(detail.get("damage", 0.0)))),
			int(round(float(object["health"]) * 100.0))]
	return "HEALTH %d%%" % int(round(float(object["health"]) * 100.0))


## The tracks' own mean course, or the truth that a parked formation has none.
func _track_line(tracks: Array) -> String:
	var east := 0.0
	var north := 0.0
	for candidate in tracks:
		var velocity: Vector3 = candidate["velocity"]
		east += velocity.x
		north -= velocity.z
	if Vector2(east, north).length() < 1.0:
		return "TRACK HELD"
	return "TRK %03d° · %.0f m/s" % [
		int(round(fposmod(rad_to_deg(atan2(east, north)), 360.0))),
		Vector2(east, north).length() / float(tracks.size())]


func _mean(tracks: Array) -> Vector3:
	var total := Vector3.ZERO
	for candidate in tracks:
		total += candidate["position"]
	return total / float(tracks.size())


## The nearest member of a formation, by the same ground range the card prints,
## so that ASSIGN and the number beside it can never disagree.
func _nearest(tracks: Array, own: Vector3) -> Dictionary:
	var chosen: Dictionary = tracks[0]
	var distance := INF
	for candidate in tracks:
		var at: Vector3 = candidate["position"]
		var separation := Vector2(at.x - own.x, at.z - own.z).length()
		if separation < distance:
			distance = separation
			chosen = candidate
	return chosen


static func _speed(velocity: Vector3) -> String:
	return "STATIONARY" if velocity.length_squared() < 1.0 else "SPD %03d m/s" % roundi(velocity.length())


static func _course(velocity: Vector3) -> String:
	if velocity.length_squared() < 1.0:
		return "TRACK HELD"
	return "TRK %03d°" % int(round(fposmod(rad_to_deg(atan2(velocity.x, -velocity.z)), 360.0)))


static func _metres(value: float) -> String:
	var whole := int(round(value))
	var text := str(absi(whole))
	var digits := text.length()
	if digits > 3:
		text = text.substr(0, digits - 3) + " " + text.substr(digits - 3)
	return ("-" if whole < 0 else "") + text

func _resize_layout() -> void:
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 8 if size.x < 760 or size.y < 460 else 20)
	_rail.custom_minimum_size.x = 98 if size.x < 500 else 116
	_card_lines.add_theme_font_size_override("font_size", 11 if size.x < 500 else 13)
	_density_label.add_theme_font_size_override("font_size", 11 if size.x < 500 else 13)
	for button in _range_buttons:
		button.add_theme_font_size_override("font_size", 11 if size.x < 500 else 15)
		# Compact range keys must fit alongside each other even on portrait phones.
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.07, 0.13, 0.15)
		normal.border_color = Color(0.19, 0.35, 0.34)
		normal.set_border_width_all(1)
		normal.content_margin_left = 4
		normal.content_margin_right = 4
		button.add_theme_stylebox_override("normal", normal)

func _set_style(index: int) -> void:
	map.map_style = index
	map._update_shader()
	map.queue_redraw()
	for i in range(_style_buttons.size()):
		_style_buttons[i].set_pressed_no_signal(i == index)

func _range_changed(metres: float) -> void:
	for i in range(_range_buttons.size()):
		_range_buttons[i].set_pressed_no_signal(is_equal_approx(metres, RANGES[i]))


func _level_changed(level: int) -> void:
	_density = LEVELS.level_name(level)
	_set_header()


func _set_header() -> void:
	_density_label.text = "%s · %s" % [_density, "PAUSED" if pause_flight else "LIVE"]


## A layer with nothing behind it says so on its key. The war layers are the map
## the campaign will eventually draw, and a toggle that changed nothing would be
## the one thing a pilot cannot forgive on a map.
func _layer_text(id: StringName) -> String:
	var label := String(map.semantic.label(id))
	return label if map.semantic.has_source(id) else "%s · NONE" % label


func _toggle_layer(id: StringName) -> void:
	if not map.semantic.toggle(id):
		_status.text = "%s has no intelligence behind it yet" % map.semantic.label(id)
	_refresh_layers()
	map.queue_redraw()


func _refresh_layers() -> void:
	for id in _layer_buttons:
		var button: Button = _layer_buttons[id]
		button.text = _layer_text(id)
		button.disabled = not map.semantic.has_source(id)
		button.set_pressed_no_signal(map.semantic.is_enabled(id))

func _toggle_waypoint() -> void:
	map.add_waypoint = not map.add_waypoint
	_waypoint.set_pressed_no_signal(map.add_waypoint)
	_status.text = "WAYPOINT MODE · Tap the map to append a waypoint. Next WP skips the current leg." if map.add_waypoint else "TARGET MODE · Tap a contact to select it; double tap flies the map onto it."

func show_message(message: String) -> void:
	_status.text = message

func open_panel() -> void:
	if visible:
		return
	get_parent().move_child(self, -1)
	visible = true
	map.recenter()
	map.cancel_gesture()
	_refresh_layers()
	_level_changed(map.semantic.level())
	_close.grab_focus()
	open_changed.emit(true)

func close_panel() -> void:
	if not visible:
		return
	visible = false
	map.cancel_gesture()
	_clear_subject()
	# Release shared detail references so terrain eviction can reclaim memory.
	map.set_layers({})
	open_changed.emit(false)

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()
