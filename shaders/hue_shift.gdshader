shader_type canvas_item;
// 音符史莱姆染色：把贴图的色相与饱和度换成目标值，明暗压进一条窄亮带。
//
// 为什么不用 modulate：modulate 是逐通道乘法，换不了色相。绿史莱姆 (79,157,56) × 红 = 暗栗色，
// × 蓝 ≈ 近黑。所以必须走 HSV。
//
// 黑色描边与白色高光的饱和度为 0，换色相后仍是黑/白，不会被染坏。
//
// 用法：在节点脚本里 duplicate() 一份材质，再逐只设置 uniform
//       （不要用共享材质，否则多只史莱姆会串色）。
//
// ⚠️⚠️ 关于 modulate（踩过两次的坑）⚠️⚠️
// 本版本 Godot 的 canvas_item 里，**fragment() 入口的 COLOR 已经包含贴图颜色**
// （实测：输出成了"目标色 × 原贴图色"，红史莱姆变暗褐、黄史莱姆变绿）。
// 所以在 fragment 里 `* COLOR.rgb` 会把贴图乘两遍；而完全不用它，
// 又会把 self_modulate / modulate 一起丢掉（受击闪白、通关变暗全都没反应）。
// 正解：在 **vertex()** 里把 COLOR 存进 varying —— 顶点阶段访问不到贴图，
// 那里的 COLOR 就是干净的 modulate × 顶点色。

varying vec4 v_modulate;

uniform float target_hue : hint_range(0.0, 1.0) = 0.0;
uniform float target_saturation : hint_range(0.0, 1.0) = 0.72;
// 往目标饱和度的混合比例：1 = 完全用目标饱和度（色最纯、最易分辨），0 = 保留原贴图饱和度
uniform float saturation_blend : hint_range(0.0, 1.0) = 1.0;
// ⚠️ 明暗不能直接用原图的 V —— 史莱姆贴图一半像素 V>0.74、四分之一接近纯白，
//    保留它们会把颜色冲成近白（"看不出红橙黄绿青蓝紫"就是这么来的）。
//    改成：把原图明暗压进一条较窄的亮带，形体细节还在，但整只都落在目标色上。
uniform float value_floor : hint_range(0.0, 1.0) = 0.80;     // 中调像素的亮度基准
uniform float value_contrast : hint_range(0.0, 1.0) = 0.45;  // 保留多少原图明暗起伏
uniform float value_scale : hint_range(0.0, 2.0) = 1.0;      // 整体提亮/压暗（银白的高八度 C 用）

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
	// 只用 v_modulate（不要用 fragment 入口的 COLOR，它含贴图）：
	// 这样受击闪白（self_modulate）和通关变暗（modulate）才生效。
	COLOR = vec4(_hsv2rgb(hsv) * v_modulate.rgb, tex.a * v_modulate.a);
}
