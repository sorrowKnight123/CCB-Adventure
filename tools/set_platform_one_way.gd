extends SceneTree
## 一次性工具：给平台 TileSet（MirageTilesPlatform.tres）的所有碰撞多边形设置 one_way。
## 用法：godot --headless --path ccb-adventure --script res://tools/set_platform_one_way.gd


func _init() -> void:
	_run()


func _run() -> void:
	var path := "res://tile_set/level_1 tower/MirageTilesPlatform.tres"
	var ts: TileSet = load(path)
	if ts == null:
		print("[ERR] 无法加载 ", path)
		quit(1)
		return
	var src := ts.get_source(0) as TileSetAtlasSource
	var count := 0
	for i in src.get_tiles_count():
		var coords := src.get_tile_id(i)
		var data := src.get_tile_data(coords, 0) as TileData
		if data == null:
			continue
		for poly in data.get_collision_polygons_count(0):
			data.set_collision_polygon_one_way(0, poly, true)
			count += 1
	var err := ResourceSaver.save(ts, path)
	print("one_way 已设置 %d 个碰撞多边形，保存 err=%d" % [count, err])
	quit(0 if err == OK else 1)
