class_name AttackData
extends Resource
## 攻击手感数据资源：每种攻击类型一个 .tres，在检查器配置不同数值。
## 手感代码只写一套（FeedbackManager + Player._on_hit），换攻击/换数值只改资源。

@export var hitstop_duration: float = 0.06   # 命中顿帧（秒），轻击短、重击长
@export var shake_strength: float = 1.5      # 镜头震动强度
@export var damage: int = 1                  # 伤害
@export var player_knockback: float = 0.0    # 玩家自身反冲（后坐力，0=无反冲）
# TODO: 音效预留（后续可加命中音效资源字段）
