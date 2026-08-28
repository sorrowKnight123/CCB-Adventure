# art/menu · 主界面素材出处

工程内实际使用 3 个文件（均为 Godot 4.7 原生支持的格式）：

| 工程文件 | 用途 | 源文件 |
|----------|------|--------|
| `fly_final.ogv` | 标题背景循环视频 | `entity/start_menu/fly_final.mp4` |
| `bgm_menu.mp3` | 标题背景音乐 | `entity/start_menu/Pascal Rogé - Deux Arabesques L. 66 - No. 1 Andante con moto.flac` |
| `logo.png` | 标题 logo | `entity/start_menu/logo.png` |

## 背景视频 fly_final.ogv

- 源视频 `fly_final.mp4`：1920x1080，24fps，5 秒循环，魔女骑扫帚飞行（固定镜头、右侧留白）。
- 生成方式：本项目用户用 **Grok video1.5**（`entity/create_video.py`，参考图驱动）生成的 AI 视频。
- 工程内转换：mp4 → **OGV Theora**（1280x720，`imageio-ffmpeg` 内置 ffmpeg v7.1 `libtheora` 编码）。
  因为 **Godot 4.7 原生只支持 .ogv 视频流**（`VideoStreamPlayer` / `VideoStreamTheora`），mp4/webm 均无法导入。

## 背景音乐 bgm_menu.mp3

- 曲目：德彪西《阿拉伯风格曲 No.1》（Deux Arabesques L.66 – No.1 Andante con moto）。
- 演奏：**Pascal Rogé**（Decca 商业录音）。
- 工程内转换：flac → **MP3 192kbps 立体声 44.1kHz**（`imageio-ffmpeg` ffmpeg v7.1 `libmp3lame`），Godot 原生支持 .mp3。
- ⚠️ **版权提醒**：这是商业录音，本仓库是公开的（sorrowKnight123/CCB-Adventure）。
  内部开发/试玩无碍；若游戏要公开发布或发行，请替换为公有领域/CC0 演绎（如公有领域录音、自录钢琴、或 MIDI 合成），否则录音版权可能构成风险。

## logo.png

- 项目主视觉 logo（1024x619，透明底），由用户提供。

## 转换工具备注

- `pip install imageio-ffmpeg` 为本机新增（提供静态 ffmpeg 二进制，用于 mp4→ogv、flac→mp3）。
- 源文件 mp4/flac 保留在 `entity/start_menu/`（美术源归档，勿删），不入库到 `art/menu/`。
