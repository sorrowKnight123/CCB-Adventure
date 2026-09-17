class_name MusicNotes
extends RefCounted
## 8 个钢琴音的统一表：音名 → 音频 + 颜色 + 染色亮度。
##
## 颜色按音阶位置固定为彩虹：
##   C4 红 / D4 橙 / E4 黄 / F4 绿 / G4 青 / A4 蓝 / B4 紫 / C5 银白
## 史莱姆染色与飘出的音符特效都从这里取色 —— 改配色只需改这一处。
##
## 音频文件按 `音名.wav` 命名，全部在同一个目录下（8 个音长度一致，都是 1.5093s）。
##
## ⚠️ 增删/重排音名时，下面两处要同步（都按本表的顺序）：
##    ① `scripts/minigame/MusicSlime.gd` 的 `@export_enum` 音名列表
##    ② `tests/test_music_notes.gd` 的断言
##    跑 `godot --headless --path . --script res://tests/test_music_notes.gd` 可以验出来。

const AUDIO_DIR: String = "res://audio/enemy/effect/piano_notes_C4-C5/"

const NOTES: Array[Dictionary] = [
	{"name": "C4", "color": Color(0.93, 0.22, 0.24), "value_scale": 1.05},
	{"name": "D4", "color": Color(0.96, 0.53, 0.16), "value_scale": 1.05},
	{"name": "E4", "color": Color(0.97, 0.86, 0.22), "value_scale": 1.05},
	{"name": "F4", "color": Color(0.38, 0.86, 0.34), "value_scale": 1.05},
	{"name": "G4", "color": Color(0.24, 0.83, 0.82), "value_scale": 1.05},
	{"name": "A4", "color": Color(0.30, 0.54, 0.96), "value_scale": 1.05},
	{"name": "B4", "color": Color(0.65, 0.38, 0.94), "value_scale": 1.05},
	# 高八度 C：银白。饱和度接近 0，靠 value_scale 提亮成"银"而不是灰。
	{"name": "C5", "color": Color(0.94, 0.96, 1.00), "value_scale": 1.70},
]


## 全部音名（顺序即彩虹顺序）。
static func names() -> Array[String]:
	var out: Array[String] = []
	for entry in NOTES:
		out.append(str(entry["name"]))
	return out


static func has(note_name: String) -> bool:
	return _index_of(note_name) >= 0


static func get_audio_path(note_name: String) -> String:
	return AUDIO_DIR + note_name + ".wav"


## 音频流。音名非法时返回 null（调用方自行判空）。
static func get_stream(note_name: String) -> AudioStream:
	if not has(note_name):
		return null
	return load(get_audio_path(note_name)) as AudioStream


## 该音对应的颜色。音名非法时返回白色。
static func get_color(note_name: String) -> Color:
	var i := _index_of(note_name)
	return NOTES[i]["color"] if i >= 0 else Color.WHITE


## 史莱姆染色时的亮度倍数（银白的高八度 C 需要提亮）。
static func get_value_scale(note_name: String) -> float:
	var i := _index_of(note_name)
	return float(NOTES[i]["value_scale"]) if i >= 0 else 1.0


static func _index_of(note_name: String) -> int:
	for i in NOTES.size():
		if str(NOTES[i]["name"]) == note_name:
			return i
	return -1
