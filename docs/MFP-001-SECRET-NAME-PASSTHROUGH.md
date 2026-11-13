# MFP-001：加密矿名直显（候选，未实测）

日期：2026-11-14。分支 `feature/ux-001-unified-style`。**没有在游戏里验证过**；下面区分“官方接口文档写明的”“模拟通过的”“需要实机确认的”。未改版本号，未发布。

## 换了一个问题

之前的思路是“读出矿名 → 查资源表 → 提醒”。dev.22 的实机记录说明第一步走不通：小地图提示的 `leftText` 是受保护值（secret），代码遇到它就按规则锁定本次会话，功能等于关闭。

但提醒玩家并不需要插件**知道**矿名，只需要把名字**显示**出来。这个客户端的受保护值机制正好留了这条路。

## 依据

Gethe/wow-ui-source 提交 `4cd0ab752a77164f654ccbca9d0c1fe8dafceebe`（`version.txt` 为 1.60.1.70888，即此前调查引用的同一提交）的官方接口文档：

| 接口 | 文档标注 | 含义 |
| --- | --- | --- |
| `FontString:SetText` | `SecretArguments = "AllowedWhenTainted"`，`SecretArgumentsAddAspect = { Text }` | 插件代码可以把受保护字符串交给字体串显示；字体串随后带上“文本受保护”标记 |
| `FontString:SetFormattedText` | 同上 | 同上 |
| `Minimap:UpdateMouseoverAtPoint`、`SetUsingSoftCursor` | `AllowedWhenUntainted` | 与本方案无关，仅记录 |

文件：`Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFontStringAPIDocumentation.lua`。

边界：文档是 70888 的，实机是 70938；文档标注不等于实机行为。

## 实现

只动扫描读名的一处和提醒显示的一处，替身地图、原地图恢复、输入保护、对照与复核流程都没改。

- `GatherResources.lua`：占位键 `ns.GATHER_OPAQUE_NAME` 与开关 `ns.GatherOpaqueAllowed()`。
- `GatherCursorScan.lua`：`leftText`/`rightText` 是受保护值且开关开启时，不再锁定会话，而是把这次命中记在占位键下，并保留该值仅用于显示。之后照常走“地图外对照 → 回原点复核”，通过才发布。容器、行表、行、键是受保护值时仍按原规则锁定。
- `GatherAlerts.lua`：占位键的命中用当前已学且已开启的追踪类型（矿/草/鱼）决定是否显示和用什么颜色；标题直接 `title:SetText(受保护值)`，副行写“小地图范围内 · 名称由游戏显示”。声音、冷却、“出现—消失—再出现才再响”沿用现有逻辑。
- `Core.lua`：新设置 `gatherOpaque`，存档默认开启。`/myprof gather passthrough on|off` 切换；关闭即回到原规则。

代码对受保护值只做三件事：存进局部变量、放进表的值位置、传给 `SetText`。不比较、不取长度、不拼接、不当键、不写存档、不进诊断输出。

## 与原规则的关系

`AGENTS.md` 要求“旧悬停文字不能冒充真实发现”。这里的命中仍然必须通过对照和复核，不是旧缓存；名字由游戏自己画出来。**变化在于插件无法确认这个标记是不是矿**——它不能查资源表，也不能判断技能等级够不够。所以：

- 只在玩家开着寻找矿物/草药/鱼群、且学了对应专业时才接受这类命中。
- 小地图上其他带提示的标记（队友、追踪到的 NPC 等）如果被扫到，也会被当作命中显示出来，显示的是它自己的名字。组队时更容易出现。
- 同一时间多个不同矿种无法区分，按“同名”处理：第一个响，之后要等安静期。

这是产品取舍，所以做成了开关。是否默认开启请作者决定。

## 验证

- 模拟：`professions_cursor_scan_test.lua` 新增 16 项（受保护值用一碰就报错的替身：索引、比较、取长度、拼接、转字符串均会抛错），`professions_gather_alerts_test.lua` 新增 8 项。全部 68 组通过。开关关闭时原有锁定断言一条未改。
- 未运行：游戏。

## 实机先做这一步（两分钟）

在动任何别的之前，先确认客户端是否真的允许显示。建一个宏并绑定按键，鼠标**停在小地图的矿点黄点上**时按：

```
/run local f=MFPT or UIParent:CreateFontString(nil,"OVERLAY","GameFontNormalHuge") MFPT=f f:SetPoint("CENTER") local d=C_TooltipInfo.GetMinimapMouseover() local l=d and d.lines and d.lines[1] if l then f:SetText(l.leftText) end
```

- 屏幕中央出现矿名：路是通的，重载带本分支的插件做完整验收（近处/远处新矿、声音、右键、战斗与切图恢复、三项开关）。
- 报错或什么都不显示：把错误原文记下来。备选是让游戏自己的提示框来画——建一个私有 `GameTooltip`，对扫描点调用 `SetMinimapMouseover`，把这个提示框当作提醒窗口，插件完全不经手文本。这条我没有实现。
- 清理：`/run MFPT:SetText("") MFPT:Hide()`。
