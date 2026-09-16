extends Node2D
## 小兰：3-1 的巫师 NPC。首次进入 npc_area2 自动对白，之后进入小 npc_area 按 W 交互。
## 对话内容放在 dialogues/game.dialogue；商店 UI 放在 ShopPanel.tscn，方便编辑器调整。

const INTRO_TRIGGER_ID := "npc_xiaolan_intro"
const SHOP_PANEL_SCENE: PackedScene = preload("res://scenes/ui/ShopPanel.tscn")

@export var dialogue_file: String = "res://dialogues/game.dialogue"
@export var intro_cue: String = "lan_intro"
@export var menu_cue: String = "lan_menu"
@export var records_menu_cue: String = "lan_menu_records"
@export var interact_action: StringName = &"interact"
@export var camera_focus_duration: float = 0.6
@export var interaction_prompt: String = "W"

@onready var intro_area: Area2D = get_node_or_null("npc_area2") as Area2D
@onready var npc_area: Area2D = get_node_or_null("npc_area") as Area2D
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

var _player_in_range: bool = false
var _conversation_active: bool = false
var _pending_shop_mode: String = ""
var _shop_panel: CanvasLayer = null
var _camera: Camera2D = null
var _camera_tween: Tween = null
var _camera_focus_active: bool = false
var _camera_focus_sliding: bool = false
var _camera_focus_target := Vector2.ZERO
var _active_dialogue_resource: DialogueResource = null
var _saved_camera_top_level: bool = false
var _saved_camera_smoothing: bool = false
var _saved_camera_offset := Vector2.ZERO
var _saved_camera_position := Vector2.ZERO


func _ready() -> void:
	add_to_group("npc")
	anim.play("idle")
	if intro_area == null:
		# In 3-1 npc_area2 is the one-shot introduction trigger added to the
		# level instance. Keep the fallback for opening BlueWizard.tscn alone.
		intro_area = npc_area
	if intro_area:
		intro_area.body_entered.connect(_on_intro_area_body_entered)
	if npc_area:
		npc_area.body_entered.connect(_on_npc_area_body_entered)
		npc_area.body_exited.connect(_on_npc_area_body_exited)
	DialogueManager.passed_cue.connect(_on_dialogue_passed_cue)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)


func _process(_delta: float) -> void:
	# Camera2D normally follows Player because it is a child node. During the
	# conversation it is top-level, so keep the settled focus point explicitly.
	if _camera_focus_active and not _camera_focus_sliding and is_instance_valid(_camera):
		_camera.global_position = _camera_focus_target
	if not _player_in_range or _conversation_active or _shop_panel != null:
		return
	if DialogueBridge.is_active:
		return
	if Input.is_action_just_pressed(interact_action):
		_start_conversation(false)


func _on_intro_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if not GameState.has_trigger(INTRO_TRIGGER_ID):
		GameState.mark_trigger(INTRO_TRIGGER_ID)
		GameState.save_game()
		_start_conversation(true)


func _on_npc_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true


func _on_npc_area_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false


func _start_conversation(is_first_visit: bool) -> void:
	if _conversation_active or _shop_panel != null or DialogueBridge.is_active:
		return
	var resource := load(dialogue_file) as DialogueResource
	if resource == null:
		push_warning("BlueWizard: 无法加载对白资源 %s" % dialogue_file)
		return
	_conversation_active = true
	_pending_shop_mode = ""
	_active_dialogue_resource = resource
	_focus_camera()
	var cue := intro_cue if is_first_visit else menu_cue
	if not is_first_visit and GameState.is_records_unlocked():
		cue = records_menu_cue
	DialogueBridge.show_cue(dialogue_file, cue)


func _on_dialogue_passed_cue(cue: String) -> void:
	if not _conversation_active:
		return
	match cue:
		"lan_shop":
			_pending_shop_mode = "upgrades"
		"lan_records":
			_pending_shop_mode = "records"


func _on_dialogue_ended(resource: DialogueResource) -> void:
	if not _conversation_active:
		return
	if _active_dialogue_resource != null and resource != _active_dialogue_resource:
		return
	_conversation_active = false
	_active_dialogue_resource = null
	var mode := _pending_shop_mode
	_pending_shop_mode = ""
	if mode.is_empty():
		_restore_camera()
	else:
		call_deferred("_open_shop", mode)


func _focus_camera() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	_camera = player.get_node_or_null("Camera2D") as Camera2D
	if _camera == null:
		return
	var start_position := _camera.global_position
	if not _camera_focus_active:
		_saved_camera_top_level = _camera.top_level
		_saved_camera_smoothing = _camera.position_smoothing_enabled
		_saved_camera_offset = _camera.offset
		_saved_camera_position = _camera.position
	_camera_focus_active = true
	_camera_focus_target = global_position
	_camera.top_level = true
	_camera.position_smoothing_enabled = false
	_camera.offset = Vector2.ZERO
	# Switching top_level changes the inherited transform. Restore the captured
	# world position before creating the tween so the camera does not jump first.
	_camera.global_position = start_position
	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween()
	_camera_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_camera_focus_sliding = true
	_camera_tween.tween_property(_camera, "global_position", _camera_focus_target, camera_focus_duration)
	_camera_tween.tween_callback(_finish_camera_focus)


func _finish_camera_focus() -> void:
	if not _camera_focus_active or not is_instance_valid(_camera):
		return
	_camera_focus_sliding = false
	_camera.global_position = _camera_focus_target


func _restore_camera() -> void:
	if not is_instance_valid(_camera):
		return
	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_focus_active = false
	_camera_focus_sliding = false
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var target := player.global_position if player else _camera.global_position
	_camera_tween = create_tween()
	_camera_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(_camera, "global_position", target, camera_focus_duration)
	_camera_tween.tween_callback(_finish_camera_restore)


func _finish_camera_restore() -> void:
	if not is_instance_valid(_camera):
		return
	_camera.top_level = _saved_camera_top_level
	_camera.position_smoothing_enabled = _saved_camera_smoothing
	_camera.offset = _saved_camera_offset
	if not _saved_camera_top_level:
		_camera.position = _saved_camera_position
	_camera_focus_target = Vector2.ZERO
	_camera.reset_smoothing()


func _open_shop(mode: String) -> void:
	if not is_inside_tree() or _shop_panel != null:
		return
	_shop_panel = SHOP_PANEL_SCENE.instantiate() as CanvasLayer
	get_tree().current_scene.add_child(_shop_panel)
	_shop_panel.closed.connect(_on_shop_closed)
	_shop_panel.open(mode)


func _on_shop_closed() -> void:
	if is_instance_valid(_shop_panel):
		_shop_panel.queue_free()
		_shop_panel = null
	_restore_camera()
