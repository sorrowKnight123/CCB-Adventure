extends SceneTree
## 探针：ASCII 预览蝙蝠素材每帧的 alpha 形状，确认是否有骷髅图案混入。
## 用法：godot --headless --path ccb-adventure --script res://tools/preview_bat.gd


func _init() -> void:
	var dir := "res://art/enemy/level 1/Bat with VFX/"
	_preview(dir + "Bat-IdleFly.png", 0, 2)
	_preview(dir + "Bat-Attack1.png", 0, 1)
	quit()


func _preview(path: String, frame: int, max_frames: int) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		print(path, " 加载失败")
		return
	img.convert(Image.FORMAT_RGBA8)
	print("=== ", path.get_file(), " 第 ", frame, " 帧 ===")
	for y in range(0, 64, 2):
		var line := ""
		for x in range(frame * 64, frame * 64 + 64):
			var a := img.get_pixel(x, y).a
			line += "#" if a > 0.3 else ("+" if a > 0.05 else ".")
		print(line)
	print("--- 第 ", frame + 1, " 帧 ---")
	if max_frames > 1 and frame + 1 < max_frames:
		_preview(path, frame + 1, max_frames)
