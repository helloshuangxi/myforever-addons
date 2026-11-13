# MyForeverChat：离线消息与自建群聊可行性

研究日期：2026-11-06。基线：MyForeverChat 0.8.1，国服《魔兽世界：无限》1.60.1。

静态研究阶段仅核对代码和公开资料。随后用户授权游戏内验证，已在当前国服无限账号成功创建角色社区并发出一条仅社区内的测试消息；双方离线收取仍待验证，详见 [游戏内验证记录](INGAME-VALIDATION.md)。原生 UI 源码参考 Forever 提交 `eac30af597e5aaa43a60f6675ef5fdcea100375f`（1.60.1 / 70790）。有接口或原生 UI 实现，不等于国服账号已开放对应服务。

## 结论与建议

目标必须区分普通角色好友与战网好友。这里重点研究普通角色好友的真正离线留言：**A 发消息时 B 离线；A 随后下线；B 后来上线仍能收到**。本地待发、上线重试不满足这个条件，不能当作该功能的完成结果。

当前结论：公开普通角色 `WHISPER` 接口没有发现离线托管投递能力。最值得继续验证的是**原生角色社区的服务器历史**，它不要求先成为战网好友，但双方必须先加入同一社区。当前账号的角色社区创建与原生文字发送已验证可用，离线历史补收尚未完成。游戏邮件可作为另一种服务器保存的离线文字渠道，但需要邮箱操作。频道群聊可以单独做，不能承诺它同时解决离线留言。

| 路径 | 能实现的体验 | 主要边界 |
| --- | --- | --- |
| 普通角色私聊：本地待发 | 离线时保留内容；发现上线后提醒，点击发送 | 不满足真正离线投递；发件人关闭游戏后插件不工作 |
| 战网好友私聊 | 按原生发送路径尝试留言，由战网处理投递 | App 的离线能力已由暴雪说明；国服无限游戏内投递、重新登录后的历史是否补入插件未实测 |
| 原生自定义频道 | 创建/加入多人文字频道，独立气泡会话、未读和本地历史 | 普通文字接收者不必安装本插件；不保证离线历史、跨服/跨阵营、永久群主或持久成员表 |
| 原生社区 / 战网群组 | 服务开放时可接入成员、频道、服务器消息历史 | 运行时权限和服务门控；不能由源码断言国服无限可用 |
| 自建云端聊天 | 独立账号系统与服务器可保存离线消息和群历史 | 还需要网页或伴随客户端；现有插件没有直连官网聊天后端的受支持实现，工作范围远超聊天 UI |

## 1. 离线消息

### 普通角色密语：没有找到离线托管接口

Forever 原生好友界面对普通角色检查 `info.connected`；普通角色私聊发送只调用 `C_ChatInfo.SendChatMessage(..., "WHISPER", ..., target)`。检查的公开接口中未发现普通角色离线入队、服务器收件箱、历史补拉或收件人送达回执。这些证据支持“现有公开支持的普通密语路径不能实现目标”，不等于声称已经穷尽暴雪内部私有实现。

即使双方都安装本插件，仍然缺少离线期间替双方接收和保管消息的服务；换成 addon 消息或自定义气泡不会凭空增加服务器托管能力。

### 可落地替代：游戏邮箱留言

游戏邮件由服务器保存，因此可以覆盖收件人离线、发送者随后也下线的场景。插件可以把待留的话填入邮件，在用户完成有效邮箱交互后发送；收件人打开邮箱时，再把指定的留言文本展示到插件会话中。没有安装插件的收件人仍能在原生邮件中阅读文字。

这条路不能提供“任意地点发出，好友上线立即在聊天框收到”的体验。官方手册说明发信要使用邮箱；Forever 原生 `MailFrame` 通过 `PlayerInteractionType.MailInfo` 管理有效交互，发送用 `SendMail`，读取用 `GetInboxHeaderInfo` / `GetInboxText`，配合 `MAIL_INBOX_UPDATE` 等事件。本次没有找到脱离有效邮箱交互随时远程发信、拉正文的受支持路径。

如果实现，应命名为“邮箱留言”，明确区分“等待到邮箱寄出”“邮件已寄出”“在邮箱读取的留言”。状态以 `MAIL_SEND_SUCCESS` / `MAIL_FAILED` 等原生结果为准；插件不会因填好了邮件就声称已经寄出。读取和展示不应顺带删除邮件、取出物品或操作金钱；原生邮费、时限和规则以当前客户端为准，不预先写死。

### 可选降级：可靠的待发体验

当前每个会话已有持久化单条 `draft`。可以先增加“上线时提醒我”，收到明确在线状态或对方新消息后展示“有内容待发送”，由用户点击发送。陌生人没有可读取的在线状态时，显示“状态未知”，不能当作离线，也不能承诺及时提醒。

需要多条留言时再增加 `Outbox.lua`：待发条目保存完整目标身份、正文、创建时间、状态和尝试记录，与编辑中的草稿分开。建议状态是“待发 → 本次已提交 → 收到原生回显”以及“失败 / 状态未确认 / 已取消”。其中“收到回显”仍不能标为“对方已读”。

发送服务必须接受明确的会话目标。当前 `Core.lua` 的 `NS.Send(text)` 只读取当前选中会话；不能用后台切换 `selectedId` 的方式发送队列，否则可能发错对象。

其他必要处理：

- 发送前重新确认完整目标；频道编号、战网临时账号 ID 不能跨会话生命周期盲用。
- 超时只是未确认，不自动重复发送；重启后原来的“发送中”也不能悄悄重发。
- 用户可取消待发项；删除会话、清理历史时不得遗失或偷偷投递仍排队的消息。
- `SavedVariablesPerCharacter` 是本机角色存档，不是云端备份；异常退出不能承诺每次输入已落盘。
- 原生发送接口标有限制。第一版发送仍保留用户点击/回车触发，不承诺定时器自动补发。

代码位置：`Core.lua:268` 会话清理、`:300` 草稿/历史结构、`:889` 当前发送入口；`Profiles.lua:415` 在线三态；`UI.lua:373` 附近的内存发送状态；`Main.lua:10` 附近的状态事件。

### 战网好友：必须与普通角色分开

暴雪官方说明 Battle.net App 支持向离线好友留言和查看聊天历史。Forever 原生 Camelot 好友列表也允许对 BNET 好友发起密语，不像普通角色好友一样要求 `connected`；原生编辑框直接调用 `C_BattleNet.SendWhisper`。

因此，插件不宜把“战网好友离线”一律等同于“不能提交”。当前 `Core.lua:894` 同时对 `whisper` 和 `bnet` 执行离线拦截，应在后续实现时拆分策略；账户在线、角色在线、平台是否接受留言也应分开表达。

另外，`Profiles.lua:270` 的 `AccountProfile` 和 `:328` 的 presence map 使用 `gameAccountInfo.isOnline`。这存在把游戏状态用于判断账户可联系性的风险；不能据此断言所有未登录 WoW 的用户都被误判，也不能未经字段核实直接改读假定存在的 `info.isOnline`。它是独立的战网状态问题，不是普通角色离线消息的解决方案。

建议界面：

- 普通角色明确离线：“对方离线，已保留待发内容”。
- 战网好友不在线：“可尝试通过战网留言，实际投递由战网处理”。
- 平台接受请求：“已提交至战网，尚未确认送达”。
- 平台拒绝或结果不明：保留原文并提示原因，不显示发送成功或已读。

本次检查的公开 `C_BattleNet` / 聊天接口没有找到私聊历史分页补拉能力。因此，**App 里能看到离线历史，不代表插件重新登录就能同步完整历史**。这个差异必须在后续验收中分别检查。

## 2. 自建群聊

### 第一版：原生自定义频道

当前插件已把加入的频道映射为独立会话：`Core.lua:730` 同步频道、`:789` 接收频道消息、`:934` 按频道名称重新解析当前编号后发送。气泡、历史、未读、静音、置顶可复用。

建议增加 `Channels.lua` 和“＋ → 创建群聊 / 加入群聊”入口：

1. 输入频道名；创建时可设置原生频道密码。
2. 使用原生创建/加入路径；依据加入事件和频道列表确认成功。
3. 显示独立群会话、当前在线成员，以及“复制加入方式”。原生权限允许时提供邀请入口。
4. 提供离开频道；重新登录时按用户选择恢复加入，并重新核对可用状态。

Forever 原生频道界面使用 `JoinPermanentChannel` 创建/加入、`LeaveChannelByName` 离开，并有密码及邀请弹窗。初版可以优先复用原生管理入口，避免自己模拟权限。

产品应说明：这是基于游戏频道的多人聊天。没有安装插件的人也可以使用原生频道收发普通文字；但插件专属显示、表情扩展或后续历史同步能力可能要求双方安装。频道历史仅包含本机实际收到的消息，不包含离线期间漏掉的内容。频道名、密码及当前在线成员也不能包装成永久的微信群身份与成员库。

不采用循环私聊多人来冒充群聊：它无法提供统一回复流，还会引入重复转发、部分发送成功和频率限制问题。

### 第二版候选：接入原生社区历史

Forever 源码中存在真实 `C_Club` 调用链：发送消息、请求更早的历史、读取消息，并处理历史到达事件。创建入口检查 `C_Club.ShouldAllowClubType`，服务也有 `IsEnabled`、`IsRestricted` 等判断；创建位于原生安全环境界面。

适合先做能力探测：API 存在 → 服务初始化和权限可用 → 已加入社区/频道可读取 → 才启用对应入口。创建优先跳转原生安全界面，不能绕过服务端或安全环境限制。社区关闭时保留频道群聊方案，不显示不可用按钮。

如果可用，可增加 `club:<clubId>:<streamId>` 会话，以原生消息 ID 去重、排序、补拉；离线回补不要对每条旧消息反复弹通知。国服无限是否开放，需要实际账号环境验证，本次没有执行。

对普通角色离线留言而言，这是目前最有希望同时覆盖“多人群聊”和“双方错开上线”的原生路径：双方先加入同一个 **Character 社区**，发送者把文字提交到该社区的流，接收者后来补拉服务器历史，发送者届时可以已经下线。必须明确显示为“社区留言 / 社区群聊”，不能冒充原生角色私聊。

特别注意成员可见范围：不能把原本发给一个好友的私聊正文偷偷转发到多人社区。当前 `CreateStream` 的权限形态不是任意指定一个收件人的私密信箱，因此不能把“建一条流”当成“为每个好友建立私密离线通道”。即使做两人社区，也必须事先完成双方加入和权限确认。

### 历史互传不是离线服务器

插件之间可以研究经允许的 addon 消息通道交换近期历史，但双方需安装插件，而且必须有保存历史的成员上线。这只能称为“成员协助补历史”，无法保证全员下线后消息仍可投递；还需要消息 ID、去重、节流、成员权限和群身份验证，不建议放入第一版。

## 3. 实施与验证顺序

1. 针对真正离线留言，优先验证原生角色社区的服务门控、成员关系及消息历史；未验证前不承诺国服可用。
2. 分别定义“角色密语”“战网私聊”“社区留言”“频道聊天”的身份与投递状态，避免功能混淆。
3. 实现群聊时，社区可用则接入服务器历史；不可用则提供原生频道群聊并写明没有离线历史。
4. 本地待发箱和游戏邮件作为单独的降级方案，由用户选用；不能以它们替代真正离线聊天的验收。

模拟验证应覆盖：未知状态不误拦截、战网与角色策略分开、晚到回显不清掉新草稿、超时和重启不重发、队列不串对象、频道编号变化、加入被拒绝、同名/密码冲突、离开后的发送拦截、社区未开放时回退。

未来实际环境验收要分开记录：普通角色离线、战网在线但未进游戏、战网离线/隐身、收件人恢复在线、发件人退出游戏、插件重载后的历史、频道重新登录及跨服范围。未经用户重新授权，不为这些测试登录游戏。开发完成并发版时，按根目录 `AGENTS.md` 同步版本、下载包、官网与更新记录。

## 资料

- [暴雪 Battle.net 社交功能说明](https://news.blizzard.com/en-us/article/21124623/new-ways-to-connect-through-blizzard-battle-net)：App 离线好友留言、私聊历史和群组功能；不是国服无限插件 API 验收。
- [暴雪 WoW 社区介绍](https://news.blizzard.com/en-us/article/21952590/battle-for-azeroth-preview-world-of-warcraft-communities)：社区聊天及历史；正式服产品介绍不能证明无限服当前开放。
- [Forever 原生好友密语判断](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_FriendsFrame/Camelot/FriendsFrame.lua#L756)
- [Forever 原生聊天发送](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua#L295)
- [Forever 自定义频道创建](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_Channels/Mainline/ChannelFrame.lua#L689)
- [Forever 社区创建门控](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_CommunitiesSecure/CommunitiesAddDialog.lua#L1)
- [Forever 社区消息与历史实现](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_Communities/CommunitiesChatFrame.lua#L118)
- [Forever 社区 API 文档](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/ClubDocumentation.lua)
- [Forever 聊天 API 文档](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua)
- [暴雪官方游戏手册：Postal Service（PDF 第 75 页）](https://bnetcmsus-a.akamaihd.net/cms/template_resource/LO0VQ46XB1281555957773363.pdf)：说明邮件保存与邮箱流程；旧版手册中的时限、价格、阵营限制不作为无限服当前保证。
- [Forever 原生邮件界面](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_MailFrame/MailFrame.lua)
- [Forever 邮件 API 与事件](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/MailInfoDocumentation.lua)

同目录的 `channel-sources.json` 记录本次抓取的频道源码地址与 SHA-256；这些是研究快照，不会进入插件发行包。
