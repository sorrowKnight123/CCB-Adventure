class_name MusicSheet
extends RefCounted
## Day 6：曲谱数据目录（数据层，与收集逻辑分离）。
## 每张曲谱：sheet_id / title / composer / map_id / description。
## 未来可扩展 emotion / memory / story_branch / ending_id / required_for_true_ending 等字段（直接新增键即可）。

const SHEETS: Dictionary = {
	"mozart_k622": {
		"sheet_id": "mozart_k622",
		"title": "A大调单簧管协奏曲 K.622",
		"composer": "莫扎特",
		"map_id": "school",
		"description": "莫扎特最后的器乐协奏曲，明朗如校园午后。",
	},
	"tchaikovsky_flower_waltz": {
		"sheet_id": "tchaikovsky_flower_waltz",
		"title": "花之圆舞曲",
		"composer": "柴可夫斯基",
		"map_id": "forest",
		"description": "《胡桃夹子》中的圆舞曲，如花海般层层展开。",
	},
	"brahms_op118_2": {
		"sheet_id": "brahms_op118_2",
		"title": "间奏曲 Op.118 No.2",
		"composer": "勃拉姆斯",
		"map_id": "village",
		"description": "温柔而略带忧伤的间奏曲。",
	},
	"debussy_prelude_faun": {
		"sheet_id": "debussy_prelude_faun",
		"title": "牧神午后前奏曲",
		"composer": "德彪西",
		"map_id": "grassland",
		"description": "牧神午后的慵懒梦幻，印象派的开端。",
	},
	"mussorgsky_pictures": {
		"sheet_id": "mussorgsky_pictures",
		"title": "图画展览会",
		"composer": "穆索尔斯基",
		"map_id": "gallery",
		"description": "由多段小品组成的组曲，如漫步画廊。",
	},
	"shostakovich_symphony_11": {
		"sheet_id": "shostakovich_symphony_11",
		"title": "第十一交响曲",
		"composer": "肖斯塔科维奇",
		"map_id": "camp",
		"description": "沉重而有力的交响曲。",
	},
	"debussy_arabesque": {
		"sheet_id": "debussy_arabesque",
		"title": "阿拉伯风格曲",
		"composer": "德彪西",
		"map_id": "musichall",
		"description": "轻盈流动的旋律。",
	},
}


static func total() -> int:
	return SHEETS.size()


static func is_valid(sheet_id: String) -> bool:
	return SHEETS.has(sheet_id)


static func get_sheet(sheet_id: String) -> Dictionary:
	return SHEETS.get(sheet_id, {}).duplicate()


static func get_sheet_ids() -> Array:
	return SHEETS.keys()
