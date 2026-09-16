extends Sprite2D
## 苔藓洞穴荧光点：轻微呼吸（透明度正弦起伏），模拟洞穴生物荧光。
## 节点上可调：呼吸速度 / 呼吸幅度（相对 modulate.a 的比例）。

@export var 呼吸速度: float = 0.9   # 呼吸周期速度（TAU/秒）
@export var 呼吸幅度: float = 0.25  # alpha 起伏幅度（相对基础 alpha 的比例）

var _base_a: float = 1.0
var _t: float = 0.0


func _ready() -> void:
	_base_a = modulate.a


func _process(delta: float) -> void:
	_t += delta
	modulate.a = _base_a * (1.0 + sin(_t * 呼吸速度 * TAU) * 呼吸幅度)
