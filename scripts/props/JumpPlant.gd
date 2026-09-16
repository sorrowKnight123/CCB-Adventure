extends AnimatedSprite2D
## 弹跳植物（level3）：玩家从上方踩踏 → 植物播放 jump 动画 + 玩家弹跳。
## idle 动画（PlantJump2 序列，待机晃动）↔ jump 动画（PlantJump 序列）。
## 弹跳效果：① 玩家弹跳（跳跃强度可调）；② 随机钢琴音（C4-C5 八音等概率）；
##            ③ 随机颜色音符图标（note.png）等概率出现在植物左侧或右侧，飘起淡出（音符大小可调）。

@export var 跳跃强度: float = 700.0     # 玩家弹跳初速度（越大跳越高）
@export var 音符大小: float = 0.25       # 音符图标缩放（note.png 104x130，可调）
@export var 音符飘动速度: float = 70.0   # 音符飘起速度（px/s）
@export var 触发冷却: float = 0.4        # 防连续触发

const PIANO_NOTES: Array[AudioStream] = [
	preload("res://audio/enemy/effect/piano_notes_C4-C5/C4.wav"),
	preload("res://audio/enemy/effect/piano_notes_C4-C5/D4.wav"),
	preload("res://audio/enemy/effect/piano_notes_C4-C5/E4.wav"),
	preload("res://audio/enemy/effect/piano_notes_C4-C5/F4.wav"),
	preload("res://audio/enemy/effect/piano_notes_C4-C5/G4.wav"),
	preload("res://audio/enemy/effect/piano_notes_C4-C5/A4.wav"),
	preload("res://audio/enemy/effect/piano_notes_C4-C5/B4.wav"),
	preload("res://audio/enemy/effect/piano_notes_C4-C5/C5.wav"),
]
const NOTE_TEXTURE: Texture2D = preload("res://art/hud/note.png")
# 音符随机颜色池（等概率取一个）
const NOTE_COLORS: Array[Color] = [
	Color(1.0, 0.25, 0.3), Color(1.0, 0.6, 0.1), Color(1.0, 0.9, 0.2),
	Color(0.35, 0.9, 0.35), Color(0.3, 0.75, 1.0), Color(0.6, 0.4, 1.0),
]

var _cooldown: float = 0.0
var _bouncing := false

@onready var audio_player: AudioStreamPlayer = $PianoPlayer


func _ready() -> void:
	play("idle")
	$Trigger.body_entered.connect(_on_trigger_body_entered)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func _on_trigger_body_entered(body: Node2D) -> void:
	if _cooldown > 0.0 or _bouncing:
		return
	if not body.is_in_group("player"):
		return
	# 只响应玩家下落（从上方踩踏）；从下方顶上来不触发
	if body.velocity.y <= 0.0:
		return
	_bounce(body)


func _bounce(player: Node2D) -> void:
	_cooldown = 触发冷却
	_bouncing = true
	play("jump")
	# 1) 玩家弹跳
	player.velocity.y = -跳跃强度
	# 1b) 刷新玩家空中行动：可再冲刺一次 + 二段跳次数重置
	if player.has_method("reset_air_actions"):
		player.reset_air_actions()
	# 2) 随机钢琴音（等概率八音）
	var note: AudioStream = PIANO_NOTES[randi() % PIANO_NOTES.size()]
	audio_player.stream = note
	audio_player.play()
	# 3) 随机颜色音符，等概率出现在植物左/右，飘起淡出
	_spawn_note()
	# 4) jump 动画播完回 idle
	var sf: SpriteFrames = sprite_frames
	var dur := 0.0
	for i in sf.get_frame_count("jump"):
		dur += sf.get_frame_duration("jump", i)
	await get_tree().create_timer(dur / sf.get_animation_speed("jump")).timeout
	_bouncing = false
	play("idle")


func _spawn_note() -> void:
	var note := Sprite2D.new()
	note.texture = NOTE_TEXTURE
	note.modulate = NOTE_COLORS[randi() % NOTE_COLORS.size()]
	note.scale = Vector2.ONE * 音符大小
	# 等概率左/右，出现位置：植物两侧略偏移
	var side := 1.0 if randi() % 2 == 0 else -1.0
	var offset := 90.0 * scale.x * side  # 相对植物宽度
	note.position = Vector2(offset, -30.0 * scale.y)
	# 音符在弹跳植物下方挂靠（随植物移动），结束后独立飘起 —— 直接加到场景层
	var world := get_parent()
	note.global_position = to_global(note.position)
	world.add_child(note)
	# 飘起 + 淡出
	var tween := note.create_tween()
	tween.set_parallel(true)
	tween.tween_property(note, "global_position:y", note.global_position.y - 60.0, 0.6)
	tween.tween_property(note, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(note.queue_free)
