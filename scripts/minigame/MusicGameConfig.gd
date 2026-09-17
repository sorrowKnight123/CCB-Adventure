extends Resource
class_name MusicGameConfig
## 音乐小游戏的「曲子」数据。
##
## 场地数据（史莱姆数量、位置、每只的音符）不在这里 —— 那些是手摆在场景里的
## MusicSlime 节点，跟着关卡走。这里只放「同一首曲子可以搬到不同关卡」的部分。

## 演示顺序，填的是**槽位编号**（`Slimes` 容器里子节点的顺序，0 = 第一个）。
## 留空 = 从左到右依次演示。
## ⚠️ 用编号而不是音名：两只史莱姆可能是同一个音，用音名无法确定该打哪一只。
@export var 演奏顺序: PackedInt32Array = PackedInt32Array()

## 通关后给的「绕梁余音」数量。
@export var 通关奖励: int = 30

## 演示时每个音之间的间隔（秒）。8 个钢琴音都长 1.5093s，
## 小于这个长度时后一个音会和前一个叠起来（听起来更像乐器而不是玩具）。
@export_range(0.05, 3.0, 0.05) var 演示间隔: float = 0.5


## 返回实际要演示的槽位顺序。留空 = 从左到右；越界的编号直接丢掉（不会崩）。
func get_sequence(slot_count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if 演奏顺序.is_empty():
		for i in slot_count:
			out.append(i)
		return out
	for index in 演奏顺序:
		if index >= 0 and index < slot_count:
			out.append(index)
	return out
