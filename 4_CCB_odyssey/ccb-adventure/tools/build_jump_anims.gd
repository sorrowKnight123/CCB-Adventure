extends Node
## 一次性工具：用生成的 4 帧 jump_01~04.png 替换 Player.tscn 的 jump 动画。
## 运行：godot --headless --path ccb-adventure res://tools/build_jump_anims.tscn

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const FRAME_DIR := "res://art/character/animations"
const FRAME_COUNT := 4
const FRAME_TIME := 0.15
const SCALE := Vector2(0.085, 0.085)
const POS := Vector2(-1, -34)


func _ready() -> void:
	var scene := load(PLAYER_SCENE) as PackedScene
	if scene == null:
		printerr("加载失败")
		get_tree().quit(1)
		return
	var player := scene.instantiate()
	var ap := player.get_node("AnimationPlayer") as AnimationPlayer
	var lib := ap.get_animation_library(&"")
	if lib == null:
		printerr("无默认动画库")
		get_tree().quit(1)
		return

	var anim := Animation.new()
	anim.resource_name = "jump"
	anim.length = FRAME_COUNT * FRAME_TIME
	anim.loop_mode = Animation.LOOP_NONE

	var tex_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(tex_track, NodePath("ActionSprite:texture"))
	var sc_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(sc_track, NodePath("ActionSprite:scale"))
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("ActionSprite:position"))

	for i in range(FRAME_COUNT):
		var tex := load("%s/jump_%02d.png" % [FRAME_DIR, i + 1]) as Texture2D
		if tex == null:
			printerr("贴图缺失 jump_%02d" % (i + 1))
			get_tree().quit(1)
			return
		anim.track_insert_key(tex_track, i * FRAME_TIME, tex)
	anim.track_insert_key(sc_track, 0.0, SCALE)
	anim.track_insert_key(pos_track, 0.0, POS)

	lib.add_animation(&"jump", anim)
	print("jump animation rebuilt length=", anim.length)

	var packed := PackedScene.new()
	packed.pack(player)
	var err := ResourceSaver.save(packed, PLAYER_SCENE)
	print("saved err=", err)
	player.free()
	get_tree().quit(0)
