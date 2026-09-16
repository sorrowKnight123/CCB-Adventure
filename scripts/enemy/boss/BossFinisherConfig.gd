extends Resource
class_name BossFinisherConfig
## 尾杀时间轴配置。note_spawn_times 非空时，按相对尾杀开始时间出音符。

@export var note_count: int = 8
@export var first_note_delay: float = 0.0
@export var note_interval: float = 0.8
@export var note_duration: float = 1.0
@export var perfect_window: float = 0.2
@export var required_perfect: int = 6
@export var intro_duration: float = 0.5
@export var outro_duration: float = 0.5
@export var note_spawn_times: PackedFloat32Array = PackedFloat32Array()
@export var success_intro_duration: float = 0.4
@export var violin_pull_duration: float = 0.8
@export var retaliation_damage: int = 2
@export var retaliation_pause: float = 0.25
@export var vulnerable_duration: float = 3.0
@export_range(0.05, 1.0, 0.05) var recovery_hp_ratio: float = 0.25
@export var finisher_end_time: float = 28.0


func get_note_spawn_time(index: int) -> float:
	if index >= 0 and index < note_spawn_times.size():
		return note_spawn_times[index]
	return first_note_delay + float(index) * note_interval


func get_note_count() -> int:
	return note_spawn_times.size() if not note_spawn_times.is_empty() else note_count


func get_total_duration() -> float:
	if get_note_count() <= 0:
		return intro_duration + outro_duration
	return intro_duration + get_note_spawn_time(get_note_count() - 1) + note_duration + outro_duration
