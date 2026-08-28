extends CanvasLayer
## HUD：右上 HP 红条 + 音乐灵感白条，左上音符计数，左下能力提示，底部存档 toast，顶部 Boss 条。
## 所有 UI 节点都在 HUD.tscn 里可视化摆放，本脚本只负责更新数值。

@onready var hp_bar: ProgressBar = $Control/HpBar
@onready var music_bar: ProgressBar = $Control/MusicBar
@onready var notes_label: Label = $Control/NotesLabel
@onready var collect_label: Label = get_node_or_null("Control/CollectLabel")
@onready var sheet_label: Label = get_node_or_null("Control/SheetLabel")
@onready var ability_label: Label = get_node_or_null("Control/AbilityLabel")
@onready var save_toast: Label = $Control/SaveToast
@onready var boss_bar_bg: ColorRect = $Control/BossBarBg
@onready var boss_bar_fill: ColorRect = $Control/BossBarFill
@onready var low_hp_overlay: ColorRect = $Control/LowHpOverlay

var _low_hp_tween: Tween = null


func _ready() -> void:
	add_to_group("hud")
	hp_bar.max_value = GameState.MAX_HP
	hp_bar.value = GameState.hp
	music_bar.max_value = GameState.MAX_MUSIC_INSPIRATION
	music_bar.value = GameState.music_inspiration
	notes_label.text = str(GameState.notes)
	set_collect_count(GameState.collected_ids.size(), GameState.COLLECT_TOTAL)
	set_sheet_count(GameState.sheet_count(), GameState.SHEET_TOTAL)
	refresh_abilities()
	GameState.game_saved.connect(_on_game_saved)
	GameState.sheet_collected.connect(_on_sheet_collected)
	GameState.notes_changed.connect(_on_notes_changed)
	GameState.music_inspiration_changed.connect(_on_music_inspiration_changed)
	call_deferred("_connect_player")
	call_deferred("_connect_boss")


func _connect_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player:
		player.health_changed.connect(_on_health_changed)
		_on_health_changed(player.hp, player.max_hp)


func _connect_boss() -> void:
	var boss := get_tree().get_first_node_in_group("boss")
	if boss and boss.has_signal("health_changed"):
		boss.health_changed.connect(_on_boss_health_changed)
		_on_boss_health_changed(boss.hp, boss.max_hp)


func set_collect_count(current: int, total: int) -> void:
	if collect_label:
		collect_label.text = "收集 %d/%d" % [current, total]


func set_sheet_count(current: int, total: int) -> void:
	if sheet_label:
		sheet_label.text = "曲谱 %d/%d" % [current, total]


func refresh_abilities() -> void:
	var text := "能力：冲刺·近战·魔法"
	if GameState.has_double_jump:
		text += "  二段跳"
	if GameState.has_magic_dash:
		text += "  魔法冲刺"
	if GameState.has_magic_climb:
		text += "  魔法攀升"
	if GameState.has_magic_flight:
		text += "  魔法飞行"
	if ability_label:
		ability_label.text = text


func show_note_toast(amount: int) -> void:
	_show_toast("音符 +%d" % amount)


func _on_notes_changed(total: int) -> void:
	notes_label.text = str(total)


func _on_health_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current
	_update_low_hp_effect(current)


func _on_music_inspiration_changed(current: int, maximum: int) -> void:
	music_bar.max_value = maximum
	music_bar.value = current


func _update_low_hp_effect(current: int) -> void:
	if current <= 1:
		low_hp_overlay.visible = true
		if _low_hp_tween == null or not _low_hp_tween.is_valid():
			_low_hp_tween = create_tween()
			_low_hp_tween.set_loops()
			_low_hp_tween.tween_property(low_hp_overlay, "modulate:a", 0.3, 0.5)
			_low_hp_tween.tween_property(low_hp_overlay, "modulate:a", 0.08, 0.5)
	else:
		if _low_hp_tween and _low_hp_tween.is_valid():
			_low_hp_tween.kill()
		low_hp_overlay.visible = false


func _on_sheet_collected(sheet_id: String) -> void:
	set_sheet_count(GameState.sheet_count(), GameState.SHEET_TOTAL)
	var data := GameState.get_sheet_data(sheet_id)
	var title: String = data.get("title", sheet_id)
	_show_toast("获得曲谱：《%s》" % title)


func _on_game_saved() -> void:
	_show_toast("已保存 ✓")


func _show_toast(text: String) -> void:
	save_toast.text = text
	save_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(save_toast, "modulate:a", 0.0, 0.4)


func _on_boss_health_changed(current: int, maximum: int) -> void:
	if current <= 0:
		boss_bar_bg.hide()
		boss_bar_fill.hide()
		return
	boss_bar_bg.show()
	boss_bar_fill.show()
	var ratio: float = float(current) / float(maximum)
	boss_bar_fill.offset_right = -198.0 + 396.0 * ratio
