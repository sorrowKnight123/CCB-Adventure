@tool
extends Node2D
## 音序模仿小游戏：进区域锁相机 → 站谱台按 W 听一遍 → 玩家按同样顺序攻击史莱姆。
##
## 场景里手摆 N 只 MusicSlime 就是 N 只，数量 / 位置 / 每只的音符都在场景里调，
## 没有档位限制、没有坐标数组。容器 `Slimes` 里子节点的顺序 = 槽位编号（0 = 第一个）。
##
## ── 流程 ──
##   IDLE  未进区：史莱姆与谱台都隐藏
##   ARMED 进区：史莱姆出现、相机滑到史莱姆中心并锁定、玩家仍可自由行动
##   DEMO  站谱台按 W：软冻结玩家，按「演奏顺序」依次闪白 + 出声 + 飘音符
##   PLAY  解锁：玩家按同样顺序攻击；打错 → 归零 + 重播 DEMO
##   DONE  全对：给货币 + 发 `通关` 信号 + mark_trigger（永久完成）
##
## ── 两个刻意的取舍 ──
## ① 演示期间**不**用 `get_tree().paused`：Tween 默认 process_mode = INHERIT，
##    硬暂停会让相机滑入的 Tween 停摆（项目里几份相机实现都没有超时兜底，会挂死）。
##    所以走 `Player.输入软冻结` —— 玩家不能动/不能打，但世界照常跑。
## ② 相机锁定用 BlueWizard 那套（top_level + 钉住 global_position），**不碰 limit_***。
##    limit_* 是全局单一状态、没有引用计数，容易和 GameFlow / BossArena 互相踩。
##    而且锁定期不能用 offset 构图：玩家每次命中都会触发 camera_shake，
##    而 Player._process_camera_shake 在震动结束时会强制把 offset 写回 ZERO。

signal 通关

enum State { IDLE, ARMED, DEMO, PLAY, DONE }

const NOTE_TEXTURE: Texture2D = preload("res://art/icons/note.png")
const SFX_MISS: AudioStream = preload("res://audio/enemy/moss/miss.wav")
const NOTE_PICKUP_SCENE: PackedScene = preload("res://scenes/items/NotePickup.tscn")

@export_category("曲子")
## 留空则用下面的默认值（演奏顺序 = 从左到右）。
@export var 配置: MusicGameConfig
## 用于永久完成（GameState.mark_trigger）。多个小游戏实例要用不同的 ID。
@export var 触发ID: String = "music_game_1"
## 没有配 `配置` 时用的奖励数量。
@export var 默认通关奖励: int = 30

@export_category("场地")
## 打开后按 `平铺起点 + 间距` 在运行时重排史莱姆 —— ⚠️ 会覆盖你手摆的位置。
## 只在快速搭一排新的时打开，调好位置后关掉。
## 间距默认 220：玩家近战判定盒 1 段 80px、3 段 105px 宽，
## 间距太小会一次挥砍同时罩到相邻两只（虽然判定会优先认目标那只，但少蹭到更干净）。
@export var 自动平铺: bool = false
@export var 平铺起点: Vector2 = Vector2.ZERO
@export var 间距: float = 220.0

@export_category("手感")
## 通关奖励不从天上直接进账，而是把 `通关奖励` 个音符**抛到场地里**让玩家自己捡。
## 这里只给初速度 —— 之后加重力、撞墙、落平台、落斜坡全交给物理引擎（NotePickup 是 CharacterBody2D）。
## 横向随机 ±`奖励横向初速度`；纵向向上 `奖励上抛初速度` 的 0.75~1.25 倍。
@export var 奖励横向初速度: float = 480.0
@export var 奖励上抛初速度: float = 520.0
## 抛出点比史莱姆中心抬高多少像素。
## ⚠️ 必须 > 0：拾取物的碰撞圆圆心如果正好压在地面高度上（史莱姆中心就在地面上），
## 第一帧 move_and_slide() 就会判定 is_on_floor() → 速度清零 → 原地落下、完全飞不出去。
@export var 奖励抛出点抬高: float = 80.0
@export var 音符特效大小: float = 0.34
@export var 音符飘动距离: float = 70.0
@export var 音符飘动时长: float = 0.65
@export var 演示前停顿: float = 0.45
@export var 演示后停顿: float = 0.5
@export var 打错后重播延迟: float = 0.9
@export var 相机滑入时长: float = 0.6
## 锁定时镜头往上偏多少像素：史莱姆落在画面偏下位置，上方留出空间。
@export var 相机垂直偏移: float = 150.0
## 锁定期间镜头允许在基准点周围"滑动"的范围（像素）。
## 玩家在范围内 → 镜头完全固定；超出范围 → 镜头跟着走这么多，好把玩家留在画面里。
## ⚠️ 两个分量都要明显小于半屏（1280×720 的一半 = 640×360），否则玩家会被甩出画面。
@export var 相机滑动范围: Vector2 = Vector2(260.0, 170.0)
## 演示期间改用"框住所有史莱姆"的取景：以史莱姆群包围盒（四周加 `演示框选留白`）为准，
## 必要时把镜头拉远到 `演示最小缩放`。此时**不再保证玩家在画面内**
## （玩家本来就被软冻结、动不了），演示结束后自动切回"跟着玩家"。
@export var 演示自动缩放: bool = true
@export var 演示框选留白: Vector2 = Vector2(120.0, 150.0)
@export var 演示最小缩放: float = 0.55
@export var 相机框选速度: float = 7.0
@export var 流光周期: float = 2.4
@export var 谱台浮动幅度: float = 7.0
@export var 谱台浮动速度: float = 1.8

@export_category("调试")
## 在编辑器里画出每只槽位的编号 + 音名（颜色 = 该音的颜色）。
## 「演奏顺序」填的是编号，靠这个才看得出 0 号、1 号分别是哪只。
@export var 调试显示槽位: bool = true

var _state: int = State.IDLE
var _slimes: Array = []
var _demo_sequence: PackedInt32Array = PackedInt32Array()   # 演示用（含停顿标记）
var _answer_sequence: PackedInt32Array = PackedInt32Array() # 玩家要复现的（去掉停顿）
var _progress: int = 0
## 演示协程代号：状态一变就作废上一段协程，避免重复触发时两段演示叠着跑。
var _serial: int = 0
var _pending_hits: Array = []
var _player_on_pedestal: bool = false
var _sweep_time: float = 0.0
var _bob_time: float = 0.0
var _pedestal_base_position: Vector2 = Vector2.ZERO
var _sfx_index: int = 0

# 相机保存（BlueWizard 那套）
var _camera: Camera2D = null
var _saved_top_level: bool = false
var _saved_smoothing: bool = true
var _saved_offset: Vector2 = Vector2.ZERO
var _saved_position: Vector2 = Vector2.ZERO
var _saved_zoom: Vector2 = Vector2.ONE
var _camera_tween: Tween = null
var _camera_locked: bool = false
var _demo_framing: bool = false      # 演示取景中（框所有史莱姆，不管玩家）

@onready var _slimes_root: Node2D = $Slimes
@onready var _fx: Node2D = $FxLayer
@onready var _trigger: Area2D = $Trigger
@onready var _pedestal: Area2D = $Pedestal
@onready var _pedestal_visual: Sprite2D = $Pedestal/Visual
@onready var _prompt: Label = $Pedestal/Prompt
@onready var _sfx: Array = [$Sfx/Sfx0, $Sfx/Sfx1, $Sfx/Sfx2]


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	_slimes = _collect_slimes()
	if 自动平铺:
		_apply_tiling()
	for i in _slimes.size():
		(_slimes[i] as Node2D).被击中.connect(_on_slime_hit.bind(i))
	_trigger.body_entered.connect(_on_trigger_entered)
	_trigger.body_exited.connect(_on_trigger_exited)
	_pedestal.body_entered.connect(_on_pedestal_entered)
	_pedestal.body_exited.connect(_on_pedestal_exited)
	_pedestal_base_position = _pedestal_visual.position
	# 谱台一直可见、一直可交互；史莱姆等到跟谱台交互之后才出现。
	if GameState.has_trigger(触发ID):
		# 已通关：整排史莱姆留在场景里，保持变暗状态（不隐藏、不删除）
		_state = State.DONE
		_set_slimes_visible(true)
		_dim_all_slimes()
	else:
		_set_slimes_visible(false)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	_animate_pedestal(delta)
	if _camera_locked:
		_update_locked_camera(delta)
	if _state == State.ARMED and _player_on_pedestal \
			and Input.is_action_just_pressed("interact"):
		_start_demo()


# ──────────────────────────── 区域进入 / 离开 ────────────────────────────


func _on_trigger_entered(body: Node2D) -> void:
	if _state != State.IDLE or not body.is_in_group("player"):
		return
	_state = State.ARMED
	# 只锁相机；史莱姆要等玩家跟谱台交互才出现。
	_slide_camera_and_lock()


func _on_trigger_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	# 走远就取消（不设墙，避免卡死）。DEMO 期间玩家被软冻结、理论上走不出去，
	# 但万一触发也一并取消，顺便保证不会被永久冻住。
	if _state == State.ARMED or _state == State.PLAY or _state == State.DEMO:
		_cancel_to_idle()


func _cancel_to_idle() -> void:
	_state = State.IDLE
	_serial += 1
	_set_player_frozen(false)
	_reset_progress()
	_set_slimes_visible(false)
	if _prompt != null:
		_prompt.visible = false
	_restore_camera()


# ──────────────────────────── 演示 ────────────────────────────


func _start_demo() -> void:
	_demo_sequence = _config_demo_sequence()
	_answer_sequence = _config_answer_sequence()
	if _answer_sequence.is_empty():
		push_warning("音乐小游戏：演奏序列是空的（只有停顿？还是 Slimes 下没有子节点？）")
		return
	_set_slimes_visible(true)   # 与谱台交互 → 史莱姆出现
	if _prompt != null:
		_prompt.visible = false
	_run_demo()


func _run_demo() -> void:
	_serial += 1
	var serial := _serial
	_state = State.DEMO
	_demo_framing = true      # 演示期间优先保证所有史莱姆在镜头内
	_set_player_frozen(true)
	_reset_progress()
	await get_tree().create_timer(演示前停顿).timeout
	if serial != _serial:
		return
	for entry in _demo_sequence:
		# 停顿（0）照样占一个节拍，但不出声、不闪白、不飘音符
		if entry != MusicGameConfig.停顿:
			_play_slot(entry)
		await get_tree().create_timer(_demo_interval()).timeout
		if serial != _serial:
			return
	await get_tree().create_timer(演示后停顿).timeout
	if serial != _serial:
		return
	_state = State.PLAY
	_demo_framing = false     # 回到"跟着玩家"的取景
	_restore_locked_zoom()
	_set_player_frozen(false)


func _play_slot(slot: int) -> void:
	## 一只史莱姆"被弹响"：受击表现 + 出声 + 飘一个同色音符。
	if slot < 0 or slot >= _slimes.size():
		return
	var slime := _slimes[slot] as Node2D
	slime.play_hurt()
	_play_note(slime.get_note())
	_spawn_note_fx(slime.global_position + Vector2(0.0, -72.0), MusicNotes.get_color(slime.get_note()))


func _play_note(note_name: String) -> void:
	## 3 个播放器轮转：8 个音各 1.5093s，单个播放器在间隔 <1.5s 时会切掉前一个音。
	var stream := MusicNotes.get_stream(note_name)
	if stream == null:
		return
	var player := _sfx[_sfx_index] as AudioStreamPlayer
	_sfx_index = (_sfx_index + 1) % _sfx.size()
	player.stream = stream
	player.play()


func _spawn_note_fx(world_position: Vector2, color: Color) -> void:
	## 仿 JumpPlant._spawn_note()：飘起 + 淡出。颜色提亮一点，
	## 因为 art/icons/note.png 是银白底图（亮度 ~0.67），直接 modulate 会偏暗。
	var note := Sprite2D.new()
	note.texture = NOTE_TEXTURE
	note.modulate = Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, 1.0)
	note.scale = Vector2.ONE * 音符特效大小
	_fx.add_child(note)
	note.global_position = world_position
	var tween := note.create_tween()
	tween.set_parallel(true)
	tween.tween_property(note, "global_position:y", world_position.y - 音符飘动距离, 音符飘动时长)
	tween.tween_property(note, "modulate:a", 0.0, 音符飘动时长)
	tween.chain().tween_callback(note.queue_free)


# ──────────────────────────── 玩家演奏与判定 ────────────────────────────


func _on_slime_hit(from_pos: Vector2, slot: int) -> void:
	if _state != State.PLAY:
		return
	_pending_hits.append({"slot": slot, "from_pos": from_pos})
	# 延到本帧所有 _physics_process 跑完再仲裁：一次挥砍可能同时碰到多只。
	_resolve_pending_hits.call_deferred()


func _resolve_pending_hits() -> void:
	var hits := _pending_hits
	_pending_hits = []
	if hits.is_empty() or _state != State.PLAY:
		return
	# 一次挥砍的判定盒（1 段 80px、3 段 105px 宽）可能同时罩到相邻两只史莱姆。
	# 规则：**只要其中包含"该打的那只"就算对**，忽略被蹭到的其他只。
	# （否则玩家站位稍偏就会莫名判错。）
	var expected := int(_answer_sequence[_progress])
	for hit in hits:
		if int(hit["slot"]) == expected:
			_resolve_hit(expected)
			return
	# 没碰到目标 → 取离玩家最近的一只当作"打错的那只"
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var best_slot: int = hits[0]["slot"]
	var best_distance := INF
	for hit in hits:
		var slot: int = hit["slot"]
		var distance := 0.0
		if player != null:
			distance = player.global_position.distance_to((_slimes[slot] as Node2D).global_position)
		if distance < best_distance:
			best_distance = distance
			best_slot = slot
	_resolve_hit(best_slot)


func _resolve_hit(slot: int) -> void:
	if _progress >= _answer_sequence.size():
		return
	if slot == int(_answer_sequence[_progress]):
		_progress += 1
		# 玩家自己弹奏时也要出声 + 飘音符（受击表现已由 take_damage 触发了）。
		# ⚠️ 这里**不做**"打对就变暗"：同一只史莱姆可能在序列里被弹响多次。
		var slime := _slimes[slot] as Node2D
		_play_note(slime.get_note())
		_spawn_note_fx(slime.global_position + Vector2(0.0, -72.0), MusicNotes.get_color(slime.get_note()))
		if _progress >= _answer_sequence.size():
			_complete()
	else:
		_fail()


func _fail() -> void:
	## 打错：归零 + 播 miss 反馈 + 停顿后自动重播演示。期间保持软冻结。
	_serial += 1
	var serial := _serial
	_state = State.DEMO
	_set_player_frozen(true)
	_reset_progress()
	_play_miss()
	await get_tree().create_timer(打错后重播延迟).timeout
	if serial != _serial:
		return
	_run_demo()


func _play_miss() -> void:
	var player := _sfx[_sfx_index] as AudioStreamPlayer
	_sfx_index = (_sfx_index + 1) % _sfx.size()
	player.stream = SFX_MISS
	player.play()


func _reset_progress() -> void:
	## 只归零进度。史莱姆的"变暗"只发生在通关那一刻，所以这里不用恢复外观。
	_progress = 0


func _dim_all_slimes() -> void:
	## 通关：整排史莱姆变暗，但**保留在场景里**（不隐藏、不删除）。
	for slime in _slimes:
		(slime as Node2D).设为已完成()


func _complete() -> void:
	_state = State.DONE
	_serial += 1
	_set_player_frozen(false)
	GameState.mark_trigger(触发ID)
	GameState.save_game()
	_spawn_reward_pickups()
	通关.emit()
	_dim_all_slimes()
	_restore_camera()


func _spawn_reward_pickups() -> void:
	## 通关奖励散落一地，玩家自己捡。
	## - **不直接入账**：金额只在真的捡到时才 +1（NotePickup 自己处理）。
	## - **不弹「+N」提示**：玩家看左上角的音符计数就知道拿了多少，别用文字破坏沉浸感。
	## - 每个拾取物价值 1，数量 = `通关奖励`；想少捡几次就把 通关奖励 调小。
	## ⚠️ 拾取物只存在于当前场景：通关后若没捡完就离开房间（场景重载），剩下的就没了。
	var total := _config_reward()
	if total <= 0:
		return
	var parent := get_parent()
	if parent == null:
		return
	var origin := _slimes_center() + Vector2(0.0, -奖励抛出点抬高)
	for i in total:
		var pickup := NOTE_PICKUP_SCENE.instantiate()
		pickup.显示提示 = false
		parent.add_child(pickup)
		pickup.global_position = origin
		# 只给初速度：往上抛 + 左右散开。撞墙、落平台、落斜坡全交给物理引擎。
		var vx := randf_range(-奖励横向初速度, 奖励横向初速度)
		var vy := -奖励上抛初速度 * randf_range(0.75, 1.25)
		pickup.setup_launch(1, Vector2(vx, vy))


# ──────────────────────────── 配置读取 ────────────────────────────


func _config_demo_sequence() -> PackedInt32Array:
	## 演示序列（含停顿标记）。
	if 配置 != null:
		return 配置.演示序列(_slimes.size())
	var out := PackedInt32Array()
	for i in _slimes.size():
		out.append(i)
	return out


func _config_answer_sequence() -> PackedInt32Array:
	## 玩家要复现的序列：去掉所有停顿。没有配 `配置` 时跟演示序列一样（从左到右）。
	if 配置 != null:
		return 配置.演奏序列(_slimes.size())
	return _config_demo_sequence()


func _config_reward() -> int:
	return 配置.通关奖励 if 配置 != null else 默认通关奖励


func _demo_interval() -> float:
	return maxf(配置.演示间隔 if 配置 != null else 0.5, 0.05)


# ──────────────────────────── 槽位 / 可见性 / 平铺 ────────────────────────────


func _collect_slimes() -> Array:
	## 容器里带 get_note() 的 Node2D 才是槽位（顺序 = 子节点顺序）。
	var out := []
	var root := get_node_or_null("Slimes")
	if root == null:
		return out
	for child in root.get_children():
		if child is Node2D and child.has_method("get_note"):
			out.append(child)
	return out


func _set_slimes_visible(active: bool) -> void:
	## ⚠️ 只切可见性，**绝不改 collision_layer**。
	## 曾经用 `collision_layer = 0/4` 来表示"史莱姆未出现/已出现"，结果玩家挥砍完全打不到它们：
	## 运行时改动一个 StaticBody2D 的碰撞层之后，**已经存在并处于 monitoring 的 Area2D
	## 不会重新评估这个重叠**（新创建的 Area2D 反而能发现它）。可见性完全够用 ——
	## 非 PLAY 阶段的命中本来就被 `_on_slime_hit` 忽略掉了。
	_slimes_root.visible = active


func _apply_tiling() -> void:
	for i in _slimes.size():
		(_slimes[i] as Node2D).position = 平铺起点 + Vector2(间距 * float(i), 0.0)


func _animate_pedestal(delta: float) -> void:
	if _pedestal_visual == null:
		return
	# 小幅上下浮动，让谱台在场景里更醒目
	_bob_time += delta
	_pedestal_visual.position.y = _pedestal_base_position.y \
		+ sin(_bob_time * 谱台浮动速度) * 谱台浮动幅度
	var material := _pedestal_visual.material as ShaderMaterial
	if material == null:
		return
	_sweep_time = fmod(_sweep_time + delta / maxf(流光周期, 0.05), 1.0)
	material.set_shader_parameter("sweep", _sweep_time)


func _on_pedestal_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_on_pedestal = true
		if _prompt != null:
			_prompt.visible = _state == State.ARMED


func _on_pedestal_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_on_pedestal = false
		if _prompt != null:
			_prompt.visible = false


# ──────────────────────────── 玩家软冻结 ────────────────────────────


func _set_player_frozen(frozen: bool) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if player.get("输入软冻结") == null:
		return   # 玩家脚本没有这个开关（旧版本），静默跳过
	if player.get("输入软冻结") != frozen:
		player.set("输入软冻结", frozen)


# ──────────────────────────── 相机（BlueWizard 那套） ────────────────────────────


func _acquire_camera() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return false
	_camera = player.get_node_or_null("Camera2D") as Camera2D
	return _camera != null


func _slimes_center() -> Vector2:
	if _slimes.is_empty():
		return global_position
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for slime in _slimes:
		var p := (slime as Node2D).global_position
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	return Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)


func _camera_focus_point() -> Vector2:
	## 镜头基准点：史莱姆群中心再往上偏 `相机垂直偏移`。
	## 史莱姆因此落在画面偏下位置，上方留出空间（平台跳跃的常见构图）。
	return _slimes_center() + Vector2(0.0, -相机垂直偏移)


func _camera_target_position() -> Vector2:
	## 锁定期间的镜头目标 = 基准点 + 被 `相机滑动范围` 夹住的玩家偏移。
	## 效果：玩家在范围内时镜头纹丝不动（"锁定"）；他走远了镜头才跟一点，
	## 保证他不会被甩出画面。用户明确要求"优先保证玩家在镜头内"。
	##
	## ⚠️ 玩家偏移要相对**史莱姆中心**算，不能相对基准点算：
	## 玩家站在地面上，天然就在基准点下方约 `相机垂直偏移` 的距离，
	## 相对基准点算的话这个偏移会把自己抵消掉，垂直构图完全失效。
	var base := _slimes_center()
	var focus := _camera_focus_point()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return focus
	var offset := player.global_position - base
	return focus + Vector2(
		clampf(offset.x, -相机滑动范围.x, 相机滑动范围.x),
		clampf(offset.y, -相机滑动范围.y, 相机滑动范围.y))


func _update_locked_camera(delta: float) -> void:
	if not is_instance_valid(_camera):
		return
	if _demo_framing:
		# 演示取景：框住所有史莱姆，顺便把镜头拉远到能装下
		var bounds := _slimes_bounds()
		var target_position := bounds.get_center()
		var target_zoom := _demo_zoom(bounds) if 演示自动缩放 else Vector2.ONE
		# 平滑过去（直接赋值会是很突兀的一跳）
		var t := clampf(delta * 相机框选速度, 0.0, 1.0)
		_camera.global_position = _camera.global_position.lerp(target_position, t)
		_camera.zoom = _camera.zoom.lerp(target_zoom, t)
		return
	_camera.global_position = _camera_target_position()


func _slimes_bounds() -> Rect2:
	## 史莱姆群的包围盒（四周加 `演示框选留白`），用来把它们全部框进画面。
	if _slimes.is_empty():
		return Rect2(global_position, Vector2.ZERO)
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for slime in _slimes:
		var p := (slime as Node2D).global_position
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	return Rect2(
		Vector2(min_x - 演示框选留白.x, min_y - 演示框选留白.y),
		Vector2((max_x - min_x) + 演示框选留白.x * 2.0,
			(max_y - min_y) + 演示框选留白.y * 2.0))


func _demo_zoom(bounds: Rect2) -> Vector2:
	## 让 bounds 全部装进视口所需的缩放。
	## ⚠️ Godot 里 zoom < 1 是**拉远**（看到更多），所以这里是 min() 不是 max()。
	var view := get_viewport().get_visible_rect().size
	if view.x <= 0.0 or view.y <= 0.0 or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return Vector2.ONE
	var z := minf(1.0, minf(view.x / bounds.size.x, view.y / bounds.size.y))
	return Vector2(maxf(z, 演示最小缩放), maxf(z, 演示最小缩放))


func _slide_camera_and_lock() -> void:
	if not _acquire_camera():
		return
	var start_position := _camera.global_position
	_saved_top_level = _camera.top_level
	_saved_smoothing = _camera.position_smoothing_enabled
	_saved_offset = _camera.offset
	_saved_position = _camera.position
	_saved_zoom = _camera.zoom
	# 切 top_level 会改变继承来的变换，必须先存下世界坐标再赋回，否则会先跳一下。
	_camera.top_level = true
	_camera.position_smoothing_enabled = false
	_camera.offset = Vector2.ZERO
	_camera.global_position = start_position
	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween()
	_camera_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(_camera, "global_position", _camera_target_position(), 相机滑入时长)
	_camera_tween.tween_callback(_finish_camera_lock)


func _finish_camera_lock() -> void:
	if not is_instance_valid(_camera):
		return
	_camera_locked = true
	_camera.global_position = _camera_target_position()
	_camera.reset_smoothing()


func _restore_locked_zoom() -> void:
	## 退出演示取景后把缩放还原成玩家自己的值（演示期间我们改过 zoom）。
	if not is_instance_valid(_camera):
		return
	var tw := create_tween()
	tw.tween_property(_camera, "zoom", _saved_zoom, 0.4)


func _restore_camera() -> void:
	_camera_locked = false
	_demo_framing = false
	if not is_instance_valid(_camera):
		return
	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var target := player.global_position if player != null else _camera.global_position
	_camera_tween = create_tween()
	_camera_tween.set_parallel(true)
	_camera_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(_camera, "zoom", _saved_zoom, 相机滑入时长)
	_camera_tween.chain().tween_property(_camera, "global_position", target, 相机滑入时长)
	_camera_tween.chain().tween_callback(_finish_camera_restore)


func _finish_camera_restore() -> void:
	if not is_instance_valid(_camera):
		return
	_camera.top_level = _saved_top_level
	_camera.position_smoothing_enabled = _saved_smoothing
	_camera.offset = _saved_offset
	if not _saved_top_level:
		_camera.position = _saved_position
	_camera.reset_smoothing()


# ──────────────────────────── 编辑器可视化 ────────────────────────────


func _draw() -> void:
	if not Engine.is_editor_hint() or not 调试显示槽位:
		return
	var font := ThemeDB.fallback_font
	var slots := _collect_slimes()
	for i in slots.size():
		var slime := slots[i] as Node2D
		var note: String = str(slime.get_note())
		var center := to_local(slime.global_position)
		draw_line(center + Vector2(-14.0, 0.0), center + Vector2(14.0, 0.0), Color(1, 1, 0, 0.85), 1.0)
		draw_line(center + Vector2(0.0, -14.0), center + Vector2(0.0, 14.0), Color(1, 1, 0, 0.85), 1.0)
		draw_string(font, center + Vector2(18.0, -18.0), "%d  %s" % [i + 1, note],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MusicNotes.get_color(note))
	draw_string(font, Vector2(0.0, -8.0),
		"演奏顺序：0 = 停顿，1..N = 第 N 只（上面的编号从 1 开始）；留空 = 从左到右",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
