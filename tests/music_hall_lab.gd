extends Node2D
## 音乐厅背景「两层 · 镜像无缝 · 分层视差」试验台（**非 headless**）。
## 打开方式：编辑器里打开本场景 → F5 运行；或命令行
##   godot --path . res://tests/music_hall_lab.tscn
##
## 分层（作者定稿的分法）：
##   **背景层** = 上下两层的建筑与布景：拱顶天花 + 中央水晶吊灯 + 上下两层镀金包厢
##                + 舞台拱门 + 红色幕布 + 管风琴 + 墙体。**不含地板。**
##   **平台层** = 最下方的舞台台面（浅色地面 + 深色裙板）。不参与视差，1:1 跟镜头走；
##                真关卡里它就是可行走地面，配 StaticBody2D + RectangleShape2D。
##
## 横向无缝：两张图都是【原图 | 它的水平镜像】拼成的 2172 宽（作者选的方案1）。
##   这样每一道缝的两侧都是同一列像素（缝变成镜像轴），结构接不上的问题从原理上消失。
##   ⚠️ 平台层必须和背景层**用同一张镜像图**：平台是舞台地面，要和背景里的舞台对得上，
##      周期不一致就会错位。
##
## 铺法用项目现有惯例（见 `2_1.tscn`）：**一个 Sprite2D + repeat_size + repeat_times**，
##   由引擎负责重复 —— 不是手动摆多份。
##
## 尺寸对应：单幅 1086×1448，房间 2 格宽 × 2 格高 = 2560×1440，
##           所以高度基本 1:1（上下两层各约 720），横向镜像图 2172 已接近房间宽。
##
## 操作：
##   ← / →      左右移动镜头          ↑ / ↓   上下移动镜头（房间有 2 格高）
##   , / .      调背景层滚动系数       A       自动平移开关（默认开）
##   R          参考线开关（绿竖线 = 镜像轴/平铺缝；橙横线 = 上下两格分界）
##   P          只看平台层开关（检查它对不对得上背景里的舞台）

const 单幅宽: float = 1086.0
const 背景高: float = 3600.0
const 背景宽: float = 2172.0
const BACK: Texture2D = preload("res://art/level/7_music_hall/hall_back_tall5.png")
const PLATFORM: Texture2D = preload("res://art/level/7_music_hall/hall_platform_mirror.png")

const 缩放: float = 1.0
const 移动速度: float = 900.0
const 自动速度: float = 220.0
const 自动范围: float = 640.0

var 自动平移: bool = true
var 显示参考线: bool = true
var 只看平台: bool = false

var _back: Parallax2D
var _plat: Parallax2D
var _cam: Camera2D
var _label: Label
var _lines: Node2D
var _a_was_down: bool = false
var _r_was_down: bool = false
var _p_was_down: bool = false


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	_back = _add_layer(BACK, 0.45, -2)      # 背景层：慢滚
	_plat = _add_layer(PLATFORM, 1.0, -1)   # 平台层：1:1 跟镜头（scroll_scale=1 即无视差）
	# 背景压暗遮罩：夹在两层背景之间（只压暗背景，不影响别的东西）；按 B 切换
	var dim := ColorRect.new()
	dim.name = "背景压暗遮罩"
	dim.size = Vector2(2560, 3600)
	dim.color = Color(0, 0, 0, 0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.z_index = -1
	dim.set_script(preload("res://scripts/props/HallBackdropDim.gd"))
	add_child(dim)
	_lines = _add_reference_lines()

	_cam = Camera2D.new()
	add_child(_cam)
	_cam.make_current()

	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(1, 0.92, 0.7))
	layer.add_child(_label)
	_刷新文字()


func _process(delta: float) -> void:
	var a_down := Input.is_physical_key_pressed(KEY_A)
	if a_down and not _a_was_down:
		自动平移 = not 自动平移
	_a_was_down = a_down
	var r_down := Input.is_physical_key_pressed(KEY_R)
	if r_down and not _r_was_down:
		显示参考线 = not 显示参考线
		_lines.visible = 显示参考线
	_r_was_down = r_down
	var p_down := Input.is_physical_key_pressed(KEY_P)
	if p_down and not _p_was_down:
		只看平台 = not 只看平台
		_back.visible = not 只看平台
	_p_was_down = p_down

	if Input.is_action_pressed("ui_left"):
		_cam.position.x -= 移动速度 * delta
		自动平移 = false
	elif Input.is_action_pressed("ui_right"):
		_cam.position.x += 移动速度 * delta
		自动平移 = false
	elif 自动平移:
		_cam.position.x = sin(Time.get_ticks_msec() / 1000.0 * 自动速度 / 自动范围) * 自动范围
	if Input.is_action_pressed("ui_up"):
		_cam.position.y -= 移动速度 * delta
	if Input.is_action_pressed("ui_down"):
		_cam.position.y += 移动速度 * delta
	_cam.position.y = clampf(_cam.position.y, -360.0, 360.0)

	if Input.is_physical_key_pressed(KEY_COMMA):
		_back.scroll_scale.x = maxf(_back.scroll_scale.x - 0.02, 0.0)
	if Input.is_physical_key_pressed(KEY_PERIOD):
		_back.scroll_scale.x = minf(_back.scroll_scale.x + 0.02, 1.0)

	_刷新文字()


func _刷新文字() -> void:
	_label.text = "音乐厅 两层 · 镜像无缝 · 分层视差试验台\n镜头 x=%6.1f  y=%6.1f\n背景层 scroll_scale=%.2f（拱顶+吊灯+上下包厢+拱门+幕布+管风琴，无地板）\n平台层 scroll_scale=1.00（舞台台面，1:1）\n自动平移：%s　参考线：%s　只看平台：%s\n←/→ 左右　↑/↓ 上下　, / . 调系数　A 自动　R 参考线　P 只看平台" % [
		_cam.position.x, _cam.position.y, _back.scroll_scale.x,
		"开" if 自动平移 else "关", "显示" if 显示参考线 else "隐藏", "是" if 只看平台 else "否"]


func _add_layer(tex: Texture2D, scroll: float, z: int) -> Parallax2D:
	## 项目惯例（2_1.tscn）：一个 Sprite2D + repeat_size + repeat_times，引擎负责重复
	var p := Parallax2D.new()
	p.scroll_scale = Vector2(scroll, 1.0)
	p.repeat_size = Vector2(tex.get_width() * 缩放, 0.0)
	p.repeat_times = 3
	p.z_index = z
	add_child(p)
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2(缩放, 缩放)
	p.add_child(s)
	return p


func _add_reference_lines() -> Node2D:
	## 绿竖线画在【每 1086】处：既是镜像轴，也是平铺缝的位置（两者现在是同一批线）
	var root := Node2D.new()
	add_child(root)
	for k in range(-3, 4):
		var v := ColorRect.new()
		v.color = Color(0.2, 1, 0.6, 0.5)
		v.position = Vector2(k * 单幅宽 * 缩放 - 1.0, -720.0)
		v.size = Vector2(2.0, 1440.0)
		root.add_child(v)
	# 橙横线：上下两格分界（图高中点）与房间顶/底边
	var h := BACK.get_height() * 缩放
	for y in [-h * 0.5, 0.0, h * 0.5]:
		var hline := ColorRect.new()
		hline.color = Color(1, 0.45, 0.2, 0.8) if is_zero_approx(y) else Color(1, 0.85, 0.2, 0.5)
		hline.position = Vector2(-4000.0, y - 1.0)
		hline.size = Vector2(8000.0, 2.0)
		root.add_child(hline)
	return root
