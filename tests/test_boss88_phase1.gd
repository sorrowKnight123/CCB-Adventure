extends Node
## 88 一阶段战斗自检。
##
## 覆盖：接线 / 动画骨架 / 状态机 / **命中帧窗口与命中帧号的自洽** / 教程序列 / 距离盒选招 /
## 闪现落点防呆 / KNOCKED 与 WEAKENED 免伤 / 竞技场锁与门 / 唱片面板 / 新增对话 cue。
##
## 运行：godot --headless --path . res://tests/test_boss88_phase1.tscn --quit-after 9000

const LEVEL := preload("res://scenes/levels/music_hall/4_1.tscn")
const 面板场景 := preload("res://scenes/ui/RecordSelectPanel.tscn")
const 对话文件 := "res://dialogues/game.dialogue"
const 新增CUE: Array[String] = ["boss88_intro", "boss88_taunt_half", "boss88_weakened",
	"boss88_record_pick", "boss88_transform", "ending_normal", "ending_true"]

var _p: int = 0
var _f: int = 0
var _lvl: Node2D = null
var _boss: CharacterBody2D = null
var _arena: Node = null
var _player: CharacterBody2D = null


func _ready() -> void:
	_lvl = LEVEL.instantiate()
	add_child(_lvl)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_boss = _lvl.get_node_or_null("Boss88Phase1") as CharacterBody2D
	_arena = _lvl.get_node_or_null("ArenaLock")
	_player = _lvl.get_node_or_null("Player")

	await _检查接线()
	await _检查动画骨架()
	await _检查命中帧()
	await _检查状态机()
	await _检查选招()
	await _检查闪现落点()
	await _检查收尾与免伤()
	await _检查竞技场()
	await _检查唱片面板()
	await _检查对话cue()

	print("\n===== 88 一阶段自检结果：通过 %d / 失败 %d =====" % [_p, _f])
	get_tree().quit(0 if _f == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_p += 1
		print("[PASS] " + what)
	else:
		_f += 1
		print("[FAIL] " + what)


func _等物理(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


## 把玩家挪远，避免断言时真打到人
func _挪开玩家() -> void:
	_player.global_position = Vector2(300.0, 3369.0)
	_player.velocity = Vector2.ZERO


# ──────────────────────────── 接线 ────────────────────────────


func _检查接线() -> void:
	_check(_boss != null, "接线：4_1 里有 Boss88Phase1")
	_check(_arena != null, "接线：4_1 里有 ArenaLock")
	_check(_player != null, "接线：4_1 里有 Player")
	if _boss == null or _arena == null:
		return
	_check(_lvl.get_node_or_null("闪烁提示") is ColorRect, "接线：闪烁提示（全屏红闪层）存在")
	_check(_boss.get_node_or_null("BossSprite") is AnimatedSprite2D, "接线：BossSprite 是 AnimatedSprite2D")
	for n in ["AttackHitbox", "近身盒", "中距盒", "InteractArea", "Bubble", "SfxPlayer"]:
		_check(_boss.get_node_or_null(n) != null, "接线：%s 存在" % n)
	_check(not (_boss.get_node("AttackHitbox") as Area2D).monitoring, "接线：判定盒默认关闭")
	_check(int(_boss.contact_damage) == 0, "接线：接触伤害默认关闭（没开战不该撞死人）")
	# ── 音效接线：4 起手音 + 5 招式音 + 3 反馈音，一个都不能空 ──
	# （空了的后果是"静音"——不报错、不崩，最难查，所以逐个断言）
	var 音效表 := {
		"起手音_爪击": "钢琴单音", "起手音_五线谱": "钢琴单音",
		"起手音_突刺": "钢琴单音", "起手音_闪现": "钢琴单音",
		"招式音_爪击": "CC0 swish", "招式音_五线谱": "CC0 swish",
		"招式音_突刺": "CC0 swish", "招式音_闪现消失": "CC0 swish",
		"招式音_闪现现身": "CC0 swish",
		"音效_受击": "CC0 bfh1", "音效_击退落地": "CC0 bfh1", "音效_破甲": "CC0 bfh1",
	}
	for 键 in 音效表:
		_check(_boss.get(键) != null, "接线：%s 已接（%s）" % [键, 音效表[键]])
	_check(_boss.get("一阶段曲") != null, "接线：一阶段曲已接（占位）")
	# 音效池：单播放器会让后一个音掐掉前一个（受击音切掉突刺风声最明显）
	var 池: Array = _boss.get("_sfx_pool")
	_check(池.size() == int(_boss.get("音效池大小")), "接线：音效池建满（%d 个）" % 池.size())
	_check(池.size() >= 3, "接线：音效池至少 3 个（够起手音+招式音+受击叠着响）")
	var 首 := 池[0] as AudioStreamPlayer
	_check(首 != null and 首.name == "SfxPlayer",
		"接线：池里第一个就是场景里原有的 SfxPlayer（旧接线不失效）")
	if 首 != null:
		_check(str(首.bus) == "SFX", "接线：池走 SFX 总线（受设置里的音效音量控制）")
	# 起手音必须音高稳定（玩家靠音高分辨下一招），招式音才允许抖动
	var 钢琴 := _boss.get("起手音_爪击") as AudioStream
	_停全池(池)
	_boss.call("_播", 钢琴, 0.0)
	var 定 := _唯一开声的池成员(池).pitch_scale
	_check(is_equal_approx(定, 1.0), "音效：起手音音高恒为 1.0（不抖动，玩家才能听音辨招）")
	_停全池(池)
	_boss.call("_播", 钢琴, 0.06)
	var 抖 := _唯一开声的池成员(池).pitch_scale
	_check(抖 >= 0.94 and 抖 <= 1.06, "音效：招式音抖动落在 ±6% 内（实测 " + str(抖) + "）")
	_check(not is_equal_approx(抖, 1.0), "音效：招式音确实抖了（不是复读机）")
	# 池要真的会轮转：连播 4 声，不该全挤在同一个播放器上
	_停全池(池)
	for _i in 池.size():
		_boss.call("_播", 钢琴, 0.0)
	var 开声 := 0
	for p in 池:
		if (p as AudioStreamPlayer).playing:
			开声 += 1
	_check(开声 == 池.size(), "音效：连播 %d 声铺满 %d 个播放器（不互相掐断）" % [池.size(), 池.size()])
	_停全池(池)


func _停全池(池: Array) -> void:
	for p in 池:
		var a := p as AudioStreamPlayer
		if a != null:
			a.stop()


## 刚被 `_播` 点着的那个播放器 —— 调用前请先 `_停全池`，否则会撞上还在响的旧声音
func _唯一开声的池成员(池: Array) -> AudioStreamPlayer:
	for p in 池:
		var a := p as AudioStreamPlayer
		if a != null and a.playing:
			return a
	return 池[0] as AudioStreamPlayer
	var 近 := _boss.get_node("近身盒/CollisionShape2D") as CollisionShape2D
	var 中 := _boss.get_node("中距盒/CollisionShape2D") as CollisionShape2D
	_check(is_equal_approx((近.shape as CircleShape2D).radius, float(_boss.近身盒半径)),
		"接线：近身盒半径与导出项一致（%d）" % int(_boss.近身盒半径))
	_check(is_equal_approx((中.shape as CircleShape2D).radius, float(_boss.中距盒半径)),
		"接线：中距盒半径与导出项一致（%d）" % int(_boss.中距盒半径))
	# Boss 自己不该在 AWAIT 就参与敌人碰撞
	_check(_boss.is_in_group("boss"), "接线：Boss 在 boss 组（HUD 血条契约）")


func _检查动画骨架() -> void:
	if _boss == null:
		return
	var sf: SpriteFrames = (_boss.get_node("BossSprite") as AnimatedSprite2D).sprite_frames
	_check(sf != null, "动画：SpriteFrames 已挂")
	if sf == null:
		return
	var 期望 := {
		"idle": 24, "walk": 16, "intro": 36, "claw_1": 26, "claw_2": 26, "claw_3": 32,
		"thrust": 26, "blink_out": 10, "blink_in": 12, "staff_cast": 18,
		"hurt": 6, "knocked": 12, "weakened": 32,
	}
	var 缺: Array = []
	var 帧数不对: Array = []
	for 名 in 期望:
		if not sf.has_animation(名):
			缺.append(名)
		elif sf.get_frame_count(名) != 期望[名]:
			帧数不对.append("%s=%d(期望%d)" % [名, sf.get_frame_count(名), 期望[名]])
	_check(缺.is_empty(), "动画：13 个动画名齐（缺 %s）" % str(缺))
	_check(帧数不对.is_empty(), "动画：帧数与设计一致（%s）" % str(帧数不对))
	_check(sf.get_animation_loop("idle") and sf.get_animation_loop("weakened"),
		"动画：idle / weakened 循环")
	_check(not sf.get_animation_loop("claw_1") and not sf.get_animation_loop("thrust")
		and not sf.get_animation_loop("hurt"), "动画：attack / thrust / hurt 不循环")


# ──────────────────────────── 命中帧（核心） ────────────────────────────


func _检查命中帧() -> void:
	if _boss == null:
		return
	# ① 设计硬闸：判定盒开启时长必须 1~2 帧
	_check(int(_boss.命中盒持续帧) >= 1 and int(_boss.命中盒持续帧) <= 2,
		"命中帧：命中盒持续帧 = %d（**设计硬闸：1~2**）" % int(_boss.命中盒持续帧))
	# ② 开关真的能切 monitoring
	var 盒 := _boss.get_node("AttackHitbox") as Area2D
	_boss._设判定盒(true)
	_check(盒.monitoring, "命中帧：_设判定盒(true) 打开 monitoring")
	_boss._设判定盒(false)
	_check(not 盒.monitoring, "命中帧：_设判定盒(false) 关掉 monitoring")
	# ③ 命中帧号必须落在动画帧数之内 —— 否则 _等到帧 会一直等到超时，招式会静默卡住
	var sf: SpriteFrames = (_boss.get_node("BossSprite") as AnimatedSprite2D).sprite_frames
	var 越界: Array = []
	if sf != null:
		var 对: Array = [["爪击命中帧", "claw_1"], ["爪击三命中帧", "claw_3"], ["突刺命中帧", "thrust"]]
		for p in 对:
			var 帧号 := int(_boss.get(p[0]))
			var 总帧 := sf.get_frame_count(p[1])
			if 帧号 < 1 or 帧号 >= 总帧:
				越界.append("%s=%d 不在 %s(0~%d)" % [p[0], 帧号, p[1], 总帧 - 1])
	_check(越界.is_empty(), "命中帧：三个命中帧号都在各自动画内（%s）" % str(越界))
	# ⑤ 两拍节奏：起手音在动画第 0 帧、招式音在命中帧 → 中间必须留够预警时间。
	#    < 0.3 秒的预警等于没有（玩家听清了也来不及动），这是"重而可读"的底线。
	var 预警表 := {
		"爪击": int(_boss.爪击命中帧), "爪击三": int(_boss.爪击三命中帧),
		"突刺": int(_boss.突刺命中帧), "五线谱": int(_boss.五线谱生成帧),
		"闪现消失": sf.get_frame_count("blink_out") if sf != null else 10,
	}
	var 太短: Array = []
	for 名 in 预警表:
		var 秒 := float(预警表[名]) / 24.0
		if 秒 < 0.3:
			太短.append("%s=%.2f秒" % [名, 秒])
	_check(太短.is_empty(), "命中帧：四招预警都 >= 0.3 秒（%s）" % str(太短))
	if sf != null:
		_check(int(_boss.五线谱生成帧) < sf.get_frame_count("staff_cast"),
			"命中帧：五线谱生成帧落在 staff_cast 动画内（改它不用改代码）")
	# ④ 跑完整招之后判定盒不能卡在开着
	_挪开玩家()
	_boss.global_position = Vector2(1100.0, 3426.0)
	_boss.state = _boss.State.IDLE
	await _boss._出前突刺(int(_boss._attack_serial))
	_check(not 盒.monitoring, "命中帧：一招跑完后判定盒没卡住")
	_挪开玩家()


# ──────────────────────────── 状态机 ────────────────────────────


func _检查状态机() -> void:
	if _boss == null:
		return
	# 4_1 里的这个实例：玩家出生点就在触发区内 → 竞技场应当已经自动开战
	_check(_boss.battle_started, "状态机：4_1 里竞技场已自动开战（玩家出生即在触发区内）")
	_check(int(_boss.state) != int(_boss.State.AWAIT),
		"状态机：自动开战后已离开 AWAIT（state=%d）" % int(_boss.state))
	# 出手间隔调大，免得攻击循环打扰后面的断言
	_boss.出手间隔 = 999.0
	_boss.出手间隔_半血 = 999.0
	# 用一个**独立实例**验完整的 AWAIT → INTRO 链路（4_1 里那个已经被开战了）
	var 裸 := (load("res://scenes/enemies/boss/Boss88Phase1.tscn") as PackedScene).instantiate()
	add_child(裸)
	await get_tree().physics_frame
	_check(int(裸.state) == int(裸.State.AWAIT), "状态机：裸实例初始 AWAIT")
	_check(裸.hp == 裸.max_hp and 裸.max_hp == int(裸.最大生命值),
		"状态机：max_hp 与导出项同步（%d / %d）" % [裸.max_hp, int(裸.最大生命值)])
	_check(裸.get("max_hp") != null, "状态机：有 max_hp（HUD 血条契约要这个名字）")
	_check(裸.get("battle_started") != null, "状态机：有 battle_started（HUD 契约）")
	裸.start_battle()
	_check(裸.battle_started, "状态机：start_battle 后 battle_started = true")
	_check(int(裸.state) == int(裸.State.INTRO), "状态机：进入 INTRO")
	_check(int(裸.contact_damage) == 0, "状态机：INTRO 期间接触伤害关闭（演出不被打断）")
	var 血0: int = 裸.hp
	裸.take_damage(20, Vector2.ZERO)
	_check(裸.hp == 血0, "状态机：INTRO 期间打不掉血")
	await _等物理(10)
	_check(int(裸.state) == int(裸.State.INTRO), "状态机：对话没结束时停在 INTRO")
	# 半血阈值：单独验一次（一击跨过阈值也要置位）
	裸.state = 裸.State.IDLE
	裸.phase = 1
	裸._半血已触发 = false
	裸.hp = int(round(裸.max_hp * 裸.半血阈值)) + 1
	裸.take_damage(1, Vector2.ZERO)
	_check(裸._半血已触发 and 裸.phase == 2,
		"数值：跨过 50% 阈值时置位 phase=2（hp=%d / max=%d）" % [裸.hp, 裸.max_hp])
	裸.queue_free()
	# 主实例推进到 IDLE，供后面的招式断言用
	_boss.state = _boss.State.IDLE
	_boss.contact_damage = int(_boss.伤害)


# ──────────────────────────── 选招 ────────────────────────────


func _检查选招() -> void:
	if _boss == null:
		return
	_boss.state = _boss.State.IDLE
	_boss._attack_index = 0
	_check(_boss._选招() == "claw", "选招：第 0 招固定爪击（教学）")
	_boss._attack_index = 1
	_check(_boss._选招() == "staff", "选招：第 1 招固定五线谱（教学）")
	_boss._attack_index = 9
	_boss._贴脸计时 = 0.0
	_boss.global_position = Vector2(1100.0, 3426.0)
	_player.global_position = Vector2(1160.0, 3369.0)
	await _等物理(4)
	_check(_boss._选招() == "claw", "选招：玩家贴身 → 爪击")
	_player.global_position = Vector2(1400.0, 3369.0)
	await _等物理(4)
	var 招: String = _boss._选招()
	_check(招 == "thrust", "选招：中距 → 前突刺（实际 %s）" % 招)
	_player.global_position = Vector2(2000.0, 3369.0)
	await _等物理(4)
	_check(_boss._选招() == "staff", "选招：很远 → 五线谱控空间")
	_player.global_position = Vector2(1140.0, 3369.0)
	await _等物理(4)
	_boss._贴脸计时 = float(_boss.贴脸容忍秒) + 0.1
	_check(_boss._选招() == "blink", "选招：持续贴脸超时 → 闪现背刺（惩罚无脑追击）")
	_boss._贴脸计时 = 0.0
	_挪开玩家()


# ──────────────────────────── 闪现落点防呆 ────────────────────────────


func _检查闪现落点() -> void:
	if _boss == null:
		return
	_boss.global_position = Vector2(1200.0, 3426.0)
	_player.global_position = Vector2(210.0, 3369.0)
	await _等物理(2)
	var 点: Vector2 = _boss._闪现落点()
	_check(点.x >= float(_boss.活动左) - 0.5 and 点.x <= float(_boss.活动右) + 0.5,
		"闪现落点：夹在活动范围 200~1400（实际 x=%.0f）" % 点.x)
	_check(absf(点.y - 3426.0) < 6.0,
		"闪现落点：向下探到地面（y=%.0f，地面顶边 3426）" % 点.y)
	_挪开玩家()


# ──────────────────────────── 收尾与免伤 ────────────────────────────


func _检查收尾与免伤() -> void:
	if _boss == null:
		return
	# 这些状态一律免伤
	for 状态 in [_boss.State.INTRO, _boss.State.KNOCKED, _boss.State.WEAKENED,
			_boss.State.RECORD, _boss.State.DONE]:
		_boss.state = 状态
		_boss.hp = 30
		_boss.take_damage(10, Vector2.ZERO)
		_check(_boss.hp == 30, "免伤：state=%d 时打不掉血" % int(状态))
	# 正常状态能打死 → 进击退
	_boss.state = _boss.State.IDLE
	_boss.hp = 5
	_boss.take_damage(5, Vector2.ZERO)
	await _等物理(4)
	_check(int(_boss.state) == int(_boss.State.KNOCKED),
		"收尾：血量归零进 KNOCKED（实际 state=%d）" % int(_boss.state))
	_check(int(_boss.contact_damage) == 0, "收尾：KNOCKED 期间接触伤害关闭（玩家靠近不会被撞死）")
	for _i in 200:
		await get_tree().physics_frame
		if int(_boss.state) == int(_boss.State.WEAKENED):
			break
	_check(int(_boss.state) == int(_boss.State.WEAKENED), "收尾：走到 WEAKENED 等玩家按 W")
	_check(int(_boss.contact_damage) == 0, "收尾：WEAKENED 期间接触伤害仍是关的")
	_check(GameState.is_boss_defeated("boss88_phase1"), "收尾：已写 boss88_phase1 战胜标记")
	_boss.take_damage(99, Vector2.ZERO)
	_check(_boss.hp == 0, "收尾：WEAKENED 期间打不掉血（hp 保持 0）")


# ──────────────────────────── 竞技场 ────────────────────────────


func _检查竞技场() -> void:
	if _arena == null:
		return
	var 区 := _arena.get_node_or_null("触发区") as Area2D
	_check(区 != null and 区.collision_mask == 2, "竞技场：触发区存在且只检测玩家层")
	# 触发区形状必须真是那块矩形（曾经因为 sub_resource 插错位置退成默认 20x20）
	var 形 := 区.get_node_or_null("CollisionShape2D") as CollisionShape2D
	_check(形 != null and 形.shape is RectangleShape2D
		and (形.shape as RectangleShape2D).size == Vector2(1400, 300),
		"竞技场：触发区形状 = 1400x300（实际 %s）"
		% (str((形.shape as RectangleShape2D).size) if 形 != null and 形.shape is RectangleShape2D else "非矩形"))
	# 二阶段的视口矩形也不能被碰坏（同一份场景）
	var p2 := _lvl.get_node_or_null("phase_2_area/CollisionShape2D") as CollisionShape2D
	_check(p2 != null and p2.shape is RectangleShape2D
		and (p2.shape as RectangleShape2D).size == Vector2(1280, 720),
		"竞技场：phase_2_area 形状 = 1280x720（实际 %s）"
		% (str((p2.shape as RectangleShape2D).size) if p2 != null and p2.shape is RectangleShape2D else "非矩形"))
	_check(_arena.竞技场矩形 == Rect2(0, 2880, 1600, 720),
		"竞技场：矩形 = x0~1600 / y2880~3600（实际 %s）" % str(_arena.竞技场矩形))
	_arena.已结束 = false
	_arena.战斗中 = false
	_arena.开始()
	await _等物理(4)
	_check(_arena.门是否锁着(), "竞技场：开战后回程门被锁（意图）")
	# ⚠️ 意图之外还要验「物理属性真的落地」：_锁门 走 set_deferred（它从 body_entered 里被调下来，
	#    直接赋值会被引擎挡掉且只报一行 ERROR，门其实没锁上）。只验意图会漏掉这个 bug。
	var 门 := _lvl.get_node_or_null("Door/4_1-3_1") as Area2D
	_check(门 != null, "竞技场：找得到回程门 Door/4_1-3_1")
	if 门 != null:
		_check(not 门.monitoring and not 门.monitorable,
			"竞技场：门的 monitoring/monitorable 真关掉了（set_deferred 已落地）")
	var 相机 := _player.get_node_or_null("Camera2D") as Camera2D
	if 相机 != null:
		_check(相机.limit_right - 相机.limit_left == 1600,
			"竞技场：镜头 limits 收到 1600 宽（实际 %d）" % (相机.limit_right - 相机.limit_left))
		_check(相机.limit_top == 2880 and 相机.limit_bottom == 3600,
			"竞技场：镜头上下限到第 1 格（%d~%d）" % [相机.limit_top, 相机.limit_bottom])
	_arena._on_胜利()
	await _等物理(4)
	_check(not _arena.门是否锁着(), "竞技场：胜利后门解锁（意图）")
	if 门 != null:
		_check(门.monitoring and 门.monitorable,
			"竞技场：胜利后门的 monitoring/monitorable 真的开回来了")


# ──────────────────────────── 唱片面板 ────────────────────────────


func _检查唱片面板() -> void:
	# 默认并不拥有《狂喜之诗》（它靠小兰的隐藏任务或作弊栏发放）→ 先发一张再验面板
	var 发 := GameState.强制获得唱片("ecstasy_poem")
	_check(发 or GameState.has_record("ecstasy_poem"), "面板：作弊入口能发出《狂喜之诗》")
	_check(GameState.has_record("ecstasy_poem"), "面板：已拥有 ecstasy_poem（真结局钥匙）")
	var 面板: Node = 面板场景.instantiate()
	add_child(面板)
	await _等物理(2)
	await get_tree().process_frame
	var 列表 := 面板.get_node_or_null("根/面板/列表") as VBoxContainer
	_check(列表 != null, "面板：列表节点存在")
	if 列表 == null:
		面板.queue_free()
		return
	_check(列表.get_child_count() == GameState.owned_records.size(),
		"面板：列出已拥有唱片 %d 张（实际 %d 行）"
		% [GameState.owned_records.size(), 列表.get_child_count()])
	var 目标 := -1
	for i in 面板._唱片.size():
		if str(面板._唱片[i].get("id", "")) == "ecstasy_poem":
			目标 = i
	_check(目标 >= 0, "面板：已拥有唱片里有 ecstasy_poem（真结局钥匙）")
	if 目标 >= 0:
		面板._选中 = 目标
		var 记录 := {"id": "", "次数": 0}
		面板.选择完成.connect(func(id: String) -> void:
			记录["id"] = id
			记录["次数"] += 1)
		面板._确认()
		await get_tree().process_frame
		_check(记录["次数"] == 1 and 记录["id"] == "ecstasy_poem",
			"面板：确认后发出 选择完成(ecstasy_poem)")
		_check(GameState.selected_record_id == "ecstasy_poem", "面板：写入了 selected_record_id")
	var 面板2: Node = 面板场景.instantiate()
	add_child(面板2)
	await _等物理(2)
	var 次数 := [0]
	面板2.选择完成.connect(func(_id: String) -> void: 次数[0] += 1)
	面板2._取消()
	await get_tree().process_frame
	_check(次数[0] == 0, "面板：Esc 取消时不发 选择完成（88 留在虚弱，可再按 W）")
	await _等物理(4)
	_check(_player.输入软冻结 == false, "面板：关闭后玩家软冻结已解除")
	_check(_boss != null and _boss.has_method("_on_面板取消"), "面板：boss 侧有取消回落")
	_check(_boss != null and _boss.has_method("_on_唱片选定"), "面板：boss 侧有选定处理")


# ──────────────────────────── 对话 cue ────────────────────────────


func _检查对话cue() -> void:
	var res: DialogueResource = load(对话文件)
	_check(res != null, "对话：game.dialogue 能加载")
	if res == null:
		return
	var 坏: Array = []
	for c in 新增CUE:
		var line: DialogueLine = await DialogueManager.get_next_dialogue_line(res, c)
		if line == null or line.text.strip_edges().is_empty():
			坏.append(c)
	_check(坏.is_empty(), "对话：7 个新 cue 都能解析出文本（坏 %s）" % str(坏))
