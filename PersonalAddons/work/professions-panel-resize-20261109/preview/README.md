# 窗口尺寸私有预览

全部 PNG 标注**模拟布局，非游戏截图**。只读执行真实 `Core.lua` 与 `UI.lua`，不启动游戏、不读取角色配置、不操作网站或发行包。旧 `professions-panel-20261109/preview/` 证据保持原样。

在项目根目录运行：

```bash
PersonalAddons/.venv/bin/python PersonalAddons/work/professions-panel-resize-20261109/preview/render_preview.py
```

在同一 1440×1000 模拟屏幕、同一 `scale=1` 下，生成 340×260、372×474、700×800 三种窗口。五种虚构场景沿用上一候选：制造、长中文次选与替代材料、采矿、未学习、无配方；每种窗口均有滚动顶端/底端与完整内容图。`*-content.png` 是离线完整内容图，不是游戏内自动展开效果。

`wow_mock.lua` 只记录原生 frame API；尺寸约束与响应式布局来自真实 Core/UI 源码，不在 mock 复制业务逻辑。`report.json` 记录两份源码的 SHA-256、依赖路径、实际 frame/font 数据、文字交叠、视口范围以及横向比较：字体大小是否保持、技能书入口在顶/底滚动时是否固定、长材料行数与可见内容行数。

依赖使用现有 `lupa.lua51`、Pillow 与系统中文替代字体。如果项目 venv 没有 Pillow，读取现有同 ABI `~/.codex/skills/sprite-gen/.venv/lib/python3.12/site-packages`；不会安装新依赖。

限制：系统替代字体字距/行高可能与游戏字体不同；图标、状态条、背景纹理以实参颜色和斜线占位。不验证真实鼠标拖动、屏幕钳制、Esc 或游戏像素；这些仍需用户游戏内测试。FontString 分配框体相交和实际文字占用相交分开记录。
