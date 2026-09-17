extends Node2D
## 音乐小游戏流程自检（headless，场景模式 —— `--script` 不会加载 autoload）。
## 运行：godot --headless --path . res://tests/test_music_game.tscn --quit-after 8000
##
## 覆盖：
##   基线  —— 玩家的近战挥砍本身能打中 layer 3 的普通敌人（跟史莱姆无关的对照）
##   流程  —— 进区只锁相机 → 站谱台按 W 才出史莱姆并演示 → 演示期间软冻结 → PLAY
##   提示  —— 谱台的 W 提示是统一的 InteractBubble：渐显渐隐、牌子在谱台上方、且没被关卡覆盖成隐藏
##   判定  —— 打错归零 + 自动重播；真实挥砍命中史莱姆 → 进度推进
##   结算  —— 全对 → DONE + 发货币 + 写触发 ID；0 点接触伤害不让玩家受伤
##   能力  —— 配了 `奖励能力` 时额外喷一枚能力音符（2 倍大 / 彩虹在变 / 有光晕 / 有扫光），
##            捡到发能力 + 播过场；漏抢的话下次进场会补发一枚悬停的
##
## 会写真实存档，所以开头备份、结尾还原（跟 test_music_sheet.gd 一样）。

const MUSIC_GAME_SCENE: PackedScene = preload("res://scenes/minigame/MusicGame.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/Player.tscn")
const CONFIG_SCRIPT := preload("res://scripts/minigame/MusicGameConfig.gd")
const MusicNotesScript := preload("res://scripts/game/MusicNotes.gd")
const NOTE_PICKUP_SCENE: PackedScene = preload("res://scenes/items/NotePickup.tscn")
const JUMP_PLANT_SCENE: PackedScene = preload("res://scenes/props/level3/JumpPlant.tscn")

const TRIGGER_ID := "test_music_game"
const REWARD := 7

var _pass: int = 0
var _fail: int = 0
var _player: CharacterBody2D
var _game: Node2D
var _had_save: bool = false
var _backup: String = ""


func _ready() -> void:
	_had_save = FileAccess.file_exists("user://save.json")
	if _had_save:
		var f := FileAccess.open("user://save.json", FileAccess.READ)
		_backup = f.get_as_text()
		f.close()
	await _run()
	_restore_save()
	print("\n===== 音乐小游戏流程自检结果：通过 %d / 失败 %d =====" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _run() -> void:
	GameState.reset()
	_add_floor()

	# 基线：先确认玩家的近战挥砍本身是好的。它不过就说明问题在近战，不在这小游戏。
	await _baseline_melee_check()

	_player = PLAYER_SCENE.instantiate()
	_player.position = Vector2(-900, 0)   # 故意站在触发区外，进区由测试手动触发
	add_child(_player)

	# ── 搭一个小游戏：砍掉两只史莱姆，只用 3 只，顺序故意乱序（E4 → C4 → D4）──
	_game = MUSIC_GAME_SCENE.instantiate()
	var slimes_root: Node2D = _game.get_node("Slimes")
	slimes_root.get_node("Slime3").free()
	slimes_root.get_node("Slime4").free()
	var config = CONFIG_SCRIPT.new()
	# 1-based：第3只、停顿、第1只、第2只 → 演示 [2,-1,0,1]，演奏 [2,0,1]
	config.演奏顺序 = PackedInt32Array([3, 0, 1, 2])
	config.通关奖励 = REWARD
	config.演示间隔 = 0.25   # 拉长一点，好观察演示取景
	_game.配置 = config
	_game.触发ID = TRIGGER_ID
	_game.奖励能力 = "double_jump"      # 通关额外喷一枚能力音符（3_1 的 MusicGame2 就是这么配的）
	_game.演示前停顿 = 0.02
	_game.演示后停顿 = 0.02
	_game.打错后重播延迟 = 0.05
	_game.相机滑入时长 = 0.05
	_game.相机垂直偏移 = 150.0
	_game.position = Vector2(0, 180)   # 让史莱姆站在测试地面(顶面 180)上，跟真实关卡一致
	add_child(_game)
	await _settle()

	# 0. 通关奖励门禁：绑定 需要通关ID 的弹跳植物，通关前必须隐藏 + 踩不到
	var gated_plant := JUMP_PLANT_SCENE.instantiate()
	gated_plant.需要通关ID = TRIGGER_ID
	add_child(gated_plant)
	gated_plant.global_position = Vector2(-700.0, 100.0)
	await _settle()
	_check(not gated_plant.visible, "通关前：绑定通关ID的弹跳植物隐藏")
	_check(not (gated_plant.get_node("Trigger") as Area2D).monitoring,
		"通关前：它的触发区关闭（踩不到，不会隐形弹飞玩家）")

	# 1. 初始：史莱姆隐藏，谱台常驻可见
	_check(_state() == 0, "初始状态 IDLE")
	_check(not slimes_root.visible, "初始史莱姆隐藏（还没跟谱台交互）")
	_check(_game.get_node("Pedestal").visible, "谱台一开始就可见（不依赖进区）")

	# 谱台的上下浮动动画
	var pedestal_visual := _game.get_node("Pedestal/Visual") as Sprite2D
	var bob_before := pedestal_visual.position.y
	await get_tree().create_timer(0.5).timeout
	_check(not is_equal_approx(pedestal_visual.position.y, bob_before), "谱台有上下浮动动画")

	# 染色：每只史莱姆必须用**独立材质**、且色相/饱和度等于自己那个音的颜色。
	# 共享材质会让一排史莱姆全体串色；参数不对则会出现"不是红橙黄绿青蓝紫"。
	var mats := {}
	var report := ""
	for i in _game.get_node("Slimes").get_child_count():
		var sprite := _slime(i).get_node("Sprite") as AnimatedSprite2D
		var mat := sprite.material as ShaderMaterial
		var note: String = _slime(i).get_note()
		var want := MusicNotesScript.get_color(note)
		var got_h: float = float(mat.get_shader_parameter("target_hue"))
		var got_s: float = float(mat.get_shader_parameter("target_saturation"))
		var got_v: float = float(mat.get_shader_parameter("value_scale"))
		mats[mat.get_instance_id()] = true
		report += "%s(h%.3f/s%.2f/v%.2f) " % [note, got_h, got_s, got_v]
		_check(absf(got_h - want.h) < 0.001 and absf(got_s - want.s) < 0.001,
			"%s 的材质色相/饱和度 = 该音的颜色" % note)
	print("[染色] 各史莱姆材质参数：%s" % report)
	_check(mats.size() == _game.get_node("Slimes").get_child_count(),
		"每只史莱姆用独立材质（没有串色）")

	# 2. 进区：只锁相机，史莱姆仍然不出现
	_game._on_trigger_entered(_player)
	await _settle()
	_check(_state() == 1, "进区后 ARMED")
	_check(not slimes_root.visible, "进区只锁相机，史莱姆仍隐藏")
	var cam := _player.get_node_or_null("Camera2D") as Camera2D
	_check(cam != null and cam.top_level, "进区后相机脱离跟随（锁定）")

	# 2b. 谱台的 W 提示：跟钢琴 / 留声机一样是「渐显渐隐」的 InteractBubble，
	#     不是直接切 visible（那样会硬闪出来）。可见的那块牌子得在谱台上半部分。
	var prompt := _game.get_node("Pedestal/Prompt") as InteractBubble
	_check(prompt != null, "谱台提示是统一的 InteractBubble")
	_check(prompt.visible, "谱台提示没被关卡覆盖成隐藏（3_1 里曾挂过一条 visible=false）")
	_check(is_zero_approx(prompt.modulate.a), "谱台提示初始是透明的")
	var prompt_panel := prompt.get_node("Panel") as Control
	var badge := Rect2(prompt_panel.global_position, prompt_panel.size)
	var ped_size: Vector2 = pedestal_visual.texture.get_size() * pedestal_visual.global_scale
	var ped_box := Rect2(pedestal_visual.global_position - ped_size * 0.5, ped_size)
	# ⚠️ 这里判的是"在上半部分"，不是"完全在谱台上方" —— 谱台提示的 offset_top 是
	#    作者在编辑器里定的（-56，牌子会压住谱台上沿一点），**别按"更合理"去改那个值**，
	#    只守住"别被拖到谱台下半截/埋进地里"（agent.md §12.2）。
	_check(badge.end.y <= ped_box.get_center().y,
		"提示牌在谱台上半部分（牌底 %.0f，谱台中心 %.0f，谱台顶 %.0f）"
			% [badge.end.y, ped_box.get_center().y, ped_box.position.y])

	_game._on_pedestal_entered(_player)
	await get_tree().create_timer(0.3).timeout
	_check(is_equal_approx(prompt.modulate.a, 1.0), "站上谱台 → W 提示渐显")
	_game._on_pedestal_exited(_player)
	await get_tree().create_timer(0.35).timeout
	_check(is_zero_approx(prompt.modulate.a), "离开谱台 → W 提示渐隐")

	# 镜头是"只插值、不跳变"的（agent.md §20），所以断言前要等它滑到位
	await get_tree().create_timer(1.3).timeout
	_game.get_node("Trigger").monitoring = false   # 免得玩家移动误触发"走远取消"干扰判定

	# 镜头：玩家在滑动范围内时镜头完全固定，停在他上方 150px（垂直偏移生效）
	# ⚠️ 期望值按"玩家 y - 偏移"算，不是"史莱姆中心 y - 偏移"：
	# 玩家站地上天然比史莱姆根节点高十几像素，相对中心算会差一点点。
	_player.global_position = _game._slimes_center()
	await get_tree().create_timer(0.8).timeout
	_check(absf(cam.global_position.y - (_player.global_position.y - 150.0)) < 8.0,
		"玩家在范围内时镜头停在他上方 150px（相机y=%.0f 玩家y=%.0f）"
			% [cam.global_position.y, _player.global_position.y])

	# 玩家跑到场地两端时，镜头只会让一点点，**玩家必须仍在画面内**
	# （用户报过"镜头跳转了、玩家却不在画面里"）
	for spot in [_game.get_node("Pedestal").global_position,
			_slime(2).global_position + Vector2(420.0, 0.0)]:
		_player.global_position = spot
		await get_tree().create_timer(0.8).timeout
		_check(_player_in_camera_view(),
			"镜头让位后玩家仍在画面内（玩家x=%d 镜头x=%d）"
				% [int(_player.global_position.x), int(cam.global_position.x)])

	# 2b. 史莱姆铺得比画面宽时，演示取景必须把镜头拉远（zoom < 1）
	var wide := Rect2(Vector2(-1000.0, -200.0), Vector2(2000.0, 400.0))
	var wide_zoom: Vector2 = _game._demo_zoom(wide)
	var view: Vector2 = get_viewport().get_visible_rect().size
	_check(wide_zoom.x < 1.0, "史莱姆群比画面宽时演示取景会拉远（zoom=%.2f）" % wide_zoom.x)
	_check(wide.size.x * wide_zoom.x <= view.x + 1.0
			and wide.size.y * wide_zoom.x <= view.y + 1.0,
		"拉远后整群史莱姆确实装得进画面")

	# 3. 无碰撞伤害：contact_damage = 0 不该让玩家掉血 / 进无敌 / 被击退
	var hp_before: int = _player.hp
	_player.take_damage(_slime(0).contact_damage, _slime(0).global_position)
	_check(_player.hp == hp_before, "0 点接触伤害不掉血")
	_check(_player.invincible_timer <= 0.0, "0 点伤害不进无敌帧")
	_check(_slime(0).contact_damage == 0, "史莱姆 contact_damage 恒为 0")

	# 4. 与谱台交互（按 W）→ 史莱姆出现 + 软冻结 + 演示 → PLAY
	_game._start_demo()
	_check(_state() == 2, "与谱台交互 → DEMO")
	_check(_game._demo_sequence.size() == 4, "演示序列含停顿（4 拍）")
	_check(_game._answer_sequence.size() == 3, "演奏序列去掉了停顿（3 个音要复现）")
	_check(slimes_root.visible, "交互后史莱姆出现")
	_check(_player.输入软冻结, "演示期间玩家被软冻结")
	# 演示期间：镜头要框住所有史莱姆（玩家可以不在画面里 —— 用户明确要求演示时优先框史莱姆）
	await get_tree().create_timer(0.9).timeout
	_check(_state() == 2, "0.9s 后仍在演示中（演示间隔已拉长）")
	var outside := _count_slimes_outside_camera()
	_check(outside == 0, "演示时所有史莱姆都在镜头内（超出 %d 只）" % outside)

	# 演示中还存一张截图，方便肉眼核对取景
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://music_game_demo.png")
		print("[截图] 已保存 user://music_game_demo.png")

	_check(await _wait_for_state(3, 8.0), "演示结束 → PLAY")
	_check(not _game._demo_framing, "PLAY 阶段切回「跟着玩家」的取景")
	_check(not _player.输入软冻结, "PLAY 阶段玩家解锁")

	# 4b. 受击表现真的会发生（用户报过"打史莱姆没反应"）：
	#     闪白靠 self_modulate、变暗靠 modulate —— 如果染色 shader 覆盖 COLOR 把它们吞掉，
	#     史莱姆就会毫无反应。这条守住"机制至少被触发"。
	# 先等演示残留的受击动画播完，否则抓到的"基准大小"是形变中间值。
	await get_tree().create_timer(0.35).timeout
	var sprite := _slime(0).get_node("Sprite") as AnimatedSprite2D
	var scale_before := sprite.scale
	_slime(0).play_hurt()
	_check(sprite.self_modulate.r > 1.0, "受击立刻闪白（self_modulate 提亮）")
	await get_tree().create_timer(0.03).timeout
	_check(sprite.scale != scale_before, "受击有缩放形变（压扁→回弹）")
	await get_tree().create_timer(0.4).timeout
	_check(sprite.scale.is_equal_approx(scale_before), "形变会回弹到原大小")
	_check(sprite.self_modulate.is_equal_approx(Color.WHITE), "闪白会恢复")

	# 5. 打错顺序（该打 2 号，先打 0 号）→ 归零 + 重播
	_hit(0)
	await _settle()
	_check(_game._progress == 0, "打错后进度归零")
	_check(_state() == 2, "打错后回到 DEMO 重播")
	_check(await _wait_for_state(3, 6.0), "重播结束 → 再次 PLAY")

	# 6. 真实挥砍命中史莱姆（走物理命中判定，不直接调 take_damage）→ 进度推进
	var diag := await _real_attack_on(2)
	_check(bool(diag["推进"]), "真实挥砍能打中史莱姆并推进进度（诊断：%s）" % str(diag))

	# 6b. 同一次挥砍同时罩到"目标 + 相邻一只" → 应当算对（不能因为蹭到旁边就判错）
	#     序列是 [2,0,1]，此时该打 0 号；同时报 2 号和 0 号。
	var progress_before: int = _game._progress
	_game._on_slime_hit(Vector2.ZERO, 2)
	_game._on_slime_hit(Vector2.ZERO, 0)
	await _settle()
	_check(_game._progress == progress_before + 1,
		"同时命中目标与相邻一只时判对（进度 %d→%d）" % [progress_before, _game._progress])

	# 7. 打完最后一个 → DONE；奖励**散落一地让玩家自己捡**（不直接入账、不弹文字提示）
	var notes_before: int = GameState.notes
	var pickups_before: int = _count_reward_pickups()
	_hit(1)
	await _settle()
	_check(_state() == 4, "全对 → DONE")
	# ⚠️ 立刻把玩家挪开：能力音符就撒在史莱姆中间，而玩家此刻正站在最后一只旁边，
	#    留着的话它落地时可能自己碰到玩家 —— 那就成了"测试中途自动拿到二段跳"，
	#    后面的断言全变成碰运气。捡它放到最后单独测（Trigger 在上面已关掉 monitoring，挪动不会误触）。
	_player.global_position = Vector2(-1500, 0)
	await _settle()
	var spawned: int = _count_reward_pickups() - pickups_before
	_check(spawned == REWARD, "通关撒出 %d 个音符拾取物（实际 %d）" % [REWARD, spawned])
	_check(GameState.notes == notes_before, "奖励不直接入账，要玩家自己捡")
	var no_toast := true
	for node in _reward_pickups():
		if bool(node.get("显示提示")):
			no_toast = false
	_check(no_toast, "奖励拾取物不弹「+N」文字提示（看左上角计数）")
	# 真捡一个：应该 +1
	var target = _reward_pickups()[0] if _count_reward_pickups() > 0 else null
	if target != null:
		target._on_body_entered(_player)
		await _settle()
		_check(GameState.notes == notes_before + 1, "捡起一个音符 +1")
	# 等它们落地（物理抛落），断言"真的都落在地面上"
	var settle_t := 0.0
	while settle_t < 5.0:
		var airborne := 0
		for node in _reward_pickups():
			if not node.is_on_floor():
				airborne += 1
		if airborne == 0:
			break
		await get_tree().physics_frame
		settle_t += 1.0 / 60.0
	var not_landed := 0
	var max_spread := 0.0
	var spawn: Vector2 = _game._slimes_center()
	for node in _reward_pickups():
		if not node.is_on_floor():
			not_landed += 1
		max_spread = maxf(max_spread, absf(node.global_position.x - spawn.x))
	_check(not_landed == 0, "奖励散落物全部落在地面上（没落地 %d 个）" % not_landed)
	# ⚠️ 这条是"飞溅"的关键断言：只断言"落地"会被"原地落下"骗过
	#    （拾取物圆心压在地面里 → 第一帧就 is_on_floor → 速度清零 → 根本飞不出去）
	_check(max_spread > 180.0, "奖励散落物真的飞溅开了（最远 %.0f px）" % max_spread)

	# 通关后再存一张截图，方便肉眼确认"飞溅一地"的效果
	if DisplayServer.get_name() != "headless":
		# 取景：玩家刚被挪走躲能力音符，这里把他放回奖励区中间。
		# ⚠️ 先把拾取检测全关掉 —— 否则"为了截图"就把能力音符顺手捡了，8c 的断言全废。
		_pause_pickups(true)
		var focus = _ability_notes()[0] if not _ability_notes().is_empty() else _game
		_player.global_position = focus.global_position + Vector2(-120.0, -40.0)
		await get_tree().create_timer(0.5).timeout
		# 把相位摆到"最能说明问题"的一帧：紫罗兰色 + 光带正压在音符上。
		# 音符会一路循环变色的，任意一帧都是随机的；而扫光带扫到贴图透明角落时根本看不见，
		# 所以固定一个代表性相位，这张截图才真的能用来核对"彩虹 + 光晕 + 扫光"。
		if not _ability_notes().is_empty():
			var ability = _ability_notes()[0]
			ability.set("_hue_phase", 0.75)
			ability.set("_sweep", 0.53)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://music_game_reward.png")
		print("[截图] 已保存 user://music_game_reward.png")
		_pause_pickups(false)
		_player.global_position = Vector2(-1500, 0)
		await _settle()

	# 物理碰撞验证：朝一堵墙扔音符，必须被挡住、不穿墙（用户最担心的就是撞墙）
	await _check_wall_blocks_pickup()

	_check(GameState.has_trigger(TRIGGER_ID), "通关写入触发 ID（永久完成）")
	# 通关后整排变暗，但保留在场景里（不隐藏、不删除）
	_check(slimes_root.visible, "通关后史莱姆仍显示（不移除）")
	var all_dimmed := true
	for i in slimes_root.get_child_count():
		if (_slime(i).get_node("Sprite") as AnimatedSprite2D).modulate.r >= 0.9:
			all_dimmed = false
	_check(all_dimmed, "通关后整排史莱姆变暗")

	# 通关奖励门禁：对应的 ID 一旦打卡，植物应当自己出现（轮询解锁）
	await _settle()
	_check(gated_plant.visible, "通关后：弹跳植物自动出现")
	_check((gated_plant.get_node("Trigger") as Area2D).monitoring,
		"通关后：它的触发区恢复（可以踩了）")
	await get_tree().create_timer(0.7).timeout
	_check(gated_plant.scale.is_equal_approx(Vector2(0.3, 0.3)),
		"弹出动画结束后回到原大小（实际 %s）" % gated_plant.scale)
	_check(not _player.输入软冻结, "通关后玩家未被冻住")

	# 8. 能力奖励音符（配了 `奖励能力` 才有的那一枚）
	await _check_ability_note()


# ──────────────────────────── 能力奖励音符 ────────────────────────────


func _check_ability_note() -> void:
	# 编辑器保存场景时会把没填过的导出写成 `= null`（本项目老毛病，实测 MusicGame.tscn 里就出现了）。
	# 那会让 `奖励能力 == ""` 漏过去、拼 `"has_" + null` 当场报错 —— 场景里没配这个值的
	# 实例（第一个 MusicGame）一通关就中招。这里钉住"null 必须被收口成空串"。
	var probe := MUSIC_GAME_SCENE.instantiate()
	probe.set("奖励能力", null)
	_check(probe.奖励能力 == "", "奖励能力 被写成 null 时自动收口成空串（编辑器 `= null` 残留）")
	_check(probe._make_ability_reward(Vector2.ZERO) == null, "没配能力时不生成能力音符")
	probe.free()

	var notes := _ability_notes()
	_check(notes.size() == 1, "通关额外汇出一枚能力音符（实际 %d 枚）" % notes.size())
	if notes.is_empty():
		return
	var note = notes[0]
	var visual := note.get_node("Visual") as Sprite2D
	_check(visual.scale.is_equal_approx(Vector2(0.6, 0.6)),
		"能力音符是普通音符的 2 倍大（scale=%s）" % visual.scale)
	var body_shape := note.get_node("CollisionShape2D").shape as CircleShape2D
	_check(is_equal_approx(body_shape.radius, 36.0),
		"它的碰撞圆跟着放大（半径 %.0f —— 不放大就会插进地面）" % body_shape.radius)
	var halo := note.get_node_or_null("Halo") as Sprite2D
	_check(halo != null and halo.texture != null, "有白色光晕，且光晕贴图加载成功")
	var material := visual.material as ShaderMaterial
	_check(material != null and material.shader != null, "音符挂着彩虹 shader")

	# 彩虹 / 扫光 / 呼吸必须真的在动。headless 断言不到画面，只能断言参数在逐帧变。
	var hue_before := float(material.get_shader_parameter("target_hue"))
	var sweep_before := float(material.get_shader_parameter("sweep"))
	var halo_before: float = halo.modulate.a if halo != null else 0.0
	await get_tree().create_timer(0.12).timeout
	var hue_after := float(material.get_shader_parameter("target_hue"))
	var sweep_after := float(material.get_shader_parameter("sweep"))
	_check(not is_equal_approx(hue_before, hue_after),
		"色相一直在变（彩虹 %.3f → %.3f）" % [hue_before, hue_after])
	_check(not is_equal_approx(sweep_before, sweep_after),
		"扫光一直在走（像谱台 %.3f → %.3f）" % [sweep_before, sweep_after])
	_check(halo == null or not is_equal_approx(halo_before, halo.modulate.a),
		"白色光晕在呼吸（modulate.a 在变）")

	# 8b. 漏抢补发：再立一个"已通关"的实例，它应当补一枚**悬停**的（不再抛出去）
	var respawn := MUSIC_GAME_SCENE.instantiate()
	respawn.触发ID = TRIGGER_ID          # 同一个 ID = 已通关
	respawn.奖励能力 = "double_jump"
	respawn.position = Vector2(0, 180)
	add_child(respawn)
	await _settle()
	var after := _ability_notes()
	_check(after.size() == 2, "已通关的实例会补发一枚（能力不会永久漏掉），现在共 %d 枚" % after.size())
	if after.size() > 1:
		var hovered = after[after.size() - 1]
		_check(not bool(hovered.get("_launched")), "补发的那枚是原地悬停的（不会被抛走）")
		var hover_y: float = hovered.global_position.y
		await get_tree().create_timer(0.6).timeout
		_check(absf(hovered.global_position.y - hover_y) < 2.0, "悬停的那枚不会往下掉")
		hovered.queue_free()
	respawn.queue_free()
	await _settle()

	# 8c. 捡起来 -> 二段跳「踏音而行」+ 能力获取过场
	_check(not GameState.has_double_jump, "捡之前没有二段跳")
	note._on_body_entered(_player)
	await _settle()
	_check(GameState.has_double_jump, "捡到能力音符 → 获得二段跳（存档标志已置位）")
	_check(_player.has_double_jump and _player.air_jumps == 1,
		"玩家身上立刻生效（air_jumps=%d）" % _player.air_jumps)
	var cutscene := get_tree().get_first_node_in_group("ability_cutscene")
	_check(cutscene != null, "播了能力获取过场动画")
	_check(get_tree().paused, "过场期间游戏暂停")
	if cutscene != null:
		cutscene.queue_free()
	await get_tree().process_frame
	get_tree().paused = false
	await _settle()
	_check(not is_instance_valid(note), "捡走后音符消失")

	# 已经拿到了 -> 再进关卡也不该生成（跟 DoubleJumpPickup 一个意思）
	var respawn2 := MUSIC_GAME_SCENE.instantiate()
	respawn2.触发ID = TRIGGER_ID
	respawn2.奖励能力 = "double_jump"
	respawn2.position = Vector2(0, 180)
	add_child(respawn2)
	await _settle()
	_check(_ability_notes().is_empty(), "已经拿到能力后就不再生成能力音符")
	respawn2.queue_free()
	await _settle()


# ──────────────────────────── 对照与工具 ────────────────────────────


func _baseline_melee_check() -> void:
	## 用一个最小的假敌人（CharacterBody2D + 只记次数的 take_damage）验证
	## "玩家的近战挥砍能打中 layer 3 的敌人"。它跟史莱姆无关；这条不过就说明近战本身坏了。
	var dummy_script := GDScript.new()
	dummy_script.source_code = "extends CharacterBody2D\nvar hits: int = 0\nvar contact_damage: int = 0\n\nfunc take_damage(_amount: int, _from_pos: Vector2, _from_magic := false) -> void:\n\thits += 1\n"
	dummy_script.reload()

	var dummy := CharacterBody2D.new()
	dummy.set_script(dummy_script)
	dummy.collision_layer = 4
	dummy.collision_mask = 0
	dummy.add_to_group("enemies")
	var dummy_shape := CollisionShape2D.new()
	var dummy_rect := RectangleShape2D.new()
	dummy_rect.size = Vector2(90.0, 100.0)
	dummy_shape.shape = dummy_rect
	dummy.add_child(dummy_shape)
	add_child(dummy)
	dummy.global_position = Vector2(-70.0, 165.0)

	var probe_player := PLAYER_SCENE.instantiate()
	probe_player.position = Vector2(-70.0, 165.0)
	add_child(probe_player)
	probe_player.facing = 1.0
	probe_player.melee_hitbox.position.x = 24.0

	var elapsed := 0.0
	var overlaps := 0
	await _wait_on_floor(probe_player)
	Input.action_press("attack")
	while elapsed < 3.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		if probe_player.melee_hitbox.monitoring:
			overlaps = maxi(overlaps, probe_player.melee_hitbox.get_overlapping_bodies().size())
		if int(dummy.get("hits")) > 0:
			break
	Input.action_release("attack")

	var hits: int = int(dummy.get("hits"))
	print("[基线] 假敌人被真实挥砍命中=%d 次，命中盒最大重叠=%d" % [hits, overlaps])
	_check(hits > 0, "基线：玩家的近战挥砍能打中 layer 3 的普通敌人")

	dummy.queue_free()
	probe_player.queue_free()
	await get_tree().physics_frame


func _real_attack_on(slot: int) -> Dictionary:
	## 把玩家挪到该史莱姆左侧、面向它，模拟一次真实攻击（按住 attack 键不放），轮询等进度推进。
	## ⚠️ 不能"按下后等固定帧数再松开"：无头模式 process 帧 ≠ 物理帧，玩家在 _physics_process
	## 消费输入，按 2 帧就松会正好错开（agent.md §5 第 8 条）。
	var slime := _slime(slot)
	_player.global_position = slime.global_position + Vector2(-70.0, 0.0)
	_player.velocity = Vector2.ZERO
	_player.facing = 1.0
	_player.melee_hitbox.position.x = 24.0
	var before: int = _game._progress
	var max_overlaps := 0
	var hits_seen := [0]
	var counter := func(_from: Vector2) -> void: hits_seen[0] += 1
	slime.被击中.connect(counter)

	await _wait_on_floor(_player)
	# 传送（直接改 global_position）之后补一次"真实移动"：玩家在真实游戏里是走过去而不是瞬移的，
	# 而瞬移不一定会把子节点 Area2D 的物理变换同步给服务器 —— 实测传送后命中盒的重叠表是空的。
	Input.action_press("move_right")
	for i in 3:
		await get_tree().physics_frame
	Input.action_release("move_right")
	Input.action_press("attack")
	var elapsed := 0.0
	var monitoring_seen := false
	while elapsed < 3.0:
		# ⚠️ get_overlapping_bodies() 要在物理处理期间读才准（process 帧读会拿到空结果）
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		if _player.melee_hitbox.monitoring:
			monitoring_seen = true
			max_overlaps = maxi(max_overlaps, _player.melee_hitbox.get_overlapping_bodies().size())
		if _game._progress != before:
			break
	Input.action_release("attack")
	slime.被击中.disconnect(counter)

	return {
		"推进": _game._progress > before,
		"状态": _state(),
		"进度": "%d→%d" % [before, _game._progress],
		"命中盒最大重叠": max_overlaps,
		"史莱姆收到被击中": hits_seen[0],
		"监控见过true": monitoring_seen,
	}


func _wait_on_floor(body: CharacterBody2D) -> void:
	var settle := 0.0
	while not body.is_on_floor() and settle < 2.0:
		await get_tree().physics_frame
		settle += 1.0 / 60.0


func _count_slimes_outside_camera() -> int:
	## 有几只史莱姆不在镜头里。史莱姆的视觉在根节点上方约 80px、
	## 左右各约 50px，所以按这个小方框判断（不是只看根节点位置）。
	var cam := _player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return 999
	var half := get_viewport().get_visible_rect().size * 0.5 / cam.zoom
	var outside := 0
	for i in _game.get_node("Slimes").get_child_count():
		var rel: Vector2 = _slime(i).global_position - cam.global_position
		if rel.x - 50.0 < -half.x or rel.x + 50.0 > half.x 				or rel.y - 80.0 < -half.y or rel.y > half.y:
			outside += 1
	return outside


func _player_in_camera_view() -> bool:
	## 玩家是否落在镜头视野内。视口尺寸按实际值算（headless 下视口尺寸不稳定，别硬编码）。
	var cam := _player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return false
	var half := get_viewport().get_visible_rect().size * 0.5 / cam.zoom
	var rel := _player.global_position - cam.global_position
	return absf(rel.x) <= half.x and absf(rel.y) <= half.y


func _check_wall_blocks_pickup() -> void:
	## 在测试场地里立一堵墙，朝它扔一个音符：必须被挡住（证明真的走了物理碰撞）。
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(40.0, 600.0)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	add_child(wall)
	wall.global_position = Vector2(1400.0, -100.0)   # 立在地面上（地面顶面 y=180）

	var probe := NOTE_PICKUP_SCENE.instantiate()
	probe.显示提示 = false
	add_child(probe)
	probe.global_position = Vector2(1150.0, 100.0)
	probe.setup_launch(1, Vector2(900.0, -260.0))    # 朝右上方扔，正对那堵墙

	var t := 0.0
	while t < 5.0 and not probe.is_on_floor():
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_check(probe.global_position.x < 1372.0,
		"音符被墙挡住、没有穿墙（x=%.0f，墙左面 1380）" % probe.global_position.x)
	_check(probe.is_on_floor(), "撞墙后仍会沿墙滑下来落到地面")

	probe.queue_free()
	wall.queue_free()
	await get_tree().physics_frame


func _reward_pickups() -> Array:
	## 通关奖励的拾取物被挂在小游戏节点的父级（关卡层），跟 EnemyDrop 的做法一致。
	## ⚠️ 能力音符是 NotePickup 的子类（同样有 setup_launch / _on_body_entered），
	##    不排掉的话它会被算进"撒了 REWARD 个"里，这条断言就废了。
	var out := []
	for child in get_children():
		if child.has_method("setup_launch") and child.has_method("_on_body_entered") \
				and not child.has_method("是能力奖励"):
			out.append(child)
	return out


func _ability_notes() -> Array:
	## 能力奖励音符（同样是本级的子节点）。
	var out := []
	for child in get_children():
		if child.has_method("是能力奖励"):
			out.append(child)
	return out


func _count_reward_pickups() -> int:
	return _reward_pickups().size()


func _pause_pickups(paused: bool) -> void:
	## 只给截图取景用：临时关掉所有拾取物的检测，免得挪玩家过去拍照时顺手捡了东西。
	for node in _reward_pickups() + _ability_notes():
		var area := node.get_node_or_null("PickupArea") as Area2D
		if area != null:
			area.set_deferred("monitoring", not paused)


func _add_floor() -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4000, 40)
	shape.shape = rect
	body.add_child(shape)
	body.position = Vector2(0, 200)
	add_child(body)


func _state() -> int:
	return int(_game._state)


func _slime(slot: int) -> Node2D:
	return _game.get_node("Slimes").get_child(slot) as Node2D


func _hit(slot: int) -> void:
	## 走真实链路：史莱姆 take_damage → 被击中信号 → 控制器仲裁。
	_slime(slot).take_damage(1, _player.global_position)


func _settle() -> void:
	## 等两帧：让 deferred 的命中仲裁跑完。
	await get_tree().physics_frame
	await get_tree().physics_frame


func _wait_for_state(target: int, timeout: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if _state() == target:
			return true
		await get_tree().process_frame
		elapsed += maxf(get_process_delta_time(), 0.0)
	return _state() == target


func _restore_save() -> void:
	if _had_save:
		var r := FileAccess.open("user://save.json", FileAccess.WRITE)
		r.store_string(_backup)
		r.close()
	else:
		var dir := DirAccess.open("user://")
		if dir:
			dir.remove("save.json")


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[PASS] " + name)
	else:
		_fail += 1
		print("[FAIL] " + name)
