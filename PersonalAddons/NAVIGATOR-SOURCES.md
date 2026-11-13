# 世界向导 0.4.0：Questie 扩展目录与离线参考来源

更新日期：2026-11-13。NPC 搜索由内置精选目录与运行时 Questie 扩展目录组成；任务离线参考单独维护。以下区分用户本机数据库的只读接口接入与发行包内的 pfQuest MIT 数据。参考坐标不是实体实时追踪，数据库和自动化校验不等于 Forever 游戏实测。

## Questie / QuestieDB 运行时扩展（0.4.0）

- 上游：[Questie](https://github.com/Questie/Questie) 与 [QuestieDB](https://github.com/Questie/QuestieDB)。本次核对本机 Questie 12.8.0、QuestieDB 1.1.0 / contract 4，DB build commit `90ab55bdddd6ef6507fe51610b9c26948bbeb637`。
- 等待 `Questie.API.isReady` 后，只读 `LibQuestieDB.Npc.GetAllIds()` 与 `GetAll()` 的本地化姓名、副标题、刷新点、功能标记、阵营友好关系及任务接取／交付字段；`GetRaw(id, "name")` 仅提供英文搜索别名，不用原始坐标替代已修正位置。
- 使用 Questie `ZoneDB:GetUiMapIdByAreaId()` 与客户端 `C_Map.GetMapInfo()`，仅接纳客户端认可的区域地图；百分比坐标转为 0–1，不再次套用旧版地图变换。无效坐标、未知地图和副本区域不进入扩展目的地；即使副本 AreaID 被别名映射到室外区域图，也通过 ZoneDB 的副本判断排除。
- 每 NPC／地图保留一条目录记录；已有精选的同 NPC／地图组合保留旧标识，不重复添加，其他地图的有效记录可以补入。多刷新点依据 `Phasing.IsSpawnVisible()` 选择当前可见参考位置，开始导航后固定所选坐标。
- 不设置 Questie 的语言、修正、缓存策略或用户选项，不将数据库内容保存进本插件的 SavedVariables。只保存收藏／活动目标的稳定标识；分批构建的目录仅驻留本次游戏内存。

扩大 NPC 搜索需要用户已安装并启用兼容的 Questie 与 QuestieDB。缺失、未就绪或读取失败时保留原精选目录并显示状态。实际覆盖随数据版本、客户端识别地图及角色相位变化，不宣称全 NPC、全地图或实时追踪。

QuestieDB 的[许可说明](https://github.com/Questie/QuestieDB/blob/master/LICENSE.md)保留历史贡献授权复杂性的说明；本版没有将其完整数据库、代码、中文表、图标或品牌素材复制进发行 ZIP，也不将它们标注为 pfQuest 的 MIT 内容。以下 MIT 原文仅对应发行包中既有 pfQuest 衍生离线参考。

本地只读审计通过安装的 50 个实际 QuestieDB Lua 文件验证公开接口。与世界向导结合的离线测试成功搜索、收藏并定位治安官杜汉（240）、旅店老板法雷（295）、马迪亚斯·肖尔（332）、伊安·斯托姆（1411）；地图 API 使用模型，不能据此承诺游戏内覆盖数量或实际站位。工具为 `PersonalAddons/tools/audit_navigator_questie.py` 与 `verify_navigator_questie.py`，不随玩家包分发数据库。

## 内置精选目录范围

内置 NPC 用途目录保持 **427 个 NPC / 427 个点位，45 张区域及主城地图**：职业训练师 195、声望与军需官 40、材料商人 109、特殊 NPC 26、常用服务 57。常用服务目前为飞行管理员。阵营分布：联盟 194、部落 165、双方可接洽或依赖声望 68。0.2.2 新增 195 位角色职业训练师时，原有 232 条记录逐字段、逐字节保留；0.3.0 的任务参考不加入这个目录计数。

声望目录包括银色黎明、木喉要塞、海达希亚水元素、冬刃豹训练师、银翼要塞、战歌氏族、阿拉索联军、污染者、雷矛卫队、霜狼氏族、赞达拉部族、塞纳里奥议会、瑟银兄弟会与拉文霍德的精选接洽点。

覆盖东部王国与卡利姆多的经典区域和六座主城。材料商人涵盖炼金、附魔、裁缝、工程、制皮、锻造、商贸及部分施法材料。用途和搜索词是本项目整理的功能描述；没有承诺某件配方或商品当前有库存。声望、阵营、任务前置、等级与训练条件以游戏内为准。“Neutral”仅用于阵营筛选，不代表对所有玩家初始友好。

## 内置离线数据的来源：pfQuest（MIT）

来源键：`pfquest-104f356`。

- [pfQuest 项目](https://github.com/shagu/pfQuest)
- 固定版本：`104f35678ca39ab1fb78b655f815cc7016f5e0c8`
- [NPC 坐标与阵营](https://github.com/shagu/pfQuest/blob/104f35678ca39ab1fb78b655f815cc7016f5e0c8/db/units.lua)
- [中文 NPC 名称](https://github.com/shagu/pfQuest/blob/104f35678ca39ab1fb78b655f815cc7016f5e0c8/db/zhCN/units.lua)
- [英文 NPC 名称](https://github.com/shagu/pfQuest/blob/104f35678ca39ab1fb78b655f815cc7016f5e0c8/db/enUS/units.lua)
- [中文区域名称](https://github.com/shagu/pfQuest/blob/104f35678ca39ab1fb78b655f815cc7016f5e0c8/db/zhCN/zones.lua)
- [上游 MIT 许可](https://github.com/shagu/pfQuest/blob/104f35678ca39ab1fb78b655f815cc7016f5e0c8/LICENSE)

NPC 目录提取上述数据库的精选 NPC 身份、名称、位置和阵营；任务参考另提取下述任务关联、实体名称及参考位置。没有打包完整数据库、上游插件运行代码、品牌素材或个人数据。保留上游 MIT 声明见本文末尾。

## Forever 地图坐标核对

原版地图和 Forever/Classic 地图的边界不完全一致。不能把 pfQuest 的旧百分比坐标直接用于所有 Forever 地图。本次以 QuestieDB 的 Forever 数据作事实核对参考：

- [QuestieDB 固定版本](https://github.com/Questie/QuestieDB/tree/aa1d7e7294596cf50a6fd0946dfae0d969cb9623)
- [Forever 区域到 UiMapID 对照](https://github.com/Questie/QuestieDB/blob/aa1d7e7294596cf50a6fd0946dfae0d969cb9623/support/Forever/Zones/areaIdToUiMapId.lua)：文件注明核对至客户端 `1.60.1.70291`。
- [Forever NPC 参考点](https://github.com/Questie/QuestieDB/blob/aa1d7e7294596cf50a6fd0946dfae0d969cb9623/data/Forever/foreverNpcDB.lua)
- [NPC 字段解释](https://github.com/Questie/QuestieDB/blob/aa1d7e7294596cf50a6fd0946dfae0d969cb9623/src/meta/npcMeta.lua)

原版 AreaID 对应本插件使用的 UiMapID 已逐项核对。赤脊山、东瘟疫之地、莫高雷、暴风城通过两套坐标中大量固定单点 NPC 的位置配对，计算稳健的独立 X/Y 仿射换算。这里只存最终筛选后的参考点，不将上游原表或代码打包。

令 `x,y` 为 pfQuest 的 0–100 百分比坐标，`X,Y` 为本目录使用的地图百分比坐标。以下系数保留六位仅用于审计，生成器使用完整浮点精度：

| 区域 | AreaID → UiMapID | X 换算 | Y 换算 | 配对样本数 | 换算后中位误差 |
| --- | --- | --- | --- | --- | --- |
| 赤脊山 | 44 → 1433 | 0.999856 x − 5.096041 | 0.999806 y + 0.019870 | 69 | 0.052 坐标百分点 |
| 东瘟疫之地 | 139 → 1423 | 0.900000 x − 1.655000 | 0.900351 y − 3.774158 | 62 | 0.047 坐标百分点 |
| 莫高雷 | 215 → 1412 | 0.834510 x + 7.016536 | 0.834343 y + 13.184083 | 77 | 0.040 坐标百分点 |
| 暴风城 | 1519 → 1453 | 0.773631 x + 19.686105 | 0.773814 y + 24.435567 | 253 | 0.046 坐标百分点 |

误差定义是 `abs(X−参考X) + abs(Y−参考Y)`。它是坐标系换算的数据库对照误差，不能解释为 NPC 实际站位精度或游戏验证。换算模型有异常样本，因此在所有地区对每个发布点再次核对：只有同一 AreaID、同一 NPC ID，且与 Forever 参考点的误差不超过 **0.65 坐标百分点**才进入目录。旧资料中的邻区投影、重复显示点、坐标漂移或不明确点直接舍弃。发布坐标保留五位小数仅为存储需要，不表示厘米级精确。

核对示例：米兰达 NPC 11536 的旧东瘟疫坐标 `(81.6,60.0)` 换算为 `(71.785,50.247)`；玛丽亚·卢米尔 NPC 1313 的旧暴风城坐标 `(46.8,79.1)` 换算为约 `(55.891,85.644)`。它们与上述 Forever 数据的对应地图坐标相符。

QuestieDB 的许可说明明确保留了历史贡献授权复杂性的说明，因此本次没有复制其插件代码、中文名称表或完整数据表进行再发布。这里用它核对少量客观字段、地图关系和坐标系差异，内置离线参考的主要来源与署名仍为 pfQuest。0.4.0 的运行时扩展另见上文：读取已安装数据库的可定位记录加入搜索；数据库为扩展功能所需依赖，不随本包附送。

## 九职业训练师筛选（0.2.2）

新增“职业训练师”用途，按战士、圣骑士、猎人、盗贼、牧师、萨满祭司、法师、术士、德鲁伊细分。这里指角色职业技能训练 NPC，排除宠物训练师和商业专业训练师，不根据角色等级推荐具体技能。

名称、英文名、原版坐标及阵营继续来自上述固定版本的 pfQuest MIT 数据。候选身份使用 Forever 参考表中的精确职业训练师称号与 trainer 标志交叉核对；只含职业名称但缺少训练师标志的 NPC 不进入目录。每个点继续使用同一地图坐标换算及不超过 0.65 坐标百分点的核对门槛；没有明确阵营、缺少可靠位置或坐标漂移的候选拒绝收录。没有复制完整参考表、其中文名表或插件代码到玩家发行包。

本次核对 235 个精确职业称号候选，排除 36 个缺少训练师标志的 NPC、2 个无明确阵营的候选（NPC 1411、12042）和 2 个坐标不一致的候选（NPC 4606、4607），最终新增 195 位训练师，每位保留一个可靠参考点。新增阵营分布为联盟 105、部落 90，没有将未知阵营默认为中立。

| 角色职业 | NPC／点位数 |
| --- | ---: |
| 战士 | 32 |
| 圣骑士 | 11 |
| 猎人 | 29 |
| 盗贼 | 24 |
| 牧师 | 28 |
| 萨满祭司 | 11 |
| 法师 | 24 |
| 术士 | 21 |
| 德鲁伊 | 15 |
| 合计 | 195 |

新增点分布在原有地图中的 19 张：六座主城内 114 点、新手区域 68 点、其他野外区域 13 点。因此本版总覆盖仍为 45 张地图，没有把新增点位误报为新增地图。

训练师身份、坐标系和阵营的数据库核对不等同于游戏实测。训练等级、费用、可学法术、任务条件与 Forever 站位以当前游戏为准，新增目录没有承诺玩家能与每一位训练师交互。

## 任务目标与交付参考（0.3.0）

任务参考继续使用来源键 `pfquest-104f356` 和同一固定 MIT 版本。新增使用以下原始字段，另复用已有 NPC 名称、位置和区域名称：

- [任务关系与目标 ID：db/quests.lua](https://github.com/shagu/pfQuest/blob/104f35678ca39ab1fb78b655f815cc7016f5e0c8/db/quests.lua)
- [物品来源：db/items.lua](https://github.com/shagu/pfQuest/blob/104f35678ca39ab1fb78b655f815cc7016f5e0c8/db/items.lua) 与 [间接掉落表：db/refloot.lua](https://github.com/shagu/pfQuest/blob/104f35678ca39ab1fb78b655f815cc7016f5e0c8/db/refloot.lua)
- [任务物件：db/objects.lua](https://github.com/shagu/pfQuest/blob/104f35678ca39ab1fb78b655f815cc7016f5e0c8/db/objects.lua) 与 [区域触发点：db/areatrigger.lua](https://github.com/shagu/pfQuest/blob/104f35678ca39ab1fb78b655f815cc7016f5e0c8/db/areatrigger.lua)
- [中文任务名称：db/zhCN/quests.lua](https://github.com/shagu/pfQuest/blob/104f35678ca39ab1fb78b655f815cc7016f5e0c8/db/zhCN/quests.lua)，中文物品、物件名称 `db/zhCN/items.lua`、`db/zhCN/objects.lua`，英文名称 `db/enUS/items.lua`、`db/enUS/objects.lua`。

不复制上游完整任务说明、插件运行代码或品牌素材。生成器为 `PersonalAddons/research/navigator/build_quest_catalog.py`，筛选统计、源文件地址与校验值记录在同目录 `quest-catalog-audit.json`。这些调研原表和审计文件不进入玩家发行包，发行包保留生成后的任务参考及本来源声明。

| 任务参考范围 | 数量与含义 |
| --- | --- |
| 有位置参考的任务 | 3,817 个；至少有一处可定位目标或交付参考 |
| 有交付参考的任务 | 3,762 个 |
| 有目标参考的任务 | 1,365 个；至少一项 NPC、物品来源、物件或区域目标可定位 |
| 实体坐标样本 | 57,775 个；NPC／物件的参考出现点，不是新增 NPC 目录数 |
| 区域目标参考 | 36 个触发点，涉及 29 个任务 |
| 参考地图 | 46 张，与 NPC 目录的 45 张分开统计 |

同一任务可能同时计入目标与交付两项，数量不能相加。一个任务有参考不表示它的每项目标都有坐标；也不表示能自动做完这些任务。物品来源包括掉落 NPC、容器和商人，没有保证掉率、库存、任务阶段或实际可交互性。

任务关联先按同一任务 ID、目标类型和实体 ID，与固定版本的 [Forever 任务参考](https://github.com/Questie/QuestieDB/blob/aa1d7e7294596cf50a6fd0946dfae0d969cb9623/data/Forever/foreverQuestDB.lua) 的目标／交付关系交叉核对。NPC／物件位置再要求同实体 ID、同 AreaID；旧地图使用上文仿射换算，与 [Forever 物件参考](https://github.com/Questie/QuestieDB/blob/aa1d7e7294596cf50a6fd0946dfae0d969cb9623/data/Forever/foreverObjectDB.lua) 或 NPC 参考的误差不超过 0.65 坐标百分点。无法核对的关系、邻区投影和坐标直接舍弃，不为达到数量而截取出现点。

区域目标只在同任务 ID 的触发点、同 AreaID 和位置可相互核对时收录；参考表没有暴露相同的 AreaTrigger ID，因此不宣称这类点完成了同实体 ID 核对。36 个区域点是任务触发位置参考，没有用任意区域中心或交付位置代替。不导入未经核对的副本内部坐标、使用物品／法术交互链或完整任务描述。

运行时优先使用客户端给出的任务下一站。离线目标不按表内顺序与原生进度行对应：只在原生目标文字能明确匹配实体或物品名称时识别该项进度，明确完成的目标可跳过；没有进度、名称歧义或无法对应时提示玩家选择并核对任务文字。任务完成后重新查询交付参考，不自动按离线顺序推进任务链。这部分离线任务参考的物理双击、真实任务状态、站位和实际行程仍未完成游戏内实测。

## 局限与维护

- Forever 新增、重做或有特殊分层的 NPC 可能不在离线目录中，或位置、任务、商品已经变化。
- 内置精选与扩展目的地使用区域地图上的参考位置。没有伪造黑石深渊、厄运之槌等副本内部的精确坐标；例如黑石深渊内的瑟银兄弟会商人罗克图斯不在首批导航点中。
- 飞行管理员目录不表示已解锁航点，也不保证可直接飞到目的地。
- 附近到达判定只基于平面距离，无法判断楼层、洞穴、围墙、敌对守卫、任务条件。
- 坐标搜索与地图箭头是方向参考，不是道路寻路；不能视为完整的步行、船班或飞行路线图。
- 后续补充点位应优先来自当前 Forever API 或明确可再使用的公开源，继续记录版本、地图、来源和真实验证范围。新增 NPC 不应仅凭名称推测坐标。

本次本地审计素材和提取脚本在 `PersonalAddons/research/navigator/`；这些大型参考原表和调研文件不应进入玩家发行 ZIP。发行包应包含本来源说明，以保留 MIT 声明。

## pfQuest MIT notice（原文）

MIT License

Copyright (c) 2017-2021 Eric Mauser (Shagu)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
