extends Node
## 一次性工具：用 Player.tscn 里的 AnimatedSprite2D（40 帧 Heal 精灵图）生成 heal 动画。
## 只需要把 40 帧平铺进 `AnimatedSprite2D:frame`，时长 2s（0.05s/帧）。
## 运行：
##   godot --headless --path ccb-adventure res://tools/build_heal_anims.tscn

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const FRAME_COUNT := 40
const FRAME_TIME := 0.05


func _ready() -> void:
	var scene := load(PLAYER_SCENE) as PackedScene
	if scene == null:
		printerr("Player.tscn 加载失败")
		get_tree().quit(1)
		return
	var player := scene.instantiate()

	var animated := player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if animated == null:
		printerr("AnimatedSprite2D 节点不存在")
		player.free()
		get_tree().quit(1)
		return

	var ap := player.get_node("AnimationPlayer") as AnimationPlayer
	var lib := ap.get_animation_library(&"")
	if lib == null:
		printerr("未找到默认动画库")
		player.free()
		get_tree().quit(1)
		return
	if lib.has_animation(&"heal"):
		lib.remove_animation(&"heal")

	var anim := Animation.new()
	anim.resource_name = "heal"
	anim.length = FRAME_COUNT * FRAME_TIME
	anim.loop_mode = Animation.LOOP_NONE

	var frame_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(frame_track, NodePath("AnimatedSprite2D:frame"))
	anim.track_set_interpolation_type(frame_track, Animation.INTERPOLATION_NEAREST)

	for i in range(FRAME_COUNT):
		anim.track_insert_key(frame_track, i * FRAME_TIME, i)

	lib.add_animation(&"heal", anim)
	print("added animation: heal 40 frames length=", anim.length)

	var packed := PackedScene.new()
	packed.pack(player)
	var err := ResourceSaver.save(packed, PLAYER_SCENE)
	print("saved ", PLAYER_SCENE, " err=", err)
	player.free()
	get_tree().quit(0)
