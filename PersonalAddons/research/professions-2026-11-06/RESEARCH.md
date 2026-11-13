# Forever 商业技能 API 核对（2026-11-06）

来源为 Blizzard 原生 UI 的 Gethe/wow-ui-source forever 镜像；逐文件 URL 与 SHA-256 见 SOURCES.json。本目录仅供研究，不随插件分发。未进行游戏内验证。

- 当前原生 Camelot 专业总览调用 GetProfessions()、GetProfessionInfo(index)，其结果覆盖角色的主专业、急救、钓鱼、烹饪。GetProfessions 的槽位可能含 nil，因此应 select 遍历全部返回值，不能 ipairs({GetProfessions()})。
- C_SkillInfo.GetSkillLineInfoByID(id) 提供 rank/maxRank/tempPoints/modifier 等实时字段；按明确专业 ID 读取可免展开技能页。现代 GetSkillLineInfo(index) 提供表格，而旧全局版本返回多值。
- TradeSkillRecipeInfo.relativeDifficulty: 0=Optimal 橙，1=Medium 黄，2=Easy 绿，3=Trivial 灰。训练建议还需 learned、canSkillUp、disabled；numSkillUps 是潜在提升点数，不是成功概率。isGatheringRecipe 标识采集记录；原生明确将采矿、草药、剥皮、钓鱼作为 Gathering。
- C_TradeSkillUI.GetRecipeSchematic(recipeID,false) 的 reagentSlotSchematics 记录 required/quantityRequired/reagents；每个 reagents 元素含 itemID 或 currencyID。同一槽位多个 reagent 是可替代材料，不应全部视作必需。required=false 的可选槽不计入必需材料。
- 原生 GenerateCraftingDataProvider 使用 GetFilteredRecipeIDs()，其列表受原生过滤器影响。GetAllRecipeIDs 没有出现在此版本生成文档或已下载原生调用中；实现应 feature-detect，不能假定必有。只能取得过滤列表时，应明确数据不完整，合并已见配方，避免清空自己的完整缓存或改动玩家过滤器。
- 枚举 API 是当前专业数据源；尚无证据支持无需打开专业即可枚举所有专业的全部配方。可缓存各专业，首次提示手动打开一次；OpenTradeSkill(skillLineID) / OpenRecipe(recipeID) 可由用户按钮打开。GetRecipeInfo 已知 ID 与材料示意接口可以由追踪器使用，但跨专业难度即时刷新需实测。
- 扫描前排除 IsTradeSkillLinked / IsTradeSkillGuild / IsTradeSkillGuildMember / IsNPCCrafting，避免将别人的配方当成本角色配方。等待 IsTradeSkillReady 并响应 TRADE_SKILL_LIST_UPDATE / TRADE_SKILL_DATA_SOURCE_CHANGED / TRADE_SKILL_DETAILS_UPDATE；数据源更换期间不得写入旧专业。
- 技能点监听 SKILL_LINES_CHANGED；新配方 NEW_RECIPE_LEARNED；材料数量 BAG_UPDATE_DELAYED；物品名异步 ITEM_DATA_LOAD_RESULT。技能 rank 变动而配方难度无法实时重读时，应标明缓存待更新，不能沿用旧颜色当作实况。
- 用户“距下一级”可可靠显示当前 rank 至下一技能点和当前 maxRank 差额；技能增点通常不暴露内部经验进度，不应伪造“还做 N 次必升”。rank 达 maxRank 时提醒提升技能上限。

## 打开界面与额外审查

原生 Blizzard_FrameXMLUtil/ProfessionsUtil.lua:78–102 的 OpenProfessionFrameToRecipe 先调用 ProfessionsFrame_LoadUI，再调用 C_TradeSkillUI.OpenTradeSkill(tradeSkillID)，无需手动 Show。Blizzard_Professions/Blizzard_ProfessionsFrame.lua:210 的 TRADE_SKILL_SHOW 路径处理 BookPage/CraftingPage。原生 GenerateCraftingDataProvider 在不是跨专业搜索时还调用 IsRecipeInSkillLine(recipeID,professionID)，插件逐条校验归属可避免混入其它专业记录。
