extends CanvasLayer
## 88 战收尾用的**唱片选择面板**：列出已拥有的唱片，选哪张决定后续剧情。
##
## 操作：↑↓ 选择 ｜ W / 回车 确认 ｜ Esc 取消（取消后 88 仍在虚弱状态，可以再按 W）
## 界面结构放在 `.tscn` 里（`agent.md §11`：UI 尽量可视化），脚本只填列表与逻辑。
##
## 没有图标也能用：`RECORDS[].icon` 为空时退回显示曲名（现在三条都为空）。

signal 选择完成(唱片id: String)
signal 已取消

@export var 根路径: NodePath = NodePath("根")
@export var 列表路径: NodePath = NodePath("根/面板/列表")
@export var 标题路径: NodePath = NodePath("根/面板/标题")
@export var 提示路径: NodePath = NodePath("根/面板/提示")
@export var 打开渐入时长: float = 0.25
@export var 关闭渐出时长: float = 0.18

var _唱片: Array[Dictionary] = []
var _选中: int = 0
var _条目: Array[Control] = []
var _已关闭: bool = false

@onready var _根: Control = get_node_or_null(根路径) as Control
@onready var _列表: VBoxContainer = get_node_or_null(列表路径) as VBoxContainer
@onready var _标题: Label = get_node_or_null(标题路径) as Label
@onready var _提示: Label = get_node_or_null(提示路径) as Label


func _ready() -> void:
	layer = 10
	add_to_group("record_panel")
	_收集()
	_建条目()
	_刷新选中()
	if _标题 != null:
		_标题.text = "播放哪一张？"
	if _提示 != null:
		_提示.text = "↑↓ 选择      W / 回车 确认      Esc 取消"
	if _根 != null:
		_根.modulate.a = 0.0
		var t := create_tween()
		t.tween_property(_根, "modulate:a", 1.0, 打开渐入时长)
	_软冻结(true)


func _收集() -> void:
	_唱片.clear()
	for 条 in GameState.get_owned_records():
		_唱片.append(条)


func _建条目() -> void:
	if _列表 == null:
		return
	for c in _列表.get_children():
		c.queue_free()
	_条目.clear()
	var 选中id: String = GameState.selected_record_id
	for i in _唱片.size():
		var 条 := _唱片[i]
		var 行 := HBoxContainer.new()
		行.custom_minimum_size = Vector2(420, 44)

		var 图标 := _做图标(条)
		if 图标 != null:
			行.add_child(图标)

		var 名 := Label.new()
		名.text = str(条.get("title", "（未命名）"))
		名.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		名.add_theme_font_size_override("font_size", 22)
		行.add_child(名)

		_列表.add_child(行)
		_条目.append(行)
		if str(条.get("id", "")) == 选中id:
			_选中 = i


## `RECORDS[].icon` 是路径字符串；为空或加载失败就返回 null（退回纯文字）
func _做图标(条: Dictionary) -> Control:
	var 路径 := str(条.get("icon", ""))
	if 路径.is_empty() or not ResourceLoader.exists(路径):
		return null
	var 纹 := TextureRect.new()
	纹.texture = load(路径)
	纹.custom_minimum_size = Vector2(40, 40)
	纹.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	纹.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return 纹


func _刷新选中() -> void:
	for i in _条目.size():
		var 行 := _条目[i]
		var 亮 := i == _选中
		行.modulate = Color(1, 1, 1, 1) if 亮 else Color(1, 1, 1, 0.55)
		if 亮:
			行.add_theme_constant_override("separation", 10)


func _unhandled_input(event: InputEvent) -> void:
	if _已关闭:
		return
	if event.is_action_pressed("ui_up"):
		_移动(-1)
	elif event.is_action_pressed("ui_down"):
		_移动(1)
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_确认()
	elif event.is_action_pressed("ui_cancel"):
		_取消()


func _移动(方向: int) -> void:
	if _唱片.is_empty():
		return
	_选中 = wrapi(_选中 + 方向, 0, _唱片.size())
	_刷新选中()


func _确认() -> void:
	if _已关闭:
		return
	var id := ""
	if not _唱片.is_empty():
		id = str(_唱片[_选中].get("id", ""))
	_关闭(true)
	选择完成.emit(id)


func _取消() -> void:
	if _已关闭:
		return
	_关闭(false)
	已取消.emit()


func _关闭(确认: bool) -> void:
	_已关闭 = true
	_软冻结(false)
	# 确认时才改"当前携带的唱片"；取消不动它
	if 确认 and not _唱片.is_empty():
		var id := str(_唱片[_选中].get("id", ""))
		if id != "":
			GameState.select_record(id)
			GameState.save_game()
	if _根 == null:
		queue_free()
		return
	var t := create_tween()
	t.tween_property(_根, "modulate:a", 0.0, 关闭渐出时长)
	t.tween_callback(queue_free)


## 面板开着时冻结玩家输入（用项目既有的"软冻结"标志，**不要用** get_tree().paused）
func _软冻结(开: bool) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p.get("输入软冻结") != null:
			p.set("输入软冻结", 开)
