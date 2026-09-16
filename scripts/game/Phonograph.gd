extends Node2D
## 留声机核心存档点：靠近弹气泡，按 E 存档 → 播放 40 帧动画 + wav → 进入 sit。
## 动画播完循环最后 15 帧并播放当前唱片；退出 sit 时倒放一遍动画 + 再播一次 wav。

const TOTAL_FRAMES := 40   # 5 行 × 8 列
const FRAME_TIME := 0.1
const LOOP_START := 25      # 第 26 帧（0-based）开始循环
const INTERACT_RADIUS := 100.0
const SAVE_ZOOM := 1.6
const SAVE_PLAYER_SCREEN_X := 0.35   # 角色在屏幕左 35%，右侧留 UI 区
const CAMERA_TWEEN := 0.3

const SAVE_AUDIO := "res://audio/item/phonograph/phonograph.wav"

## 是否在玩家首次离开本留声机时授予「悠远的旋律」（回血能力，播放能力过场）。
## 默认 false；只在指定场景（scenes/levels/1/2.tscn）的实例上开启。
@export var grants_heal_melody: bool = false

enum AnimState { IDLE, PLAYING, LOOP, REVERSING }

@onready var anim: AnimatedSprite2D = $Anim
@onready var save_audio: AudioStreamPlayer = $SaveAudio
@onready var bubble: Control = $Bubble
@onready var record_switch_ui: CanvasLayer = $RecordSwitchUI
@onready var record_name_label: Label = $RecordSwitchUI/Panel/Container/Selector/RecordName
@onready var record_status_label: Label = $RecordSwitchUI/Panel/Container/RecordStatus
@onready var previous_record_button: Button = $RecordSwitchUI/Panel/Container/Selector/Previous
@onready var next_record_button: Button = $RecordSwitchUI/Panel/Container/Selector/Next

var _state := AnimState.IDLE
var _frame_index := 0
var _anim_acc := 0.0
var _player_in_range := false
var _sit_active := false
var _prev_camera_zoom := Vector2.ONE
var _prev_camera_offset := Vector2.ZERO
var _music_key := ""


func _ready() -> void:
	add_to_group("phonograph")
	anim.animation = "default"
	anim.stop()
	anim.frame = 0
	bubble.hide()
	record_switch_ui.hide()
	previous_record_button.pressed.connect(_select_previous_record)
	next_record_button.pressed.connect(_select_next_record)
	_music_key = "phonograph:%s" % str(get_path())


func _exit_tree() -> void:
	if _music_key != "":
		AudioManager.clear_music(_music_key)


func can_interact() -> bool:
	return _player_in_range


func _update_range() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	_player_in_range = player != null and is_instance_valid(player) \
		and player.global_position.distance_to(global_position) <= INTERACT_RADIUS


func _process(delta: float) -> void:
	_update_range()
	_step_anim(delta)
	bubble.visible = _player_in_range


func _physics_process(_delta: float) -> void:
	if _player_in_range and Input.is_action_just_pressed("heal"):
		on_interact()


func _step_anim(delta: float) -> void:
	if _state == AnimState.IDLE:
		_frame_index = 0
		anim.frame = _frame_index
		return
	_anim_acc += delta
	while _anim_acc >= FRAME_TIME:
		_anim_acc -= FRAME_TIME
		match _state:
			AnimState.PLAYING:
				_frame_index += 1
				if _frame_index >= TOTAL_FRAMES:
					_frame_index = LOOP_START
					_state = AnimState.LOOP
					_start_selected_record()
			AnimState.LOOP:
				_frame_index = LOOP_START + ((_frame_index - LOOP_START + 1) % (TOTAL_FRAMES - LOOP_START))
			AnimState.REVERSING:
				_frame_index -= 1
				if _frame_index < 0:
					_frame_index = 0
					_state = AnimState.IDLE
	anim.frame = _frame_index
	_update_record_switch_ui()


func on_interact() -> void:
	if not _player_in_range:
		return
	if _sit_active:
		_exit_sit()
	else:
		_do_save()


func _focus_camera(player: Node2D) -> void:
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	_prev_camera_zoom = cam.zoom
	_prev_camera_offset = cam.offset
	var view_w := 1280.0 / SAVE_ZOOM
	var target_offset := Vector2((0.5 - SAVE_PLAYER_SCREEN_X) * view_w, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(cam, "zoom", Vector2(SAVE_ZOOM, SAVE_ZOOM), CAMERA_TWEEN)
	tw.tween_property(cam, "offset", target_offset, CAMERA_TWEEN)


func _restore_camera(player: Node2D) -> void:
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(cam, "zoom", _prev_camera_zoom, CAMERA_TWEEN)
	tw.tween_property(cam, "offset", _prev_camera_offset, CAMERA_TWEEN)


func _do_save() -> void:
	if _state != AnimState.IDLE:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	GameState.set_checkpoint(scene.scene_file_path, global_position)
	if player.has_method("restore_full_hp"):
		player.restore_full_hp()  # 真正回满玩家 HP 并刷新 HUD
	GameState.save_game()
	_focus_camera(player)

	save_audio.play()  # 4s 音频放一遍
	_state = AnimState.PLAYING
	_frame_index = 0
	_anim_acc = 0.0
	_sit_active = true

	if player.has_method("start_sit"):
		player.start_sit()


func _exit_sit() -> void:
	if not _sit_active:
		return
	_sit_active = false
	AudioManager.pop_music(_music_key)
	record_switch_ui.hide()
	save_audio.play()   # 退出 sit 再放一遍 wav（不倒放）
	_state = AnimState.REVERSING
	_frame_index = TOTAL_FRAMES - 1
	_anim_acc = 0.0

	var player := get_tree().get_first_node_in_group("player")
	if player:
		_restore_camera(player)  # 退出 sit 时 camera 恢复
		if player.has_method("exit_sit"):
			player.exit_sit()
		# 首次离开留声机：等起身动画（0.2s）与相机恢复（0.3s）完成后授予「悠远的旋律」并播放能力过场。
		# 只在本场景的留声机（grants_heal_melody=true）且玩家尚未获取时触发一次。
		if grants_heal_melody and not GameState.has_heal_melody:
			get_tree().create_timer(0.3).timeout.connect(_grant_heal_melody)


func _start_selected_record() -> void:
	var record_audio := GameState.get_record_audio(GameState.selected_record_id)
	if record_audio == null:
		_update_record_switch_ui()
		return
	AudioManager.push_music(_music_key, record_audio, true)


func _update_record_switch_ui() -> void:
	if not _sit_active:
		record_switch_ui.hide()
		return
	var records := GameState.get_owned_records()
	if records.size() < 2:
		record_switch_ui.hide()
		return
	record_switch_ui.show()
	var selected_index := 0
	for index in records.size():
		if str(records[index].get("id", "")) == GameState.selected_record_id:
			selected_index = index
			break
	var selected := records[selected_index]
	record_name_label.text = str(selected.get("title", "未命名唱片"))
	var selected_audio := GameState.get_record_audio(GameState.selected_record_id)
	record_status_label.text = "当前播放" if selected_audio != null else "音频占位"
	previous_record_button.disabled = false
	next_record_button.disabled = false


func _select_previous_record() -> void:
	_select_record(-1)


func _select_next_record() -> void:
	_select_record(1)


func _select_record(direction: int) -> void:
	var records := GameState.get_owned_records()
	if records.size() < 2:
		return
	var selected_index := 0
	for index in records.size():
		if str(records[index].get("id", "")) == GameState.selected_record_id:
			selected_index = index
			break
	selected_index = posmod(selected_index + direction, records.size())
	var record_id := str(records[selected_index].get("id", ""))
	if not GameState.select_record(record_id):
		return
	GameState.save_game()
	var record_audio := GameState.get_record_audio(record_id)
	if record_audio != null and _sit_active:
		if AudioManager.get_current_music_key() == _music_key:
			AudioManager.switch_music(_music_key, record_audio, true)
		else:
			AudioManager.push_music(_music_key, record_audio, true)
	_update_record_switch_ui()


func _grant_heal_melody() -> void:
	if GameState.has_heal_melody:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("grant_heal_melody"):
		player.grant_heal_melody()  # 播放能力过场（内部会暂停游戏）
		GameState.save_game()
