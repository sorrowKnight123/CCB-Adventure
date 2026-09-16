extends Area2D
## Boss 共鸣音符：只负责缩圈、计时和发出一次判定结果。
## 输入由 BossQTEController 统一处理，避免多个音符各自监听左键。

signal judged(perfect: bool)

@onready var note_sprite: Sprite2D = $Visual/NoteSprite
@onready var shrink_ring: Node2D = $Visual/ShrinkRing
@onready var outer_ring: Sprite2D = $Visual/OuterRing
@onready var perfect_sprite: Sprite2D = $Visual/PerfectSprite
@onready var miss_sprite: Sprite2D = $Visual/MissSprite
@onready var perfect_sfx: AudioStreamPlayer = $PerfectSfx
@onready var miss_sfx: AudioStreamPlayer = $MissSfx

var duration: float = 1.0
var perfect_window: float = 0.25
var elapsed: float = 0.0
var active: bool = false
var _resolved: bool = false
@export var perfect_feedback_duration: float = 0.36
@export var perfect_feedback_scale_multiplier: float = 3.0
@export var miss_feedback_duration: float = 0.18


func start(note_duration: float, note_perfect_window: float) -> void:
	duration = maxf(note_duration, 0.05)
	perfect_window = clampf(note_perfect_window, 0.0, duration)
	elapsed = 0.0
	active = true
	_resolved = false
	note_sprite.visible = true
	outer_ring.visible = true
	shrink_ring.visible = true
	perfect_sprite.visible = false
	miss_sprite.visible = false
	shrink_ring.scale = Vector2(1.8, 1.8)
	set_process(true)


func try_hit() -> void:
	if not active or _resolved:
		return
	var timing_error := absf(duration - elapsed)
	_resolve(timing_error <= perfect_window * 0.5)


func is_judgement_window() -> bool:
	if not active or _resolved:
		return false
	return elapsed >= duration - perfect_window * 0.5 and elapsed < duration


func cancel() -> void:
	if active and not _resolved:
		_resolve(false)


func _process(delta: float) -> void:
	if not active or _resolved:
		return
	elapsed += delta
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	shrink_ring.scale = Vector2.ONE * lerpf(1.8, 0.08, progress)
	if elapsed >= duration:
		_resolve(false)


func _resolve(perfect: bool) -> void:
	if _resolved:
		return
	_resolved = true
	active = false
	set_process(false)
	note_sprite.visible = false
	outer_ring.visible = false
	shrink_ring.visible = false
	perfect_sprite.visible = perfect
	miss_sprite.visible = not perfect
	var feedback_sprite: Sprite2D = perfect_sprite if perfect else miss_sprite
	var feedback_sfx: AudioStreamPlayer = perfect_sfx if perfect else miss_sfx
	feedback_sprite.modulate = Color.WHITE
	var feedback_duration: float = perfect_feedback_duration if perfect else miss_feedback_duration
	feedback_sfx.play()
	var feedback_tween := create_tween()
	feedback_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if perfect:
		var target_scale := feedback_sprite.scale * maxf(perfect_feedback_scale_multiplier, 1.0)
		feedback_tween.parallel().tween_property(feedback_sprite, "scale", target_scale, maxf(feedback_duration, 0.01))
	feedback_tween.parallel().tween_property(feedback_sprite, "modulate", Color(1, 1, 1, 0), maxf(feedback_duration, 0.01))
	judged.emit(perfect)
	await feedback_tween.finished
	if feedback_sfx.playing:
		await feedback_sfx.finished
	queue_free()
