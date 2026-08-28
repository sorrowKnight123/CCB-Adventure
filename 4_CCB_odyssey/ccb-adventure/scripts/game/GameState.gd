extends Node
## Day 4：全局持久化状态（autoload 单例）。跨场景保存 HP、能力、线索、检查点。
## Day 5：新增磁盘存档（user://save.json）、第二能力（魔法冲刺）、收集品统一。

const MAX_HP: int = 5
const START_SCENE: String = "res://scenes/levels/main_new.tscn"
const START_SPAWN: String = "start_school"
const START_POSITION: Vector2 = Vector2(186, 523)
const SAVE_PATH: String = "user://save.json"

# 音乐灵感：满条 90，近战有效攻击 +10；魔法攻击消耗 5；不写档，死亡清零。
const MAX_MUSIC_INSPIRATION: int = 90
const MUSIC_INSPIRATION_PER_HIT: int = 10
const MAGIC_INSPIRATION_COST: int = 5

# 回血旋律配置（tier 0/1/2）：消耗灵感、吟唱秒数、回复 HP 量。
const HEAL_TIERS: Array[Dictionary] = [
	{"name": "悠远的旋律", "cost": 30, "chant_time": 2.0, "heal": 1},
	{"name": "抒情的乐章", "cost": 25, "chant_time": 1.5, "heal": 2},
	{"name": "生命的交响", "cost": 20, "chant_time": 1.0, "heal": 3},
]

# Day 6：曲谱目录（数据层，与收集逻辑分离）
const MusicSheetData = preload("res://scripts/game/MusicSheet.gd")

# 收集品登记表：id → 列表标题。COLLECT_TOTAL 由此派生。
const COLLECTIBLES: Dictionary = {
	"clue_village_note": "88的纸条",
	"clue_forest_secret": "88的日记残页",
	"clue_school_high": "88的练琴记录",
	"diary_village": "88的日记·一",
	"diary_forest": "88的日记·二",
	"letter_musichall": "88的信",
}
var COLLECT_TOTAL: int = COLLECTIBLES.size()
var SHEET_TOTAL: int = MusicSheetData.total()

signal game_saved
signal sheet_collected(sheet_id: String)
signal notes_changed(total: int)
signal music_inspiration_changed(current: int, maximum: int)

var hp: int = MAX_HP
var notes: int = 0
var music_inspiration: int = 0
var heal_tier: int = 0
var has_double_jump: bool = false
var has_magic_dash: bool = false
var has_magic_climb: bool = false
var has_magic_flight: bool = false
var boss_defeated: bool = false

var collected_ids: Array[String] = []
var triggered_ids: Array[String] = []
var collected_sheets: Array[String] = []

# 下次加载场景后的出生点（Door 用 spawn_id 匹配 SpawnPoint；检查点复活用 spawn_position 兜底）
var spawn_scene: String = START_SCENE
var spawn_id: String = START_SPAWN
var spawn_position: Vector2 = START_POSITION

# 检查点（死亡后在这里复活）
var has_checkpoint: bool = false
var checkpoint_scene: String = START_SCENE
var checkpoint_position: Vector2 = START_POSITION

# 临时存档点（danger 地形伤害后返回）
var temp_checkpoint_scene: String = ""
var temp_checkpoint_position: Vector2 = Vector2.ZERO


func reset() -> void:
	hp = MAX_HP
	notes = 0
	music_inspiration = 30  # 新游戏初始 30 音乐灵感
	music_inspiration_changed.emit(music_inspiration, MAX_MUSIC_INSPIRATION)
	heal_tier = 0
	has_double_jump = false
	has_magic_dash = false
	has_magic_climb = false
	has_magic_flight = false
	boss_defeated = false
	collected_ids.clear()
	triggered_ids.clear()
	collected_sheets.clear()
	spawn_scene = START_SCENE
	spawn_id = START_SPAWN
	spawn_position = START_POSITION
	has_checkpoint = false
	checkpoint_scene = START_SCENE
	checkpoint_position = START_POSITION
	clear_temp_checkpoint()
	_delete_save()


func collect(id: String) -> void:
	if id == "" or has_collectible(id):
		return
	collected_ids.append(id)


func has_collectible(id: String) -> bool:
	return id in collected_ids


func collected_count() -> int:
	return collected_ids.size()


# ---- 音符货币 ----

func add_notes(amount: int) -> void:
	if amount <= 0:
		return
	notes += amount
	notes_changed.emit(notes)


func spend_notes(amount: int) -> bool:
	if amount <= 0 or notes < amount:
		return false
	notes -= amount
	notes_changed.emit(notes)
	return true


# ---- 音乐灵感 ----

func add_music_inspiration(amount: int) -> void:
	if amount <= 0:
		return
	music_inspiration = mini(music_inspiration + amount, MAX_MUSIC_INSPIRATION)
	music_inspiration_changed.emit(music_inspiration, MAX_MUSIC_INSPIRATION)


func spend_music_inspiration(amount: int) -> bool:
	if amount <= 0 or music_inspiration < amount:
		return false
	music_inspiration -= amount
	music_inspiration_changed.emit(music_inspiration, MAX_MUSIC_INSPIRATION)
	return true


func reset_music_inspiration() -> void:
	music_inspiration = 0
	music_inspiration_changed.emit(music_inspiration, MAX_MUSIC_INSPIRATION)


func mark_trigger(id: String) -> void:
	if id == "" or has_trigger(id):
		return
	triggered_ids.append(id)


func has_trigger(id: String) -> bool:
	return id in triggered_ids


func set_spawn(scene: String, id: String) -> void:
	spawn_scene = scene
	spawn_id = id


func set_checkpoint(scene: String, pos: Vector2) -> void:
	has_checkpoint = true
	checkpoint_scene = scene
	checkpoint_position = pos


func respawn_at_checkpoint() -> void:
	if not has_checkpoint:
		# 从未激活存档点：回到初始出生点 start_school
		spawn_scene = START_SCENE
		spawn_id = START_SPAWN
		spawn_position = START_POSITION
		return
	spawn_scene = checkpoint_scene
	spawn_id = ""
	spawn_position = checkpoint_position


func set_temp_checkpoint(scene: String, pos: Vector2) -> void:
	temp_checkpoint_scene = scene
	temp_checkpoint_position = pos


func clear_temp_checkpoint() -> void:
	temp_checkpoint_scene = ""
	temp_checkpoint_position = Vector2.ZERO


func has_temp_checkpoint() -> bool:
	return not temp_checkpoint_scene.is_empty()


func respawn_at_temp_checkpoint() -> void:
	if temp_checkpoint_scene.is_empty():
		respawn_at_checkpoint()
		return
	spawn_scene = temp_checkpoint_scene
	spawn_id = ""
	spawn_position = temp_checkpoint_position
	clear_temp_checkpoint()


# ---- Day 6：曲谱收集 ----

func has_sheet(sheet_id: String) -> bool:
	return sheet_id in collected_sheets


func collect_sheet(sheet_id: String) -> bool:
	if sheet_id == "" or has_sheet(sheet_id):
		return false
	if not MusicSheetData.is_valid(sheet_id):
		return false
	collected_sheets.append(sheet_id)
	sheet_collected.emit(sheet_id)
	return true


func get_collected_sheets() -> Array[String]:
	return collected_sheets


func sheet_count() -> int:
	return collected_sheets.size()


func get_sheet_data(sheet_id: String) -> Dictionary:
	return MusicSheetData.get_sheet(sheet_id)


# ---- Day 5：磁盘存档 ----

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	var data := {
		"hp": hp,
		"notes": notes,
		"has_double_jump": has_double_jump,
		"has_magic_dash": has_magic_dash,
		"has_magic_climb": has_magic_climb,
		"has_magic_flight": has_magic_flight,
		"boss_defeated": boss_defeated,
		"collected_ids": collected_ids,
		"triggered_ids": triggered_ids,
		"spawn_scene": spawn_scene,
		"spawn_id": spawn_id,
		"spawn_position": [spawn_position.x, spawn_position.y],
		"has_checkpoint": has_checkpoint,
		"checkpoint_scene": checkpoint_scene,
		"checkpoint_position": [checkpoint_position.x, checkpoint_position.y],
		"heal_tier": heal_tier,
		"music_sheets": collected_sheets,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	game_saved.emit()


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return false
	hp = int(data.get("hp", MAX_HP))
	notes = int(data.get("notes", 0))
	has_double_jump = bool(data.get("has_double_jump", false))
	has_magic_dash = bool(data.get("has_magic_dash", false))
	has_magic_climb = bool(data.get("has_magic_climb", false))
	has_magic_flight = bool(data.get("has_magic_flight", false))
	boss_defeated = bool(data.get("boss_defeated", false))
	collected_ids = _str_array(data.get("collected_ids", []))
	triggered_ids = _str_array(data.get("triggered_ids", []))
	spawn_scene = str(data.get("spawn_scene", START_SCENE))
	spawn_id = str(data.get("spawn_id", START_SPAWN))
	spawn_position = _vec2(data.get("spawn_position"), START_POSITION)
	has_checkpoint = bool(data.get("has_checkpoint", false))
	checkpoint_scene = str(data.get("checkpoint_scene", START_SCENE))
	checkpoint_position = _vec2(data.get("checkpoint_position"), START_POSITION)
	heal_tier = int(data.get("heal_tier", 0))
	music_inspiration = 0
	music_inspiration_changed.emit(music_inspiration, MAX_MUSIC_INSPIRATION)
	collected_sheets = _str_array(data.get("music_sheets", []))
	return true


func _delete_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(SAVE_PATH.get_file())


func _str_array(v) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for x in v:
			out.append(str(x))
	return out


func _vec2(v, fallback: Vector2) -> Vector2:
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback
