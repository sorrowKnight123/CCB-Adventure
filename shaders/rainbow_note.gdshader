shader_type canvas_item;
// 能力奖励音符：色相随时间循环（彩虹）+ 谱台同款的流光扫过。
//
// 为什么把两件事合进一个 shader：hue_shift（彩虹）和 sweep_shine（扫光）各自都会输出
// 「处理过的贴图」，同一条音符合成一次就够；两个 shader 挂两层的话贴图会被画两遍，
// 银白的 note.png 直接被刷成白块。
//
// ⚠️ modulate 必须在 vertex() 里取：fragment 入口的 COLOR 已经含贴图
//    （详见 hue_shift.gdshader 的说明），在 fragment 里乘一次会双重着色。
//
// 由 AbilityNote.gd 每帧驱动 target_hue（彩虹周期）与 sweep（流光周期）。

varying vec4 v_modulate;

// ── 染色（同 hue_shift）──
uniform float target_hue : hint_range(0.0, 1.0) = 0.0;
// 音符比史莱姆小得多，饱和度给高一点才看得出是彩虹色
uniform float target_saturation : hint_range(0.0, 1.0) = 0.90;
uniform float saturation_blend : hint_range(0.0, 1.0) = 1.0;
uniform float value_floor : hint_range(0.0, 1.0) = 0.80;
uniform float value_contrast : hint_range(0.0, 1.0) = 0.45;
uniform float value_scale : hint_range(0.0, 2.0) = 1.15;

// ── 流光（同 sweep_shine，但带更宽更亮）──
// ⚠️ 别照抄谱台的 0.16 / 0.85：谱台是 215px 的大块金色，音符只有 ~78px 且是细笔画，
//    同样的带宽在屏幕上只有几像素、被平方衰减吃掉后就完全看不出来了。
//    这里是按大小等比放大的（带宽 0.30、强度 1.6 → 峰值能压到纯白，才有"闪一下"的感觉）。
uniform float sweep : hint_range(-0.5, 1.5) = 0.0;
uniform float band_width : hint_range(0.01, 1.0) = 0.30;
uniform float strength : hint_range(0.0, 3.0) = 1.60;
uniform vec3 shine_color : source_color = vec3(1.0, 1.0, 1.0);

vec3 _rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 _hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void vertex() {
	// 顶点阶段访问不到贴图，所以这里的 COLOR 就是干净的 modulate × 顶点色。
	v_modulate = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	vec3 hsv = _rgb2hsv(tex.rgb);
	hsv.x = target_hue;
	hsv.y = clamp(mix(hsv.y, target_saturation, saturation_blend), 0.0, 1.0);
	hsv.z = clamp((value_floor + (hsv.z - 0.5) * value_contrast) * value_scale, 0.0, 1.0);

	// 斜向光带：左上 → 右下；乘 tex.a 免得在透明处拉出一条亮带
	float axis = (UV.x + UV.y) * 0.5;
	float center = mix(-band_width, 1.0 + band_width, sweep);
	float band = clamp(1.0 - abs(axis - center) / band_width, 0.0, 1.0);
	band = band * band;

	vec3 rgb = _hsv2rgb(hsv) + shine_color * band * strength * tex.a;
	COLOR = vec4(rgb * v_modulate.rgb, tex.a * v_modulate.a);
}
