extends SceneTree
## 一次性工具：扫描蝙蝠素材每个 PNG 的内容列分布，推断帧边界（帧间透明列分隔）。
## 用法：godot --headless --path ccb-adventure --script res://tools/scan_bat_frames.gd


func _init() -> void:
	_run()


func _run() -> void:
	var dir := "res://art/enemy/level 1/Bat with VFX"
	var files := ["Bat-Attack1.png", "Bat-Attack2.png", "Bat-Die.png", "Bat-Hurt.png",
		"Bat-IdleFly.png", "Bat-Run.png", "Bat-Sleep.png", "Bat-WakeUp.png"]
	for f in files:
		var img := Image.load_from_file("%s/%s" % [dir, f])
		if img == null:
			print(f, " 加载失败")
			continue
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		# 每列内容像素数
		var col_content := PackedInt32Array()
		col_content.resize(w)
		for x in w:
			var cnt := 0
			for y in h:
				if img.get_pixel(x, y).a > 0.02:
					cnt += 1
			col_content[x] = cnt
		# 找内容列段（≥1 像素内容的列，连续段）
		var segs: Array = []
		var in_seg := false
		var seg_start := 0
		var total_content := 0
		for x in w:
			if col_content[x] > 0:
				total_content += 1
				if not in_seg:
					in_seg = true
					seg_start = x
			else:
				if in_seg:
					segs.append([seg_start, x - 1])
					in_seg = false
		if in_seg:
			segs.append([seg_start, w - 1])
		var seg_str := ""
		for s in segs:
			seg_str += " [%d-%d](%d)" % [s[0], s[1], s[1] - s[0] + 1]
		print("%s: %dx%d 内容列=%d 段=%d%s" % [f, w, h, total_content, segs.size(), seg_str])
	quit()
