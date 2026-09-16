extends Node
## 一次性工具：把 entity 生成的 8 帧“骑扫帚蓄力”图片写入 Player.tscn，
## 生成 flight_charge 动画（8 帧 / 2 秒，复用默认 AnimationLibrary）。
## 以场景方式运行，确保 autoload 已加载：
##   godot --headless --path ccb-adventure res://tools/build_flight_charge_anims.tscn

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const FRAME_DIR := "res://art/character/flight_charge"
const FRAME_COUNT := 8
const FRAME_TIME := 0.125
const SPRITE_SCALE := Vector2(0.18, 0.18)
const SPRITE_POS := Vector2(-90, -90)


func _ready() -> void:
	var scene := load(PLAYER_SCENE) as PackedScene
	if scene == null:
		printerr("Player.tscn 加载失败")
		get_tree().quit(1)
		return
	var player := scene.instantiate()

	# 1. 确保 ChargeSprite 节点存在（可见性默认 false，蓄力时才显示）
	var charge_sprite := player.get_node_or_null("ChargeSprite") as Sprite2D
	if charge_sprite == null:
		charge_sprite = Sprite2D.new()
		charge_sprite.name = "ChargeSprite"
		charge_sprite.position = SPRITE_POS
		charge_sprite.scale = SPRITE_SCALE
		charge_sprite.visible = false
		player.add_child(charge_sprite)
		charge_sprite.owner = player
		print("created ChargeSprite")
	else:
		charge_sprite.position = SPRITE_POS
		charge_sprite.scale = SPRITE_SCALE
		charge_sprite.visible = false

	var ap := player.get_node("AnimationPlayer") as AnimationPlayer
	var lib := ap.get_animation_library(&"")
	if lib == null:
		printerr("未找到默认动画库")
		get_tree().quit(1)
		return

	# 2. 建立 flight_charge 动画
	var anim := Animation.new()
	anim.resource_name = "flight_charge"
	anim.length = FRAME_COUNT * FRAME_TIME
	anim.loop_mode = Animation.LOOP_NONE

	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, NodePath("ChargeSprite:texture"))
	for i in range(FRAME_COUNT):
		var tex_path := "%s/frame_%02d.png" % [FRAME_DIR, i + 1]
		var tex := load(tex_path) as Texture2D
		if tex == null:
			printerr("贴图加载失败: %s" % tex_path)
			get_tree().quit(1)
			return
		anim.track_insert_key(track, i * FRAME_TIME, tex)

	lib.add_animation(&"flight_charge", anim)
	print("added animation: flight_charge  length=", anim.length)

	# 3. 保存回 Player.tscn
	var packed := PackedScene.new()
	packed.pack(player)
	var err := ResourceSaver.save(packed, PLAYER_SCENE)
	print("saved ", PLAYER_SCENE, " err=", err)
	player.free()
	get_tree().quit(0)
