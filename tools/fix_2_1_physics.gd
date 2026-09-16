extends SceneTree
## 一次性工具：修复 2_1.tscn platform 瓦片物理——
## 每个瓦片按实际像素尺寸（size_in_atlas × 8px region）生成完整矩形物理多边形；
## tile_size 统一为 136×144。
## 用法：godot --headless --path ccb-adventure --script res://tools/fix_2_1_physics.gd


func _init() -> void:
	var path := "res://scenes/levels/2_forgotten/2_1.tscn"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("[ERR] 打开失败")
		quit(1)
		return
	var text := f.get_as_text()
	f.close()
	var lines := text.split("\n")

	# 收集瓦片像素尺寸
	var re_size := RegEx.new()
	re_size.compile("^(\\d+:\\d+)/size_in_atlas = Vector2i\\((\\d+), (\\d+)\\)")
	var sizes := {}
	for l in lines:
		var m := re_size.search(l)
		if m:
			sizes[m.get_string(1)] = Vector2i(int(m.get_string(2)) * 8, int(m.get_string(3)) * 8)

	# 替换物理多边形为完整矩形
	var re_pts := RegEx.new()
	re_pts.compile("^(\\d+:\\d+)/0/physics_layer_0/polygon_0/points = ")
	var changed := 0
	for i in lines.size():
		var m := re_pts.search(lines[i])
		if m and sizes.has(m.get_string(1)):
			var s: Vector2i = sizes[m.get_string(1)]
			var hw := s.x / 2
			var hh := s.y / 2
			lines[i] = "%s/0/physics_layer_0/polygon_0/points = PackedVector2Array(-%d, -%d, %d, -%d, %d, %d, -%d, %d)" % [
				m.get_string(1), hw, hh, hw, hh, hw, hh, hw, hh]
			changed += 1

	var out := "\n".join(lines)
	out = out.replace("tile_size = Vector2i(8, 4)", "tile_size = Vector2i(136, 144)")
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	f2.store_string(out)
	f2.close()
	print("物理多边形替换: ", changed, " 个（瓦片 ", sizes.size(), " 个）")
	quit(0)
