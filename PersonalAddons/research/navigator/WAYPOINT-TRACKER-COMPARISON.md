# 世界向导与 Waypoint Tracker 对比

核对日期：2026-11-08。用户已明确对标 **Waypoint Tracker**，本文不讨论 Waypoint UI。对方源码只作只读研究，未安装、执行、复制其代码或数据库。

本表以已发布的 [MyForeverNavigator 0.1.2 包](../../dist/MyForeverNavigator-0.1.2-Trial.zip) 为改进前基线；“我们 0.2.1 已实现”包含 0.2.0 的导航改进和 0.2.1 的分类界面。实现状态与验证范围分别记录，本文不据此判断 0.2.1 的公网发布状态。Waypoint Tracker 固定审阅提交为 [`345de210d6535b5a4fdffda3e251ca27ed3ee9b8`](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/tree/345de210d6535b5a4fdffda3e251ca27ed3ee9b8)，TOC 版本 1.2.3。

## 差异与本轮取舍

| 方面 | 我们 0.1.2 已有 | Waypoint Tracker 已有 | 我们 0.2.1 已实现 |
| --- | --- | --- | --- |
| 找 NPC | 232 个精选点位，45 张经典区域／主城地图；声望军需官、材料、特殊 NPC、飞行服务四类；收藏与自定义点 | NPC、敌人、任务、物体、物品、城镇和飞行点搜索，兼有模糊匹配、最近 spawn、游戏内观察与纠错 | 已有目录按可计算的直线距离排序；用途和二级分类可继续细分、分页选择；NPC 结果与个人地点分开，目录仍为 232 点 |
| 最近服务 | 常用服务目前主要是 57 个飞行管理员，没有完整邮箱／银行等目录 | Nearest 提供邮箱、旅店、飞行管理员、修理、银行、拍卖行六类 | 只对已收录点位做最近推荐；缺数据的服务不编造结果 |
| 开始导航 | 自有方向框；显式“查看地图”才设置原生航点 | 活动点可同步原生 pin，地图／小地图 pin、箭头协作 | 开始导航即设置原生追踪；停止仅取消自己仍拥有的追踪，保留共享地图标记 |
| 路上显示 | 拖动方向框，米／公里，跨洲文字交通参考；说明较长 | 不拦鼠标的 3D 箭头与独立文字，远近颜色、可调大小透明度、ETA、Edit Mode | 紧凑 HUD、独立距离与一次性到达文字提示；不声称做出同款 3D 世界标记 |
| 坐标输入与个人地点 | `/mynav go 地图ID X Y 名称`；底部四项输入 | `/way [区域或 #UiMapID] X Y [名称]`、名字搜索、地图 Ctrl 右键、当前位置快捷入口 | 通过 `/mynav way` 或 `/mynav /way` 接受当前区域坐标／#地图ID／逗号格式，不注册全局 `/way`；新增地点、保存当前位置和导入地图标记集中在“我的地点” |
| 多点与路线 | 单个活动目的地，收藏不是路线队列 | 多航点、按最近点切换；路线按站点顺序，支持录制／编辑／文本导入导出；Real routes 为 beta | 不在本轮宣称完成多点队列或道路寻路，后续独立实现与验收 |

这些差异来自对方的 [Find／输入／最近服务说明](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/README.md)、[原生 pin 与多点实现](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/WaypointTracker/Waypoints.lua)、[显示实现](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/WaypointTracker/Arrow.lua) 与 [1.2.x 变化记录](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/CHANGELOG.md)。它明显覆盖更多场景；我们的可保留重点是声望／军需官／材料商人分类、中文用途说明，以及自有管理器的发行与更新流程。

## 0.2.1 分类界面

界面分为“找 NPC”“我的地点”“当前导航”三页，每页处理一类操作：

- **找 NPC**：在“全部”和声望、材料、特殊 NPC、常用服务四类用途间切换，再选二级分类。声望按 14 个阵营细分，材料按 8 类用途细分，特殊 NPC 按坐骑、武器训练、专业进阶、其他任务 4 类细分，常用服务目前只有飞行管理员 1 类。分类按钮和结果均可分页，切换分类保留搜索词；复合用途商人可出现在多个适用材料分类中。二级分类数量来自现有目录，不代表新增或已逐个实测的 NPC。
- **我的地点**：收藏地点与自定义地点独立筛选，默认进入收藏。新增表单默认收起，只在本页展开；保存当前位置、导入地图标记也集中在这里。保存后切到自定义地点并选中新记录；导入地图标记后开始导航。个人地点不会混入“找 NPC”的结果，NPC 的用途、阵营和地图筛选也不会误筛个人地点。
- **当前导航**：独立显示活动目标与实时状态，提供地图和停止导航操作；无活动目标时显示空状态。紧凑 HUD 继续提供轻量实时距离／到达反馈。

筛选区与详情中的“更多资料”默认收起，需要时再展开，减少首屏同时出现的按钮和长说明。实现见 [UI.lua](../../../_forever_/Interface/AddOns/MyForeverNavigator/UI.lua)、[分类规则](../../../_forever_/Interface/AddOns/MyForeverNavigator/Classification.lua) 与 [搜索逻辑](../../../_forever_/Interface/AddOns/MyForeverNavigator/Core.lua)。

## 数据来源、规模与许可

对方数据库是独立的 `WaypointTracker_Data` 按需加载插件。它结合 Classic 原始数据、整理后的 Forever 数据、客户端表以及玩家观察／纠错；观察和共享层优先于静态资料。不能把所有静态条目都当成当前位置已验证、可导航的 NPC。[数据库 TOC](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/WaypointTracker_Data/WaypointTracker_Data.toc)

只读统计固定提交中数据文本的非空记录行：Classic 基础层有 **6,712 条单位、6,212 条物体、4,253 条任务、1,199 条物品**。这些是基础原始记录，单位同时含友好 NPC 和敌人；其他覆盖层会重叠，**不能相加当作 Find 最终独立条目数**。[基础数据文件](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/WaypointTracker_Data/Data.lua)

项目代码为 MIT；其数据许可文件列出 All The Things 与 pfQuest 的 MIT 声明。来源审计另记录 pfQuest 固定提交 `104f35678ca39ab1fb78b655f815cc7016f5e0c8`、ATT 固定提交 `ec1aa307198d92d18c601ae2c9338a67b71e7d6b` 和客户端表。当前 `Client.lua` 标记 build `1.60.1.70862`；审计文档的一些旧 fixture 仍标记 70338，两个范围不能混说为全部最新。我们未据此复制数据库，后续扩容仍要逐项维护来源与许可。[项目许可](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/LICENSE)、[第三方许可](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/WaypointTracker_Data/THIRD-PARTY-LICENSES.txt)、[数据审计](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/docs/data-audit.md)、[客户端数据头](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/WaypointTracker_Data/Client.lua)

## 导航行为核实

- **ETA**：普通直线导航每约 0.5 秒采样到目标距离的缩短速度，平滑后仅在接近速度超过 0.5 码／秒时显示估算；是当前行进趋势估算，不是道路最短用时承诺。travel 模式另有行程估算。[Arrow.lua](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/WaypointTracker/Arrow.lua)
- **到达与队列**：到达距离可设置，声音／移除点／转向下一点受玩家选项控制；普通列表可找最近点，路线用自己的下一站钩子维持顺序。站在当前位置新建的点会先等玩家离开，不会立即连续触发到达。[Waypoints.lua](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/WaypointTracker/Waypoints.lua)
- **道路／交通**：1.2.x 的 Real routes 是 beta，会利用交通网络和学过的飞行点，并涉及船、飞艇、地铁、炉石与传送；它不是纯直线箭头，但作者也列出了未实测路段与交通时序，不保证完整最优路线。[CHANGELOG.md](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/CHANGELOG.md)、[routing-behaviour.md](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/docs/routing-behaviour.md)
- **外部航点**：它实现 TomTom 兼容桥；`AddWaypoint` 接受 UiMapID 与 0–1 坐标，支持标题、是否持久保存、是否激活、来源、到达距离和回调。现有 TomTom 或其他箭头提供者在场时退让；`/way` 等别名也不抢现有提供者。文本路线导入与这个 API 是两种入口。[AddonBridge.lua](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/WaypointTracker/AddonBridge.lua)、[Slash.lua](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/WaypointTracker/Slash.lua)
- **兼容性证据**：主插件和数据插件的 TOC 均为 Interface 16001、版本 1.2.3；更新记录明确客户端 70862。此处只确认作者声明与源码匹配，未在我们的客户端安装运行对方插件。[主插件 TOC](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/345de210d6535b5a4fdffda3e251ca27ed3ee9b8/WaypointTracker/WaypointTracker.toc)

## 我们的验收边界

0.2.0 的已有点位最近距离排序、开始即原生追踪、紧凑 HUD、便捷坐标输入、到达反馈均已保留；0.2.1 在此基础上完成上面的分类界面。7 个 Lua 文件语法检查和 7 组模拟检查通过，其中导航检查通过 175 项断言、界面检查通过 274 项断言。

真实客户端通过 `/run` 调用实际控件的 `Click` 处理器，验证了用途切换、“木喉熊怪”得到 3 条结果、筛选展开、个人地点新增表单，以及当前导航的空／活动状态页；这属于客户端控件处理器验证，**不是鼠标点击测试**。活动导航启用了原生追踪并显示 89 米距离；测试结束停止导航，并恢复了测试前的原生地图标记与追踪。不能将这一恢复步骤表述为“停止导航会自动恢复此前标记”。

NPC 目前站位、箭头朝向、实际行程仍未验证。路线规划、ETA、多点队列、数据库扩容、物品／任务关联及自动学习仍未实现，不能因本次调研或分类界面完成而写成我们的现有功能。
