extends SceneTree
## 探针：分析 level3 植物帧内容（alpha 分布：内容占比/位置）+ Mossy 主瓦片图网格。

func _init() -> void:
	_analyze("res://art/level/3/Plant Animations/Plant 1/Plant1_00000.png", "Plant1")
	_analyze("res://art/level/3/Plant Animations/Plant 8 Poison/PlantPosion_00000.png", "Poison")
	_analyze("res://art/level/3/Plant Animations/PlantJump/JumpPlant_00000.png", "JumpPlant")
	_analyze("res://art/level/3/Plant Animations/BlueFlower1/BlueFlower1_00000.png", "BlueFlower")
	quit()


func _analyze(path: String, label: String) -> void:
	var tex := load(path) as Texture2D
	if tex == null:
		print(label, " 加载失败")
		return
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var minx := w; var miny := h; var maxx := 0; var maxy := 0
	var cnt := 0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			if img.get_pixel(x, y).a > 0.1:
				cnt += 1
				minx = mini(minx, x); maxx = maxi(maxx, x)
				miny = mini(miny, y); maxy = maxi(maxy, y)
	if cnt == 0:
		print(label, " 全透明?")
		return
	print("%s  %dx%d  内容box x[%d..%d] y[%d..%d] 宽%d 高%d (占比 %.0f%%×%.0f%%)" % [
		label, w, h, minx, maxx, miny, maxy, maxx - minx + 1, maxy - miny + 1,
		(maxx - minx + 1) * 100.0 / w, (maxy - miny + 1) * 100.0 / h])
