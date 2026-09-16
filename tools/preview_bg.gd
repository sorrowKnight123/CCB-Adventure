extends SceneTree
## 探针：分析 level2 背景素材的内容分布（找地面顶面 y、天空/地面分界）。
## 用法：godot --headless --path ccb-adventure --script res://tools/preview_bg.gd


func _init() -> void:
	var dir := "res://art/background/2_forgotten/"
	for f in ["far.png", "mid.png", "floor.png", "front.png"]:
		_analyze(dir + f)
	quit()


func _analyze(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		print(path, " 加载失败")
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	print("=== ", path.get_file(), " ", w, "x", h, " ===")
	# 每 64px 一行的内容量（alpha>0.1 像素占比）
	for y in range(0, h, 64):
		var cnt := 0
		for yy in range(y, mini(y + 64, h)):
			for x in range(0, w, 8):
				if img.get_pixel(x, yy).a > 0.1:
					cnt += 1
		var ratio := float(cnt) / (64.0 * (w / 8.0))
		var bar := ""
		for i in 20:
			bar += "#" if ratio > (i + 1) / 20.0 else "."
		print("y%4d-%4d  内容占比 %.2f  %s" % [y, mini(y + 64, h) - 1, ratio, bar])
	# 底部 256px 的横向内容分布（确认地面连续性）
	var bottom := h - 256
	var seg := 128
	var seg_str := ""
	for x in range(0, w, seg):
		var c := 0
		for xx in range(x, mini(x + seg, w)):
			for yy in range(bottom, h, 8):
				if img.get_pixel(xx, yy).a > 0.1:
					c += 1
		seg_str += ("%d" % (1 if c > 0 else 0))
	print("底部256px横向段(每", seg, "px): ", seg_str)
