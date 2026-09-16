extends SceneTree
## Day 6：曲谱系统最小自动化测试（headless）。
## 运行：godot --headless --path . --script res://tests/test_music_sheet.gd
## 覆盖：初始 0/7、收集、去重、存档往返、旧存档兼容、get_sheet_data。

const GameStateScript = preload("res://scripts/game/GameState.gd")

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	# 备份真实存档，测试结束后还原（避免污染用户存档）
	var had_save := FileAccess.file_exists("user://save.json")
	var backup := ""
	if had_save:
		var f := FileAccess.open("user://save.json", FileAccess.READ)
		backup = f.get_as_text()
		f.close()

	var gs = GameStateScript.new()

	# 1. 初始 0/7
	_check(gs.sheet_count() == 0, "初始 0/7")
	_check(gs.has_sheet("mozart_k622") == false, "初始未拥有 mozart_k622")

	# 2. 收集一张
	_check(gs.collect_sheet("mozart_k622") == true, "首次收集返回 true")
	_check(gs.sheet_count() == 1, "收集后 1/7")
	_check(gs.has_sheet("mozart_k622") == true, "收集后 has_sheet 为 true")

	# 3. 重复收集去重
	_check(gs.collect_sheet("mozart_k622") == false, "重复收集返回 false")
	_check(gs.sheet_count() == 1, "重复后仍 1/7")

	# 4-6. 存档往返
	gs.save_game()
	var gs2 = GameStateScript.new()
	_check(gs2.load_game() == true, "读取存档成功")
	_check(gs2.sheet_count() == 1, "读档后仍 1/7")
	_check(gs2.has_sheet("mozart_k622") == true, "读档后 has_sheet 为 true")

	# 7. get_sheet_data
	var d := gs.get_sheet_data("mozart_k622")
	_check(d.get("title", "") == "A大调单簧管协奏曲 K.622", "title 正确")
	_check(d.get("composer", "") == "莫扎特", "composer 正确")
	_check(d.get("map_id", "") == "school", "map_id 正确")

	# 8. 不存在的 id 不崩溃
	var miss := gs.get_sheet_data("not_exist")
	_check(miss.is_empty(), "不存在 id 返回空字典")
	_check(gs.collect_sheet("not_exist") == false, "不存在 id 收集返回 false")

	# 17. 旧存档兼容（无 music_sheets 字段）
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	var gs3 = GameStateScript.new()
	_check(gs3.load_game() == true, "旧存档（空对象）可读取")
	_check(gs3.sheet_count() == 0, "旧存档曲谱自动初始化为 0")

	# 还原真实存档
	if had_save:
		var r := FileAccess.open("user://save.json", FileAccess.WRITE)
		r.store_string(backup)
		r.close()
	else:
		var dir := DirAccess.open("user://")
		if dir:
			dir.remove("save.json")

	print("\n===== 曲谱测试结果：通过 %d / 失败 %d =====" % [_pass, _fail])

	# 释放测试实例，避免退出时残留警告
	gs.free()
	gs2.free()
	gs3.free()

	quit(0 if _fail == 0 else 1)


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[PASS] " + name)
	else:
		_fail += 1
		print("[FAIL] " + name)
