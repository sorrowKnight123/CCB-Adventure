extends SceneTree
## 探针：扫描 front.png 纹理的不透明残垣横向分布（y∈[1024,2048] 每 64px 段的不透明占比），
## 用于校准 ParallaxFront 的采样公式（判断玩家在哪些 x 会被前景遮挡）。


func _init() -> void:
	var tex := load("res://art/background/2_forgotten/front.png") as Texture2D
	if tex == null:
		print("加载失败")
		quit(1)
		return
	var img := tex.get_image()
	if img == null:
		print("get_image 失败")
		quit(1)
		return
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	print("front.png ", w, "x", h, " sample_a(100,1500)=", img.get_pixel(100, 1500).a, " (100,300)=", img.get_pixel(100, 300).a)
	var line := ""
	for x in range(0, w, 64):
		var cnt := 0
		for y in range(0, h, 8):
			if img.get_pixel(x, y).a > 0.1:
				cnt += 1
		line += "%2d," % mini(cnt, 99)
	print("全高每64px列cnt(每列y步进8):")
	print(line)
	print("共", line.length(), "字符，每3字符一格")
	quit()
