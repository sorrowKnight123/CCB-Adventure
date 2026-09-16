extends Node
## 全局打击反馈引擎（autoload）：顿帧 / 镜头震动 / 命中 VFX。
## 所有攻击类型共用这一套反馈代码，具体数值由 AttackData 资源配置。

var _hitstop_active: bool = false


## 命中顿帧：把全局 time_scale 短暂压到 0，用忽略 time_scale 的计时器恢复。
## 防重入：连续攻击时后一次在锁内直接忽略。
func hit_stop(duration: float) -> void:
	if _hitstop_active or duration <= 0.0:
		return
	_hitstop_active = true
	Engine.time_scale = 0.0
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_active = false


## 镜头震动：委托玩家相机的震动逻辑（Player._start_camera_shake，衰减参数在 Player）。
func camera_shake(strength: float, duration: float = 0.08) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("_start_camera_shake"):
		player._start_camera_shake(maxf(duration, 0.0), strength)


## 命中 VFX 占位（后续替换正式粒子/闪白特效）。
func emit_hit_vfx(_pos: Vector2) -> void:
	# TODO: 命中粒子 / 闪白占位
	pass
