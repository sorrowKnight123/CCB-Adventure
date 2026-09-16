extends Node
## Boss QTE 统一输入控制器：一个时刻只允许一个音符接受左键判定。

signal note_resolved(perfect: bool)

const NOTE_SCENE: PackedScene = preload("res://scenes/enemies/boss/BossNote.tscn")

var active_note: Node = null
var active_notes: Array[Node] = []
var _waiting_for_note: bool = false


func _process(_delta: float) -> void:
	# A note can be freed by a scene transition or a canceled attack before
	# its signal is delivered. Do not let that stale entry block later notes.
	for note in active_notes.duplicate():
		if not is_instance_valid(note):
			active_notes.erase(note)
	_waiting_for_note = not active_notes.is_empty()
	if active_note != null and not is_instance_valid(active_note):
		active_note = active_notes.back() if not active_notes.is_empty() else null


func _input(event: InputEvent) -> void:
	if not _waiting_for_note:
		return
	if not event.is_action_pressed("attack"):
		return
	var candidate: Node = null
	var candidate_elapsed := -1.0
	for note in active_notes:
		if is_instance_valid(note) and note.has_method("is_judgement_window") and note.is_judgement_window():
			var elapsed: float = float(note.get("elapsed"))
			if elapsed > candidate_elapsed:
				candidate = note
				candidate_elapsed = elapsed
	if candidate:
		candidate.try_hit()


func spawn_note(world_position: Vector2, duration: float, perfect_window: float) -> bool:
	_prune_notes()
	if _waiting_for_note and not active_notes.is_empty():
		return false
	_waiting_for_note = false
	_spawn_note(world_position, duration, perfect_window)
	return true


func spawn_finisher_note(world_position: Vector2, duration: float, perfect_window: float) -> bool:
	_spawn_note(world_position, duration, perfect_window)
	return true


func _spawn_note(world_position: Vector2, duration: float, perfect_window: float) -> void:
	var note := NOTE_SCENE.instantiate()
	get_tree().current_scene.add_child(note)
	note.global_position = world_position
	note.z_index = 100
	active_note = note
	active_notes.append(note)
	_waiting_for_note = true
	note.judged.connect(_on_note_judged.bind(note))
	note.start(duration, perfect_window)


func wait_for_note() -> bool:
	if not _waiting_for_note:
		return false
	return await note_resolved


func cancel_active_note() -> void:
	if active_notes.is_empty():
		return
	for note in active_notes.duplicate():
		if is_instance_valid(note) and note.has_method("cancel"):
			note.cancel()


func _on_note_judged(perfect: bool, note: Node) -> void:
	active_notes.erase(note)
	if active_note == note:
		active_note = active_notes.back() if not active_notes.is_empty() else null
	_waiting_for_note = not active_notes.is_empty()
	note_resolved.emit(perfect)


func _prune_notes() -> void:
	for note in active_notes.duplicate():
		if not is_instance_valid(note):
			active_notes.erase(note)
	_waiting_for_note = not active_notes.is_empty()
