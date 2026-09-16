extends Sprite2D
## 前景图层（ParallaxBackground 前景层，视差系数 >1，位于玩家前面）。
## 效果：当玩家被前景物遮挡（玩家屏幕位置对应到 front 纹理的不透明区域）时，
##       前景整体半透明，让玩家可见。遮挡透明度可在检查器调。
## 实现：缓存纹理，每帧把玩家屏幕位置换算到 front 纹理坐标，采样该点 alpha，>阈值即视为遮挡。

@export var 玩家被遮挡时透明度: float = 0.35
@export var 采样缩放: float = 2.35  # ≈ 1 + front 视差系数（Parallax 换算：纹理坐标 = cam××(1+scale) − base）
@export var 校准X: float = 0.0       # 采样偏移校准（自动含 base，这里只微调）
@export var 校准Y: float = 0.0

var _img: Image
var _obscured: bool = false


func _ready() -> void:
	_img = texture.get_image() if texture else null


func _process(_delta: float) -> void:
	if _img == null:
		return
	var cam := get_viewport().get_camera_2d() as Camera2D
	if cam == null:
		_set_obscured(false)
		return
	# 玩家基本在屏幕中心（相机跟随）。Parallax 换算：
	# 相机中心在 front 纹理的坐标 = cam_center × (1+视差系数) − Sprite2D.position（+微调），取模纹理尺寸。
	var cam_center := cam.get_screen_center_position()
	var w := _img.get_width()
	var h := _img.get_height()
	var u := fposmod(cam_center.x * 采样缩放 - position.x + 校准X, w)
	var v := fposmod(cam_center.y * 采样缩放 - position.y + 校准Y, h)
	var px := _img.get_pixel(clampi(int(u), 0, w - 1), clampi(int(v), 0, h - 1))
	_set_obscured(px.a > 0.1)


func _set_obscured(ob: bool) -> void:
	if _obscured == ob:
		return
	_obscured = ob
	modulate.a = 玩家被遮挡时透明度 if ob else 1.0
