extends Node
## 一次性工具：把 fall 单帧动画写入 Player.tscn 的 AnimationPlayer。
## 运行：godot --headless --path ccb-adventure res://tools/build_fall_anims.tscn

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const FRAME := "res://art/character/animations/fall/fall.png"
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

	var tex := load(FRAME) as Texture2D
	if tex == null:
		printerr("fall 贴图缺失")
		get_tree().quit(1)
		return

	var anim := Animation.new()
	anim.resource_name = "fall"
	anim.length = 0.001
	anim.loop_mode = Animation.LOOP_NONE
	var tex_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(tex_track, NodePath("ActionSprite:texture"))
	var sc_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(sc_track, NodePath("ActionSprite:scale"))
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("ActionSprite:position"))
	anim.track_insert_key(tex_track, 0.0, tex)
	anim.track_insert_key(sc_track, 0.0, SCALE)
	anim.track_insert_key(pos_track, 0.0, POS)
	lib.add_animation(&"fall", anim)
	print("fall animation added")

	var packed := PackedScene.new()
	packed.pack(player)
	var err := ResourceSaver.save(packed, PLAYER_SCENE)
	print("saved err=", err)
	player.free()
	get_tree().quit(0)
