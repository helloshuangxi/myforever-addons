# 私有布局预览

所有 PNG 均为**模拟布局，非游戏截图**。本目录不读取角色配置、不连接或启动游戏、不生成发行包、不修改官网。

从项目根目录运行：

```bash
PersonalAddons/.venv/bin/python PersonalAddons/work/professions-panel-20261109/preview/render_preview.py
```

`wow_mock.lua` 只实现记录型 WoW Frame API，使用 `lupa.lua51` 加载并执行实际 `_forever_/Interface/AddOns/MyForeverProfessions/UI.lua`，通过真实控件 OnClick 选中专业及次选。没有复制推荐、材料、折叠或布局业务逻辑。虚构样本包括制造/采矿、橙黄绿、材料缺口、长中文配方及材料、替代材料、未学专业和无配方。

`render_preview.py` 使用已有 Pillow 测量替代中文字体，并向真实 Lua 的 `GetStringHeight` 返回模拟测量值；记录实际 frame、锚点、宽高、文字、颜色、字号和源文件 SHA-256，然后生成 PNG。它不会写入生产源码。当前 Python venv 缺少 Pillow 时，仅从已安装的 `~/.codex/skills/sprite-gen/.venv/lib/python3.12/site-packages` 只读加载同 ABI Pillow；不安装依赖。准确运行路径见 `report.json` 的 `dependencies`。

- `*-065.png`、`*-100.png`、`*-160.png`：1440×1000 模拟视口，分别为 65%、100%、160%。
- `*-bottom.png`：100% 时调用实际滚动条回调到内容底部，以检查训练师及辅助操作可达。
- `*-content.png`：100% 离线完整内容图，展示滚动视口外内容；不是游戏内自动展开效果。
- 同名 `*.json`：实际 API 记录及解析后物理矩形。
- `report.json`：源文件哈希、依赖、视口可见与文字交叠检查。

交叠检查分别报告文字实际行宽占用和分配给 FontString 的框体。文字在同一滚动内容中按完整内容检查；与面板顶栏/底栏比较时先按滚动视口裁切。短专业名的实际文字互不碰撞时，框体边缘交叠也保留记录，不当作已发生的文字碰撞。

限制：系统中文替代字体的字距、行高和 WoW 原生字体不完全相同；游戏背景纹理、图标和状态条以色块/斜线占位。此工具可检查布局层级、长文换行与模拟几何，不验证原生像素效果、鼠标拖动、屏幕钳制、Esc 或游戏行为。游戏内实际视觉与交互仍需用户测试。
