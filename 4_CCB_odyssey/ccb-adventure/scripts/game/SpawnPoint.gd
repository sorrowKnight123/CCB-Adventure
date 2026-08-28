extends Marker2D
## Day 4：出生点。玩家加载场景后，按 GameState.spawn_id 找到对应出生点定位。

@export var id: String = ""


func _ready() -> void:
	add_to_group("spawn_points")
