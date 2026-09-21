extends Node
## 88 一阶段战斗自检。
##
## 覆盖：接线 / 动画骨架 / 状态机 / **命中帧窗口与命中帧号的自洽** / 教程序列 / 距离盒选招 /
## 闪现落点防呆 / KNOCKED 与 WEAKENED 免伤 / 竞技场锁与门 / 唱片面板 / 新增对话 cue。
##
## 运行：godot --headless --path . res://tests/test_boss88_phase1.tscn --quit-after 9000

const LEVEL := preload("res://scenes/levels/music_hall/4_1.tscn")
const LEVEL_PATH := "res://scenes/levels/music_hall/4_1.tscn"
const 面板场景 := preload("res://scenes/ui/RecordSelectPanel.tscn")
const 对话文件 := "res://dialogues/game.dialogue"
const 新增CUE: Array[String] = ["boss88_intro", "boss88_taunt_half", "boss88_weakened",
	"boss88_record_pick", "boss88_transform", "ending_normal", "ending_true"]

var _p: int = 0
var _f: int = 0
var _lvl: Node2D = null
var _boss: CharacterBody2D = null
var _arena: Node = null
var _player: CharacterBody2D = null


func _ready() -> void:
	_lvl = LEVEL.instantiate()
	add_child(_lvl)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_boss = _lvl.get_node_or_null("Boss88Phase1") as CharacterBody2D
	_arena = _lvl.get_node_or_null("ArenaLock")
	_player = _lvl.get_node_or_null("Player")

	await _检查接线()
	await _检查关卡没覆写调参()
	await _检查动画骨架()
	await _检查命中帧()
	await _检查体型与几何()
	await _检查招式命中()
	await _检查状态机()
	await _检查选招()
	await _检查闪现落点()
	await _检查收尾与免伤()
	await _检查竞技场()
	await _检查唱片面板()
	await _检查对话cue()

	print("\n===== 88 一阶段自检结果：通过 %d / 失败 %d =====" % [_p, _f])
	get_tree().quit(0 if _f == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_p += 1
		print("[PASS] " + what)
	else:
		_f += 1
		print("[FAIL] " + what)


func _等物理(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


## 地面碰撞顶边（**从关卡里读，不写死** —— 作者会调关卡布局，写死会让自检误报）
func _地面顶边() -> float:
	var g := _lvl.get_node_or_null("tile/Ground") as Node2D
	if g == null:
		return 3426.0
	var cs := g.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or not (cs.shape is RectangleShape2D):
		return g.global_position.y
	return g.global_position.y - (cs.shape as RectangleShape2D).size.y * 0.5


## Boss 站在地面上时原点该在的 y（胶囊底边在原点下方 14px）
func _站位y() -> float:
	return _地面顶边() - 14.0


## 把玩家挪远，避免断言时真打到人
func _挪开玩家() -> void:
	_player.global_position = Vector2(300.0, _站位y() - 43.0)
	_player.velocity = Vector2.ZERO


# ──────────────────────────── 接线 ────────────────────────────


func _检查接线() -> void:
	_check(_boss != null, "接线：4_1 里有 Boss88Phase1")
	_check(_arena != null, "接线：4_1 里有 ArenaLock")
	_check(_player != null, "接线：4_1 里有 Player")
	if _boss == null or _arena == null:
		return
	_check(_lvl.get_node_or_null("闪烁提示") is ColorRect, "接线：闪烁提示（全屏红闪层）存在")
	_check(_boss.get_node_or_null("BossSprite") is AnimatedSprite2D, "接线：BossSprite 是 AnimatedSprite2D")
	for n in ["AttackHitbox", "近身盒", "中距盒", "InteractArea", "Bubble", "SfxPlayer"]:
		_check(_boss.get_node_or_null(n) != null, "接线：%s 存在" % n)
	_check(not (_boss.get_node("AttackHitbox") as Area2D).monitoring, "接线：判定盒默认关闭")
	_check(int(_boss.contact_damage) == 0, "接线：接触伤害默认关闭（没开战不该撞死人）")
	# ── 音效接线：4 起手音 + 5 招式音 + 3 反馈音，一个都不能空 ──
	# （空了的后果是"静音"——不报错、不崩，最难查，所以逐个断言）
	var 音效表 := {
		"起手音_爪击": "钢琴单音", "起手音_五线谱": "钢琴单音",
		"起手音_突刺": "钢琴单音", "起手音_闪现": "钢琴单音",
		"招式音_爪击": "CC0 swish", "招式音_五线谱": "CC0 swish",
		"招式音_突刺": "CC0 swish", "招式音_闪现消失": "CC0 swish",
		"招式音_闪现现身": "CC0 swish",
		"音效_受击": "CC0 bfh1", "音效_击退落地": "CC0 bfh1", "音效_破甲": "CC0 bfh1",
	}
	for 键 in 音效表:
		_check(_boss.get(键) != null, "接线：%s 已接（%s）" % [键, 音效表[键]])
	_check(_boss.get("一阶段曲") != null, "接线：一阶段曲已接（占位）")
	# 音效池：单播放器会让后一个音掐掉前一个（受击音切掉突刺风声最明显）
	var 池: Array = _boss.get("_sfx_pool")
	_check(池.size() == int(_boss.get("音效池大小")), "接线：音效池建满（%d 个）" % 池.size())
	_check(池.size() >= 3, "接线：音效池至少 3 个（够起手音+招式音+受击叠着响）")
	var 首 := 池[0] as AudioStreamPlayer
	_check(首 != null and 首.name == "SfxPlayer",
		"接线：池里第一个就是场景里原有的 SfxPlayer（旧接线不失效）")
	if 首 != null:
		_check(str(首.bus) == "SFX", "接线：池走 SFX 总线（受设置里的音效音量控制）")
	# 起手音必须音高稳定（玩家靠音高分辨下一招），招式音才允许抖动
	var 钢琴 := _boss.get("起手音_爪击") as AudioStream
	_停全池(池)
	_boss.call("_播", 钢琴, 0.0)
	var 定 := _唯一开声的池成员(池).pitch_scale
	_check(is_equal_approx(定, 1.0), "音效：起手音音高恒为 1.0（不抖动，玩家才能听音辨招）")
	_停全池(池)
	_boss.call("_播", 钢琴, 0.06)
	var 抖 := _唯一开声的池成员(池).pitch_scale
	_check(抖 >= 0.94 and 抖 <= 1.06, "音效：招式音抖动落在 ±6% 内（实测 " + str(抖) + "）")
	_check(not is_equal_approx(抖, 1.0), "音效：招式音确实抖了（不是复读机）")
	# 池要真的会轮转：连播 4 声，不该全挤在同一个播放器上
	_停全池(池)
	for _i in 池.size():
		_boss.call("_播", 钢琴, 0.0)
	var 开声 := 0
	for p in 池:
		if (p as AudioStreamPlayer).playing:
			开声 += 1
	_check(开声 == 池.size(), "音效：连播 %d 声铺满 %d 个播放器（不互相掐断）" % [池.size(), 池.size()])
	_停全池(池)


func _停全池(池: Array) -> void:
	for p in 池:
		var a := p as AudioStreamPlayer
		if a != null:
			a.stop()


## 刚被 `_播` 点着的那个播放器 —— 调用前请先 `_停全池`，否则会撞上还在响的旧声音
func _唯一开声的池成员(池: Array) -> AudioStreamPlayer:
	for p in 池:
		var a := p as AudioStreamPlayer
		if a != null and a.playing:
			return a
	return 池[0] as AudioStreamPlayer
	var 近 := _boss.get_node("近身盒/CollisionShape2D") as CollisionShape2D
	var 中 := _boss.get_node("中距盒/CollisionShape2D") as CollisionShape2D
	_check(is_equal_approx((近.shape as CircleShape2D).radius, float(_boss.近身盒半径)),
		"接线：近身盒半径与导出项一致（%d）" % int(_boss.近身盒半径))
	_check(is_equal_approx((中.shape as CircleShape2D).radius, float(_boss.中距盒半径)),
		"接线：中距盒半径与导出项一致（%d）" % int(_boss.中距盒半径))
	# Boss 自己不该在 AWAIT 就参与敌人碰撞
	_check(_boss.is_in_group("boss"), "接线：Boss 在 boss 组（HUD 血条契约）")


func _检查动画骨架() -> void:
	if _boss == null:
		return
	var sf: SpriteFrames = (_boss.get_node("BossSprite") as AnimatedSprite2D).sprite_frames
	_check(sf != null, "动画：SpriteFrames 已挂")
	if sf == null:
		return
	var 期望 := {
		# 爪击三段的后摇 2026-09-21 减半（16 → 8 帧），见 build_88_frames.gd
		"idle": 24, "walk": 16, "intro": 36, "claw_1": 18, "claw_2": 18, "claw_3": 24,
		"thrust": 26, "blink_out": 10, "blink_in": 12, "staff_cast": 18,
		"hurt": 6, "knocked": 12, "weakened": 32,
	}
	var 缺: Array = []
	var 帧数不对: Array = []
	for 名 in 期望:
		if not sf.has_animation(名):
			缺.append(名)
		elif sf.get_frame_count(名) != 期望[名]:
			帧数不对.append("%s=%d(期望%d)" % [名, sf.get_frame_count(名), 期望[名]])
	_check(缺.is_empty(), "动画：13 个动画名齐（缺 %s）" % str(缺))
	_check(帧数不对.is_empty(), "动画：帧数与设计一致（%s）" % str(帧数不对))
	_check(sf.get_animation_loop("idle") and sf.get_animation_loop("weakened"),
		"动画：idle / weakened 循环")
	_check(not sf.get_animation_loop("claw_1") and not sf.get_animation_loop("thrust")
		and not sf.get_animation_loop("hurt"), "动画：attack / thrust / hurt 不循环")
	# 爪击三段的**后摇**（命中帧之后的帧数）必须 <= 8 —— 作者定的手感：
	# 连段每段之间的间隔就是后摇，太长会"每段间隔特别大"。
	var 后摇长: Array = []
	if sf != null:
		for 对 in [["claw_1", int(_boss.爪击命中帧)], ["claw_2", int(_boss.爪击命中帧)],
				["claw_3", int(_boss.爪击三命中帧)]]:
			var 后摇 := sf.get_frame_count(对[0]) - int(对[1])
			if 后摇 > 8:
				后摇长.append("%s=%d帧" % [对[0], 后摇])
	_check(后摇长.is_empty(),
		"动画：爪击三段的后摇都 <= 8 帧（%s）" % str(后摇长))

	# 后摇**帧数** <= 8 只是必要条件 —— 2026-09-21 第二次收紧改的是**每帧 duration**
	# （挥击 1.5 倍速、后摇 2 倍速），帧数一个没动，上面那条完全抓不到时长漂移。
	# 所以这里按 duration 算**真实秒数**：后摇是玩家的输出窗口，必须短；
	# 挥击要有可读的下限（太快玩家看不清预警），也不能慢回去。
	# 作者原话："挥击 1.5 倍速，然后后摇也缩短到 0.5 倍。实测手感，后摇还是有点点长。"
	var 后摇秒长: Array = []
	var 挥击秒偏: Array = []
	for 对 in [["claw_1", 0.31], ["claw_2", 0.31], ["claw_3", 0.47]]:
		var 名: String = 对[0]
		var 命中 := int(_boss.爪击命中帧 if 名 != "claw_3" else _boss.爪击三命中帧)
		var 挥击秒 := _前段秒(sf, 名, 命中 + 1)
		var 后摇秒 := _动画秒(sf, 名) - 挥击秒
		if 后摇秒 > 0.20:
			后摇秒长.append("%s=%.2fs" % [名, 后摇秒])
		if absf(挥击秒 - float(对[1])) > 0.06:
			挥击秒偏.append("%s=%.2fs(期望%.2f)" % [名, 挥击秒, 对[1]])
	_check(后摇秒长.is_empty(),
		"动画：爪击三段的后摇真实时长 <= 0.20 秒（%s）—— 后摇是玩家的输出窗口"
		% str(后摇秒长))
	_check(挥击秒偏.is_empty(),
		"动画：爪击三段的挥击真实时长 ≈ 设计值 ±0.06 秒（%s）" % str(挥击秒偏))


# ──────────────────────────── 命中帧（核心） ────────────────────────────


func _检查命中帧() -> void:
	if _boss == null:
		return
	# ① 判定窗口语义：盒子只在出手/冲刺期间开，且至少 2 帧（1 帧刷重叠表 + 1 帧结算）。
	#    旧断言是"必须 <= 2" —— 那约束的是实现细节，而且挡不住真正的 bug：
	#    以前开盒与查询在同一物理帧，2 帧窗口照样一下都打不中。
	_check(int(_boss.命中盒持续帧) >= 2,
		"命中帧：判定窗口 >= 2 物理帧（1 帧刷重叠表 + 1 帧结算），实际 %d" % int(_boss.命中盒持续帧))
	# ② 开关真的能切 monitoring
	var 盒 := _boss.get_node("AttackHitbox") as Area2D
	_boss._设判定盒(true)
	_check(盒.monitoring, "命中帧：_设判定盒(true) 打开 monitoring")
	_boss._设判定盒(false)
	_check(not 盒.monitoring, "命中帧：_设判定盒(false) 关掉 monitoring")
	# ③ 命中帧号必须落在动画帧数之内 —— 否则 _等到帧 会一直等到超时，招式会静默卡住
	var sf: SpriteFrames = (_boss.get_node("BossSprite") as AnimatedSprite2D).sprite_frames
	var 越界: Array = []
	if sf != null:
		var 对: Array = [["爪击命中帧", "claw_1"], ["爪击三命中帧", "claw_3"], ["突刺命中帧", "thrust"]]
		for p in 对:
			var 帧号 := int(_boss.get(p[0]))
			var 总帧 := sf.get_frame_count(p[1])
			if 帧号 < 1 or 帧号 >= 总帧:
				越界.append("%s=%d 不在 %s(0~%d)" % [p[0], 帧号, p[1], 总帧 - 1])
	_check(越界.is_empty(), "命中帧：三个命中帧号都在各自动画内（%s）" % str(越界))
	# ⑤ 两拍节奏：起手音在动画第 0 帧、招式音在命中帧 → 中间必须留够预警时间。
	#    < 0.3 秒的预警等于没有（玩家听清了也来不及动），这是"重而可读"的底线。
	var 预警表 := {
		"爪击": int(_boss.爪击命中帧), "爪击三": int(_boss.爪击三命中帧),
		"突刺": int(_boss.突刺命中帧), "五线谱": int(_boss.五线谱生成帧),
		"闪现消失": sf.get_frame_count("blink_out") if sf != null else 10,
	}
	var 太短: Array = []
	for 名 in 预警表:
		var 秒 := float(预警表[名]) / 24.0
		if 秒 < 0.3:
			太短.append("%s=%.2f秒" % [名, 秒])
	_check(太短.is_empty(), "命中帧：四招预警都 >= 0.3 秒（%s）" % str(太短))
	if sf != null:
		_check(int(_boss.五线谱生成帧) < sf.get_frame_count("staff_cast"),
			"命中帧：五线谱生成帧落在 staff_cast 动画内（改它不用改代码）")
	# ④ 跑完整招之后判定盒不能卡在开着
	_挪开玩家()
	_boss.global_position = Vector2(1100.0, _站位y())
	_boss.state = _boss.State.IDLE
	await _boss._出前突刺(int(_boss._attack_serial))
	_check(not 盒.monitoring, "命中帧：一招跑完后判定盒没卡住")
	_挪开玩家()


# ──────────────────────────── 关卡不许覆写调参（踩过两次的坑） ────────────────────────────
#
# 作者的 Godot 编辑器两次把**旧值**写回 4_1 里的 Boss88Phase1 实例
# （判定盒前伸=95、爪击前突距离=60、爪击前突速度=520…），于是脚本里调好的值
# 在关卡里被静默 revert —— 而自检的期望值也跟着导出项走，**完全发现不了**。
# 还会顺手写下 `"新导出项" = null` 这种无效序列化行。
# 这里直接读 .tscn 文本查覆写行；关卡里只该有 `position`。


## 调参导出项：只该在脚本里定，关卡实例不许覆写
const 调参导出项: Array[String] = [
	"判定盒前伸", "爪击前突距离", "爪击三前突距离", "爪击前突速度", "爪击三前突速度",
	"突刺距离", "突刺速度", "偏好概率", "同招连用上限", "冲刺卡住帧", "冲刺提前帧",
	"闪现落点比例", "闪现最小落点间距", "最大生命值", "出手间隔", "出手间隔_半血",
]


func _检查关卡没覆写调参() -> void:
	var f := FileAccess.open(LEVEL_PATH, FileAccess.READ)
	_check(f != null, "关卡覆写：读得到 4_1.tscn")
	if f == null:
		return
	var 文本 := f.get_as_text()
	f.close()
	var 起 := 文本.find('name="Boss88Phase1" parent="."')
	_check(起 >= 0, "关卡覆写：找得到 Boss88Phase1 实例块")
	if 起 < 0:
		return
	var 尾 := 文本.find("
[node ", 起)
	var 块 := 文本.substr(起, (尾 - 起) if 尾 > 0 else 文本.length() - 起)
	var 命中: Array = []
	for 名 in 调参导出项:
		if 块.find('"%s" =' % 名) >= 0:
			命中.append(名)
	_check(命中.is_empty(),
		"关卡覆写：实例块没覆写调参导出项（命中 %s）—— 覆写会把脚本里的值在关卡里 revert 掉"
		% str(命中))
	_check(块.find("= null") < 0,
		"关卡覆写：实例块里没有编辑器写坏的 `= null` 行（会污染序列化）")


# ──────────────────────────── 体型与判定几何 ────────────────────────────
#
# 作者实测："88 体型过大，差不多有 6 个 77 大"、"88 一直在攻击空气，因为够不着"。
# 这两件事都是**几何**问题，所以必须有几何断言 —— 否则下次换美术/改碰撞又会漂移。


## 贴图里**非透明内容**的像素包围盒（相对帧左上角）。
## 必须用 alpha 包围盒而不是整帧：77 的美术帧里有一大片透明留白，
## 按整帧算会得出 153.6px —— 那是帧高，不是人高；按内容算才是 125.4px。
## 取不到图（压缩格式异常等）就退回整帧，不让断言因为读图失败而误报。
## 一个动画的**真实时长**（秒）= Σ 每帧 duration ÷ 动画速度。
## ⚠️ 不能按"帧数 ÷ 24"算：爪击三段用**每帧 duration** 分了挥击/后摇两档
## （挥击 1.5 倍速、后摇 2 倍速），帧数与时长已经不是线性关系了。
func _动画秒(sf: SpriteFrames, 名: String) -> float:
	return _前段秒(sf, 名, sf.get_frame_count(名))


## 一个动画**前 n 帧**的真实时长（秒）。
func _前段秒(sf: SpriteFrames, 名: String, n: int) -> float:
	if sf == null or not sf.has_animation(名):
		return 0.0
	var 速 := sf.get_animation_speed(名)
	if 速 <= 0.0:
		return 0.0
	var 总 := 0.0
	for i in mini(n, sf.get_frame_count(名)):
		总 += sf.get_frame_duration(名, i)
	return 总 / 速


func _内容盒(贴图: Texture2D, 帧矩形: Rect2i) -> Rect2:
	var 全帧 := Rect2(Vector2.ZERO, Vector2(帧矩形.size))
	var 图 := 贴图.get_image()
	if 图 == null:
		return 全帧
	var 裁 := 图
	if 帧矩形 != Rect2i(0, 0, 图.get_width(), 图.get_height()):
		裁 = 图.get_region(帧矩形)
	if 裁 == null:
		return 全帧
	var 用 := 裁.get_used_rect()
	if 用.size.x <= 0 or 用.size.y <= 0:
		return 全帧
	return Rect2(用.position, 用.size)


## 一个 Sprite 的**实际可视**包围盒（屏幕坐标，相对其父节点）。
## 绘制顺序：纹理以 offset 为中心画在局部坐标，再乘节点 scale、加 position。
func _可视盒(节点: Node2D, 帧尺寸: Vector2, 偏移: Vector2, 内容: Rect2) -> Rect2:
	var 帧左上 := 偏移 - 帧尺寸 * 0.5
	var 局部左上 := 帧左上 + 内容.position
	return Rect2(
		节点.position.x + 节点.scale.x * 局部左上.x,
		节点.position.y + 节点.scale.y * 局部左上.y,
		absf(节点.scale.x) * 内容.size.x,
		absf(节点.scale.y) * 内容.size.y)


func _检查体型与几何() -> void:
	if _boss == null or _player == null:
		return

	# ── ① 88 的可视包围盒必须等于 77 的（"跟 77 同体型"）
	var 八八精灵 := _boss.get_node_or_null("BossSprite") as AnimatedSprite2D
	var 七七精灵 := _player.get_node_or_null("Sprite2D") as Sprite2D
	_check(八八精灵 != null and 七七精灵 != null, "体型：找得到 88 的 BossSprite 与 77 的 Sprite2D")
	if 八八精灵 != null and 七七精灵 != null:
		var 八八贴图 := 八八精灵.sprite_frames.get_frame_texture("idle", 0)
		var 七七贴图 := 七七精灵.texture
		_check(八八贴图 != null and 七七贴图 != null, "体型：两边都拿得到贴图")
		if 八八贴图 != null and 七七贴图 != null:
			var 八八帧 := Vector2(八八贴图.get_width(), 八八贴图.get_height())
			var 七七帧 := Vector2(七七贴图.get_width() / float(maxi(七七精灵.hframes, 1)),
				七七贴图.get_height() / float(maxi(七七精灵.vframes, 1)))
			var 八八内容 := _内容盒(八八贴图, Rect2i(0, 0, int(八八帧.x), int(八八帧.y)))
			var 七七内容 := _内容盒(七七贴图, Rect2i(0, 0, int(七七帧.x), int(七七帧.y)))
			var 八八盒 := _可视盒(八八精灵, 八八帧, 八八精灵.offset, 八八内容)
			var 七七盒 := _可视盒(七七精灵, 七七帧, 七七精灵.offset, 七七内容)
			_check(absf(八八盒.size.y - 七七盒.size.y) <= 3.0,
				"体型：88 可视高 = 77 可视高（88 %.1f vs 77 %.1f）" % [八八盒.size.y, 七七盒.size.y])
			_check(absf(八八盒.end.y - 七七盒.end.y) <= 3.0,
				"体型：88 可视底边与 77 对齐（88 %.1f vs 77 %.1f）" % [八八盒.end.y, 七七盒.end.y])
			# 面积比也要贴近 1 —— 只等高但宽 2.6 倍的话，观感还是"大得离谱"
			var 面积比 := (八八盒.size.x * 八八盒.size.y) / maxf(七七盒.size.x * 七七盒.size.y, 0.001)
			_check(面积比 <= 2.2,
				"体型：88 可视面积不超过 77 的 2.2 倍（实际 %.2f 倍）" % 面积比)

	# ── ② 两个距离盒的圆心必须和身体胶囊同心。
	#    以前它们在 y=-110（旧的高体型中心），而 77 胶囊中心在 -43 → 竖向偏差 67px，
	#    把 r150 的近身盒水平有效半径压成 sqrt(150²-67²)=134px。同心后水平半径才等于标称值。
	var 胶囊 := _boss.get_node_or_null("CollisionShape2D") as CollisionShape2D
	_check(胶囊 != null, "几何：本体碰撞节点叫 CollisionShape2D（作者手改过名字，这里钉住）")
	if 胶囊 != null:
		for 对 in [["近身盒", "近身盒半径"], ["中距盒", "中距盒半径"]]:
			var 盒 := _boss.get_node_or_null(对[0]) as Area2D
			_check(盒 != null and absf(盒.position.y - 胶囊.position.y) <= 1.0,
				"几何：%s 与胶囊同心（盒 y=%.1f，胶囊 y=%.1f）"
				% [对[0], 盒.position.y if 盒 else 999.0, 胶囊.position.y])

	# ── ②.5 跨动画体型一致（作者 2026-09-21 实测："88 使用三连击时体型变小"）。
	#    根因：`AnimatedSprite2D` 的 scale/offset 是**按节点**的、只有一套，所以各组动画
	#    必须共用同一画布尺寸，且中立姿势身高要一致。爪击那几组当初抽帧用了小尺寸的首帧
	#    参考图，角色只画到 idle 的 66%，切过去 88 就缩水。
	#    上面 ① 只比了 idle 第 0 帧与 77 —— 漏的正是"动画之间"这一维，这里补上。
	var 已用真帧 := ["idle", "claw_1", "claw_2", "claw_3"]
	var 参考帧寸 := Vector2.ZERO
	var 参考高 := 0.0
	for 名 in 已用真帧:
		if 八八精灵 == null or not 八八精灵.sprite_frames.has_animation(名):
			continue
		var 贴 := 八八精灵.sprite_frames.get_frame_texture(名, 0)
		if 贴 == null:
			continue
		var 寸 := Vector2(贴.get_width(), 贴.get_height())
		var 内容 := _内容盒(贴, Rect2i(0, 0, int(寸.x), int(寸.y)))
		if 参考帧寸 == Vector2.ZERO:
			参考帧寸 = 寸
			参考高 = 内容.size.y
		_check(寸 == 参考帧寸,
			"体型：%s 的画布尺寸与 idle 相同（%s vs %s —— 不同则切动画时 88 会跳/缩）"
			% [名, str(寸), str(参考帧寸)])
		_check(absf(内容.size.y - 参考高) <= 参考高 * 0.06,
			"体型：%s 的中立姿势身高与 idle 一致（%.0f vs %.0f，容差 6%%）"
			% [名, 内容.size.y, 参考高])

	# ── ③ 判定盒前缘必须 >= 近身盒半径，否则"玩家站在近身带边缘"时爪击够不着
	var 判形 := _boss.get_node_or_null("AttackHitbox/CollisionShape2D") as CollisionShape2D
	if 判形 != null and 判形.shape is RectangleShape2D:
		var 半宽 := (判形.shape as RectangleShape2D).size.x * 0.5
		var 前缘 := float(_boss.判定盒前伸) + 半宽
		_check(前缘 >= float(_boss.近身盒半径),
			"几何：判定盒前缘 %.0f >= 近身盒半径 %.0f（爪击在近身带边缘够得着）"
			% [前缘, float(_boss.近身盒半径)])

	# ── ④ 突刺真的冲了 `突刺距离` 那么远（按位移停，不受帧率/顿帧影响）
	_摆好Boss(400.0)
	_摆好玩家(2200.0)          # 挪到很远的场地外，别被突刺撞到干扰测距
	await _等物理(4)
	var 起 := _boss.global_position.x
	var token := int(_boss._attack_serial)
	_boss.state = _boss.State.ATTACK
	await _boss._出前突刺(token)
	_boss.state = _boss.State.IDLE
	var 冲了 := absf(_boss.global_position.x - 起)
	_check(冲了 >= float(_boss.突刺距离) * 0.9,
		"位移：前突刺冲了 %.0fpx（目标 %.0f，下限 90%%）" % [冲了, float(_boss.突刺距离)])

	# ── ⑤ 顿帧期间冲刺距离不能归零。
	#    `FeedbackManager.hit_stop()` 会把 time_scale 压到 0，那时物理帧照常 tick 但
	#    delta = 0 → 按帧数等会直接得到 0 位移。按位移等则只是把动作拉长。
	_摆好Boss(400.0)
	await _等物理(4)
	起 = _boss.global_position.x
	token = int(_boss._attack_serial)
	_boss.state = _boss.State.ATTACK
	Engine.time_scale = 0.0
	# 用 ignore_time_scale = true 的真实时间计时器解冻（否则冻结后没人能解开）
	get_tree().create_timer(0.4, true, true, true).timeout.connect(
		func() -> void: Engine.time_scale = 1.0)
	await _boss._冲刺(float(_boss.突刺距离), float(_boss.突刺速度), token)
	Engine.time_scale = 1.0
	_boss.state = _boss.State.IDLE
	冲了 = absf(_boss.global_position.x - 起)
	_check(冲了 >= float(_boss.突刺距离) * 0.9,
		"位移：顿帧（time_scale=0）期间冲刺距离不归零（实冲 %.0fpx）" % 冲了)

	# ── ⑦ 三连爪击三段真的推了 `爪击前突距离` ×2 + `爪击三前突距离`
	#    （这四个导出项此前在自检里**零覆盖**，作者反馈"距离太短"才补上）
	_摆好Boss(600.0)
	_摆好玩家(2200.0)
	await _等物理(4)
	var 爪起 := _boss.global_position.x
	var t3 := int(_boss._attack_serial)
	_boss.state = _boss.State.ATTACK
	var 爪表 := Time.get_ticks_msec()
	await _boss._出爪击连段(t3)
	var 爪秒 := float(Time.get_ticks_msec() - 爪表) / 1000.0
	_boss.state = _boss.State.IDLE
	var 爪推 := absf(_boss.global_position.x - 爪起)
	# 连段总时长：三段动画（18+18+24 帧 @24fps = 2.5 秒）+ 三段前压。
	# **每段之间的间隔就是后摇**，作者定的手感是"后摇减半"—— 3.5 秒会显得拖。
	# 这里钉一个上限，防止后摇帧数被改回去。
	_check(爪秒 <= 3.0,
		"位移：三连爪击整段耗时 %.2f 秒 <= 3.0（后摇 8 帧/段，曾被砍到 16 帧 = 3.5 秒）" % 爪秒)
	var 爪期望 := float(_boss.爪击前突距离) * 2.0 + float(_boss.爪击三前突距离)
	# 位移是逐物理帧量化的，停下时会过冲约 2 帧行程（1040px/s 时约 36px/段），
	# 所以用区间：下限证明"推够了"，上限抓"失控跑飞"。
	_check(爪推 >= 爪期望 * 0.9 and 爪推 <= 爪期望 * 1.6,
		"位移：三连爪击三段共推了 %.0fpx（目标 %.0f，容许 0.9~1.6 倍）" % [爪推, 爪期望])

	# ── ⑧ 贴场地边界冲刺不能空转。
	#    `_冲刺` 按累计位移停，但 `_滑行` 每帧把位置夹回 活动左/右 ——
	#    88 贴边再出招时位移永远到不了目标值，没有卡住检测就会空转满
	#    `冲刺最长帧`（600 帧 = **10 秒僵直**）。作者反馈的"拖沓"很可能有一部分就是它。
	_摆好Boss(float(_boss.活动右))
	_摆好玩家(float(_boss.活动右) + 150.0)      # 玩家在它右边 → 朝右冲会被夹住
	await _等物理(4)
	var t4 := int(_boss._attack_serial)
	_boss.state = _boss.State.ATTACK
	var 秒表 := Time.get_ticks_msec()
	await _boss._冲刺(float(_boss.爪击前突距离), float(_boss.爪击前突速度), t4)
	var 耗时 := float(Time.get_ticks_msec() - 秒表) / 1000.0
	_boss.state = _boss.State.IDLE
	_check(耗时 < 1.0,
		"位移：贴场地边界冲刺不空转（耗时 %.2f 秒；没有卡住检测会是 10 秒）" % 耗时)

	# ── ⑨ 判定盒在前摇期间必须是关的（可读性：前摇不该有判定）。
	#    只观察前摇那几帧，不跑完整招 —— 这样断言直接对应"可读性"这个意图。
	_摆好Boss(1100.0)
	_摆好玩家(1400.0)
	await _等物理(3)
	var 前摇期间开着 := 0
	_boss.state = _boss.State.ATTACK
	_boss._摆("thrust")
	for _i in maxi(int(_boss.突刺命中帧) - 1, 1):
		await get_tree().physics_frame
		if (_boss.get_node("AttackHitbox") as Area2D).monitoring:
			前摇期间开着 += 1
	_check(前摇期间开着 == 0,
		"判定窗口：前突刺前摇 %d 帧内判定盒始终关闭（实测开着 %d 帧）"
		% [int(_boss.突刺命中帧), 前摇期间开着])

	_boss.state = _boss.State.IDLE
	_boss.contact_damage = int(_boss.伤害)
	_挪开玩家()


# ──────────────────────────── 招式命中（核心：这招到底打不打得到人） ────────────────────────────
#
# 这一段是整套自检里**最该有却一直缺的**：此前没有任何断言验证「Boss 出招 → 玩家掉血」，
# 测试还刻意 `_挪开玩家()` 把这条链路绕开。结果是判定盒同帧查询、突刺判定早于位移
# 这类 bug 一个都拦不住（feel-pass 的 Impact 0 分档：`Hitting an enemy feels the same
# as hitting air.`）。
#
# 关掉接触伤害再测 —— 否则分不清是「招式判定盒打到的」还是「身体撞到的」。


## 把玩家摆到指定位置、满血、清掉无敌帧
func _摆好玩家(x: float, y: float = -1.0) -> void:
	if y < 0.0:
		y = _站位y()
	_player.global_position = Vector2(x, y)
	_player.velocity = Vector2.ZERO
	_player.hp = GameState.MAX_HP
	_player.invincible_timer = 0.0
	_player._is_dash_intangible = false


## 让 Boss 站到 x，并强制只走「招式判定盒」这一条伤害通道
func _摆好Boss(x: float) -> void:
	_boss.global_position = Vector2(x, _站位y())
	_boss.velocity = Vector2.ZERO
	_boss.contact_damage = 0
	_boss.state = _boss.State.IDLE
	_boss.出手间隔 = 999.0
	_boss.出手间隔_半血 = 999.0


## 跑一招，返回玩家掉了几滴血
func _试一招(招: String) -> int:
	var 血前: int = _player.hp
	var token: int = int(_boss._attack_serial)
	_boss.state = _boss.State.ATTACK
	match 招:
		"claw": await _boss._出爪击连段(token)
		"staff": await _boss._出五线谱(token)
		"thrust": await _boss._出前突刺(token)
		"blink": await _boss._出闪现背刺(token)
	_boss.state = _boss.State.IDLE
	_boss.velocity = Vector2.ZERO
	return 血前 - _player.hp


func _检查招式命中() -> void:
	if _boss == null or _player == null:
		return

	# ── ① 爪击 @130px：距离在旧判定盒前缘（151px）之内。
	#    如果这条都不过，说明问题不是"够不着"而是"判定盒根本没查到人"。
	_摆好Boss(1100.0)
	_摆好玩家(1230.0)
	await _等物理(3)
	var 掉 := await _试一招("claw")
	_check(掉 >= 1, "命中：爪击在 130px 处能打到玩家（实测掉 %d 血）" % 掉)
	_check(_boss.boss_sprite.animation == "claw_3",
		"命中：三连爪击真的跑完三段（收招时动画 = %s）" % _boss.boss_sprite.animation)

	# ── ② 三段是三次独立打击。这条同时验证"每段只结算一次" —— 如果 `_结算过` 没生效，
	#    前压的那几帧会每帧再扣一次，总数会**远大于 3**。
	#
	#    ⚠️ 2026-09-21 段间隔缩短后（挥击 1.5 倍速 + 后摇减半）**掉 2 血而不是 3**：
	#    段间隔 ≈ 0.44s < 玩家受击无敌 `Player.invincible_time = 0.5s`，后面的段被无敌帧吸收。
	#    实测：把 `invincible_time` 临时置 0 → 立刻回到 3 血，确认就是无敌帧挡的。
	#    作者确认"允许无敌帧挡，是的话不用改" —— 所以这里守的是**上限**（结算次数没失控）
	#    与**下限**（不是只剩一下），不是精确的 3。
	_check(掉 >= 2 and 掉 <= 3,
		"命中：三连爪击掉 2~3 血（实测 %d；段间隔 < 0.5s 时无敌帧会吸收后段）" % 掉)

	# ── ③ 前突刺 @200px：旧实现（前突 83px + 判定盒前缘 151px）理论上够得着，
	#    够不着就说明判定发生在位移之前
	_摆好Boss(600.0)
	_摆好玩家(800.0)
	await _等物理(3)
	掉 = await _试一招("thrust")
	_check(掉 >= 1, "命中：前突刺在 200px 处能打到玩家（实测掉 %d 血）" % 掉)

	# ── ④ 前突刺 @420px：这是它的偏好带远端，必须够得着
	_摆好Boss(600.0)
	_摆好玩家(1020.0)
	await _等物理(3)
	掉 = await _试一招("thrust")
	_check(掉 >= 1, "命中：前突刺在 420px 处能打到玩家（实测掉 %d 血）" % 掉)

	# ── ⑤ 闪现背刺：从远带（>420px）瞬移到玩家背后再突进
	_摆好Boss(1100.0)
	_摆好玩家(500.0)
	await _等物理(3)
	掉 = await _试一招("blink")
	_check(掉 >= 1, "命中：闪现背刺在远距离能打到玩家（实测掉 %d 血）" % 掉)

	# ── ⑥ 五线谱：生成位置的 y 必须跟 88 站在同一高度
	#    （曾经生成在世界 y=0 —— 画面上方约 2900px，看不见也打不到）
	_摆好Boss(1100.0)
	_摆好玩家(700.0)
	await _等物理(6)
	_boss._attack_index = 0          # 固定用模板 0（贴地·中间留缝），让断言可复现
	_boss._生成五线谱()
	await _等物理(2)
	var 线 := get_tree().get_first_node_in_group("boss_hazard") as Node2D
	_check(线 != null, "命中：五线谱已生成（在 boss_hazard 组）")
	if 线 != null:
		_check(absf(线.global_position.y - _boss.global_position.y) < 2.0,
			"命中：五线谱锚在 88 的高度（y=%.0f，88 在 %.0f）"
			% [线.global_position.y, _boss.global_position.y])
		_check(线.global_position.y > 2880.0 and 线.global_position.y < 3600.0,
			"命中：五线谱落在竞技场 y 区间 2880~3600 内（y=%.0f）" % 线.global_position.y)
		# 挪到玩家右边一点，让它自己横扫进来（瞬移首次重叠不触发 body_entered，
		# 但它是靠 _physics_process 每帧往左推的，会真的"扫进"玩家 → 信号正常发）
		线.position.x = _player.global_position.x + 180.0
		await _等物理(14)
		掉 = GameState.MAX_HP - _player.hp
		_check(掉 >= 1, "命中：五线谱横扫能打到玩家（实测掉 %d 血）" % 掉)
		线.queue_free()

	# ── ⑦ 五线谱 5 个模板的判定都不能是空的
	#    （空判定 = 那一招在某个模板下完全打不到人，而且从画面上看不出来）
	var 空模板: Array = []
	for 模板 in 5:
		var 试线 := (load("res://scenes/enemies/boss/StaffSweep.tscn") as PackedScene).instantiate()
		add_child(试线)
		await get_tree().physics_frame
		试线.setup(260.0, 1, 模板, 200.0, 1400.0, _站位y())
		await get_tree().physics_frame
		var 判定 := 试线.get_node_or_null("判定") as Area2D
		var 块数 := 0
		var 尺寸都对 := true
		if 判定 != null:
			for c in 判定.get_children():
				var cs := c as CollisionShape2D
				if cs != null and cs.shape is RectangleShape2D:
					块数 += 1
					if (cs.shape as RectangleShape2D).size.x <= 0.0 \
							or (cs.shape as RectangleShape2D).size.y <= 0.0:
						尺寸都对 = false
		if 块数 < 2 or not 尺寸都对:
			空模板.append("模板%d:块数%d" % [模板, 块数])
		试线.queue_free()
	_check(空模板.is_empty(), "命中：五线谱 5 个模板的判定都非空（%s）" % str(空模板))

	_boss.contact_damage = int(_boss.伤害)
	_挪开玩家()


# ──────────────────────────── 状态机 ────────────────────────────


func _检查状态机() -> void:
	if _boss == null:
		return
	# 4_1 里的这个实例：玩家出生点就在触发区内 → 竞技场应当已经自动开战
	_check(_boss.battle_started, "状态机：4_1 里竞技场已自动开战（玩家出生即在触发区内）")
	_check(int(_boss.state) != int(_boss.State.AWAIT),
		"状态机：自动开战后已离开 AWAIT（state=%d）" % int(_boss.state))
	# 出手间隔调大，免得攻击循环打扰后面的断言
	_boss.出手间隔 = 999.0
	_boss.出手间隔_半血 = 999.0
	# 用一个**独立实例**验完整的 AWAIT → INTRO 链路（4_1 里那个已经被开战了）
	var 裸 := (load("res://scenes/enemies/boss/Boss88Phase1.tscn") as PackedScene).instantiate()
	add_child(裸)
	await get_tree().physics_frame
	_check(int(裸.state) == int(裸.State.AWAIT), "状态机：裸实例初始 AWAIT")
	_check(裸.hp == 裸.max_hp and 裸.max_hp == int(裸.最大生命值),
		"状态机：max_hp 与导出项同步（%d / %d）" % [裸.max_hp, int(裸.最大生命值)])
	_check(裸.get("max_hp") != null, "状态机：有 max_hp（HUD 血条契约要这个名字）")
	_check(裸.get("battle_started") != null, "状态机：有 battle_started（HUD 契约）")
	裸.start_battle()
	_check(裸.battle_started, "状态机：start_battle 后 battle_started = true")
	_check(int(裸.state) == int(裸.State.INTRO), "状态机：进入 INTRO")
	_check(int(裸.contact_damage) == 0, "状态机：INTRO 期间接触伤害关闭（演出不被打断）")
	var 血0: int = 裸.hp
	裸.take_damage(20, Vector2.ZERO)
	_check(裸.hp == 血0, "状态机：INTRO 期间打不掉血")
	await _等物理(10)
	_check(int(裸.state) == int(裸.State.INTRO), "状态机：对话没结束时停在 INTRO")
	# 半血阈值：单独验一次（一击跨过阈值也要置位）
	裸.state = 裸.State.IDLE
	裸.phase = 1
	裸._半血已触发 = false
	裸.hp = int(round(裸.max_hp * 裸.半血阈值)) + 1
	裸.take_damage(1, Vector2.ZERO)
	_check(裸._半血已触发 and 裸.phase == 2,
		"数值：跨过 50%% 阈值时置位 phase=2（hp=%d / max=%d）" % [裸.hp, 裸.max_hp])
	裸.queue_free()
	# 主实例推进到 IDLE，供后面的招式断言用
	_boss.state = _boss.State.IDLE
	_boss.contact_damage = int(_boss.伤害)


# ──────────────────────────── 选招 ────────────────────────────


func _检查选招() -> void:
	if _boss == null:
		return
	_boss.state = _boss.State.IDLE
	# 教程序列：前两招固定（设计稿 §8）
	_boss._attack_index = 0
	_boss.重置选招历史()
	_check(_boss._选招() == "claw", "选招：第 0 招固定爪击（教学）")
	_boss._attack_index = 1
	_check(_boss._选招() == "staff", "选招：第 1 招固定五线谱（教学）")

	# ── 距离带 → 偏好招（把玩家摆到带上，然后跑 400 次统计分布）──
	_boss._attack_index = 99
	_boss.global_position = Vector2(1100.0, _站位y())
	# 近带：贴身 120px
	await _摆玩家到(1220.0)
	await _验分布("近", {"claw": 0.75}, 0.0833)
	# 中带：300px
	await _摆玩家到(1400.0)
	await _验分布("中", {"thrust": 0.75}, 0.0833)
	# 远带：>420px，**两招**偏好（闪现 + 五线谱）平分 3/4 → 各 3/8
	await _摆玩家到(2000.0)
	await _验分布("远", {"blink": 0.375, "staff": 0.375}, 0.125)

	# ── 防重复：同一招不得连用超过 2 次 ──
	_boss.重置选招历史()
	var 序列: Array[String] = []
	for _i in 400:
		序列.append(_boss._选招())
	var 最长 := 1
	var 当前 := 1
	for i in 序列.size():
		if i > 0 and 序列[i] == 序列[i - 1]:
			当前 += 1
			最长 = maxi(最长, 当前)
		else:
			当前 = 1
	_check(最长 <= int(_boss.同招连用上限),
		"选招：同一招最多连用 %d 次（实测最长 %d）" % [int(_boss.同招连用上限), 最长])
	_boss.重置选招历史()
	_挪开玩家()


func _摆玩家到(x: float) -> void:
	_player.global_position = Vector2(x, _站位y() - 43.0)
	_player.velocity = Vector2.ZERO
	await _等物理(5)


## 跑很多次选招，统计每招占比。容差按二项分布标准差给（4σ），不是拍脑袋的常数 ——
## 拍脑袋会 flaky：n=400、p=0.75 时 σ≈0.022，±0.05 只有 2.3σ，12 项比较里
## 大约每 5 次就有一项误报（实测抓到过一次 claw=0.800）。
func _验分布(带名: String, 期望: Dictionary, 非偏好期望: float) -> void:
	const 次数 := 2000
	var 计 := {"claw": 0, "thrust": 0, "blink": 0, "staff": 0}
	for _i in 次数:
		_boss.重置选招历史()      # 清掉防重复，单独验权重
		计[_boss._选招()] += 1
	var 差: Array = []
	for 招 in 计:
		var 实际 := float(计[招]) / float(次数)
		var 目标: float = float(期望.get(招, 非偏好期望))
		var 容差 := maxf(4.0 * sqrt(目标 * (1.0 - 目标) / float(次数)), 0.02)
		if absf(实际 - 目标) > 容差:
			差.append("%s=%.3f(期望%.3f±%.3f)" % [招, 实际, 目标, 容差])
	_check(差.is_empty(), "选招：%s带权重分布符合（%s）" % [带名, str(差)])


# ──────────────────────────── 闪现落点防呆 ────────────────────────────


func _检查闪现落点() -> void:
	if _boss == null:
		return
	_boss.global_position = Vector2(1200.0, _站位y())
	_player.global_position = Vector2(210.0, _站位y() - 43.0)
	await _等物理(2)
	var 点: Vector2 = _boss._闪现落点()
	_check(点.x >= float(_boss.活动左) - 0.5 and 点.x <= float(_boss.活动右) + 0.5,
		"闪现落点：夹在活动范围 200~1400（实际 x=%.0f）" % 点.x)
	_check(absf(点.y - _站位y()) < 6.0,
		"闪现落点：向下探到地面（y=%.0f，站位 %.0f）" % [点.y, _站位y()])

	# ── 落点必须在玩家的**另一侧**（此前零覆盖 —— 旧实现落在同侧，闪现等于白闪）
	#    88 在玩家左边 → 应落玩家右边（用不会撞到活动边界的距离，免得被夹取干扰）
	_摆好Boss(400.0)
	_摆好玩家(800.0)
	await _等物理(3)
	var 侧点: Vector2 = _boss._闪现落点()
	var 玩家x := _player.global_position.x
	_check(signf(侧点.x - 玩家x) > 0.0,
		"闪现落点：88 在玩家左侧 → 落在玩家右侧（落点 %.0f，玩家 %.0f）" % [侧点.x, 玩家x])
	var 期望间距 := float(_boss.突刺距离) * float(_boss.闪现落点比例)
	_check(absf(absf(侧点.x - 玩家x) - 期望间距) < 6.0,
		"闪现落点：间距 ≈ 突刺距离 × 闪现落点比例（实际 %.0f，期望 %.0f）"
		% [absf(侧点.x - 玩家x), 期望间距])

	#    88 在玩家右边 → 应落玩家左边
	_摆好Boss(1300.0)
	_摆好玩家(1000.0)
	await _等物理(3)
	var 侧点2: Vector2 = _boss._闪现落点()
	_check(signf(侧点2.x - _player.global_position.x) < 0.0,
		"闪现落点：88 在玩家右侧 → 落在玩家左侧（落点 %.0f，玩家 %.0f）"
		% [侧点2.x, _player.global_position.x])

	# ── 贴边兜底：玩家贴场地右边界，想要的那一侧没空间 → 退回原来那一侧，
	#    但**绝不挤到玩家身上**（瞬移到玩家身上比同侧出现更糟）
	_摆好Boss(1000.0)
	_摆好玩家(float(_boss.活动右))
	await _等物理(3)
	var 贴边点: Vector2 = _boss._闪现落点()
	var 间距 := absf(贴边点.x - _player.global_position.x)
	_check(间距 >= float(_boss.闪现最小落点间距) - 0.5,
		"闪现落点：贴场地边界时也不挤到玩家身上（间距 %.0f ≥ %.0f）"
		% [间距, float(_boss.闪现最小落点间距)])
	_挪开玩家()


# ──────────────────────────── 收尾与免伤 ────────────────────────────


func _检查收尾与免伤() -> void:
	if _boss == null:
		return
	# 这些状态一律免伤
	for 状态 in [_boss.State.INTRO, _boss.State.KNOCKED, _boss.State.WEAKENED,
			_boss.State.RECORD, _boss.State.DONE]:
		_boss.state = 状态
		_boss.hp = 30
		_boss.take_damage(10, Vector2.ZERO)
		_check(_boss.hp == 30, "免伤：state=%d 时打不掉血" % int(状态))
	# 正常状态能打死 → 进击退
	_boss.state = _boss.State.IDLE
	_boss.hp = 5
	_boss.take_damage(5, Vector2.ZERO)
	await _等物理(4)
	_check(int(_boss.state) == int(_boss.State.KNOCKED),
		"收尾：血量归零进 KNOCKED（实际 state=%d）" % int(_boss.state))
	_check(int(_boss.contact_damage) == 0, "收尾：KNOCKED 期间接触伤害关闭（玩家靠近不会被撞死）")
	for _i in 200:
		await get_tree().physics_frame
		if int(_boss.state) == int(_boss.State.WEAKENED):
			break
	_check(int(_boss.state) == int(_boss.State.WEAKENED), "收尾：走到 WEAKENED 等玩家按 W")
	_check(int(_boss.contact_damage) == 0, "收尾：WEAKENED 期间接触伤害仍是关的")
	_check(GameState.is_boss_defeated("boss88_phase1"), "收尾：已写 boss88_phase1 战胜标记")
	_boss.take_damage(99, Vector2.ZERO)
	_check(_boss.hp == 0, "收尾：WEAKENED 期间打不掉血（hp 保持 0）")


# ──────────────────────────── 竞技场 ────────────────────────────


func _检查竞技场() -> void:
	if _arena == null:
		return
	var 区 := _arena.get_node_or_null("触发区") as Area2D
	_check(区 != null and 区.collision_mask == 2, "竞技场：触发区存在且只检测玩家层")
	# 触发区形状必须真是那块矩形（曾经因为 sub_resource 插错位置退成默认 20x20）
	var 形 := 区.get_node_or_null("CollisionShape2D") as CollisionShape2D
	_check(形 != null and 形.shape is RectangleShape2D
		and (形.shape as RectangleShape2D).size == Vector2(1400, 300),
		"竞技场：触发区形状 = 1400x300（实际 %s）"
		% (str((形.shape as RectangleShape2D).size) if 形 != null and 形.shape is RectangleShape2D else "非矩形"))
	# 二阶段的视口矩形也不能被碰坏（同一份场景）
	var p2 := _lvl.get_node_or_null("phase_2_area/CollisionShape2D") as CollisionShape2D
	_check(p2 != null and p2.shape is RectangleShape2D
		and (p2.shape as RectangleShape2D).size == Vector2(1280, 720),
		"竞技场：phase_2_area 形状 = 1280x720（实际 %s）"
		% (str((p2.shape as RectangleShape2D).size) if p2 != null and p2.shape is RectangleShape2D else "非矩形"))
	_check(_arena.竞技场矩形 == Rect2(0, 2880, 1600, 720),
		"竞技场：矩形 = x0~1600 / y2880~3600（实际 %s）" % str(_arena.竞技场矩形))
	_arena.已结束 = false
	_arena.战斗中 = false
	_arena.开始()
	await _等物理(4)
	_check(_arena.门是否锁着(), "竞技场：开战后回程门被锁（意图）")
	# ⚠️ 意图之外还要验「物理属性真的落地」：_锁门 走 set_deferred（它从 body_entered 里被调下来，
	#    直接赋值会被引擎挡掉且只报一行 ERROR，门其实没锁上）。只验意图会漏掉这个 bug。
	var 门 := _lvl.get_node_or_null("Door/4_1-3_1") as Area2D
	_check(门 != null, "竞技场：找得到回程门 Door/4_1-3_1")
	if 门 != null:
		_check(not 门.monitoring and not 门.monitorable,
			"竞技场：门的 monitoring/monitorable 真关掉了（set_deferred 已落地）")
	var 相机 := _player.get_node_or_null("Camera2D") as Camera2D
	if 相机 != null:
		_check(相机.limit_right - 相机.limit_left == 1600,
			"竞技场：镜头 limits 收到 1600 宽（实际 %d）" % (相机.limit_right - 相机.limit_left))
		_check(相机.limit_top == 2880 and 相机.limit_bottom == 3600,
			"竞技场：镜头上下限到第 1 格（%d~%d）" % [相机.limit_top, 相机.limit_bottom])
	_arena._on_胜利()
	await _等物理(4)
	_check(not _arena.门是否锁着(), "竞技场：胜利后门解锁（意图）")
	if 门 != null:
		_check(门.monitoring and 门.monitorable,
			"竞技场：胜利后门的 monitoring/monitorable 真的开回来了")


# ──────────────────────────── 唱片面板 ────────────────────────────


func _检查唱片面板() -> void:
	# 默认并不拥有《狂喜之诗》（它靠小兰的隐藏任务或作弊栏发放）→ 先发一张再验面板
	var 发 := GameState.强制获得唱片("ecstasy_poem")
	_check(发 or GameState.has_record("ecstasy_poem"), "面板：作弊入口能发出《狂喜之诗》")
	_check(GameState.has_record("ecstasy_poem"), "面板：已拥有 ecstasy_poem（真结局钥匙）")
	var 面板: Node = 面板场景.instantiate()
	add_child(面板)
	await _等物理(2)
	await get_tree().process_frame
	var 列表 := 面板.get_node_or_null("根/面板/列表") as VBoxContainer
	_check(列表 != null, "面板：列表节点存在")
	if 列表 == null:
		面板.queue_free()
		return
	_check(列表.get_child_count() == GameState.owned_records.size(),
		"面板：列出已拥有唱片 %d 张（实际 %d 行）"
		% [GameState.owned_records.size(), 列表.get_child_count()])
	var 目标 := -1
	for i in 面板._唱片.size():
		if str(面板._唱片[i].get("id", "")) == "ecstasy_poem":
			目标 = i
	_check(目标 >= 0, "面板：已拥有唱片里有 ecstasy_poem（真结局钥匙）")
	if 目标 >= 0:
		面板._选中 = 目标
		var 记录 := {"id": "", "次数": 0}
		面板.选择完成.connect(func(id: String) -> void:
			记录["id"] = id
			记录["次数"] += 1)
		面板._确认()
		await get_tree().process_frame
		_check(记录["次数"] == 1 and 记录["id"] == "ecstasy_poem",
			"面板：确认后发出 选择完成(ecstasy_poem)")
		_check(GameState.selected_record_id == "ecstasy_poem", "面板：写入了 selected_record_id")
	var 面板2: Node = 面板场景.instantiate()
	add_child(面板2)
	await _等物理(2)
	var 次数 := [0]
	面板2.选择完成.connect(func(_id: String) -> void: 次数[0] += 1)
	面板2._取消()
	await get_tree().process_frame
	_check(次数[0] == 0, "面板：Esc 取消时不发 选择完成（88 留在虚弱，可再按 W）")
	await _等物理(4)
	_check(_player.输入软冻结 == false, "面板：关闭后玩家软冻结已解除")
	_check(_boss != null and _boss.has_method("_on_面板取消"), "面板：boss 侧有取消回落")
	_check(_boss != null and _boss.has_method("_on_唱片选定"), "面板：boss 侧有选定处理")


# ──────────────────────────── 对话 cue ────────────────────────────


func _检查对话cue() -> void:
	var res: DialogueResource = load(对话文件)
	_check(res != null, "对话：game.dialogue 能加载")
	if res == null:
		return
	var 坏: Array = []
	for c in 新增CUE:
		var line: DialogueLine = await DialogueManager.get_next_dialogue_line(res, c)
		if line == null or line.text.strip_edges().is_empty():
			坏.append(c)
	_check(坏.is_empty(), "对话：7 个新 cue 都能解析出文本（坏 %s）" % str(坏))
