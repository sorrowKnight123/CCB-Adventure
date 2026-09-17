shader_type canvas_item;
// 金色谱台的「流光扫过」：一条斜向高光带按 sweep(0→1) 扫过，加法叠加在底色上。
//
// 高光乘以贴图 alpha，所以不会在透明区域拉出一条亮带。
// sweep 由 MusicGame.gd 每帧驱动（@export 流光周期 控制快慢）。

uniform float sweep : hint_range(-0.5, 1.5) = 0.0;
uniform float band_width : hint_range(0.01, 1.0) = 0.16;
uniform float strength : hint_range(0.0, 3.0) = 0.85;
uniform vec3 shine_color : source_color = vec3(1.0, 0.97, 0.78);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// 斜向坐标：左上 → 右下
	float axis = (UV.x + UV.y) * 0.5;
	// sweep 从画面外走到画面外，保证高光能完整扫过
	float center = mix(-band_width, 1.0 + band_width, sweep);
	float band = clamp(1.0 - abs(axis - center) / band_width, 0.0, 1.0);
	band = band * band;
	vec3 rgb = tex.rgb + shine_color * band * strength * tex.a;
	// COLOR 进入 fragment 时已含 modulate（默认 fragment 会乘它），这里要显式乘回去。
	COLOR = vec4(rgb * COLOR.rgb, tex.a * COLOR.a);
}
