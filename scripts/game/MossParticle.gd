extends GPUParticles2D
## 苔藓洞穴粒子尺寸控制：挂在粒子节点上，@export 粒子直径 直接调大小（px）。
## 原理：粒子视觉直径 = 贴图宽度 × 材质 scale_min/max，脚本按直径换算并保留大小随机。

@export_range(0.5, 80.0, 0.5) var 粒子直径: float = 4.0:
	set(v):
		粒子直径 = v
		_apply_scale()
@export_range(0.0, 0.9, 0.05) var 大小随机: float = 0.4:
	set(v):
		大小随机 = v
		_apply_scale()


func _ready() -> void:
	_apply_scale()


func _apply_scale() -> void:
	if process_material is ParticleProcessMaterial and texture:
		var w := float(texture.get_width())
		var mat := process_material as ParticleProcessMaterial
		mat.scale_min = 粒子直径 * (1.0 - 大小随机) / w
		mat.scale_max = 粒子直径 * (1.0 + 大小随机) / w
