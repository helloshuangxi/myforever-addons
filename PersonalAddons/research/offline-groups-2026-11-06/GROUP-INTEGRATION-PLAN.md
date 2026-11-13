# MyForeverChat 角色社区群聊：最小接入与模块合同

日期：2026-11-06。目标候选版本：0.9.0 试用版。本文先定义实现与验收，不代表已发布。

## 本轮范围和证据

优先完成多人群聊，不扩展离线私聊、邮件或后台待发队列。底层采用无限服已验证的原生 **Character 社区**；不把普通公共频道、战网群组、公会混作同一种群。

主线程已在当前客户端观察到：创建角色社区、原生窗口发消息并回显，NO61 加入后成员数 2/2 在线并回复。只读探针确认 `IsEnabled()==true`、测试社区 `clubType==1`、一个流、一个消息缓存范围、最新 `GetMessageInfo` 可读，发送/历史接口存在。插件已列出该群并读到历史身份、方向与时间；插件回车提交也已在原生频道正确回显。实机发现正文由 `|Kw数字|k` 原生句柄承载，旧 UI 转义后会显示字面句柄；当前显示与提交备份补丁仍待重载实机验收。此版不以双方离线收取为交付前置条件，也不承诺普通密语离线投递。

## 用户操作

1. 插件提供「群聊」入口，显示已加入的角色社区及其文字流。会话标题为“社区名 · 流名”，一个流一条会话，避免同名社区或多个流串聊。
2. 点击条目选择会话并读取最近 60 条可读的服务器消息；空列表提供原生创建/加入入口。
3. 「创建 / 加入群聊」与「原生社区」打开原生公会与社区窗口。创建、邀请码、邀请、退出、成员及权限管理由原生界面完成；不在插件中直接代调用受限创建接口。新建选择《魔兽世界》角色社区。
4. 输入框由用户点击/回车发送。暂时不可用、退群、无发言权限或同步 API 调用失败时保留草稿。调用成功仅显示“已提交，投递由游戏处理”，不宣称送达；Core 保存该群最近一次提交的明文备份，UI 才清空仍相同的输入。可点「找回上次发送」恢复到空草稿，已有新草稿时拒绝覆盖，恢复不会自动发送。群聊不建立待发计时器，也不以任何消息事件确认或清除草稿。
5. 免打扰、未读、置顶和本机清理沿用插件语义。清理本机记录不删除服务器消息；Core 保存清理水位，避免下一次自动补拉立即恢复用户刚清理的内容。更早历史在原生社区查看。

## 分工及依赖

| 文件 / 负责方 | 内容 |
| --- | --- |
| `Communities.lua` / build_site | C_Club 门控、Character 群/流列表、原生入口、历史读取、事件规范化、安全发送；不直接写 `NS.db` |
| `Core.lua` / deploy_audit | `kind="club"` 会话及恢复、容量、草稿、未读、稳定消息 ID 去重/排序、清理水位、发送路由、最近提交备份与恢复 |
| `Main.lua` / deploy_audit | 登录同步及社区事件分发；普通聊天事件继续使用现有路径 |
| `MyForeverChat.toc` / deploy_audit | `Communities.lua` 在 Core 之后、UI 之前加载 |
| `UI.lua` / offline_flow_map | 群入口与列表、会话选择、状态文案、原生管理入口、可信原生正文绘制、提交提示与找回上次发送 |
| `tests/chat_communities_test.lua` / build_site | 独立传输层模拟检查；Core/UI 分别补集成检查 |

现有 Core 的 `DynamicKind`、`InitDB`、`RestoreConversation`、`GetConversations`、`Send` 需要扩展 club 类型；不能只在运行时塞入未知类型，否则重载后会丢失会话。不得借用普通频道的 `channelIndex` 或修改 `selectedId` 后代发消息。

## 固定合同（全部使用点调用）

| 调用 | 行为 / 返回 |
| --- | --- |
| `NS.Communities.Refresh()` | 刷新并返回 `entries, serviceNotice`；透过 Upsert 回调更新 Core，失效条目标为不可发送，保留本机数据 |
| `GetEntries()` / `GetEntry(id)` | 已加入群流列表 / 按稳定 ID 查找 |
| `GetStatus(id)` | `{loading, hasMore, notice}`；`hasMore` 仅提示原生还有更早历史 |
| `Open(id)` | 读取缓存最近 60 条；缓存缺失才请求历史，返回 `bool, notice` |
| `LoadOlder(id)` | MVP 返回 false 与“到原生社区查看更早历史”提示，不提供误导性的本机分页 |
| `Send(id, text)` | 重新核对显式群与流身份、订阅、权限，同步调用原生发送，返回 `bool, notice`；不写发送记录、不清草稿、不重试 |
| `OpenNative(id 或 nil)` | 非战斗时加载并展示原生社区；传 id 时选中对应群流；没有直接创建/邀请/入群副作用 |
| `GetLiveSequence()` | 当前运行期的实时消息序号；仅保留事件来源信息，UI 不用它确认群消息送达 |
| `NativeContent(message)` | 仅返回本次原生读取且带瞬时授权标记的完整 `|Kw数字|k` 句柄；不解码、不枚举、不输出明文 |
| `HandleEvent(event, ...)` / `Events` | Main 注册 Events；返回 true 表示已消费该社区事件 |

Core 提供的回调：

```lua
NS.UpsertCommunity(meta, passive) -- passive=true 仅更新已存在会话；否则走容量限制的创建
NS.StoreCommunityMessage(id, message, mode) -- mode: live / history / update
NS.RestoreLastCommunitySubmission(id) -- 只恢复本群最近提交到空草稿，不自动发送
```

`meta`：`id="club:<clubId>:<streamId>"`、`kind="club"`、`target=id`、`title`、`clubId`、`streamId`、`clubName`、`streamName`、可选 `memberCount`、`available`。原生 ID 保留原类型；十进制字符串不转为浮点数字。列表刷新只被动更新现有会话；超过 30 个已加入群流也只保留在 entries 中，不挤掉普通私聊。主动 Open 或可读取的实时新消息才申请活动会话；后台历史和编辑不创建会话。

`message`：`id="clubmsg:<epoch>:<position>"`、`text`、`author`、`outgoing`、`time`（秒）、`chatType="COMMUNITIES_CHANNEL"`、`profile`、`clubEpoch`、`clubPosition`；另有 `communityEdited`、`communityDeleted`、`communityAuthorKnown`、`communityNativeContent`。无可读作者名时仅显示“社区成员”，不可把占位文字当私聊对象。

`communityLive`、`communitySequence` 与 `communityNativeContent` 都是当前运行期标记，**不从存档恢复**。群正文是原生渲染句柄，不能与输入明文比较来确认发送。UI 仅对 club 会话调用 `NativeContent`，正文、侧栏与通知把可信完整句柄直接交给 FontString，不截断、不转义；普通聊天继续使用原有清理路径。复制入口引导用户使用原生社区，不导出句柄。重载时旧正文句柄变成“[群消息待重新读取]”，旧作者句柄变成不可私聊的“社区成员”；重新打开群后，从原生缓存取回的新句柄按稳定消息 ID 替换占位。Core 不把相同正文当重复：不同 ID 的同文消息是不同消息。历史、编辑不增加未读、不弹泡泡；实时自发消息也不增加未读。

`latestSubmission={text,time}` 仅保存用户输入且同步提交成功的最近一条文本，不是服务器投递回执或待发队列。提交失败不覆盖上一条备份；每群独立，备份可随本机存档重载恢复。UI 在成功提交后清空仍匹配本次原输入的草稿，不等待自发消息事件；新输入、其他群草稿及之后到来的历史/实时消息互不覆盖。

## 原生 API 对应

以下签名来自固定 Forever 源码提交 `eac30af597e5aaa43a60f6675ef5fdcea100375f`，运行时继续检查接口与公开可读值。

- 列表：`GetSubscribedClubs()`，仅保留 `Enum.ClubType.Character`；`GetStreams(clubId)`；`FocusCommunityStreams()`；`IsSubscribedToStream(clubId, streamId)`。
- 服务：`IsEnabled()` 返回布尔；`IsRestricted()` 返回枚举，**0 才表示未受限**，不是布尔。
- 发送：`GetStreamInfo`、`IsAccountMuted`、`GetClubPrivileges().canCreateMessage`，管理员专属流结合 `GetMemberInfoForSelf().role`；`C_SocialRestrictions.IsChatDisabled` 存在时遵守其结果。最后调用 `SendMessage(clubId, streamId, text)`，该 API 无返回值。
- 历史：`GetMessageRanges` 取最后有效范围，`GetMessagesBefore(clubId, streamId, newestId, 60)` **包含边界消息**。无缓存时 `RequestMoreMessagesBefore(clubId, streamId, nil, 60)`，返回值表示是否已经缓存，并非投递结果。异步返回由 `CLUB_MESSAGE_HISTORY_RECEIVED` 驱动。
- 实时/编辑：`CLUB_MESSAGE_ADDED` / `CLUB_MESSAGE_UPDATED` 的参数是 `(clubId, streamId, messageId)`，不是普通 `CHAT_MSG_*` 的正文参数表。使用 `GetMessageInfo` 读取，并利用过滤后的 `GetMessagesBefore(..., messageId, 1)` 尊重原生忽略名单。删除更新替换成删除占位，不继续展示原正文。
- `CLUB_ERROR` 只有 action/error/clubType，没有 clubId/streamId，不能错误归因给某次群提交，也不能自动重发。仅提供一般性原生限制提示；同步提交失败保留草稿，提交后的异步失败由原生游戏提示，用户可主动找回最近提交。
- 身份/权限变化：`INITIAL_CLUBS_LOADED`、`CLUB_ADDED/REMOVED/UPDATED`、`CLUB_STREAMS_LOADED/ADDED/REMOVED/UPDATED/SUBSCRIBED/UNSUBSCRIBED`、`CLUB_SELF_MEMBER_ROLE_UPDATED` 触发列表刷新。

首版不使用全局 `SetAutoAdvanceStreamViewMarker`，避免后台读取历史把原生其他群标成已读；本插件未读由 Core 管理。不宣称已读回执、跨阵营范围或原生服务器历史的永久保存期限。

## 验收顺序

1. 模拟：角色/战网/公会类型隔离；大整数 ID；受限值；权限变化；明确目标发送；history/live/update 区分；重叠消息去重；删除、清理水位；同文新消息、跨群草稿和未读；可信句柄直绘、普通聊天不旁路清理、重载清除句柄授权；提交成功备份、失败不清、恢复不覆盖新草稿且不发送。
2. 实机：已加入的两位角色在同一个流，用 MyForeverChat 发送、原生对端接收并回复；插件显示双方实际正文与正确群名。确认发送只提示提交，随后新写草稿不被任何回显清空，主动找回上次发送不重发。重载后选回同一群，原生正文重新读取、历史不重复、提交备份可恢复。最后验证未读/免打扰、原生创建加入入口、退群后不能发送。
3. 发布：完成后由主线程统一版本、包、下载站和验证范围；候选开发与模拟通过不能写成群聊实机验证完成。

## 来源

- [C_Club API 与结构](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/ClubDocumentation.lua)
- [原生消息与历史调用](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_Communities/CommunitiesChatFrame.lua)
- [原生流选择及窗口入口](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_Communities/CommunitiesFrame.lua)
- [原生创建/加入安全界面](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_CommunitiesSecure/CommunitiesAddDialog.lua)
- [本地实机证据](INGAME-VALIDATION.md)；本文的新增探针结果由主线程当前会话反馈，详细实机结果以主线程最终验收记录为准。
