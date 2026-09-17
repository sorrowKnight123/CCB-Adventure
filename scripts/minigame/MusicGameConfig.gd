extends Resource
class_name MusicGameConfig
## 音乐小游戏的「曲子」数据。
##
## 场地数据（史莱姆数量、位置、每只的音符）不在这里 —— 那些是手摆在场景里的
## MusicSlime 节点，跟着关卡走。这里只放「同一首曲子可以搬到不同关卡」的部分。

## 内部用的「停顿 / 空音」标记。`演奏顺序` 里写 `0` 就是停顿，见下。
const 停顿: int = -1

## 演奏顺序。填的数字：**`0` = 停顿（空音，不放音），`1..N` = 第 N 只史莱姆**
## （`1` = 最左边那只，也就是编号从 1 开始数）。
## 留空 = 从左到右依次演示。
##
## 例：5 只史莱姆时 `[1,3,5,3,1]` = 第 1、3、5、3、1 只；
##     `[1,0,2,0,3]` = 第 1 只、（停一拍）、第 2 只、（停一拍）、第 3 只。
##
## 停顿只在**演示**时占一个节拍（不出声）；玩家演奏时**不需要管停顿**，
## 只要把非 0 的部分按顺序复现即可（见 `演奏序列()`）。
##
## ⚠️ 用编号而不是音名：两只史莱姆可能是同一个音，用音名无法确定该打哪一只。
@export var 演奏顺序: PackedInt32Array = PackedInt32Array()

## 通关后给的「绕梁余音」数量（会撒成这么多个拾取物，每个价值 1）。
@export var 通关奖励: int = 30

## 演示时每个音之间的间隔（秒）。8 个钢琴音都长 1.5093s，
## 小于这个长度时后一个音会和前一个叠起来（听起来更像乐器而不是玩具）。
@export_range(0.05, 3.0, 0.05) var 演示间隔: float = 0.5


## 演示用的序列：`0 → 停顿(-1)`、`1..N → N-1`（换成内部 0-based 槽位编号）。
## 留空 = 从左到右。越界的编号直接丢掉（不会崩）。
func 演示序列(slot_count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if 演奏顺序.is_empty():
		for i in slot_count:
			out.append(i)
		return out
	for value in 演奏顺序:
		if value == 0:
			out.append(停顿)
		elif value >= 1 and value <= slot_count:
			out.append(value - 1)
	return out


## 玩家要复现的序列：把停顿全部去掉，只留槽位。
## 所以「玩家演奏时只看非 0 的部分对不对」；整首只有停顿时返回空。
func 演奏序列(slot_count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for value in 演示序列(slot_count):
		if value != 停顿:
			out.append(value)
	return out
