extends Node
## 能力获取过场动画测试：
## 1) AbilityCutscene.tscn 结构完整（图标/获得能力/能力名/介绍小字/继续提示 + show_ability/fade_out 动画）。
## 2) 作弊保护：暂停状态下 grant_* 不触发过场；正常状态下触发。
## 3) 触发后：游戏暂停、能力名正确（新名）、介绍小字正确、无图标时 texture 为 null 占位、动画播放。
## 4) 继续提示晚约 3 秒才淡入：期间按 ui_accept 不退出；淡入后按 ui_accept → fade_out → 恢复 + finished + 释放。
## 注意：headless 帧率不稳定，一律用真实时钟轮询等待（不数帧）。

const CUTSCENE_SCENE: PackedScene = preload("res://ui/AbilityCutscene.tscn")

var _checks: int = 0
var _failures: int = 0
var _finished_seen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	await get_tree().process_frame

	# ---- 1) 场景结构 ----
	var cs: CanvasLayer = CUTSCENE_SCENE.instantiate()
	_check(cs != null, "AbilityCutscene.tscn 可实例化")
	add_child(cs)
	var anim: AnimationPlayer = cs.get_node("AnimationPlayer") as AnimationPlayer
	_check(anim != null, "AnimationPlayer 存在")
	_check(anim.has_animation("show_ability") and anim.has_animation("fade_out"), "show_ability / fade_out 动画存在")
	_check(cs.get_node("Background") is ColorRect, "Background 遮罩存在")
	_check(cs.get_node("CenterContainer/VBoxContainer/Icon") is TextureRect, "Icon 图标位存在")
	_check(cs.get_node("CenterContainer/VBoxContainer/TitleLabel") is Label, "TitleLabel 存在")
	_check(cs.get_node("CenterContainer/VBoxContainer/NameLabel") is Label, "NameLabel 存在")
	_check(cs.get_node("CenterContainer/VBoxContainer/DescLabel") is Label, "DescLabel 介绍小字存在")
	_check(cs.get_node("ContinueLabel") is Label, "ContinueLabel 存在")
	cs.queue_free()
	await get_tree().process_frame

	# ---- 2) 作弊保护：暂停状态下 grant 不触发过场 ----
	get_tree().paused = true
	$Player.grant_double_jump()
	_check(GameState.has_double_jump, "作弊：grant 仍设置 GameState 能力标志")
	_check(get_tree().get_first_node_in_group("ability_cutscene") == null, "作弊：暂停状态下不触发过场")
	get_tree().paused = false
	await get_tree().process_frame

	# ---- 3) 正常拾取触发 ----
	_check(not get_tree().paused, "前置：未暂停")
	$Player.grant_magic_dash()
	_check(GameState.has_magic_dash, "grant_magic_dash 设置 GameState")
	_check(get_tree().paused, "过场激活后游戏暂停")
	var cutscene: Node = get_tree().get_first_node_in_group("ability_cutscene")
	_check(cutscene != null, "过场实例已加入场景（group ability_cutscene）")
	if cutscene:
		var name_label: Label = cutscene.get_node("CenterContainer/VBoxContainer/NameLabel") as Label
		_check(name_label.text == "碎影颤音", "能力名=%s（新名）" % name_label.text)
		var desc_label: Label = cutscene.get_node("CenterContainer/VBoxContainer/DescLabel") as Label
		_check(desc_label.text == "强化冲刺：可穿过魔法屏障", "介绍小字=%s" % desc_label.text)
		var icon: TextureRect = cutscene.get_node("CenterContainer/VBoxContainer/Icon") as TextureRect
		_check(icon.texture == null, "无图标时 texture 为 null（占位）")
		var cs_anim: AnimationPlayer = cutscene.get_node("AnimationPlayer") as AnimationPlayer
		_check(cs_anim.is_playing() and cs_anim.current_animation == "show_ability", "show_ability 正在播放")

		# ---- 4) 阅读期内按 Space 不退出（内容已淡入但继续提示未出现）----
		# 节奏：0-3s 屏幕渐暗 → 3-5s 图标文字一起淡入 → 5-8s 阅读期 → 8s 才出现继续提示
		var content_in: bool = await _wait_until(func() -> bool:
			var n: Label = cutscene.get_node("CenterContainer/VBoxContainer/NameLabel") as Label
			return n.modulate.a >= 0.999, 10.0)
		_check(content_in, "能力名已淡入（内容阶段，3s 渐暗后 2s 淡入）")
		var bg: ColorRect = cutscene.get_node("Background") as ColorRect
		# Color 分量是 float32，0.7 存为 0.69999998…，与 float64 字面量比较需容差
		_check(bg.modulate.a >= 0.69, "背景已渐暗至 0.7（实际 %.3f）" % bg.modulate.a)
		var cont_before: Label = cutscene.get_node("ContinueLabel") as Label
		var early_alpha: float = cont_before.modulate.a
		_check(early_alpha < 0.01, "继续提示尚未淡入（alpha=%.2f）" % early_alpha)
		_send_accept()
		await get_tree().process_frame
		_check(get_tree().paused, "阅读期内按 Space：游戏仍暂停")
		_check(is_instance_valid(cutscene), "阅读期内按 Space：过场未退出")
		_check(cont_before.modulate.a < 0.01, "阅读期内按 Space：继续提示仍未出现")

		# 继续提示在内容淡入完成 3 秒后（约 8s）淡入
		var shown: bool = await _wait_until(func() -> bool:
			var l: Label = cutscene.get_node("ContinueLabel") as Label
			return l.modulate.a >= 0.999, 10.0)
		_check(shown, "继续提示在 3 秒阅读期后淡入完成")
		_check(cont_before.modulate.a >= 0.999, "按下 [Space] 继续 提示可见")

		# ---- 5) 按 ui_accept 继续 ----
		cutscene.finished.connect(func() -> void: _finished_seen = true)
		_send_accept()
		var done: bool = await _wait_until(func() -> bool:
			return not get_tree().paused and get_tree().get_first_node_in_group("ability_cutscene") == null, 8.0)
		_check(done, "fade_out 播完：游戏恢复 + 过场已释放")
		_check(_finished_seen, "finished 信号已发出")
		_check(not get_tree().paused, "游戏未暂停")

	# ---- 6) 悠远的旋律（回血能力）过场 ----
	_check(not GameState.has_heal_tier(0), "初始未获取悠远的旋律（不能回血）")
	$Player.grant_heal_melody()
	_check(GameState.has_heal_melody, "grant_heal_melody 设置 GameState")
	_check(GameState.has_heal_tier(0), "获取后 has_heal_tier(0) 为 true")
	_check(get_tree().paused, "回血能力过场：游戏暂停")
	var cs2: Node = get_tree().get_first_node_in_group("ability_cutscene")
	_check(cs2 != null, "回血能力过场已出现")
	if cs2:
		var nl: Label = cs2.get_node("CenterContainer/VBoxContainer/NameLabel") as Label
		_check(nl.text == "悠远的旋律", "能力名=%s" % nl.text)
		var dl: Label = cs2.get_node("CenterContainer/VBoxContainer/DescLabel") as Label
		_check(dl.text == "回血 1 点，消耗 30 音乐灵感", "介绍小字=%s" % dl.text)
		var ready2: bool = await _wait_until(func() -> bool:
			var l: Label = cs2.get_node("ContinueLabel") as Label
			return l.modulate.a >= 0.999, 10.0)
		_check(ready2, "回血过场：继续提示淡入完成")
		_send_accept()
		var done2: bool = await _wait_until(func() -> bool:
			return not get_tree().paused and get_tree().get_first_node_in_group("ability_cutscene") == null, 8.0)
		_check(done2, "回血能力过场结束：游戏恢复")

	_finish()


func _send_accept() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	Input.parse_input_event(ev)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	# headless 帧率不固定，用真实时钟计时，避免按帧数估算失真
	var start := Time.get_ticks_msec()
	while not cond.call():
		if (Time.get_ticks_msec() - start) / 1000.0 >= timeout_s:
			return false
		await get_tree().process_frame
	return true


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[PASS] %s" % what)
	else:
		_failures += 1
		print("[FAIL] %s" % what)


func _finish() -> void:
	print("AbilityCutscene test: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
