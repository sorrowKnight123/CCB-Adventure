extends Node2D
## 能力奖励模板的自检（headless，场景模式 —— `--script` 不加载 autoload）。
## 运行：godot --headless --path . res://tests/test_ability_reward.tscn --quit-after 8000
##
## 「掉落彩虹音符 → 拾取 → 获得能力」是发能力的统一模板（`AbilityNote.掉落()`）。
## 小游戏那条链子由 test_music_game.gd 覆盖，这里补上**模板本身**和 **Boss 那边**：
##   模板 —— 没给 id / 已经拥有 -> 不生成；给了就生成，且 能力 / 位置 / 不弹提示 都对
##   抛出 —— 有初速度走抛落物理；没有则原地悬停（漏捡补发靠这个）
##   Boss —— 战胜时爆一枚 magic_flight（华彩终章）的音符；已拥有不再掉；
##           重进关卡（已战胜但没拿到能力）会补发一枚悬停的
##
## 会写真实存档，所以开头备份、结尾还原（跟 test_hidden_room.gd 一样）。

const BOSS_SCENE: PackedScene = preload("res://scenes/enemies/boss/MossResonanceBoss.tscn")
const BOSS_ID := "moss_resonance_boss"

var _pass: int = 0
var _fail: int = 0
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
	print("\n===== 能力奖励模板自检结果：通过 %d / 失败 %d =====" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _run() -> void:
	GameState.reset()
	await get_tree().process_frame
	await _check_template()
	await _check_boss()


func _check_template() -> void:
	var holder := Node2D.new()
	add_child(holder)
	await _settle()

	_check(AbilityNote.掉落(holder, Vector2.ZERO, "") == null, "模板：没给能力 id 什么都不生成")
	_check(AbilityNote.掉落(holder, Vector2.ZERO, "double_jump") != null, "模板：给了 id 生成一枚")
	_check(holder.get_child_count() == 1, "模板：挂在调用方给的父节点下（实际 %d 个）" % holder.get_child_count())
	var note := holder.get_child(0) as AbilityNote
	_check(note.能力 == "double_jump", "模板：能力 id 写进了音符（%s）" % note.能力)
	_check(note.显示提示 == false, "模板：不弹「+N」提示（看左上角计数就够了）")
	_check(not note._launched, "模板：不给初速度 -> 原地悬停（漏捡补发用）")

	GameState.has_double_jump = true
	_check(AbilityNote.掉落(holder, Vector2.ZERO, "double_jump") == null, "模板：已经拥有该能力就不再生成")
	GameState.has_double_jump = false

	var tossed := AbilityNote.掉落(holder, Vector2(120, 80), "magic_dash", Vector2(0, -300))
	_check(tossed != null, "模板：同一父节点下还能再生成一枚")
	if tossed != null:
		_check(tossed.global_position.is_equal_approx(Vector2(120, 80)),
			"模板：位置按传进来的 origin 摆（实际 %s）" % tossed.global_position)
		_check(tossed._launched, "模板：给了初速度 -> 走抛落物理（撞墙落地交给物理引擎）")

	holder.queue_free()
	await _settle()


func _check_boss() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var boss := BOSS_SCENE.instantiate() as Node2D
	arena.add_child(boss)
	await _settle()

	boss.call("_掉落能力奖励", true)
	await _settle()
	var notes := _ability_notes(arena)
	_check(notes.size() == 1, "Boss：战胜后爆出一枚彩虹音符（实际 %d 枚）" % notes.size())
	if notes.size() == 1:
		_check(notes[0].能力 == "magic_flight", "Boss：这枚音符发的是「华彩终章」（%s）" % notes[0].能力)
		_check(notes[0]._launched, "Boss：是「爆」出来的（带初速度，不是原地摆着）")

	# 已经拿到华彩终章 -> 不再掉（不然会重复发）
	GameState.has_magic_flight = true
	boss.call("_掉落能力奖励", true)
	await _settle()
	_check(_ability_notes(arena).size() == 1, "Boss：已经拥有华彩终章时不再掉")
	GameState.has_magic_flight = false

	# 漏捡补发：重进关卡时 Boss 已被标记战胜、但能力还没拿到 -> 悬停补一枚
	GameState.mark_boss_defeated(BOSS_ID)
	var arena2 := Node2D.new()
	add_child(arena2)
	var boss2 := BOSS_SCENE.instantiate() as Node2D
	arena2.add_child(boss2)
	await _settle()
	var refill := _ability_notes(arena2)
	_check(refill.size() == 1, "Boss：已战胜但没拿到能力 -> 重进关卡补发一枚（实际 %d 枚）" % refill.size())
	if refill.size() == 1:
		_check(not refill[0]._launched, "Boss：补发的是原地悬停的（不会再飞丢）")
		_check(refill[0].能力 == "magic_flight", "Boss：补发的也是华彩终章")

	# 能力已经拿到 -> 重进关卡什么都不补
	GameState.has_magic_flight = true
	var arena3 := Node2D.new()
	add_child(arena3)
	arena3.add_child(BOSS_SCENE.instantiate())
	await _settle()
	_check(_ability_notes(arena3).is_empty(), "Boss：已经拿到能力后重进关卡不补发")


func _ability_notes(parent: Node) -> Array[AbilityNote]:
	var found: Array[AbilityNote] = []
	for child in parent.get_children():
		if child is AbilityNote:
			found.append(child)
	return found


func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


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
