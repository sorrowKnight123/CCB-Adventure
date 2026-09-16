extends SceneTree
## 史莱姆资源与场景结构回归检查。

const GREEN_SCENE := "res://scenes/enemies/level1/SlimeGreen.tscn"
const ORANGE_SCENE := "res://scenes/enemies/level1/SlimeOrange.tscn"
const GREEN_FRAMES := "res://art/enemy/level 1/SlimeGreen_frames.tres"
const ORANGE_FRAMES := "res://art/enemy/level 1/SlimeOrange_frames.tres"

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ResourceLoader.exists(GREEN_FRAMES), "绿色 SpriteFrames 存在")
	_check(ResourceLoader.exists(ORANGE_FRAMES), "橙色 SpriteFrames 存在")
	_check(ResourceLoader.exists(GREEN_SCENE), "绿色史莱姆场景存在")
	_check(ResourceLoader.exists(ORANGE_SCENE), "橙色史莱姆场景存在")

	var green_frames := load(GREEN_FRAMES) as SpriteFrames
	var orange_frames := load(ORANGE_FRAMES) as SpriteFrames
	_check(green_frames != null and green_frames.has_animation("idle"), "绿色包含 idle 动画")
	_check(orange_frames != null and orange_frames.has_animation("idle"), "橙色包含 idle 动画")
	_check(green_frames != null and green_frames.get_frame_count("idle") == 30, "绿色 idle 为 30 帧")
	_check(orange_frames != null and orange_frames.get_frame_count("idle") == 30, "橙色 idle 为 30 帧")

	var green := load(GREEN_SCENE).instantiate() as CharacterBody2D
	var orange := load(ORANGE_SCENE).instantiate() as CharacterBody2D
	_check(green != null and green.get_node_or_null("CollisionShape2D") != null, "绿色只有根碰撞盒")
	_check(orange != null and orange.get_node_or_null("CollisionShape2D") != null, "橙色有根碰撞盒")
	_check(green != null and green.get_node_or_null("ContactDamageArea") == null, "绿色没有独立接触伤害盒")
	_check(orange != null and orange.get_node_or_null("ContactDamageArea") == null, "橙色没有独立接触伤害盒")
	_check(orange != null and orange.get_node_or_null("DetectionArea") != null, "橙色有独立警戒范围")

	if green != null and orange != null:
		root.add_child(green)
		root.add_child(orange)
		await physics_frame
		_check(green.get("行为模式") == 0, "绿色配置为巡逻型")
		_check(orange.get("行为模式") == 1, "橙色配置为警戒型")

		var player := load("res://scenes/player/Player.tscn").instantiate() as CharacterBody2D
		root.add_child(player)
		player.global_position = Vector2(0.0, 0.0)
		orange.set("重力", 0.0)
		orange.global_position = Vector2(0.0, 0.0)
		await physics_frame
		await physics_frame
		var hp_after_first_contact: int = player.hp
		_check(hp_after_first_contact < player.max_hp, "根碰撞盒首次接触能造成伤害")
		player.set_physics_process(false)
		player.global_position = Vector2(0.0, 0.0)
		player.velocity = Vector2.ZERO
		player.invincible_timer = 0.0
		await create_timer(0.2).timeout
		_check(player.hp == hp_after_first_contact, "接触冷却期间不会重复扣血")
		player.invincible_timer = 0.0
		await create_timer(0.7).timeout
		_check(player.hp < hp_after_first_contact, "接触冷却结束后可以再次扣血")
		player.queue_free()
		green.queue_free()
		orange.queue_free()

	print("Slime asset test: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("[PASS] %s" % message)
	else:
		failures += 1
		print("[FAIL] %s" % message)
