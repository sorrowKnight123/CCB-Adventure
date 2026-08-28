extends CanvasLayer
## Day 5：暂停菜单 + 背包/能力面板。
## Esc（ui_cancel）切换暂停；Tab（inventory）切换背包/能力面板。
## process_mode = ALWAYS，暂停时仍响应输入。


var _pause_panel: Control
var _inventory_panel: Control
var _collect_label: Label
var _collect_list: Label
var _ability_label: Label

var _cheat_double_jump: CheckBox
var _cheat_magic_dash: CheckBox
var _cheat_magic_climb: CheckBox
var _cheat_magic_flight: CheckBox
var _heal_tier_option: OptionButton


func _ready() -> void:
	add_to_group("pause_menu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pause_panel()
	_build_inventory_panel()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Day 7 地图互斥：全屏地图开着时 Esc 只关地图，不误开暂停。
		# 同帧内 _input 先于 _process 执行，所以此时地图仍处于打开状态。
		if _is_map_open():
			return
		_toggle_pause()
	elif event.is_action_pressed("inventory") and not get_tree().paused:
		_toggle_inventory()


func _is_map_open() -> bool:
	var map := get_tree().get_first_node_in_group("map_screen")
	return map != null and map.is_open()


func _toggle_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_pause_panel.visible = paused
	if paused:
		_inventory_panel.visible = false
		_refresh_cheat_toggles()
		_refresh_inventory()


func _toggle_inventory() -> void:
	_inventory_panel.visible = not _inventory_panel.visible
	if _inventory_panel.visible:
		_refresh_inventory()


func _build_pause_panel() -> void:
	_pause_panel = Control.new()
	_pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false
	add_child(_pause_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_panel.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)

	var title := Label.new()
	title.text = "已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	box.add_child(title)

	var cheat_title := Label.new()
	cheat_title.text = "作弊栏（开发用）"
	cheat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cheat_title.add_theme_font_size_override("font_size", 20)
	cheat_title.add_theme_color_override("font_color", Color(1, 0.6, 0.6, 1))
	box.add_child(cheat_title)

	var cheat_box := VBoxContainer.new()
	cheat_box.add_theme_constant_override("separation", 4)
	box.add_child(cheat_box)

	_cheat_double_jump = _make_cheat_toggle("二段跳", _on_cheat_double_jump, GameState.has_double_jump)
	_cheat_magic_dash = _make_cheat_toggle("魔法冲刺", _on_cheat_magic_dash, GameState.has_magic_dash)
	_cheat_magic_climb = _make_cheat_toggle("魔法攀升", _on_cheat_magic_climb, GameState.has_magic_climb)
	_cheat_magic_flight = _make_cheat_toggle("魔法飞行", _on_cheat_magic_flight, GameState.has_magic_flight)
	cheat_box.add_child(_cheat_double_jump)
	cheat_box.add_child(_cheat_magic_dash)
	cheat_box.add_child(_cheat_magic_climb)
	cheat_box.add_child(_cheat_magic_flight)

	var heal_row := HBoxContainer.new()
	heal_row.add_theme_constant_override("separation", 8)
	var heal_label := Label.new()
	heal_label.text = "回血旋律"
	heal_label.add_theme_font_size_override("font_size", 18)
	heal_label.add_theme_color_override("font_color", Color(1, 1, 1))
	heal_row.add_child(heal_label)
	_heal_tier_option = OptionButton.new()
	_heal_tier_option.add_theme_font_size_override("font_size", 18)
	for cfg in GameState.HEAL_TIERS:
		_heal_tier_option.add_item(str(cfg["name"]))
	_heal_tier_option.item_selected.connect(_on_heal_tier_changed)
	heal_row.add_child(_heal_tier_option)
	cheat_box.add_child(heal_row)

	box.add_child(_make_button("继续", _on_resume))
	box.add_child(_make_button("重新开始", _on_restart))
	box.add_child(_make_button("回到主界面", _on_main_menu))


func _build_inventory_panel() -> void:
	_inventory_panel = Control.new()
	_inventory_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inventory_panel.visible = false
	add_child(_inventory_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inventory_panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inventory_panel.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "收集品 / 能力"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
	box.add_child(title)

	_collect_label = Label.new()
	_collect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_collect_label.add_theme_font_size_override("font_size", 22)
	_collect_label.add_theme_color_override("font_color", Color(1, 1, 1))
	box.add_child(_collect_label)

	_collect_list = Label.new()
	_collect_list.add_theme_font_size_override("font_size", 20)
	_collect_list.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_collect_list.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_collect_list.add_theme_constant_override("outline_size", 4)
	box.add_child(_collect_list)

	_ability_label = Label.new()
	_ability_label.add_theme_font_size_override("font_size", 20)
	_ability_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1, 1))
	box.add_child(_ability_label)

	var hint := Label.new()
	hint.text = "按 Tab 关闭"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	box.add_child(hint)


func _make_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(260, 56)
	btn.add_theme_font_size_override("font_size", 26)
	btn.pressed.connect(callback)
	return btn


func _make_cheat_toggle(text: String, callback: Callable, initial: bool) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = initial
	cb.add_theme_font_size_override("font_size", 18)
	cb.add_theme_color_override("font_color", Color(1, 1, 1))
	cb.toggled.connect(callback)
	return cb


func _refresh_cheat_toggles() -> void:
	_cheat_double_jump.button_pressed = GameState.has_double_jump
	_cheat_magic_dash.button_pressed = GameState.has_magic_dash
	_cheat_magic_climb.button_pressed = GameState.has_magic_climb
	_cheat_magic_flight.button_pressed = GameState.has_magic_flight
	_heal_tier_option.select(clamp(GameState.heal_tier, 0, GameState.HEAL_TIERS.size() - 1))


func _on_heal_tier_changed(idx: int) -> void:
	GameState.heal_tier = clamp(idx, 0, GameState.HEAL_TIERS.size() - 1)


func _on_cheat_double_jump(v: bool) -> void:
	GameState.has_double_jump = v
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player:
		player.has_double_jump = v
		player.air_jumps = 1 if v else 0
	_refresh_hud_abilities()


func _on_cheat_magic_dash(v: bool) -> void:
	GameState.has_magic_dash = v
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player:
		player.has_magic_dash = v
	_refresh_hud_abilities()


func _on_cheat_magic_climb(v: bool) -> void:
	GameState.has_magic_climb = v
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player:
		player.has_magic_climb = v
	_refresh_hud_abilities()


func _on_cheat_magic_flight(v: bool) -> void:
	GameState.has_magic_flight = v
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player:
		player.has_magic_flight = v
	_refresh_hud_abilities()


func _refresh_hud_abilities() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("refresh_abilities"):
		hud.refresh_abilities()


func _refresh_inventory() -> void:
	_collect_label.text = "收集 %d/%d" % [GameState.collected_ids.size(), GameState.COLLECT_TOTAL]
	var lines := ""
	for id in GameState.COLLECTIBLES:
		var title: String = GameState.COLLECTIBLES[id]
		lines += ("✓ " if GameState.has_collectible(id) else "? ") + title + "\n"
	_collect_list.text = lines
	var ab := "能力：冲刺·近战·魔法"
	if GameState.has_double_jump:
		ab += "  ✓二段跳"
	if GameState.has_magic_dash:
		ab += "  ✓魔法冲刺"
	if GameState.has_magic_climb:
		ab += "  ✓魔法攀升"
	if GameState.has_magic_flight:
		ab += "  ✓魔法飞行"
	_ability_label.text = ab


func _on_resume() -> void:
	get_tree().paused = false
	_pause_panel.visible = false


func _on_restart() -> void:
	get_tree().paused = false
	GameState.reset()
	Transition.fade_to(GameState.START_SCENE)


func _on_main_menu() -> void:
	get_tree().paused = false
	GameState.save_game()
	Transition.fade_to("res://scenes/ui/title.tscn")
