extends SceneTree
## 音乐小游戏数据层自检（headless）。
## 运行：godot --headless --path . --script res://tests/test_music_notes.gd
##
## 覆盖：8 音齐全且顺序正确、颜色是彩虹顺序（红→紫 + 银白的高八度 C）、
##       8 个 wav 文件都存在、非法音名安全回退、MusicGameConfig 的演奏顺序回退、
##       以及 MusicSlime 的 @export_enum 音名列表与 MusicNotes 是否同步。

const MusicNotesScript = preload("res://scripts/game/MusicNotes.gd")
const ConfigScript = preload("res://scripts/minigame/MusicGameConfig.gd")

const EXPECTED_NAMES: Array[String] = ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	var names: Array[String] = MusicNotesScript.names()

	# 1. 音名齐全且顺序正确
	_check(names.size() == 8, "共 8 个音（实际 %d）" % names.size())
	_check(names == EXPECTED_NAMES, "音名顺序 = %s" % str(EXPECTED_NAMES))

	# 2. 颜色是彩虹顺序：C4 红 → B4 紫，高八度 C5 银白
	var hues: Array[float] = []
	for i in names.size():
		hues.append(MusicNotesScript.get_color(names[i]).h)

	var c4 := MusicNotesScript.get_color("C4")
	_check(c4.h > 0.95 or c4.h < 0.05, "C4 是红色（h=%.3f）" % c4.h)
	_check(c4.s > 0.5, "C4 饱和度高（s=%.2f）" % c4.s)

	var d4_to_b4_increasing := true
	for i in range(1, 6):
		if hues[i] >= hues[i + 1]:
			d4_to_b4_increasing = false
	_check(d4_to_b4_increasing, "D4→B4 色相单调递增（橙→黄→绿→青→蓝→紫）")

	var c5 := MusicNotesScript.get_color("C5")
	_check(c5.s <= 0.15, "C5 是银白（s=%.3f 接近 0）" % c5.s)
	_check(c5.s < c4.s, "C5 比 C4 更接近灰白")
	_check(MusicNotesScript.get_value_scale("C5") > MusicNotesScript.get_value_scale("C4"),
		"C5 靠亮度提成银白（value_scale 更高）")

	# 3. 8 个音频文件都存在
	var missing := ""
	for note_name in names:
		if not ResourceLoader.exists(MusicNotesScript.get_audio_path(note_name)):
			missing += note_name + " "
	_check(missing == "", "8 个 wav 都存在（缺失：%s）" % ("无" if missing == "" else missing))
	for note_name in names:
		_check(MusicNotesScript.get_stream(note_name) != null, "%s 能取到音频流" % note_name)

	# 4. 非法音名安全回退
	_check(MusicNotesScript.has("not_a_note") == false, "非法音名 has() = false")
	_check(MusicNotesScript.get_stream("not_a_note") == null, "非法音名 get_stream() = null")
	_check(MusicNotesScript.get_color("not_a_note") == Color.WHITE, "非法音名 get_color() 回退白色")
	_check(MusicNotesScript.get_value_scale("not_a_note") == 1.0, "非法音名 value_scale 回退 1.0")

	# 5. MusicSlime 的 @export_enum 音名列表有没有漏（增删音名时最容易忘的地方）
	var source := FileAccess.get_file_as_string("res://scripts/minigame/MusicSlime.gd")
	var enum_line := ""
	for line in source.split("\n"):
		if line.contains("@export_enum"):
			enum_line = line
			break
	_check(enum_line != "", "MusicSlime.gd 里能找到 @export_enum")
	var enum_missing := ""
	for note_name in names:
		if not enum_line.contains("\"%s\"" % note_name):
			enum_missing += note_name + " "
	_check(enum_missing == "", "MusicSlime 的下拉框含全部音名（缺：%s）"
		% ("无" if enum_missing == "" else enum_missing))

	# 6. MusicGameConfig 的顺序表：0 = 停顿（空音），1..N = 第 N 只史莱姆
	var config = ConfigScript.new()
	_check(config.演示序列(5) == PackedInt32Array([0, 1, 2, 3, 4]), "演奏顺序留空 = 从左到右")
	_check(config.演示序列(0).is_empty(), "没有槽位时演示序列为空")
	config.演奏顺序 = PackedInt32Array([1, 0, 3])
	_check(config.演示序列(3) == PackedInt32Array([0, -1, 2]),
		"[1,0,3] → 演示序列 = 第1只、停顿、第3只")
	_check(config.演奏序列(3) == PackedInt32Array([0, 2]),
		"演奏序列去掉停顿 = [第1只, 第3只]")
	config.演奏顺序 = PackedInt32Array([0, 0])
	_check(config.演奏序列(3).is_empty(), "整首只有停顿 → 演奏序列为空")
	_check(config.演示序列(3) == PackedInt32Array([-1, -1]), "整首只有停顿 → 演示序列全是停顿")
	config.演奏顺序 = PackedInt32Array([1, 9, -1, 2])
	_check(config.演示序列(3) == PackedInt32Array([0, 1]), "越界/负数编号被丢掉")
	_check(config.通关奖励 > 0, "默认通关奖励为正数")
	_check(config.演示间隔 > 0.0, "默认演示间隔为正数")

	# 7. 在场的示例配置能加载，且演奏序列的编号都合法
	var example = load("res://data/music_game/example_melody.tres")
	_check(example != null, "example_melody.tres 能加载")
	if example != null:
		var answer: PackedInt32Array = example.演奏序列(5)
		_check(answer.size() > 0, "示例配置能出演奏序列")
		var all_valid := true
		for index in answer:
			if index < 0 or index >= 5:
				all_valid = false
		_check(all_valid, "示例配置的演奏序列编号都在 0..4 内")
		_check(example.演示序列(5).size() >= answer.size(),
			"演示序列长度 ≥ 演奏序列长度（多出来的是停顿）")

	# MusicGameConfig 是 Resource(RefCounted)，引用计数自动回收，不能手动 free()。

	print("\n===== 音乐小游戏数据自检结果：通过 %d / 失败 %d =====" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[PASS] " + name)
	else:
		_fail += 1
		print("[FAIL] " + name)
