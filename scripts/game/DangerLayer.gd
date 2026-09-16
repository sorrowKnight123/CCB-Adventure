@tool
extends TileMapLayer
## 危险地形层（地刺 / 带刺藤蔓等）：检测范围按层单独配置。
## 挂在场景的 danger 节点上；不挂则用 Player 的默认 3 点采样（地刺原判定，不受影响）。
## 参数按当前危险地形的实际需要调：瓦片小 → 步进调小；视觉范围大 → 扩展/覆盖调大。
## 调试可视化（仅编辑器显示）：每个瓦片向外扩展的检测区域红框，改参数实时可见。

@export var 检测扩展X: float = 8.0     # 水平扩展：玩家两侧各延伸多少 px 也算触发
@export var 检测覆盖高度: float = 70.0  # 垂直覆盖：从脚底(+30)向上覆盖到该高度（px）
@export var 检测步进: float = 20.0      # 采样点间距（px）：瓦片小就调小（如 8），保证采样不落在刺之间
@export var 启用瓦片检测: bool = true   # false = 本层瓦片只作视觉，判定改用 DangerZone（Area2D）
@export var 调试显示范围: bool = true   # 编辑器里显示检测范围（红框）
@export var 调试颜色: Color = Color(1, 0.25, 0.25, 0.22)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and 调试显示范围:
		queue_redraw()


func _draw() -> void:
	## 检测范围可视化（仅编辑器显示）：每个危险瓦片向外扩展（水平 ±扩展X、垂直向上 覆盖高度）的红色区域。
	if not Engine.is_editor_hint():
		return  # 运行游戏不显示
	if not 调试显示范围:
		return
	var s := scale
	if s.x == 0.0 or s.y == 0.0:
		return
	var ts: Vector2i = tile_set.tile_size
	for c in get_used_cells():
		var center := map_to_local(c)
		var w := ts.x + 检测扩展X * 2.0 / s.x
		var h := ts.y + 检测覆盖高度 / s.y
		var rect := Rect2(center.x - w / 2.0, center.y - ts.y / 2.0 - 检测覆盖高度 / s.y, w, h)
		draw_rect(rect, 调试颜色, true)
		draw_rect(rect, Color(调试颜色.r, 调试颜色.g, 调试颜色.b, 0.9), false, 1.5)
