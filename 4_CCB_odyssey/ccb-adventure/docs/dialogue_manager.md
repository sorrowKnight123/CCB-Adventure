# Dialogue Manager 操作指南（Day 12 引入）

对话管理器插件：**Dialogue Manager v4.0.3**（nathanhoad，MIT），已装进 `addons/dialogue_manager/` 并启用。
对话文件用 `res://dialogues/*.dialogue`，示例见 `dialogues/demo.dialogue`，回归测试见 `tests/test_dialogue_loader.tscn`。

## 1. 编辑器用法（可视化）

1. 顶部菜单栏出现 **Dialogue** 标签页（插件的编辑器）。
2. 点 **New Dialogue File** 新建 `.dialogue`，或 **Open** 打开已有文件；左侧是文件列表，右侧是代码编辑器。
3. 编辑器会**实时检查语法**：有错误时底部 Errors 面板列出错误行。编译通过后文件会导入成 `DialogueResource`（代码里 `load()` 直接用）。

## 2. 对话文件语法（最简用法）

```
~ start
骑士77: 你好，我是 77，在找失踪的 88。
- 你是谁？
	骑士77: 我是来帮你的，跟我来吧。
- 我赶时间。
	骑士77: 那下次再说。走吧。
-> outro

~ outro
王老师: 对话演示结束。点击任意键继续。
```

| 语法 | 含义 |
|---|---|
| `~ start` | **cue（标题）**：对话入口标记，代码用 `"start"` 作为 key 从这开始 |
| `骑士77: 台词` | **对话行**：`角色名:` + 台词。台词支持 BBCode（`[b]`/`[color]` 等） |
| `- 选项` | **选项（response）**：和它归属的对话行**同一缩进** |
| `→ 缩进一格的对话行` | 该选项跳到的**目标行**（缩进在选项之下） |
| `-> outro` | **跳转**到另一个 cue |
| `=> END` | 对话结束（编译器自动补在文件末尾，不用写） |

> ⚠️ **缩进关键**：选项 `- ` 必须和对话行**同级**（不缩进），选项的目标行缩进**在选项之下**。
> 把选项缩进到对话行下面 / 目标行和选项同级，都会报语法错误。
> ⚠️ **保留词**：cue 名**不能用 `end`**（`end` = 对话结束的内置哨兵，会拿不到该 cue）。改名如 `outro`。
> ⚠️ 选项前缀是 `- `（短横线）。`| ` 是"多人同时说话"，不是选项。

### 进阶（够用再学）
- 条件：`- 我有钥匙 [if has_key /]`；变量：`set` / `$变量名`。
- 随机行：行首加 `%`（`%3 权重`）。
- 标签：`骑士77: [#开心] 台词`，运行时 `line.tags` / `line.get_tag_value("情绪")`。
- 同屏多人：`| 另一位: 同时说的话`。
- 官方文档：仓库 `docs/Basic_Dialogue.md`、`docs/Conditions_Mutations.md`、`docs/State.md`。

## 3. 代码里怎么调（GDScript）

```gdscript
# 最简单：弹默认对话气球（角色对话 + 选项面板全自动）
var res: DialogueResource = load("res://dialogues/demo.dialogue")
DialogueManager.show_dialogue_balloon(res, "start")   # 第二个参数=起始 cue

# 不用气球、自己控制：逐行拿（注意 get_next_dialogue_line / get_line 是协程，必须 await！）
var line: DialogueLine = await DialogueManager.get_next_dialogue_line(res, "start")
print(line.character, ": ", line.text)   # → 骑士77: 你好...
# line.responses 是 Array[DialogueResponse]（有选项时才非空）
# line.next_id 是跳转目标；line.tags / line.has_tag("") 查标签
```

| 函数 | 说明 |
|---|---|
| `DialogueManager.show_dialogue_balloon(res, cue)` | 弹出对话 UI，自动播放/选项/点按跳过 |
| `DialogueManager.get_next_dialogue_line(res, cue)` | 拿下一行（协程，`await`）。取完自动 emit `dialogue_ended` |
| `DialogueManager.get_line(res, id_or_cue, states)` | 拿指定行（协程，`await`） |
| 信号 | `dialogue_started` / `got_dialogue` / `dialogue_ended` / `passed_cue` |

## 4. 对话气球（Balloon）UI

- 默认用内置 `addons/dialogue_manager/example_balloon/example_balloon.tscn`（一个 CanvasLayer 自动弹出）。
- 换自己的气球：`DialogueManager.set_default_balloon("res://ui/balloon.tscn")`（或在 Project Settings → runtime/balloon_path）。
- **改气球外观**：复制 `example_balloon/` 到 `res://ui/`，在编辑器里可视化改（对齐本项目"UI 能可视化就可视化"规约），别用代码搭 UI。
- 例子里用的节点：`%CharacterLabel`、`%DialogueLabel`、`%ResponsesMenu`。

## 5. 已验证 / 已知坑

- ✅ `get_next_dialogue_line`/`get_line` 是**协程**，调用必须 `await`（v4.0.3）。
- ✅ 选项目标行缩进在选项下，选项与对话行同级。
- ✅ cue 名避开 `end`（保留值）。
- ✅ 中文角色名/台词正常（`骑士77`、`王老师`）。
- ⚠️ headless 测试退出时会报 "2 resources still in use"——协程里持有的对话资源没释放，是 DM 自持引用，测试环境无害。
- 本项目回归：test_dorm 70/0、test_map_state 15/0、对话冒烟 8/0，全绿。
