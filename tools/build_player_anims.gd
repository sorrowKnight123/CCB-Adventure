extends Node
## 一次性工具：把 crouch/land/fail 动画写入 Player.tscn 的 AnimationPlayer。
## sit 暂不处理。
## 运行：godot --headless --path ccb-adventure res://tools/build_player_anims.tscn

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const ANIM_ROOT := "res://art/character/animations"
const SCALE := Vector2(0.085, 0.085)
const POS := Vector2(-1, -34)

const GROUPS := {
	"crouch": {
		"frames": ["crouch_01 半蹲，手靠近膝盖.png"],
		"time": 0.0,
	},
	"land": {
		"frames": [
			"land_01 高处落地，膝盖深弯、裙摆张开.png",
			"land_02 落地后低蹲，手触地.png",
			"land_03 半蹲，逐渐站起来.png",
			"land_04 从落地蹲姿起身.png",
		],
		"time": 0.125,
	},
	"fail": {
		"frames": [
			"01 拿扫帚支撑站立，身体微抖.png",
			"02 靠在扫帚上，膝盖打颤.png",
			"03 向后晃，扫帚仍撑着.png",
			"04 向侧边倒下，扫帚脱手.png",
			"05 77_fail.png",
		],
		"time": 0.2,
	},
}


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

	for anim_name in GROUPS:
		var group: Dictionary = GROUPS[anim_name]
		var frames: Array = group["frames"]
		var frame_time: float = group["time"]
		var anim := Animation.new()
		anim.resource_name = anim_name
		anim.length = frames.size() * frame_time
		anim.loop_mode = Animation.LOOP_NONE

		var tex_track := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(tex_track, NodePath("ActionSprite:texture"))
		var sc_track := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(sc_track, NodePath("ActionSprite:scale"))
		var pos_track := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(pos_track, NodePath("ActionSprite:position"))

		for i in range(frames.size()):
			var tex_path := "%s/%s/%s" % [ANIM_ROOT, anim_name, frames[i]]
			var tex := load(tex_path) as Texture2D
			if tex == null:
				printerr("贴图缺失: " + tex_path)
				get_tree().quit(1)
				return
			anim.track_insert_key(tex_track, i * frame_time, tex)
		anim.track_insert_key(sc_track, 0.0, SCALE)
		anim.track_insert_key(pos_track, 0.0, POS)

		lib.add_animation(StringName(anim_name), anim)
		print("added ", anim_name, " length=", anim.length)

	var packed := PackedScene.new()
	packed.pack(player)
	var err := ResourceSaver.save(packed, PLAYER_SCENE)
	print("saved err=", err)
	player.free()
	get_tree().quit(0)
