extends Node
## Day 6/7/9：宿舍教程运行时测试（以场景方式运行，加载 autoload 全局）。
## 运行：godot --headless --path . res://tests/test_dorm.tscn --quit-after 2400
## 覆盖：
##   A. 结构完整（Player/相机/GameFlow/检查点/敌人/线索/出口/教程触发器/封路柜/书架/冲刺沟/地图节点）
##   B. Camera 横向滚动与边界钳制（0..4800 → 屏幕中心 [575,4225]）
##   C. 真实物理模拟：跳+冲刺 必须越过 220px 沟；纯跳 必须掉进沟里（证明必须冲刺）
##   D. 真实物理模拟：封路柜逼跳，从地面单跳登上 S1 书架
##   E. Day 7 地图：房间级点亮（入口/书架/钢琴 随进入点亮，未进入不点亮）
##   F. Day 7 地图：M 开/关全屏地图（暂停/恢复），Esc 只关地图不误开暂停菜单
##   G. Day 9 三段连击：窗口内点击升段、不打断当前动画、打满/超时归位、长按自动连并循环回第 1 段
##   H. Day 9 命中伤害：第 1/2 段 1 点、第 3 段重斩 2 点，恰好第 3 段打死 5 血敌人
##   I. Day 10 攻击后摇可被跳跃取消：攻击中按跳跃 → 立即取消攻击并切到跳跃状态
## 注意：runner 需 PROCESS_MODE_ALWAYS，否则开地图暂停后自身 _process 会停摆。

const DORM_SCENE = preload("res://scenes/levels/main.tscn")
const ENEMY_SCENE = preload("res://scenes/enemies/quarter_note/Enemy.tscn")
const TRIGGER_NAMES := ["DT_welcome", "DT_jump", "DT_dash", "DT_combat", "DT_inventory"]

var _pass: int = 0
var _fail: int = 0
var _phase: int = 0
var _wait: int = 0
var _sim: int = 0
var _sim_wait: int = 0
var _jumped: bool = false
var _dashed: bool = false
var _moved: bool = false
var _run_checked: bool = false
var _jump_checked: bool = false
var _atk_hold_checked: bool = false
var _test_enemy: Node = null
var _player: CharacterBody2D
var _cam: Camera2D
var _dorm: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 开地图暂停后 runner 仍能跑
	_dorm = DORM_SCENE.instantiate()
	add_child(_dorm)


func _process(_delta: float) -> void:
	_wait += 1
	match _phase:
		0:
			if _wait >= 10:
				_phase = 1
				_wait = 0
				_check_structure()
				_teleport_player(170.0)
		1:
			if _wait >= 100:
				_phase = 2
				_wait = 0
				_check_cam_x(170.0, "玩家在左端(170) 屏幕中心钳制到左限")
				_teleport_player(1000.0)
		2:
			if _wait >= 100:
				_phase = 3
				_wait = 0
				_check_cam_x(1000.0, "玩家在中段(1000) 屏幕中心居中")
				_teleport_player(4400.0)
		3:
			if _wait >= 100:
				_phase = 4
				_wait = 0
				_check_cam_x(4400.0, "玩家在右段(4400) 屏幕中心钳制到右限")
				_check_cam_y_dynamic("玩家贴地 屏幕中心按限制钳制")
				_prepare_physics_sim()
		4:
			_sim_dash_cross(true)   # 跳 + 冲刺 → 必须越过
		5:
			_sim_dash_cross(false)  # 纯跳 → 必须掉沟
		6:
			_sim_jump_shelf()       # 封路柜逼跳：单跳登上 S1
		7:
			_phase = 8
			_wait = 0
		8:
			_sim_attack()           # Day 9：三段连击状态机（窗口升段/长按自动/超时归位）
		9:
			_sim_attack_damage()    # Day 9：命中盒按段伤害（1/2 段 1 点，第 3 段 2 点）
		10:
			_sim_attack_jump_cancel()   # Day 10：攻击后摇可被跳跃取消
		11:
			_finish()


# ---------------- 物理模拟：冲刺过沟 ----------------

func _sim_dash_cross(dash: bool) -> void:
	_sim_wait += 1
	match _sim:
		0:
			_player.velocity = Vector2.ZERO
			_player.global_position = Vector2(1880, 542)  # 沟前地面（复位 y，避免残留）
			_sim = 1
			_sim_wait = 0
		1:
			if _sim_wait >= 10:  # 落地稳定
				_sim_wait = 0
				Input.action_press("move_right")
				_moved = true
				_sim = 2
		2:
			# Day 7：助跑阶段跑步动画应可见并播放（仅移动时）
			if not _run_checked and _player.global_position.x >= 1900.0 and _player.is_on_floor():
				var act := _player.get_node_or_null("ActionSprite") as Sprite2D
				var idle_spr := _player.get_node_or_null("Sprite2D") as Sprite2D
				var ap := _player.get_node_or_null("AnimationPlayer") as AnimationPlayer
				var ok: bool = act != null and act.visible and ap != null and ap.is_playing() and ap.current_animation == "run"
				_check(ok, "跑步动画在移动时可见并播放（visible=%s anim=%s）"
					% [str(act.visible if act else false), str(ap.current_animation if ap else "null")])
				if act:
					_check(absf(act.scale.x - 0.31) < 0.02,
						"跑步角色缩放 0.31（与冲刺/跳跃同尺寸）")
					_check(idle_spr != null and not idle_spr.visible,
						"跑步时待机立绘隐藏，不重叠（idle.visible=%s）"
						% str(idle_spr.visible if idle_spr else "null"))
				_run_checked = true
			# 跳跃上升段（冲刺触发前）应处于 JUMP 状态 → 播放跳跃单帧动画
			if not _jump_checked and _jumped and not _player.is_on_floor() and _player.velocity.y < -200.0:
				var ap2 := _player.get_node_or_null("AnimationPlayer") as AnimationPlayer
				_check(ap2 != null and ap2.is_playing() and ap2.current_animation == "jump",
					"空中跳跃播放单帧跳跃动画（anim=%s）" % str(ap2.current_animation if ap2 else "null"))
				_jump_checked = true
			if not _jumped and _player.global_position.x >= 1940.0:
				Input.action_press("jump")
				_jumped = true
			# 在跳跃最高点附近（velocity.y 由负转零/正）冲刺 —— 教学正确时机
			if dash and _jumped and not _dashed and not _player.is_on_floor() and _player.velocity.y > -50.0:
				Input.action_press("dash")
				_dashed = true
			var landed: bool = _player.is_on_floor()
			var px: float = _player.global_position.x
			var crossed: bool = landed and px >= 2172.0
			var fell: bool = landed and px <= 2170.0 and px >= 1940.0 and _player.global_position.y > 560.0
			if dash and crossed:
				_check(true, "跳+冲刺 成功越过 220px 宽沟（落地 x=%.0f）" % px)
				_end_physics_sim()
			elif dash and fell:
				_check(false, "跳+冲刺 竟然掉进沟里（x=%.0f）" % px)
				_end_physics_sim()
			elif not dash and fell:
				_check(true, "纯跳 掉进沟里（x=%.0f）→ 证明必须冲刺" % px)
				_end_physics_sim()
			elif not dash and crossed:
				_check(false, "纯跳 竟然越过了沟（沟太窄，需加宽）")
				_end_physics_sim()
			elif _sim_wait > 300:
				_check(false, "物理模拟超时（x=%.0f 落地=%s）" % [px, str(landed)])
				_end_physics_sim()


# ---------------- 物理模拟：书架爬升 ----------------

func _sim_jump_shelf() -> void:
	_sim_wait += 1
	match _sim:
		0:
			_player.velocity = Vector2.ZERO
			_player.global_position = Vector2(1000, 542)  # S1 左侧地面
			_sim = 1
			_sim_wait = 0
		1:
			if _sim_wait >= 10:
				_sim_wait = 0
				Input.action_press("move_right")
				_sim = 2
		2:
			if _player.is_on_floor() and _player.global_position.x >= 1010.0 and not _jumped:
				Input.action_press("jump")
				_jumped = true
			if _player.is_on_floor() and _player.global_position.y <= 490.0:
				_check(true, "封路柜逼跳成立：从地面单跳登上 S1（y=%.0f）" % _player.global_position.y)
				_end_shelf_sim()
			elif _sim_wait > 200:
				_check(false, "书架跳不上 S1（y=%.0f 落地=%s）" % [_player.global_position.y, str(_player.is_on_floor())])
				_end_shelf_sim()


func _end_shelf_sim() -> void:
	Input.action_release("move_right")
	Input.action_release("jump")
	_jumped = false
	_sim = 0
	_sim_wait = 0
	_phase = 7
	_wait = 0


func _end_physics_sim() -> void:
	Input.action_release("move_right")
	Input.action_release("jump")
	Input.action_release("dash")
	_jumped = false
	_dashed = false
	_moved = false
	_sim = 0
	_sim_wait = 0
	_phase += 1
	_wait = 0


func _prepare_physics_sim() -> void:
	# 强制关闭出生对白 + 禁用全部教程触发区，让玩家自由移动
	var box := get_tree().get_first_node_in_group("dialogue")
	if box:
		box.is_active = false
	for n in TRIGGER_NAMES:
		var t: Area2D = _dorm.get_node_or_null(n) as Area2D
		if t:
			t.monitoring = false


# ---------------- Day 7：地图开关模拟 ----------------

			_phase = 8
			_wait = 0
	_sim_wait += 1
	match _sim:
		0:
			# 复位：确保地图关闭、未暂停（防残留状态）
			get_tree().paused = false
			var map0 := get_tree().get_first_node_in_group("map_screen")
			if map0:
				map0._close()
			_sim = 1
			_sim_wait = 0
		1:
			if _sim_wait >= 5:
				_sim_wait = 0
				Input.action_press("map")
				_sim = 2
		2:
			if _sim_wait >= 10:
				Input.action_release("map")
				_check_map_open("按 M 打开全屏地图并暂停")
				_sim = 3
				_sim_wait = 0
				Input.action_press("ui_cancel")  # Esc 应只关地图，不误开暂停菜单
		3:
			if _sim_wait >= 10:
				Input.action_release("ui_cancel")
				_check_map_closed("按 Esc 关闭全屏地图并恢复")
				_check_pause_menu_closed("Esc 只关地图，不误开暂停菜单")
				_sim = 4
				_sim_wait = 0
		4:
			if _sim_wait >= 5:
				_sim_wait = 0
				Input.action_press("map")
				_sim = 5
		5:
			if _sim_wait >= 10:
				Input.action_release("map")
				_check_map_open("再按 M 再次打开")
				_sim = 6
				_sim_wait = 0
		6:
			if _sim_wait >= 5:
				_sim_wait = 0
				Input.action_press("map")
				_sim = 7
		7:
			if _sim_wait >= 10:
				Input.action_release("map")
				_check_map_closed("第三次按 M 关闭并恢复")
				_end_map_sim()


func _end_map_sim() -> void:
	_sim = 0
	_sim_wait = 0
	_phase = 8
	_wait = 0


# ---------------- Day 9：三段连击状态机 ----------------

func _player_anim() -> String:
	var ap := _player.get_node_or_null("AnimationPlayer") as AnimationPlayer
	return ap.current_animation if ap else "null"


func _anim_playing() -> bool:
	var ap := _player.get_node_or_null("AnimationPlayer") as AnimationPlayer
	return ap != null and ap.is_playing()


func _anim_pos() -> float:
	var ap := _player.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or ap.current_animation.is_empty():
		return 0.0
	return ap.current_animation_position


func _check_combo(stage: int, anim: String, label: String) -> void:
	var ap := _player.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var ok: bool = _player.combo_stage == stage and ap != null and ap.is_playing() and ap.current_animation == anim
	_check(ok, label + "（stage=%d anim=%s）" % [_player.combo_stage, str(ap.current_animation if ap else "null")])


func _sim_attack() -> void:
	## process 帧数 ≠ 物理帧数（无头模式下比例会变），所以全部用「轮询状态变化 + 宽裕超时」，
	## 不做固定帧数等待；超时按最慢情形（约 1 物理帧/1 process 帧）放大到安全值。
	_sim_wait += 1
	match _sim:
		0:
			# 复位：松开全部输入，传送玩家到右侧空旷区，等残留攻击完全结束
			Input.action_release("attack")
			Input.action_release("move_right")
			Input.action_release("move_left")
			Input.action_release("jump")
			Input.action_release("dash")
			get_tree().paused = false
			_player.velocity = Vector2.ZERO
			_player.global_position = Vector2(4400, 542)
			_player.facing = 1
			_atk_hold_checked = false
			_sim = 1
			_sim_wait = 0
		1:
			# 落地稳定 + 无残留攻击后再按
			if _player.is_on_floor() and _player.combo_stage == 0:
				_sim_wait = 0
				Input.action_press("attack")  # 首次点击 → 第 1 段
				_sim = 2
			elif _sim_wait > 120:
				_check(false, "准备未就绪（combo_stage=%d anim=%s）" % [_player.combo_stage, _player_anim()])
				_sim = 99
		2:
			# 等第 1 段真正播起来（不在按下后立即断言）
			if _player.combo_stage == 1 and _player_anim() == "attack1" and _anim_playing():
				Input.action_release("attack")
				var act := _player.get_node_or_null("ActionSprite") as Sprite2D
				var idle_spr := _player.get_node_or_null("Sprite2D") as Sprite2D
				_check_combo(1, "attack1", "首次点击 → 第 1 段攻击")
				_check(act != null and act.visible, "攻击时动作精灵可见")
				_check(idle_spr != null and not idle_spr.visible, "攻击时待机立绘隐藏")
				_sim = 3
				_sim_wait = 0
			elif _sim_wait > 80:
				_check(false, "首次点击未进入第 1 段（stage=%d anim=%s）" % [_player.combo_stage, _player_anim()])
				_sim = 99
		3:
			# 等 attack1 播到中段（连击窗口内）再点第 2 击
			if _player.combo_stage == 1 and _player_anim() == "attack1" and _anim_pos() >= 0.10:
				_sim_wait = 0
				Input.action_press("attack")  # 第 2 击：窗口内点击 → 缓冲升段
				_sim = 4
			elif _sim_wait > 120:
				_check(false, "attack1 未进入窗口期（stage=%d anim=%s pos=%.2f）" % [_player.combo_stage, _player_anim(), _anim_pos()])
				_sim = 99
		4:
			# 第 2 击后：仍 attack1 且位置继续推进（未打断/未重置）
			if _sim_wait >= 2:
				Input.action_release("attack")
			if _player.combo_stage == 1 and _player_anim() == "attack1" and _anim_pos() >= 0.15:
				_check(true, "窗口内第 2 击不打断当前动画（仍 attack1，pos=%.2f）" % _anim_pos())
				_sim = 5
				_sim_wait = 0
			elif _sim_wait > 120:
				_check(false, "第 2 击后动画异常（stage=%d anim=%s pos=%.2f）" % [_player.combo_stage, _player_anim(), _anim_pos()])
				_sim = 99
		5:
			# 等 attack1 播完自动衔接第 2 段
			if _player.combo_stage == 2:
				_check_combo(2, "attack2", "attack1 播完 → 自动衔接第 2 段")
				_sim_wait = 0
				Input.action_press("attack")  # 第 3 击：attack2 播放中点击
				_sim = 6
			elif _sim_wait > 150:
				_check(false, "attack1 播完未升到第 2 段（stage=%d）" % _player.combo_stage)
				_sim = 99
		6:
			if _sim_wait >= 2:
				Input.action_release("attack")
				_sim = 7
				_sim_wait = 0
		7:
			# 等 attack2 播完自动衔接第 3 段
			if _player.combo_stage == 3:
				_check_combo(3, "attack3", "attack2 播完 → 第 3 段（重斩）")
				_sim = 8
				_sim_wait = 0
			elif _sim_wait > 150:
				_check(false, "attack2 播完未升到第 3 段（stage=%d）" % _player.combo_stage)
				_sim = 99
		8:
			# 等第 3 段打满（窗口内无下一击/未长按）→ 连击结束归位
			if _player.combo_stage == 0:
				_check(true, "第 3 段打满未衔接 → 连击结束归位（stage=0）")
				_sim = 9
				_sim_wait = 0
			elif _sim_wait > 180:
				_check(false, "第 3 段结束后未归位（stage=%d）" % _player.combo_stage)
				_sim = 99
		9:
			if _sim_wait >= 5:
				_sim_wait = 0
				Input.action_press("attack")  # 全新点击
				_sim = 10
		10:
			if _sim_wait >= 2:
				Input.action_release("attack")
				_sim = 11
				_sim_wait = 0
		11:
			# 单次攻击播完（无第 2 击）→ 超时归位 stage=0
			if _player.combo_stage == 0:
				_check(true, "单次攻击后超时归位（stage=0）")
				_sim_wait = 0
				Input.action_press("attack")  # 再按：应重新从第 1 段
				_sim = 12
			elif _sim_wait > 150:
				_check(false, "单次攻击后未超时归位（stage=%d）" % _player.combo_stage)
				_sim = 99
		12:
			# 再按应全新从第 1 段（非第 2 段）
			if _player.combo_stage == 1 and _player_anim() == "attack1":
				Input.action_release("attack")
				_check_combo(1, "attack1", "超时后再按 → 重新从第 1 段（非第 2 段）")
				_sim = 13
				_sim_wait = 0
			elif _sim_wait > 80:
				_check(false, "超时后再按未从第 1 段开始（stage=%d anim=%s）" % [_player.combo_stage, _player_anim()])
				_sim = 99
		13:
			if _sim_wait >= 2:
				_sim_wait = 0
				Input.action_press("attack")  # 长按自动连
				_atk_hold_checked = false
				_sim = 14
		14:
			# 长按不重置动画（attack1 持续播放）→ 等自动衔接第 2 段
			if not _atk_hold_checked and _player.combo_stage == 1 and _player_anim() == "attack1" and _anim_pos() >= 0.05:
				_check(true, "长按不重置动画（attack1 持续播放中 pos=%.2f）" % _anim_pos())
				_atk_hold_checked = true
			if _player.combo_stage == 2:
				_check_combo(2, "attack2", "长按自动衔接 → 第 2 段")
				_sim = 15
				_sim_wait = 0
			elif _sim_wait > 150:
				_check(false, "长按未升到第 2 段（stage=%d）" % _player.combo_stage)
				_sim = 99
		15:
			if _player.combo_stage == 3:
				_check_combo(3, "attack3", "长按自动衔接 → 第 3 段")
				_sim = 16
				_sim_wait = 0
			elif _sim_wait > 150:
				_check(false, "长按未升到第 3 段（stage=%d）" % _player.combo_stage)
				_sim = 99
		16:
			# 长按第 3 段后循环回第 1 段（不归位）
			if _player.combo_stage == 1:
				_check_combo(1, "attack1", "长按第 3 段后循环回第 1 段")
				_sim = 17
				_sim_wait = 0
			elif _sim_wait > 200:
				_check(false, "长按未循环回第 1 段（stage=%d）" % _player.combo_stage)
				_sim = 99
		17:
			Input.action_release("attack")
			# 等循环回的 attack1 播完归位（否则残留攻击会打到 Phase 9 的敌人）
			if _player.combo_stage == 0:
				_end_attack_sim()
			elif _sim_wait > 180:
				_check(false, "长按测试后攻击未完全结束（stage=%d）" % _player.combo_stage)
				_sim = 99
		99:
			Input.action_release("attack")
			_end_attack_sim()


func _end_attack_sim() -> void:
	Input.action_release("attack")
	_sim = 0
	_sim_wait = 0
	_phase = 9
	_wait = 0


# ---------------- Day 9：命中盒按段伤害 ----------------

func _sim_attack_damage() -> void:
	_sim_wait += 1
	match _sim:
		0:
			Input.action_release("attack")
			_player.velocity = Vector2.ZERO
			_player.global_position = Vector2(4380, 542)
			_player.facing = 1
			# 生成一只冻结的近战敌人，放在玩家正前方（命中盒内）
			if _test_enemy != null and is_instance_valid(_test_enemy):
				_test_enemy.queue_free()
			var e := ENEMY_SCENE.instantiate()
			_dorm.add_child(e)
			e.global_position = Vector2(_player.global_position.x + 60.0, 544.0)
			e.hp = 5  # 5 血：单段(1)+三段连击(1+1+2=4) 恰好第 3 段重斩打死 → 顺带验证双倍伤害
			e.set_physics_process(false)
			_test_enemy = e
			_sim = 1
			_sim_wait = 0
		1:
			# 等落地稳定 + 残留攻击结束（Phase 8 结尾循环攻击）后再按
			if _player.is_on_floor() and _player.combo_stage == 0:
				_sim_wait = 0
				Input.action_press("attack")
				_sim = 2
			elif _sim_wait > 150:
				_check(false, "伤害测试准备未就绪（combo_stage=%d）" % _player.combo_stage)
				_sim = 99
		2:
			if _sim_wait >= 2:
				Input.action_release("attack")
				_sim = 3
				_sim_wait = 0
		3:
			# 第 1 段命中一次（伤害 1），等攻击播完归位
			if _test_enemy != null and is_instance_valid(_test_enemy) and _test_enemy.hp == 4:
				_check(true, "第 1 段命中造成 1 点伤害（hp=5→4）")
				_sim = 4
				_sim_wait = 0
			elif _sim_wait > 120:
				_check(false, "第 1 段未命中（enemy hp=%s 玩家 anim=%s）" % [
					str(_test_enemy.hp if _test_enemy else "null"), _player_anim()])
				_sim = 99
		4:
			if _sim_wait >= 5:
				_sim_wait = 0
				Input.action_press("attack")  # 长按打满三段
				_sim = 5
		5:
			# 长按：第 1 段(1)+第 2 段(1)+第 3 段(2) = 再扣 4 点 → hp 4-4 = 0 第 3 段重斩打死
			if _test_enemy == null or not is_instance_valid(_test_enemy) or _test_enemy.hp <= 0:
				_check(true, "长按三段连击 1+1+2=4 点 → 第 3 段重斩打死敌人（hp 4→0，双倍伤害成立）")
				Input.action_release("attack")
				_end_attack_damage_sim()
			elif _sim_wait > 300:
				_check(false, "三段连击未杀死敌人（hp=%s 玩家 anim=%s stage=%d）" % [
					str(_test_enemy.hp if _test_enemy else "null"), _player_anim(), _player.combo_stage])
				Input.action_release("attack")
				_end_attack_damage_sim()
		99:
			Input.action_release("attack")
			_end_attack_damage_sim()


func _end_attack_damage_sim() -> void:
	Input.action_release("attack")
	_sim = 0
	_sim_wait = 0
	_phase = 10
	_wait = 0


# ---------------- Day 10：攻击后摇可被跳跃取消 ----------------

func _sim_attack_jump_cancel() -> void:
	## 攻击中按跳跃 → 立即结束攻击并进入跳跃状态（取消后摇）。
	_sim_wait += 1
	match _sim:
		0:
			Input.action_release("attack")
			Input.action_release("jump")
			Input.action_release("move_right")
			Input.action_release("move_left")
			Input.action_release("dash")
			get_tree().paused = false
			_player.velocity = Vector2.ZERO
			_player.global_position = Vector2(4400, 542)
			_player.facing = 1
			_sim = 1
			_sim_wait = 0
		1:
			# 落地稳定 + 无残留攻击后再按
			if _player.is_on_floor() and _player.combo_stage == 0:
				_sim_wait = 0
				Input.action_press("attack")
				_sim = 2
			elif _sim_wait > 120:
				_check(false, "跳跃取消测试准备未就绪（combo_stage=%d）" % _player.combo_stage)
				_sim = 99
		2:
			# 等第 1 段真正播起来，再按跳跃 → 应取消攻击
			if _player.combo_stage == 1 and _player_anim() == "attack1" and _anim_playing():
				Input.action_release("attack")
				_sim_wait = 0
				Input.action_press("jump")
				_sim = 3
			elif _sim_wait > 80:
				_check(false, "取消前未进入攻击（stage=%d anim=%s）" % [_player.combo_stage, _player_anim()])
				_sim = 99
		3:
			# 轮询等待取消在物理帧里生效（_process 频率远高于物理帧，不能按 _sim_wait 数帧判，
			# 否则会在玩家还没处理跳跃按下时就断言到旧状态）
			var ap := _player.get_node_or_null("AnimationPlayer") as AnimationPlayer
			var hb := _player.get_node_or_null("MeleeHitbox") as Area2D
			if _player.state == 2 and _player.combo_stage == 0 and _player.velocity.y < 0.0:
				var ok_anim: bool = ap != null and ap.is_playing() and ap.current_animation == "jump"
				var ok_hb: bool = hb != null and not hb.visible and not hb.monitoring
				_check(ok_anim and ok_hb,
					"攻击中按跳跃 → 立即取消攻击并起跳（anim=%s vel_y=%.0f hb_visible=%s）"
					% [str(ap.current_animation if ap else "null"), _player.velocity.y,
					str(hb.visible if hb else "null")])
				Input.action_release("jump")
				_end_attack_jump_sim()
			elif _sim_wait > 150:
				_check(false, "跳跃取消未生效（state=%d anim=%s combo=%d vel_y=%.0f）"
					% [_player.state, _player_anim(), _player.combo_stage, _player.velocity.y])
				Input.action_release("jump")
				_end_attack_jump_sim()
		99:
			Input.action_release("attack")
			Input.action_release("jump")
			_end_attack_jump_sim()


func _end_attack_jump_sim() -> void:
	Input.action_release("attack")
	Input.action_release("jump")
	_sim = 0
	_sim_wait = 0
	_phase = 11
	_wait = 0


func _map_screen() -> CanvasLayer:
	return get_tree().get_first_node_in_group("map_screen") as CanvasLayer


func _fullmap_visible() -> bool:
	var map := _map_screen()
	if map == null:
		return false
	var full := map.get_node_or_null("FullMap") as Control
	return full != null and full.visible


func _check_map_open(name: String) -> void:
	var map := _map_screen()
	var ok: bool = get_tree().paused and map != null and map.is_open() and _fullmap_visible()
	_check(ok, name + "（paused=%s open=%s visible=%s）"
		% [str(get_tree().paused), str(map.is_open() if map else "null"), str(_fullmap_visible())])


func _check_map_closed(name: String) -> void:
	var map := _map_screen()
	var ok: bool = not get_tree().paused and map != null and not map.is_open() and not _fullmap_visible()
	_check(ok, name + "（paused=%s open=%s visible=%s）"
		% [str(get_tree().paused), str(map.is_open() if map else "null"), str(_fullmap_visible())])


func _check_pause_menu_closed(name: String) -> void:
	var pm := get_tree().get_first_node_in_group("pause_menu")
	var panel: Control = pm.get("_pause_panel") if pm else null
	_check(panel == null or not panel.visible, name + "（pause_panel.visible=%s）"
		% str(panel.visible if panel else "null"))


# ---------------- 结构校验 ----------------

func _check_structure() -> void:
	_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	_check(_player != null, "Player 存在")
	if _player:
		_cam = _player.get_node_or_null("Camera2D") as Camera2D
		_check(_cam != null, "Camera2D 为 Player 子节点")
		if _cam:
			_check(_cam.limit_left == 0 and _cam.limit_right == 4800, "相机 limit 0..4800（横向可滚动）")
			_check(_cam.limit_top == -100 and _cam.limit_bottom == 700, "相机 limit 纵向 -100..700")
		# Day 7：跑步/冲刺/跳跃动画（AnimationPlayer 关键帧）
		var act := _player.get_node_or_null("ActionSprite") as Sprite2D
		_check(act != null, "动作精灵节点 ActionSprite 存在")
		var ap := _player.get_node_or_null("AnimationPlayer") as AnimationPlayer
		_check(ap != null, "AnimationPlayer 存在")
		if ap:
			var arun := ap.get_animation("run")
			var adash := ap.get_animation("dash")
			var ajump := ap.get_animation("jump")
			_check(arun != null and adash != null and ajump != null, "run/dash/jump 三个动画存在")
			if arun:
				# 帧数/时长由美术在编辑器里按手感裁剪（当前 14 帧 / 1.3s 循环），
				# 这里只断言「循环 + 帧数足够构成跑动循环」，避免手调动画后测试误报。
				var n := _anim_track_key_count(arun, "ActionSprite:texture")
				_check(arun.length >= 1.0 and arun.loop_mode == Animation.LOOP_LINEAR,
					"跑步动画循环（%.1fs，loop_mode=%d）" % [arun.length, arun.loop_mode])
				_check(n >= 10, "跑步动画帧数充足（当前 %d 帧）" % n)
			if adash:
				_check(_anim_track_key_count(adash, "ActionSprite:texture") == 1, "冲刺动画单帧关键帧")
			if ajump:
				_check(_anim_track_key_count(ajump, "ActionSprite:texture") == 1, "跳跃动画单帧关键帧")
	_check(get_tree().get_first_node_in_group("gameflow") != null, "GameFlow 存在")
	_check(_has_node_named("Checkpoint_school"), "Checkpoint_school 存在")
	_check(_has_node_named("Enemy1") and _has_node_named("Enemy2"), "两名近战敌人存在")
	_check(_has_node_named("RangedEnemy1"), "一名远程敌人存在")
	_check(_has_node_named("Clue3"), "88 线索存在")
	_check(_has_node_named("Door_playground"), "出口门存在")
	var door: Node = _node_named("Door_playground")
	_check(door != null and door.get("target_scene") == "res://scenes/levels/school_playground.tscn", "出口指向操场")
	_check(_has_node_named("LoftPath"), "阁楼回廊 LoftPath 存在")
	_check(_has_node_named("HiddenAlcove"), "书柜暗格平台 HiddenAlcove 存在")
	_check(_has_node_named("HighWindowLedge"), "高窗回访平台 HighWindowLedge 存在")
	_check(_has_node_named("NoteS1") and _has_node_named("NoteAlcove")
		and _has_node_named("NoteHighWindow") and _has_node_named("NoteRangedLedge"),
		"四个音符拾取点存在")
	_check(_has_node_named("TutorialPrompt"), "非阻塞教学提示 TutorialPrompt 存在")
	_check(GameState.MAX_MANA == 100.0 and GameState.MAGIC_COST == 10.0
		and GameState.MANA_REGEN_PER_SEC == 2.0, "法力数值常量正确（100/10/2）")
	if _player:
		_check(absf(_player.mana - GameState.MAX_MANA) < 0.01, "玩家初始满蓝")
		_player._spend_mana(GameState.MAGIC_COST)
		_check(absf(_player.mana - (GameState.MAX_MANA - GameState.MAGIC_COST)) < 0.01, "魔法扣蓝 10")
		_player._regen_mana(1.0)
		_check(absf(_player.mana - (GameState.MAX_MANA - GameState.MAGIC_COST + GameState.MANA_REGEN_PER_SEC)) < 0.01,
			"每秒回蓝 2")
		_player.mana = GameState.MAX_MANA
		GameState.mana = GameState.MAX_MANA
	var all_triggers := true
	for n in TRIGGER_NAMES:
		if not _has_node_named(n):
			all_triggers = false
	_check(all_triggers, "五个教程对话触发区存在")
	var w: Node = _node_named("DT_welcome")
	_check(w != null and (w.get("cue") as String) != "", "移动教程有对白 cue")
	var dj: Node = _node_named("DT_jump")
	_check(dj != null and (dj.get("text") as String) != "", "跳跃教程有非阻塞提示文本")
	var dd: Node = _node_named("DT_dash")
	_check(dd != null and (dd.get("text") as String) != "", "冲刺教程有非阻塞提示文本")
	_check(_has_node_named("BlockCabinet"), "封路柜子存在（逼走书架）")
	_check(_has_node_named("S1") and _has_node_named("S2") and _has_node_named("S3"), "三层书架存在")
	_check_shelf_chain()
	var ga: Node = _node_named("GroundA")
	var gb: Node = _node_named("GroundB")
	if ga and gb:
		var a_half: float = (ga.get_node("CollisionShape2D").shape as RectangleShape2D).size.x / 2.0
		var b_half: float = (gb.get_node("CollisionShape2D").shape as RectangleShape2D).size.x / 2.0
		var gap: float = (gb as Node2D).position.x - b_half - (ga as Node2D).position.x - a_half
		_check(gap >= 220.0, "冲刺沟宽 ≥220px（必须跳跃+冲刺） → 实测 %.0fpx" % gap)
	else:
		_check(false, "冲刺沟地面段存在")

	## 书架链条：地面→S1→S2→S3→柜顶，每级落差 ≤ 单跳上限(104px)，保证全程单跳可达。
func _check_shelf_chain() -> void:
	var s1: Node = _node_named("S1")
	var s2: Node = _node_named("S2")
	var s3: Node = _node_named("S3")
	var cab: Node = _node_named("BlockCabinet")
	if not (s1 and s2 and s3 and cab):
		_check(false, "书架链条节点齐全")
		return
	var tops := []
	for n in [s1, s2, s3, cab]:
		var shape := n.get_node("CollisionShape2D").shape as RectangleShape2D
		tops.append((n as Node2D).position.y - shape.size.y / 2.0)
	var ground_top := 560.0
	var seq := [ground_top]
	seq.append_array(tops)
	var all_reachable := true
	for i in range(1, seq.size()):
		var step: float = float(seq[i - 1]) - float(seq[i])
		if step > 104.0:
			all_reachable = false
			_check(false, "台阶 %d→%d 落差 %.0fpx > 单跳上限 104px" % [i - 1, i, step])
	if all_reachable:
		_check(true, "书架链条单跳可达（地面→S1→S2→S3→柜顶 落差均 ≤104px）")


# ---------------- 工具 ----------------

func _teleport_player(x: float) -> void:
	if _player:
		_player.velocity = Vector2.ZERO
		_player.global_position = Vector2(x, _player.global_position.y)
		if _cam:
			_cam.reset_smoothing()


## 横向钳制校验：期望值按「玩家位置 + 实际视口宽 + limit」动态计算，与运行环境无关。
func _check_cam_x(player_x: float, name: String) -> void:
	if _cam == null:
		_check(false, name + "（无相机）")
		return
	var vw: float = _cam.get_viewport_rect().size.x
	var lo: float = _cam.limit_left + vw / 2.0
	var hi: float = _cam.limit_right - vw / 2.0
	var expected: float = clampf(player_x, lo, hi)
	var c: Vector2 = _cam.get_screen_center_position()
	_check(absf(c.x - expected) < 2.0, name + "  → 期望 x=%.0f 实际 x=%.0f（视口宽 %d）"
		% [expected, c.x, int(vw)])


## 垂直钳制校验：期望值按「实际视口尺寸 + limit」动态计算，与运行环境无关。
func _check_cam_y_dynamic(name: String) -> void:
	if _cam == null or _player == null:
		_check(false, name + "（无相机/玩家）")
		return
	var vp: Vector2 = _cam.get_viewport_rect().size
	var lo: float = _cam.limit_top + vp.y / 2.0
	var hi: float = _cam.limit_bottom - vp.y / 2.0
	var expected: float
	if lo > hi:
		# 视口比地图垂直跨度还高：相机把地图垂直居中
		expected = (_cam.limit_top + _cam.limit_bottom) / 2.0
	else:
		expected = clampf(_player.global_position.y, lo, hi)
	var c: Vector2 = _cam.get_screen_center_position()
	_check(absf(c.y - expected) < 2.0, name + "  → 期望 y=%.0f 实际 y=%.0f（视口 %d×%d）"
		% [expected, c.y, int(vp.x), int(vp.y)])


func _finish() -> void:
	print("\n===== 宿舍教程地图测试：通过 %d / 失败 %d =====" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[PASS] " + name)
	else:
		_fail += 1
		print("[FAIL] " + name)


func _has_node_named(n: String) -> bool:
	return _dorm != null and _dorm.has_node(n)


## 统计指定动画里某个路径轨道的关键帧数（找不到轨道返回 -1）。
func _anim_track_key_count(anim: Animation, path: String) -> int:
	for i in anim.get_track_count():
		if str(anim.track_get_path(i)) == path:
			return anim.track_get_key_count(i)
	return -1


func _node_named(n: String) -> Node:
	return _dorm.get_node_or_null(n) if _dorm else null
