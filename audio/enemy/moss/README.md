# 苔藓共鸣兽音效清单

## 已接入

- `perfect_trim.wav`: 由 `perfect.wav` 保留开头 0.5 秒生成，用于共鸣音符 Perfect 判定。
- `miss.wav`: 基于 `perfect_trim.wav` 降调生成，用于共鸣音符 Miss 判定。
- `land.mp3`: 大跳落地时播放；起跳不播放音效。
- `slam.mp3`: 砸地命中时播放。
- `phase_change.wav`: 取 `Phase 2.mp3` 开头 6 秒，并变速为约 4.09 秒，匹配当前以 0.5 倍速播放的 49 帧 Phase Change 动画。
- `humordome-xp-gain-magic-tone-453274.mp3`: 所有能力获得过场统一使用，包括“华彩终章”。

## 不使用

- 共鸣音符出现：不使用单独音效，由战斗音乐和尾杀音乐承担节奏。
- 大跳起跳：不使用音效。
- 拔小提琴：不使用单独音效，由尾杀音乐承担。
- 能量墙出现/解除：不使用音效。

## 触发位置

- Perfect/Miss：`BossNote.gd` 判定结果产生时触发。
- 大跳落地：Boss 完成一次目标跳跃并落地时触发。
- 砸地：Boss 完成前摇并产生冲击波时触发。
- Phase 2：Phase Change 动画开始时触发。
- 能力获得：`AbilityCutscene` 开始播放时触发，所有能力共用同一个音效。
