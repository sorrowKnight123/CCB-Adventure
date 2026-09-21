@tool
extends CharacterBody2D
## 88 一阶段本体（人形）：读距离走位 + 四招 + 非致命收尾 + 唱片分支。
##
## 目标手感（《88_Boss_技术实现与美术资源清单.md》§1）：**重而可读**。
## 每招按三段节奏 —— 前摇(慢) → 悬停(几乎静止) → 出手(极快)，命中帧只有 1~2 帧。
## 判定只在命中帧取一次 `attack_hitbox.get_overlapping_bodies()`（`agent.md §13.4`）。
##
## 动画只 play 名字，帧由 `art/enemies/boss88/88_frames.tres` 承载 ——
## 换美术 = 换那个 .tres，本脚本不用改（骨架版先用占位贴图铺满设计帧数）。
##
## 走位用**两个 Area2D** 表达距离（近身盒 / 中距盒），不加距离数值：
## 玩家在近身盒内 → 拉开；在中距盒内 → 站定读距离；在中距盒外 → 靠近。
## 这两个盒在编辑器里可视化（`@tool` + `_draw`），符合 §13.4 的初衷。

signal health_changed(current: int, maximum: int)
signal boss_battle_started
signal phase_changed(phase: int)
signal victory
## 收尾完成：`走真结局` 由唱片选择决定，交给关卡去接变身或结局
signal 收尾完成(走真结局: bool)

enum State { AWAIT, INTRO, IDLE, ATTACK, KNOCKED, WEAKENED, RECORD, DONE }

const BOSS_ID := "boss88_phase1"
const DIALOGUE_FILE: String = "res://dialogues/game.dialogue"
const 狂喜之诗ID: String = "ecstasy_poem"
const STAFF_SWEEP: PackedScene = preload("res://scenes/enemies/boss/StaffSweep.tscn")
## 四招的 id（`_选招` 的返回值 / 权重表的键）
const 全部招式: Array[String] = ["claw", "thrust", "blink", "staff"]

@export_group("数值")
@export var 最大生命值: int = 90
## 每次命中玩家的伤害（招式与接触共用；终章不靠高伤）
@export var 伤害: int = 1
## 生命值降到这个比例以下后出手变快（一阶段内部的一点变化）
@export_range(0.1, 0.9, 0.05) var 半血阈值: float = 0.5
@export var 击退速度: float = 260.0

@export_group("走位")
@export var 移动速度: float = 110.0
@export var 重力: float = 1200.0
## 88 自己的活动范围（竞技场锁 x0~1600，这里留 200px 可视边距）
@export var 活动左: float = 200.0
@export var 活动右: float = 1400.0
## 两个距离盒的半径（编辑器里可视化；改这两个值就等于改"近 / 中"的定义）
@export var 近身盒半径: float = 150.0
@export var 中距盒半径: float = 420.0

@export_group("出招节奏")
@export var 出手间隔: float = 1.8
@export var 出手间隔_半血: float = 1.4
## 命中帧（帧号，对应 88_frames.tres 里各动画的帧序列）
@export var 爪击命中帧: int = 10
@export var 爪击三命中帧: int = 16
@export var 突刺命中帧: int = 16
@export var 闪现前摇帧: int = 5
## 五线谱在哪一帧生成（staff_cast 共 18 帧，17 = 举棒预警的最后一帧）
@export var 五线谱生成帧: int = 17
## 站定打击（爪击）的判定盒开启时长，单位**物理帧**。2 = 1 帧刷重叠表 + 1 帧结算。
@export_range(2, 6, 1) var 命中盒持续帧: int = 2

@export_group("判定盒几何")
## 判定盒中心相对身体的**前伸距离**。判定盒前缘 = 本值 + 形状半宽(65)，
## 必须 >= 近身盒半径，否则玩家站在"近身"带边缘时爪击够不着（自检会拦）。
## ⚠️ 改体型/换贴图时这里要跟着调 —— 以前它是硬编码的 56，不随体型更新。
@export var 判定盒前伸: float = 95.0

@export_group("位移距离")
## 出手时向前压的距离（像素）。**按距离驱动、不按帧数** ——
## 顿帧会把 time_scale 压到 0，等帧数会让位移归零，等距离只是把动作拉长。
@export var 爪击前突距离: float = 60.0
@export var 爪击三前突距离: float = 40.0
## 前突刺的冲程。设计稿写 225px，实机手感要 5 倍（= 417px）才够得着中距带远端
@export var 突刺距离: float = 417.0
@export var 爪击前突速度: float = 520.0
@export var 爪击三前突速度: float = 360.0
@export var 突刺速度: float = 1250.0
## 冲刺保险丝：最多等这么多物理帧（防"距离永远走不到"时卡死协程）
@export var 冲刺最长帧: int = 600
@export var 闪现背后距离: float = 200.0
@export var 落点探测距离: float = 260.0

@export_group("AI 权重")
## 符合距离带的招式概率；剩下三招平分 1-本值。
## 远带有**两招**偏好（闪现/五线谱）→ 它们平分这个 3/4。
@export_range(0.5, 0.9, 0.05) var 偏好概率: float = 0.75
## 同一招最多连用几次（连满就把它权重归零，在其余招里重抽）
@export_range(1, 4, 1) var 同招连用上限: int = 2

@export_group("五线谱")
@export var 五线谱速度: float = 260.0
@export var 五线谱伤害: int = 1

@export_group("音效 · 起手音（预备拍）")
## 四招各一个起手音，**在动画第 0 帧播** —— 音乐主题的 Boss，让玩家"听出下一招"。
## ⚠️ 这几个音是玩家的判断依据，播放时**不做音高抖动**（抖了就分不清是哪一招）。
@export var 起手音_爪击: AudioStream
@export var 起手音_五线谱: AudioStream
@export var 起手音_突刺: AudioStream
@export var 起手音_闪现: AudioStream

@export_group("音效 · 招式音（动作拍）")
## 命中帧那一瞬的挥击/冲刺声。和起手音错开约 0.4~0.7 秒，凑成"预备 → 出手"两拍。
@export var 招式音_爪击: AudioStream
@export var 招式音_五线谱: AudioStream
@export var 招式音_突刺: AudioStream
## 闪现分两次响：消失一声、现身一声（中间隔 0.5 秒，玩家靠这两声定位它去了哪）
@export var 招式音_闪现消失: AudioStream
@export var 招式音_闪现现身: AudioStream

@export_group("音效 · 反馈")
@export var 音效_受击: AudioStream
@export var 音效_击退落地: AudioStream
## 破甲音（二阶段用）。现在先接好，换阶段时不用回来改接线。
@export var 音效_破甲: AudioStream

@export_group("音乐")
## 一阶段曲（留空 = 无 BGM）。换曲只需在这里拖一个 AudioStream
@export var 一阶段曲: AudioStream
@export var 音乐键名: String = "boss88_p1"

@export_group("节点")
@export var 交互提示: NodePath = NodePath("Bubble")
@export var 交互区域: NodePath = NodePath("InteractArea")
@export var 闪烁提示: NodePath = NodePath("../闪烁提示")

## 玩家碰到这个 Boss 受到的伤害（`Player` 读 `body.get("contact_damage")`）
var contact_damage: int = 0
## ⚠️ HUD 的 Boss 血条读的就是 `max_hp` 这个名字（契约：在 boss 组 + battle_started + hp + max_hp）。
##    它由导出项 `最大生命值` 在 `_ready` 里同步过来，内部一律用 `max_hp`，两者不会漂移。
var max_hp: int = 90

var state: State = State.AWAIT
var hp: int = 0
var phase: int = 1
var battle_started: bool = false
var facing: int = -1
var player: CharacterBody2D = null

var _attack_serial: int = 0
var _attack_index: int = 0
var _半血已触发: bool = false
var _玩家在范围: bool = false
## 一次攻击只结算一次伤害（判定盒可能开着好几帧、冲刺期间每帧都在查）
var _结算过: bool = false
## 最近出过的招（新的在前），只用来数"同一招连用了几次"
var _选招历史: Array[String] = []

## 音效池：一个播放器会让后一个音掐掉前一个（受击音切掉突刺风声最明显）。
## `SfxPlayer` 就是池里的第一个 —— 保留场景里已有的节点名，旧接线与自检都不受影响。
const 音效池大小: int = 4
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0

@onready var boss_sprite: AnimatedSprite2D = $BossSprite
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var 近身盒: Area2D = $近身盒
@onready var 中距盒: Area2D = $中距盒
@onready var sfx: AudioStreamPlayer = $SfxPlayer
@onready var _bubble: InteractBubble = get_node_or_null(交互提示) as InteractBubble
@onready var _interact_area: Area2D = get_node_or_null(交互区域) as Area2D
@onready var _闪烁: ColorRect = get_node_or_null(闪烁提示) as ColorRect


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("boss")
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	max_hp = maxi(最大生命值, 1)
	hp = max_hp
	_设判定盒(false)
	_设接触伤害(false)
	_设半径()
	_建音效池()
	if _interact_area != null:
		_interact_area.body_entered.connect(_on_交互区进入)
		_interact_area.body_exited.connect(_on_交互区离开)
	if _闪烁 != null:
		_闪烁.color = Color(0.85, 0.1, 0.1, 0.0)
	health_changed.emit(hp, max_hp)
	_update_facing()
	# 上次已经打赢过（可能没选唱片就退出了）→ 直接进虚弱，等玩家来选
	if GameState.is_boss_defeated(BOSS_ID):
		call_deferred("_进入虚弱")


func _exit_tree() -> void:
	# 玩家死亡换场景时，终止仍在等待帧信号的攻击协程
	battle_started = false
	_attack_serial += 1


func _设半径() -> void:
	for 对 in [[近身盒, 近身盒半径], [中距盒, 中距盒半径]]:
		var 盒: Area2D = 对[0]
		if 盒 == null:
			continue
		var 形 := 盒.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if 形 != null and 形.shape is CircleShape2D:
			(形.shape as CircleShape2D).radius = float(对[1])


## 把 `SfxPlayer` 扩成一个池（其余几个运行时新建，不写进场景文件）
func _建音效池() -> void:
	_sfx_pool.clear()
	if sfx != null:
		_sfx_pool.append(sfx)
	for _i in maxi(音效池大小 - _sfx_pool.size(), 0):
		var 新 := AudioStreamPlayer.new()
		新.name = "SfxPlayer%d" % (_sfx_pool.size() + 1)
		if sfx != null:
			新.bus = sfx.bus
		add_child(新)
		_sfx_pool.append(新)


# ──────────────────────────── 开战 ────────────────────────────


## 由竞技场触发区调用
func start_battle() -> void:
	if battle_started or state == State.DONE or state == State.WEAKENED:
		return
	battle_started = true
	state = State.INTRO
	boss_battle_started.emit()
	_攻击作废()
	max_hp = maxi(最大生命值, 1)
	hp = max_hp
	_半血已触发 = false
	phase = 1
	health_changed.emit(hp, max_hp)
	if 一阶段曲 != null:
		AudioManager.push_music(音乐键名, 一阶段曲, true, 0.0, -6.0)
	_开场()


func _开场() -> void:
	# INTRO 期间**关闭受击判定与接触伤害**，演出不被打断
	_设判定盒(false)
	_设接触伤害(false)
	boss_sprite.play("intro")
	DialogueBridge.show_cue(DIALOGUE_FILE, "boss88_intro")
	await DialogueManager.dialogue_ended
	if not battle_started or state != State.INTRO:
		return
	boss_sprite.play("idle")
	state = State.IDLE
	_设接触伤害(true)
	_攻击循环()


# ──────────────────────────── 每帧 ────────────────────────────


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not battle_started or state == State.DONE:
		return
	var 停手 := state in [State.INTRO, State.KNOCKED, State.WEAKENED, State.RECORD]
	if not 停手:
		var dlg := get_tree().get_first_node_in_group("dialogue")
		if dlg != null and dlg.is_active:
			停手 = true
	if 停手 or state == State.ATTACK:
		# 出招与停手期间位移由招式/复位自己控制，这里只管重力与夹范围
		_滑行(delta)
		return
	_走位(delta)


func _滑行(delta: float) -> void:
	if not is_on_floor():
		velocity.y += 重力 * delta
	global_position.x = clampf(global_position.x, 活动左, 活动右)
	move_and_slide()


## 走位：只用两个距离盒判断，不引入距离数值（§13.4）。
##
## ⚠️ 近身盒内**不再主动后退**。以前它会以 移动速度 往远离玩家的方向退，
##    而 `_选招()` 正是在出手间隔结束那一瞬取样 —— 结果间距被稳定顶到近身盒
##    **外侧**，于是"近身 → 三连爪击"这条分支几乎永远拿不到（玩家实测：几乎
##    见不到三连爪击，Boss 总在出突刺）。现在近身就站定，让"近身优先爪击"成立；
##    贴脸的代价改成"吃 3/4 概率的爪击 + 第三段有 14 帧后摇"。
func _走位(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
	_face_player()
	if _在盒内(近身盒) or _在盒内(中距盒):
		# 近身 / 中距：站定读招（距离盒决定偏好哪一招，走位不再干扰这个判断）
		velocity.x = 0.0
		_摆("idle")
	else:
		var 方向 := signf(player.global_position.x - global_position.x)
		if 方向 == 0.0:
			方向 = 1.0
		velocity.x = 方向 * 移动速度
		_摆("walk")
	if not is_on_floor():
		velocity.y += 重力 * delta
	global_position.x = clampf(global_position.x, 活动左, 活动右)
	move_and_slide()


# ──────────────────────────── 攻击循环 ────────────────────────────


func _攻击循环() -> void:
	while battle_started and state not in [State.DONE, State.KNOCKED, State.WEAKENED, State.RECORD]:
		var 间隔 := 出手间隔_半血 if phase == 2 else 出手间隔
		await _等秒(间隔)
		if not battle_started or state != State.IDLE:
			continue
		await _出招(_attack_serial)
		_attack_index += 1


## 三个距离带 → 偏好招。远带有**两招**偏好（闪现是瞬移贴脸的接近手段，
## 五线谱是全屏控场，两者都是远距离工具）。
func _距离带() -> String:
	if player == null:
		return "近"
	if _在盒内(近身盒):
		return "近"
	if _在盒内(中距盒):
		return "中"
	return "远"


## 偏好招列表（按当前距离带）
func _偏好招() -> Array[String]:
	match _距离带():
		"近": return ["claw"] as Array[String]
		"中": return ["thrust"] as Array[String]
	return ["blink", "staff"] as Array[String]


## 选招：加权随机 + 防重复。
##
## 规则（作者定的）：每招基础概率均等；符合距离带的那一招提到 `偏好概率`（默认 3/4），
## 其余各招平分剩下的 1/4。远带有两招偏好 → 两招平分 3/4（各 3/8）。
## 另外：同一招不得连用超过 `同招连用上限` 次 —— 连满的招权重归零，在其余招里归一化重抽。
## 教程序列仍然保留（第 0 招爪击、第 1 招五线谱），之后才进加权随机。
func _选招() -> String:
	if _attack_index == 0:
		return _记入历史("claw")
	if _attack_index == 1:
		return _记入历史("staff")
	if player == null:
		return _记入历史("claw")

	var 偏好 := _偏好招()
	var 权重: Dictionary = {}
	for 招 in 全部招式:
		权重[招] = (偏好概率 / float(偏好.size())) if 招 in 偏好 else ((1.0 - 偏好概率) / float(全部招式.size() - 偏好.size()))

	# 防重复：连满上限的招权重归零
	for 招 in 全部招式:
		if _连用次数(招) >= 同招连用上限:
			权重[招] = 0.0

	var 总 := 0.0
	for 招 in 全部招式:
		总 += float(权重[招])
	if 总 <= 0.0:
		# 兜底：所有招都被禁（同招连用上限 = 1 且刚出过某一招时不会发生，但保险）
		return _记入历史(全部招式[randi() % 全部招式.size()])

	var 掷 := randf() * 总
	for 招 in 全部招式:
		掷 -= float(权重[招])
		if 掷 < 0.0:
			return _记入历史(招)
	return _记入历史(全部招式[全部招式.size() - 1])


## 某一招最近连续用了多少次（历史新的在前）
func _连用次数(招: String) -> int:
	var n := 0
	for 名 in _选招历史:
		if 名 != 招:
			break
		n += 1
	return n


func _记入历史(招: String) -> String:
	_选招历史.push_front(招)
	if _选招历史.size() > 8:
		_选招历史.resize(8)
	return 招


## 自检用：把防重复历史清空，好在干净状态下验概率分布
func 重置选招历史() -> void:
	_选招历史.clear()


func _出招(token: int) -> void:
	state = State.ATTACK
	# 清掉走位残留的 x 速度 —— 否则爪击的 10 帧前摇里 88 会继续按上一帧的
	# 走位速度滑出去（曾经让第一段爪击的净位移变成"倒退 45.8px"）
	velocity.x = 0.0
	_结算过 = false
	match _选招():
		"claw": await _出爪击连段(token)
		"staff": await _出五线谱(token)
		"thrust": await _出前突刺(token)
		"blink": await _出闪现背刺(token)
	if _攻击有效(token):
		_设判定盒(false)
		state = State.IDLE
		_摆("idle")


# ── 招一 / 二 / 三：爪击连段 ──

func _出爪击连段(token: int) -> void:
	var 名表 := ["claw_1", "claw_2", "claw_3"]
	var 命中表 := [爪击命中帧, 爪击命中帧, 爪击三命中帧]
	var 速度表 := [爪击前突速度, 爪击前突速度, 爪击三前突速度]
	var 距离表 := [爪击前突距离, 爪击前突距离, 爪击三前突距离]
	for 段 in 3:
		_face_player()
		_摆(名表[段])
		# 起手音在第 0 帧：claw_1 命中帧 10 → 约 0.42 秒预警，玩家听得出"要抓了"
		if 段 == 0:
			_播(起手音_爪击)
		# 前摇与悬停都在动画里，这里等到命中帧才开判定
		if not await _等到帧(命中表[段], token):
			return
		_播(招式音_爪击, 0.06)
		# 前压 + 判定：整段前压期间盒子都开着，只结算一次；冲程走完再留 `命中盒持续帧` 帧
		if not await _冲刺(距离表[段], 速度表[段], token, 命中盒持续帧):
			return
		if not await _等动画结束(token):
			return


# ── 招二：五线谱横扫 ──

func _出五线谱(token: int) -> void:
	_摆("staff_cast")
	_播(起手音_五线谱)
	# staff_cast 18 帧：前 17 帧是举棒预警，最后一帧才生成
	if not await _等到帧(五线谱生成帧, token):
		return
	_播(招式音_五线谱, 0.05)
	_生成五线谱()
	_闪屏(0.45)
	_摆("idle")
	await _等秒(0.42, token)      # 后摇 = 玩家的输出窗口


func _生成五线谱() -> void:
	var 场景 := get_tree().current_scene
	if 场景 == null:
		return
	var 线 := STAFF_SWEEP.instantiate()
	场景.add_child(线)
	# ⚠️ 必须把 88 的 y 传进去。以前 setup 里读的是刚实例化节点的 global_position.y，
	#    那是 0 —— 于是五线谱生成在世界 (1620, 0)，在画面上方约 2900px 横扫，
	#    整个生命周期都在视野外，既看不见也打不到人。
	线.setup(五线谱速度, 五线谱伤害, _attack_index % 5, 活动左, 活动右, global_position.y)


# ── 招三：前突刺 ──

func _出前突刺(token: int) -> void:
	_face_player()
	_摆("thrust")
	# 起手音在第 0 帧：命中帧 16 → 约 0.67 秒预警，比爪击更慢更重
	_播(起手音_突刺)
	if not await _等到帧(突刺命中帧, token):
		return
	_播(招式音_突刺, 0.06)
	if not await _冲刺(突刺距离, 突刺速度, token):
		return
	await _等动画结束(token)


# ── 招四：闪现背刺（必有预警，不做无提示瞬移） ──

func _出闪现背刺(token: int) -> void:
	_摆("blink_out")
	# 起手音在第 0 帧：blink_out 10 帧 → 约 0.42 秒预警，加上红闪和残影三重提示
	_播(起手音_闪现)
	await _等动画结束(token)
	if not _攻击有效(token):
		return
	_留残影()
	boss_sprite.visible = false
	_闪屏(1.0)
	_播(招式音_闪现消失, 0.04)
	if not await _等秒(0.5, token):
		return
	global_position = _闪现落点()
	boss_sprite.visible = true
	_播(招式音_闪现现身, 0.04)
	_face_player()
	_摆("blink_in")
	if not await _等到帧(闪现前摇帧, token):
		return
	_摆("thrust")
	if not await _等到帧(突刺命中帧, token):
		return
	if not await _冲刺(突刺距离, 突刺速度, token):
		return
	await _等动画结束(token)


## 落点：玩家背后一段距离，夹进活动范围，并向下探一下确认脚下有地
func _闪现落点() -> Vector2:
	if player == null:
		return global_position
	var 背后 := signf(global_position.x - player.global_position.x)
	if 背后 == 0.0:
		背后 = 1.0
	var x := clampf(player.global_position.x + 背后 * 闪现背后距离, 活动左, 活动右)
	var y := global_position.y
	var 参 := PhysicsRayQueryParameters2D.create(Vector2(x, y), Vector2(x, y + 落点探测距离))
	参.collision_mask = 1 | 16        # 地形 + 单向平台
	参.exclude = [get_rid()]
	var 命中 := get_world_2d().direct_space_state.intersect_ray(参)
	if not 命中.is_empty():
		y = 命中.position.y - 1.0
	return Vector2(x, y)


# ──────────────────────────── 受击 / 收尾 ────────────────────────────


func take_damage(amount: int, from_pos: Vector2, from_magic := false) -> void:
	# 这些状态一律免伤：开场演出、被击退、虚弱、已收尾
	if state in [State.DONE, State.INTRO, State.KNOCKED, State.WEAKENED, State.RECORD]:
		return
	if amount <= 0:
		return
	if not from_magic:
		GameState.add_music_inspiration(GameState.MUSIC_INSPIRATION_PER_HIT)
	hp = maxi(hp - amount, 0)
	health_changed.emit(hp, max_hp)
	# 半血判定放在"归零"之前：一击跨过阈值时也要置位（它只影响出手间隔，不影响收尾）
	if not _半血已触发 and hp <= int(round(max_hp * 半血阈值)):
		_半血已触发 = true
		phase = 2
		phase_changed.emit(phase)
		# 不换曲，只把出手间隔缩短（_攻击循环 下一次循环生效）
		DialogueBridge.show_cue(DIALOGUE_FILE, "boss88_taunt_half")
	if hp <= 0:
		_进入击退()
		return
	_闪白()


func _进入击退() -> void:
	state = State.KNOCKED
	_攻击作废()
	_设判定盒(false)
	_设接触伤害(false)
	_摆("knocked")
	var 方向 := 1.0
	if player != null and player.global_position.x < global_position.x:
		方向 = 1.0
	else:
		方向 = -1.0
	velocity = Vector2(方向 * 击退速度, -140.0)
	await _等秒(0.45)
	if not is_inside_tree():
		return
	_播(音效_击退落地)
	FeedbackManager.camera_shake(6.0, 0.12)
	await _等秒(0.35)
	_进入虚弱()


func _进入虚弱() -> void:
	if state == State.WEAKENED:
		return
	state = State.WEAKENED
	battle_started = false
	_攻击作废()
	velocity = Vector2.ZERO
	hp = 0
	health_changed.emit(hp, max_hp)       # HUD 契约：current<=0 就隐藏血条
	_摆("weakened")                       # 呼吸循环，不是倒地
	GameState.mark_boss_defeated(BOSS_ID)
	GameState.save_game()
	# 静场：把 Boss 曲停住，突出"按 W 交互"这一下（AudioManager 的暂停位置在恢复时会接上）
	AudioManager.pause_current_music()
	if not DialogueBridge.is_active:
		DialogueBridge.show_cue(DIALOGUE_FILE, "boss88_weakened")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _bubble == null:
		return
	# W 气泡每帧无脑驱动（`agent.md §21.1`），别只在进出回调里显隐
	var 可交互 := state == State.WEAKENED and _玩家在范围 and not DialogueBridge.is_active
	if 可交互:
		_bubble.显示()
	else:
		_bubble.隐藏()
	if 可交互 and Input.is_action_just_pressed("interact"):
		_打开唱片面板()


func _打开唱片面板() -> void:
	state = State.RECORD
	DialogueBridge.show_cue(DIALOGUE_FILE, "boss88_record_pick")
	var 场景 := get_tree().current_scene
	if 场景 == null:
		return
	var 资源 := load("res://scenes/ui/RecordSelectPanel.tscn") as PackedScene
	if 资源 == null:
		push_warning("打不开 RecordSelectPanel.tscn，按普通结局收尾")
		_on_唱片选定("")
		return
	var 节点 := 资源.instantiate()
	场景.add_child(节点)
	if 节点.has_signal("选择完成"):
		节点.选择完成.connect(_on_唱片选定)
	if 节点.has_signal("已取消"):
		节点.已取消.connect(_on_面板取消)


## 玩家在面板上按了 Esc：回到虚弱状态，气泡会重新出现，可以再按 W
func _on_面板取消() -> void:
	if state != State.RECORD:
		return
	state = State.WEAKENED


func _on_唱片选定(唱片id: String) -> void:
	if state == State.DONE:
		return
	state = State.DONE
	var 走真结局 := 唱片id == 狂喜之诗ID
	_播唱片(唱片id)
	if 走真结局:
		DialogueBridge.show_cue(DIALOGUE_FILE, "boss88_transform")
	else:
		DialogueBridge.show_cue(DIALOGUE_FILE, "ending_normal")
	victory.emit()
	收尾完成.emit(走真结局)


# ──────────────────────────── 小工具 ────────────────────────────


## 等到动画播到指定帧 —— "命中帧"这种尖锐时刻靠它定位
func _等到帧(目标帧: int, token: int) -> bool:
	var 上限 := 480            # 最多等 8 秒，防死循环
	while 上限 > 0:
		if not _攻击有效(token):
			return false
		if boss_sprite.frame >= 目标帧:
			return true
		上限 -= 1
		await get_tree().physics_frame
	return false


func _等动画结束(token: int) -> bool:
	if not boss_sprite.is_playing():
		return _攻击有效(token)
	await boss_sprite.animation_finished
	return _攻击有效(token)


func _等物理帧(帧数: int, token: int) -> bool:
	for _i in maxi(帧数, 1):
		await get_tree().physics_frame
		if not _攻击有效(token):
			return false
	return true


func _等秒(秒: float, token: int = -1) -> bool:
	await get_tree().create_timer(maxf(秒, 0.0), false).timeout
	if token >= 0 and not _攻击有效(token):
		return false
	return true


func _攻击有效(token: int) -> bool:
	return token == _attack_serial and battle_started \
		and state not in [State.DONE, State.KNOCKED, State.WEAKENED, State.RECORD]


func _攻击作废() -> void:
	_attack_serial += 1


## 判定盒开关。**只切 monitoring，不查询** ——
## ⚠️ 查询必须隔一个物理帧（见 `_判定窗口`）。以前这里在开盒的同一帧就
##    `_结算命中()`，而 Area2D 的重叠表是在物理步里刷新的，刚开 monitoring
##    时表还是空的 → 每次拿到空数组，**所有招式判定全部空过**（玩家掉的血其实
##    来自接触伤害）。项目其它敌人（`Enemy.gd` / `SharpEnemy.gd`）都是
##    「开 → 下一物理帧才开始查」。
func _设判定盒(开: bool) -> void:
	if attack_hitbox == null:
		return
	attack_hitbox.monitoring = 开
	attack_hitbox.set_deferred("collision_layer", 4 if 开 else 0)


## 查一次重叠体；命中就扣血并返回 true。配合 `_结算过` 保证一次攻击只打一下。
func _结算命中() -> bool:
	if attack_hitbox == null:
		return false
	for body in attack_hitbox.get_overlapping_bodies():
		if body.is_in_group("player"):
			body.take_damage(伤害, global_position)
			return true
	return false


## 站定打击的判定窗口：开盒 → 等一物理帧让重叠表刷出来 → 逐帧查 → 关盒。
## `窗口帧` 是盒子保持开启的物理帧数（默认 2 = 1 帧刷表 + 1 帧结算），
## 这样"命中仍然是一个尖锐的时刻"，但不再靠"只开 2 帧"去赌重叠表已经就绪。
func _判定窗口(窗口帧: int, token: int) -> bool:
	_结算过 = false
	_设判定盒(true)
	for i in maxi(窗口帧, 2):
		await get_tree().physics_frame
		if not _攻击有效(token):
			break
		if not _结算过:
			_结算过 = _结算命中()
	_设判定盒(false)
	return _攻击有效(token)


## 位移打击：向前冲 `距离` 像素，整段冲刺期间判定盒都开着、每帧查一次、只结算一次。
##
## ⚠️ **按位移停，不按帧数停**。顿帧（`FeedbackManager.hit_stop` 把 time_scale 压到 0）
##    期间物理帧照常 tick 但 delta = 0，`move_and_slide()` 位移为 0 —— 等帧数会让
##    冲刺距离直接归零，等位移只是把冲刺在墙上多拉长几帧。
## 尾巴帧：冲程走完后盒子再多留几帧，覆盖"玩家刚好贴在判定边缘"的情况。
func _冲刺(距离: float, 速度: float, token: int, 尾巴帧: int = 0) -> bool:
	_结算过 = false
	_设判定盒(true)
	_前突(速度)
	var 起点 := global_position.x
	var 剩余 := 冲刺最长帧
	while 剩余 > 0:
		await get_tree().physics_frame
		剩余 -= 1
		if not _攻击有效(token):
			break
		if not _结算过:
			_结算过 = _结算命中()
		if absf(global_position.x - 起点) >= 距离:
			break
	for _i in maxi(尾巴帧, 0):
		await get_tree().physics_frame
		if not _攻击有效(token):
			break
		if not _结算过:
			_结算过 = _结算命中()
	_停突()
	_设判定盒(false)
	return _攻击有效(token)


func _设接触伤害(开: bool) -> void:
	contact_damage = 伤害 if 开 else 0


func _face_player() -> void:
	if player == null:
		return
	facing = 1 if player.global_position.x >= global_position.x else -1
	_update_facing()


func _update_facing() -> void:
	if boss_sprite == null:
		return
	boss_sprite.flip_h = facing < 0
	if attack_hitbox != null:
		# y 也不动 —— 判定盒与身体同心（场景里 AttackHitbox.position.y == 胶囊中心）
		attack_hitbox.position.x = facing * 判定盒前伸


func _在盒内(盒: Area2D) -> bool:
	if 盒 == null:
		return false
	for body in 盒.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false


func _前突(速度: float) -> void:
	velocity.x = facing * 速度


func _停突() -> void:
	velocity.x = 0.0


func _摆(动画名: String) -> void:
	if boss_sprite == null or boss_sprite.sprite_frames == null:
		return
	if not boss_sprite.sprite_frames.has_animation(动画名):
		return
	if boss_sprite.animation != 动画名 or not boss_sprite.is_playing():
		boss_sprite.play(动画名)


## 播放选中的那张唱片：优先用记录里的 audio_path；为空（占位唱片）就退回 Boss 曲
func _播唱片(唱片id: String) -> void:
	for 条 in GameState.RECORDS:
		if str(条.get("id", "")) != 唱片id:
			continue
		var 路径 := str(条.get("audio_path", ""))
		if 路径.is_empty() or not ResourceLoader.exists(路径):
			return          # 占位唱片没有音频：什么都不做，让静场持续到结局
		AudioManager.push_music("boss88_record", load(路径), false, 0.0, -6.0)
		return


## `音高抖动` 默认 0：**起手音靠音高区分招式，绝不能抖**。
## 招式音 / 反馈音传 0.04~0.07 —— 同一声连听 50 次会腻，轻微失谐就够破掉复读机感。
func _播(流: AudioStream, 音高抖动: float = 0.0) -> void:
	if 流 == null or _sfx_pool.is_empty():
		return
	var p := _取播放器()
	p.stream = 流
	p.pitch_scale = 1.0 if 音高抖动 <= 0.0 else 1.0 + randf_range(-音高抖动, 音高抖动)
	p.play()


## 优先挑空闲的播放器；四个都占着就抢最老的那个（宁可掐最旧的，也不掐刚起的）
func _取播放器() -> AudioStreamPlayer:
	var 总数 := _sfx_pool.size()
	for i in 总数:
		var 号 := (_sfx_cursor + i) % 总数
		if not _sfx_pool[号].playing:
			_sfx_cursor = (号 + 1) % 总数
			return _sfx_pool[号]
	var 最老 := _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % 总数
	return 最老


func _闪白() -> void:
	_播(音效_受击, 0.07)
	if boss_sprite == null:
		return
	boss_sprite.self_modulate = Color(3, 3, 3)
	await get_tree().create_timer(0.04, false).timeout
	if is_instance_valid(boss_sprite):
		boss_sprite.self_modulate = Color(1, 1, 1)


## 闪现消失时的残影：复制当前帧、淡出后自毁（程序化，不占动画资源）
func _留残影() -> void:
	if boss_sprite == null or boss_sprite.sprite_frames == null:
		return
	var 影 := Sprite2D.new()
	影.texture = boss_sprite.sprite_frames.get_frame_texture(boss_sprite.animation, boss_sprite.frame)
	影.global_position = boss_sprite.global_position
	影.flip_h = boss_sprite.flip_h
	影.z_index = -1
	get_parent().add_child(影)
	var t := create_tween()
	t.tween_property(影, "modulate:a", 0.0, 0.3)
	t.tween_callback(影.queue_free)


## 屏幕红闪（闪现预警用）。节点在关卡里排在 UI 之前 → 压得住玩法、不盖 HUD
func _闪屏(强度: float) -> void:
	if _闪烁 == null:
		return
	_闪烁.color = Color(0.85, 0.1, 0.1, 0.35 * clampf(强度, 0.0, 1.0))
	var t := create_tween()
	t.tween_property(_闪烁, "color:a", 0.0, 0.45)


func _on_交互区进入(body: Node2D) -> void:
	if body.is_in_group("player"):
		_玩家在范围 = true


func _on_交互区离开(body: Node2D) -> void:
	if body.is_in_group("player"):
		_玩家在范围 = false


# ──────────────────────────── 编辑器可视化（§13.4） ────────────────────────────


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_arc(Vector2.ZERO, 近身盒半径, 0.0, TAU, 64, Color(1.0, 0.35, 0.35, 0.8), 2.0)
	draw_arc(Vector2.ZERO, 中距盒半径, 0.0, TAU, 96, Color(1.0, 0.8, 0.3, 0.6), 2.0)
	draw_line(Vector2(活动左 - global_position.x, -360), Vector2(活动左 - global_position.x, 360),
		Color(0.4, 0.8, 1.0, 0.35), 2.0)
	draw_line(Vector2(活动右 - global_position.x, -360), Vector2(活动右 - global_position.x, 360),
		Color(0.4, 0.8, 1.0, 0.35), 2.0)
