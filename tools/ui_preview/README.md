# 离线界面预览 / Offline UI preview

把真实的插件界面 Lua 代码放进一个模拟的魔兽控件环境里运行，解析锚点、尺寸、缩放、显隐和颜色，输出 HTML 画面。用途是在没有客户端时比较改前/改后布局、占屏面积和信息层级。

**它不是游戏截图。** 字体度量、暴雪模板美术、图标贴图都是近似；安全按钮、战斗锁定、真实鼠标和原生提示不在模拟范围内。任何视觉结论仍需在游戏里确认。

```bash
# 仓库根目录；需要 Lua 5.1 解释器
lua tools/ui_preview/run.lua <场景> out/<场景>.html [宽 高]   # 默认 1920×1080
```

场景在 `scenarios/`：`fieldkit` `coach` `coach_diagnostics` `macros` `navigator` `professions` `targets` `chat`。每个场景只提供示例数据和必要的游戏接口替身，界面本身来自 `_forever_/Interface/AddOns` 的实际源码。同时输出的 `.json` 记录主窗口矩形，可用来裁图和计算占屏比例。

- `wow_mock.lua`：控件接口与布局求解。
- `render.lua`：按层级、图层绘制为绝对定位的 HTML。
- 用无头浏览器截图：`google-chrome --headless=new --screenshot=out.png --window-size=1920,1080 file://…/out.html`。
