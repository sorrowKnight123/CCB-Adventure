extends SceneTree
## 一次性工具：把 17 张已对齐的攻击帧（art/attack.png 网格图集）写入 Player.tscn，
## 生成三段连击动画 attack1/attack2/attack3（复用现有 AnimationLibrary / AtlasTexture 模式）。
## 运行：godot --headless --path ccb-adventure --script res://tools/build_attack_anims.gd

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const ATLAS_TEX := "res://art/character/attack.png"
const CELL_W := 1400
const CELL_H := 900
const COLS := 5
const FRAME_T := 0.09   # 每帧时长（约 11fps，与 run 的 1.3s/14 帧一致）
const SCALE := Vector2(0.12, 0.12)
const POS := Vector2(-84, -44)
# 每段动画的帧范围（帧号 1..17 对应 attack.png 图集单元格）：
#   攻击1 轻挥：帧 1-4；攻击2 挥击：帧 5-9；攻击3 重斩：帧 10-17
const STAGES := [[1, 2, 3, 4], [5, 6, 7, 8, 9], [10, 11, 12, 13, 14, 15, 16, 17]]


func _init() -> void:
	var scene := load(PLAYER_SCENE) as PackedScene
	var player := scene.instantiate()
	var ap := player.get_node("AnimationPlayer") as AnimationPlayer
	var lib := ap.get_animation_library(&"")
	if lib == null:
		printerr("未找到默认动画库！")
		quit(1)
		return

	var atlas := load(ATLAS_TEX) as Texture2D
	if atlas == null:
		printerr("attack.png 未导入！")
		quit(1)
		return

	# 建立 17 个 AtlasTexture（5 列 x 4 行）
	var cells: Array = []
	for i in range(17):
		var col := i % COLS
		var row := i / COLS
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2(col * CELL_W, row * CELL_H, CELL_W, CELL_H)
		cells.append(at)

	# 三段动画
	for s in range(STAGES.size()):
		var frames: Array = STAGES[s]
		var name := "attack%d" % (s + 1)
		var anim := Animation.new()
		anim.resource_name = name
		anim.length = frames.size() * FRAME_T

		var t_tex := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t_tex, NodePath("ActionSprite:texture"))
		var t_sc := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t_sc, NodePath("ActionSprite:scale"))
		var t_pos := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t_pos, NodePath("ActionSprite:position"))

		for f in range(frames.size()):
			anim.track_insert_key(t_tex, f * FRAME_T, cells[frames[f] - 1])
		anim.track_insert_key(t_sc, 0.0, SCALE)
		anim.track_insert_key(t_pos, 0.0, POS)

		lib.add_animation(StringName(name), anim)
		print("added animation: ", name, "  length=", anim.length)

	var packed := PackedScene.new()
	packed.pack(player)
	var err := ResourceSaver.save(packed, PLAYER_SCENE)
	print("saved ", PLAYER_SCENE, " err=", err)
	player.free()
	quit(0)
