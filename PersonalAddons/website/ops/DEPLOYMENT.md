# 我的无限双插件官网部署

2026-11-06 只读核验：Porkbun 权威 DNS 的 `afabiaoge.xyz` 与 `www.afabiaoge.xyz` 都指向现有新加坡服务器；无 AAAA 与 CAA 冲突。现有 Caddy 仅承担聊天网站与工作台各域名，主域尚无站点配置。根分区空闲约 8 GiB。现有聊天健康接口通过。

## 发布结构

- 本地发布目录：`../public`，仅放审计通过的公开网站内容与插件 ZIP。
- 服务器：`/var/www/myforeverchat/releases/<UTC timestamp>`。
- 入口：`/var/www/myforeverchat/current`，原子符号链接切换。
- 静态容器：`myforeverchat-site`，复用已存在的 `caddy:2.8-alpine` 镜像；只读文件系统、无宿主机端口、新增内存上限 96 MiB、`unless-stopped` 自动恢复。
- 主 Caddy 配置只添加标记块，既有 chat/studio 路由保留；`www` 永久跳转主域，HTTPS 自动签发。
- 私有配置备份与验签日志：`/var/www/myforeverchat/backups/<timestamp>`；不在公开站点根路径下。

## 执行

```bash
python3 ops/deploy.py --public public
python3 ops/deploy.py --public public --execute
```

第一条只检查目录与 ZIP 路径，没有远程写入。第二条上传白名单目录，验证 Caddy 配置，切换版本，热加载，检查原聊天健康、主域 TLS 与网页内容、www 跳转。失败则恢复入口与 Caddy 配置；初次创建的静态容器也会清除。不会拉取新镜像或重启现有服务。

发布前须逐张审查截图脱敏与下载包内容；脚本仅能阻止常见私密路径，不能替代内容审计。`ops`、源截图、原始聊天数据不能放入 public。

## 回滚

查对应 `backups/<timestamp>/previous.json` 中的旧 current 目标，恢复符号链接；将备份 Caddyfile **原位写回** `/var/www/linzihan-v3/Caddyfile`，再 `docker exec linzihan-v3-caddy-1 caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile`。必须原位写回，不能替换 inode，因为容器绑定挂载单文件。回滚后重复 TLS 与原服务健康验证。配置可能包含私有路由，读取和日志不得公开。

## 2026-11-06 上线记录

最终发布标识 `20261106T044236Z`，公开文件 12 个、总计 860030 字节。发布目录 `/var/www/myforeverchat/releases/20261106T044236Z`，Caddy 原配置备份在同标识 backups 目录。主域 HTTPS 严格证书校验与首页逐字节匹配通过；www 返回 301 永久跳转。

复用镜像中的 Caddy 二进制自带 `NET_BIND_SERVICE` 文件 capability，因此静态容器 drop ALL 后仅保留这一 capability，避免内核拒绝执行；仍使用只读文件系统、无新增宿主端口、no-new-privileges 与内存/PID 上限。首次初始化在建立 current 链接后再启动容器。

公网独立验证脚本 `verify_live.py` 核对首页、latest.json、插件 ZIP 的大小与 SHA-256、4 个 JPEG 图片的签名/类型/正文、www 重定向、chat 健康，以及 studio 未登录访问仍进入 `/login`。去敏结果见 `live-verification.json`。

## 后续发版同步入口

推荐使用对应插件的同步脚本并加 `--zip <已检查的ZIP> --notes <真实更新说明JSON> --publish`：聊天插件使用 `ops/sync_release.py`，商业技能助手使用 `ops/sync_professions_release.py`，世界向导使用 `ops/sync_navigator_release.py`，目标选择使用 `ops/sync_targets_release.py`。先同步，再校验/部署/公网验收。`--dry-run` 只展示待变更文件；不带模式只修改本地。字段与边界见上级 README。

官网首页并列展示四个插件，详情页分别是 `/chat/`、`/professions/`、`/navigator/` 和 `/targets/`。聊天插件的根 `releases.json`、`latest.json` 和原有下载地址继续保留；其他插件的元数据在各自目录。四套同步脚本都从各自数据源生成首页卡片，维护对应详情页和版本记录，不会覆盖其他插件版本。不要多处手改版本。

目标选择与管理器可先分别同步到本地，再冻结站点进行一次部署。发布目标选择时必须保留现有商业技能助手公开元数据及安装包，不得带出仍暂停上线的本机候选。所有旧版本包继续按原哈希保留。新增的 `/targets/` 页面、CSS、JSON 使用 `no-cache`，版本 ZIP 使用 immutable；`verify_live.py` 对全部登记包做真实 HTTPS 字节核验。部署标识与公网结果须在完成部署后记录，不能把本地接入视为已上线。

发布前须逐张审查截图脱敏与下载包内容。当前同范围插件发版和官网同步已有用户持续授权，无需为例行同步再次申请批准。

## 社区服务适配

新增 `/api/suggestions` 专用反向代理；其他主域路径继续走静态容器，chat/studio路由不变。`ops/deploy.py` 另传仅含server.py/admin.py的私有归档，创建带发布标识的社区容器，使用现有官方Python3.12 slim镜像、无宿主端口、只读代码/系统，固定命名卷 `myforeverchat-community-data` 存SQLite和反滥用密钥。可信转发来源取实际主Caddy容器IP，主入口覆盖X-Forwarded-For。

新容器通过内部健康检查后才切流量，随后以公开GET校验列表。候选失败回滚代码入口并保留数据；旧社区容器在成功后停止且保留。每次发布前对已有SQLite做一致性备份，位置 `/var/www/myforeverchat-community/backups/<标识>`。数据库不随静态版本切换，也不上传进public。今后重建主Caddy容器若其私网IP变化，应重新执行站点部署以刷新可信代理IP。

详细API、限流、私有删除工具及数据恢复边界见 `community/README.md`。上线验证不得在生产建议区发送测试垃圾；所有写入/分页/重试测试使用临时数据库。

## 已配置的真实收款素材

1、5、20、100元使用用户提供的四张独立支付宝截图；20元为PNG，其余为JPEG。`qr_presentation: "alipay-screenshot"` 是前端显示配置，后端无需转换。每次重复发布保留真实素材和金额映射，`verify_site.py` 在赞助启用时检查四档非空、安全路径与文件签名；`verify_live.py`逐字节核对四码及MIME，不做付款测试。


## v0.9.0 同步发布

2026-11-06 发布标识 `20261106T112815Z`。官网与所有下载入口已同步 v0.9.0 试用版，包 119961 字节、36 文件，SHA-256 `60081bc023fb0ef9cd0fdec97a7961da346686794093d213415d47a31599543b`。新增两张已复核脱敏的实机图；6 张截图及既有作者/收款素材均通过公网逐字节核对。HTTPS、版本历史、www 跳转、建议只读列表、chat 健康、studio 登录保护通过。证据见 release-0.9.0-validation.json 和 live-verification.json。

## 2026-11-07 商业技能助手首次公开发布

已将 MyForeverProfessions v0.3.1 试用版发布到 https://afabiaoge.xyz/professions/ ，首页导航和正文均提供入口。专业插件独立维护 latest.json/releases.json，聊天插件继续为 v0.9.0，所有既有发行包保持原字节。

最终部署标识 `20261106T162340Z`（北京时间 2026-11-07）。公开目录 36 文件、3936346 字节。专业包 39672 字节、11 文件，SHA-256 `1c432f96bfcd20b79804b642e2446718eb4fee7cd484ec17f1f856d49c094fea`。使用 `ops/sync_professions_release.py --zip ../dist/MyForeverProfessions-0.3.1-Trial.zip --notes ops/release-professions-0.3.1.json --publish`。

9 项专业发布回归与 7 项聊天发布回归通过；本地桌面与 390px 手机页面检查通过。公网 HTTPS、两个插件的全部登记包与校验文件、专业页面/元数据、www 跳转、建议只读列表、chat 健康与 studio 登录保护通过。浏览器从首页进入专业页后真实下载，SHA-256 与原包一致。

复查发现浏览器可能继续使用旧首页缓存，因此为首页、专业页和未带版本号的 CSS/JS/配置增加 `Cache-Control: no-cache`；版本化 ZIP 保持 immutable。公网检查现已验证重校验响应头。已有旧缓存可通过强制刷新重新获取页面。本次没有升级浏览器工具，也没有发送生产测试留言。

证据：`ops/release-professions-0.3.1-validation.json`、`ops/professions-publish-0.3.1.log`。页面如实标明试用状态，以及完整闪烁周期、实际拍卖框 Shift 点击等未独立实机验收范围。没有发布未经脱敏的游戏截图。

## 2026-11-07 双插件并列官网

用户要求两个插件并列展示，并将官网同步设为两者共同的持续交付规则。根首页已改为两张同等展示的插件卡片；聊天详情移至 `/chat/`，商业技能助手保留 `/professions/`。原聊天 JSON、ZIP 和旧根安装/更新锚点继续兼容。任一发布脚本均从两套元数据刷新首页，避免版本与下载入口遗漏更新。

部署标识 `20261106T163714Z`（北京时间 2026-11-07）；公开文件 39 个、3947872 字节。插件源码和发行包未变，聊天保持 v0.9.0、专业保持 v0.3.1。24 项发布/资产回归、站点校验、桌面 1440px 和手机 390px 布局检查通过。桌面两张卡片宽高一致，手机无横向溢出；嵌套详情页的图片、配置和作者素材路径正常。

公网校验于 `2026-11-06T16:38:10.618071+00:00` 通过：门户、两个详情页、资源、各版本下载包与校验文件逐字节一致，未版本化页面/资源的重校验头、www 跳转、chat 健康、studio 登录保护、建议只读列表正常。浏览器从新首页实际下载两个安装包，SHA-256 与已发布原包一致；旧 `/#updates` 跳至 `/chat/#updates` 正常。没有生产测试留言或付款操作。

证据：`ops/portal-publish-2026-11-07.log`、`ops/portal-release-2026-11-07-validation.json`、`ops/portal-desktop-20261107.png`、`ops/portal-mobile-20261107.png`。项目规则与 README 已同步。

## 2026-11-07 实机截图与作者头像

部署标识 `20261107T010942Z`。商业技能助手详情页新增首屏预览和三张实机截图：专业面板、熔炼铜锭的材料缺口、地图上的四种训练师图标。原始画面未上传；裁掉了角色名、聊天、战斗统计和无关界面，重新编码时移除了原图元数据。保留的训练师姓名和坐标是游戏内 NPC 数据。截图及放大交互不改变已有游戏内验证范围。

首页和聊天详情共用用户提供的新插画头像，公开文件为 `assets/hyder-avatar-illustration.jpg`，旧头像已移出公开目录。两套插件版本、版本记录和 ZIP 保持原样。站点校验、19 项发布回归和 5 项头像/社区资源回归通过；本地桌面和手机检查了三图放大与关闭，公网浏览器确认三图、新头像与地图截图放大可用。公网文件逐字节验证于 `2026-11-07T01:10:26.946821+00:00` 通过。

## 2026-11-07 MyForeverChat v0.9.1

通过 `sync_release.py --publish` 发布公共频道提醒总开关，部署标识 `20261107T012238Z`。公网 HTTPS、首页和详情页、新旧版本历史、ZIP 与校验文件、截图、建议读取及既有子域检查均通过。商业技能助手仍为 v0.3.1，版本和安装包已核对。详见 `release-0.9.1-publish.log` 和 `live-verification.json`。

证据：`ops/professions-gallery-screenshots.json`、`ops/professions-gallery-2026-11-07-validation.json`、`ops/professions-gallery-publish-2026-11-07.log`。


## 桌面插件管理器发布支持

管理器下载页为 `/manager/`；三平台不可变 ZIP 与 SHA-256 位于 `/manager/downloads/`，版本和历史位于 `/manager/latest.json`、`/manager/releases.json`。首页只增加指向管理器页的入口，两个游戏插件仍各自维护原有版本、详情页与下载路径。

使用 `sync_manager_release.py --windows <ZIP> --mac-arm64 <ZIP> --mac-x64 <ZIP> --notes <JSON> --publish` 发布；`--dry-run` 只核验和预览。本地校验器将管理器登记包加入 ZIP 白名单，仍拒绝未登记的额外 ZIP，逐一校验三个平台的身份、架构、哈希与页面信息。Caddy 对管理器未版本化页面 / CSS / JSON 使用 `no-cache`，版本 ZIP 使用 immutable 缓存。公网脚本逐字节核对管理器页、元数据、所有历史包和校验文件，并继续检查两个插件及既有子域。

桌面工具首次发布前须分别记录 Windows、Apple 芯片 Mac、Intel Mac 的编译与实机验证结果；交叉编译和核心模拟测试不等于系统实测。下载页签名提示须与实际 Windows 签名和 Apple 公证状态一致。

### 大归档上传与服务器就地公网验收

`deploy.py` 对大于等于 16 MiB 的站点归档使用 `upload_archive.py`：每块 2 MiB、最多 6 个并行 SCP 连接，每块失败最多尝试 3 次。复用既有 SSH 密钥与严格主机校验，不改变服务器服务。分块仅存于 `.incoming/upload-<随机标识>/`，服务器逐块核对大小 / SHA-256，再核对合并后的完整归档；验证完成后以原子硬链接创建原有 incoming 归档名，不覆盖已存在文件。成功与失败均只清理本次随机目录；上传或校验失败不会进入部署步骤。小型私有后端归档仍按原单次 SCP 上传。

`python3 ops/test_upload_archive.py` 使用模拟 SSH/SCP 传输和真实服务器组装脚本，在本地临时目录测试并发、失败重试、错块、漏块、最终哈希错误、已有文件保护与清理边界；不连接服务器。

本机跨境下载大包较慢时，可在服务器上对指定发布目录执行**同一份** `verify_live.py`。它仍通过真实 `https://afabiaoge.xyz/` 请求，检查 TLS、网页逐字节内容、全部新旧安装包的大小 / SHA-256、缓存头、www 跳转、建议读取、chat 健康与 studio 登录保护；没有改为只检查磁盘文件。`--output -` 仅将报告返回 stdout，避免在服务器写入路径依赖。

从网站目录执行以下示例，将发布标识换成部署结果中的实际标识：

```python
from pathlib import Path
import json, shlex, subprocess, sys
sys.path.insert(0, str(Path('ops').resolve()))
from deploy import SSH

release_dir = '/var/www/myforeverchat/releases/<UTC发布标识>'
command = 'python3 - --public ' + shlex.quote(release_dir) + ' --output -'
result = subprocess.run(SSH + [command], input=Path('ops/verify_live.py').read_text(),
                        text=True, capture_output=True, check=True)
report = json.loads(result.stdout)
assert report['status'] == 'passed'
Path('ops/live-verification-server.json').write_text(
    json.dumps(report, ensure_ascii=False, indent=2) + '\n')
```

服务器就地验收需同时保留本机对公网页面、元数据与下载入口的检查记录，分别标明两种验收位置，不能将服务器下载表述成本机浏览器完整下载。


## 2026-11-07 插件管理器 v0.1.0 试用版

部署标识 `20261107T045154Z`。新增 `/manager/` 及 Windows x64、Mac Apple 芯片、Mac Intel 下载包，首页提供独立入口。聊天 v0.9.1 与专业 v0.4.3 的代码、ZIP 和版本记录未变。管理器为外部桌面程序；插件 JSON 的 `automatic_install: false` 继续表示游戏内不自动安装。

管理器在 Apple 芯片 Mac 上通过 61 项核心回归，并实际操作目录设置、系统文件夹选择、手动/自动更新及备份恢复（隔离目录）。Linux 同源核心 60 项通过；官网与传输 47 项通过。Windows 和 Intel Mac 未做对应真机验证，30 分钟周期与退出游戏后 60 秒重试未做完整等待实测。Mac 包本地临时签名，未做 Developer ID 公证；Windows 未做 Authenticode 签名。

使用 sync_manager_release.py 先同步并通过 verify_site.py，再运行 deploy.py 分块上传；相同 verify_live.py 从服务器访问公网 HTTPS 逐字节检查 60 个文件，包含三个完整程序包及 SHA-256，同时核对已有子域。随后本机外网核对页面、元数据及三个下载的 Range/长度/缓存响应。证据：manager-0.1.0-publish.log、manager-0.1.0-live-verification.json、manager-0.1.0-external-verification.json。未发送生产测试留言。

## 2026-11-07 商业技能助手 v0.4.4 发布后复测结论修订

部署标识 `20261107T061924Z`。macOS 无限 1.60.1 build 70862 附近矿点复测仍未恢复；不同查询位置重复读到旧悬停内容，隔离其他插件后仍复现，原因未定位。已通过 `sync_professions_release.py --publish` 修订现有 v0.4.4 的专业详情页、latest.json 和 releases.json 中的验证说明，不将该现象标为已修复或已确认的客户端缺陷。

没有更换已发布 ZIP，也没有新建代码版本。商业技能助手仍为 v0.4.4，包 53269 字节，SHA-256 `cad46e8c6077d6f108e3a7cc3eb8c679a4bbe55782a761a82d70dac9066a0574`；聊天插件 v0.9.1、管理器 v0.1.0 与原下载包保留。

服务器执行同一 `verify_live.py`，通过真实公网 HTTPS 逐字节核对 62 个文件及全部登记包和校验文件，`2026-11-07T06:23:13.257752+00:00` 通过；www 跳转、chat 健康、studio 登录保护和建议只读检查正常。本机外网另核对专业页、两份专业 JSON、完整原 ZIP 与聊天/管理器元数据，共 6 项通过。证据：`professions-0.4.4-retest-publish.log`、`professions-0.4.4-retest-live-verification-server.json`、`professions-0.4.4-retest-external-verification.json`。


## 2026-11-08 商业技能助手 v0.4.5 近距离提示试用版

用户明确授权先发布附近提示范围。部署 `20261108T031537Z`，通过 `sync_professions_release.py --zip ../dist/MyForeverProfessions-0.4.5-Trial.zip --notes ops/release-professions-0.4.5.json --publish` 同步首页并列卡片、专业详情页、下载包、版本和历史。

新增近距离描边闪光、矿名文字与无定位线索，并修复主面板锁定时商字图标不能拖动。说明如实标注：可靠方向未恢复，当前近距文字/自动声音及新图标交互仍有游戏实测待办；1167 项模拟检查和 11 个 Lua 语法文件通过。

本机运行完整 verify_live.py，通过公网 HTTPS 逐字节核对 64 个文件及登记安装包、SHA-256，www 跳转、chat 健康、studio 登录保护和建议只读接口正常。另有本机 8 项重点核验。聊天 0.9.1、管理器 0.1.0 和旧包未更改。

新包 56,401 字节，SHA-256 `c6861f5b6ad9051a55c97dd83c7d92fb0012623b6bd6d79885dc5921f0ffa81c`。证据：`professions-0.4.5-publish.log`、`professions-0.4.5-live-verification.json`、`professions-0.4.5-external-verification.json`。


## 2026-11-08 商业技能助手 v0.4.6 近距离识别更新

用户明确以头顶提示实际出现作为本次验收标准。部署 `20261108T041158Z`，使用 `sync_professions_release.py --zip ../dist/MyForeverProfessions-0.4.6-Trial.zip --notes ops/release-professions-0.4.6.json --publish` 同步首页并列卡片、专业详情、下载、版本与历史。

补充原生交互目标在无姓名板时的文字/声音来源，改进声音身份去重。11 个 Lua 语法与 1254 项模拟检查通过，独立复核另 27 项断言通过。macOS 无限 1.60.1 build 70862 真实铜矿旁自动显示“铜矿／就在附近”和描边闪光，资源消失后清除；客户端声音调用成功计数为 3，实际听感未确认。无姓名板路径未隔离游戏实测，方向未恢复，官网如实说明。

新包 57,254 字节、15 个白名单文件，SHA-256 `6d1e93b4d9865216d46d532770813b38572692134a8dd16333f87d864cf62bb6`。本机完整公网 HTTPS 验证通过 66 文件，另有 8 项重点下载/元数据检查；www、chat、studio 和建议只读接口正常。聊天 0.9.1、管理器 0.1.0 和已发布旧 ZIP 保持不变。未新增原始游戏截图。

证据：`professions-0.4.6-publish.log`、`professions-0.4.6-live-verification.json`、`professions-0.4.6-external-verification.json`。

## 世界向导上线（2026-11-08）

新增 `/navigator/` 与独立 latest/releases 元数据，首页三插件等权展示。通过 `ops/sync_navigator_release.py` 发版，复用当前静态站与社区服务部署流程；导航 HTML/CSS/JSON 均采用 no-cache，带版本号 ZIP 保持 immutable。`verify_site.py`、`verify_live.py` 同时检查导航包身份、哈希和链接。

本次配套管理器 0.2.0 新增 Navigator 白名单，三个平台包通过 `ops/sync_manager_release.py` 先同步到本地，随导航的 `--publish` 一次部署。原有 Chat/Professions 版本接口保持兼容，已发布旧包不覆盖。具体部署标识、线上逐字节核验及管理器 HTTPS 回归结果见 `ops/navigator-0.1.2-manager-0.2.0-publish.log`、`ops/live-verification.json` 与本次发行验收记录。

最终部署标识 `20261108T043129Z`。公网 78 个资源逐字节／哈希校验通过；导航 ZIP 为 39076 字节，SHA-256 `650f657742b92d3a922cfff3a5aee6731ba03f7a92603fb5cf7a9e5334afbde5`，浏览器从真实首页点击下载的文件哈希一致。管理器 0.2.0 三平台包已上线，独立 HTTPS／隔离安装、升级和恢复回归 68 项通过。原 16 个公开 ZIP 哈希均未改变；www 跳转、chat 健康、studio 登录保护与建议只读接口正常。验收汇总见 `release-navigator-0.1.2-validation.json`。


## 世界向导 0.2.1 分类界面发布（2026-11-08）

版本 0.2.1 将查找 NPC、个人地点与当前导航分为三页，增加二级分类并默认收起筛选、表单和更多资料。7 个 Lua 文件、7 组模拟检查通过（导航 175 项、UI 274 项）；真实客户端通过本地命令调用实际控件处理器验证分类与原生追踪，未把它写成鼠标或行走测试。

发布使用独立冻结的 `PersonalAddons/work/navigator-0.2.1-site`，同时固定 public、发布脚本和两份私有服务源码，避免上传期间活动目录变更。部署标识 `20261108T052448Z`。ZIP 为 52,254 字节，SHA-256 `3487f3087aca631142ef9d5795ee7901f3ada6ec33a5c7c2895a779f5bda8f72`；真实浏览器下载哈希一致。管理器 0.2.0 公网 HTTPS 与隔离安装／更新／恢复检查 68 项通过，无需重新发布管理器。

公网 82 个资源逐字节／哈希校验通过，原有 21 个公开 ZIP 保持原哈希；www、chat、studio 登录保护与建议只读接口均正常。证据见 `navigator-0.2.1-publish.log`、`navigator-0.2.1-live-verification.json`、`release-navigator-0.2.1-validation.json`。


## 世界向导 0.2.2 职业训练师发布（2026-11-08）

新增独立职业训练师用途与九职业细分，加入195位训练师，总目录427点／427NPC、45地图；原232条逐字段与上一版发行ZIP一致。7组Lua 5.1模拟通过（导航175项、UI409项），网站同步7项检查与管理器0.2.0公网HTTPS／隔离安装、升级、恢复68项通过。本次客户端停在启动提示页，未把模拟检查写成训练师角色内实测。

发布采用独立冻结工作区 `PersonalAddons/work/navigator-0.2.2-site`，部署标识 `20261108T055300Z`。包为63,807字节，SHA-256 `0b3dbc687c00e3cedc35d094e635c6f5bb43d3334bdf947b9d32c0b164bf51c4`；公开导航页、latest接口与真实HTTPS下载一致。

公网84个资源逐字节／哈希校验通过，原有22个公开ZIP保持原哈希；www、chat、studio登录保护与建议只读接口正常。证据见 `navigator-0.2.2-publish.log`、`navigator-0.2.2-live-verification.json`、`release-navigator-0.2.2-validation.json`。


## 世界向导 0.3.0 任务列表导航（2026-11-08）

接入原生右侧追踪与日志的双击导航，支持任务NPC、物品来源、任务物件、指定区域与交付位置。原有427NPC／45图目录保持字节一致；另加入3817个至少有一处目标或交付参考的经典任务（3762交付、1365目标，集合重叠），不宣称全目标覆盖。临时目标不占个人地点；任务状态变化会停止旧目标，原生同阶段下一站只更新HUD、不重新抢追踪。

10个Lua文件、10组模拟通过：导航249、主界面409、任务解析／位置上下文7083、任务UI188个断言；任务参考累计核验831039个返回点。游戏未运行，物理双击与实际任务流程未游戏实测。发布脚本7项通过，固定测试ZIP时间戳以消除字节比较的时钟不确定性；管理器0.2.0公网HTTPS／隔离安装、更新、恢复68项通过。

使用当前已发布Chat0.9.2／Professions0.4.6／Manager0.2.0的public冻结为 `PersonalAddons/work/navigator-0.3.0-site`；与生产非Nav内容对照一致，没有发布暂停中的Professions候选。部署标识 `20261108T152846Z`。ZIP为566990字节，SHA-256 `62dc08d48a6c82049b206707c578bc9b4cb6b5e365596196ac4497fc2469fa83`；公开页面、版本接口与实际HTTPS下载哈希一致。

公网88个资源逐字节／哈希校验通过，原有24个公开ZIP哈希保持不变；www、chat、studio保护与建议只读接口正常。证据见 `navigator-0.3.0-publish.log`、`navigator-0.3.0-live-verification.json`、`release-navigator-0.3.0-validation.json`。


## 世界向导 0.3.1／0.3.2 界面更新（2026-11-09）

0.3.1 在大地图当前任务详情底栏原生“追踪”右侧新增“导航”，四按钮同排保留原操作；任务UI专项254项通过。部署 `20261109T054700Z`，包569000字节、SHA-256 `64175bd964ab862cc73e6f963fda7c82d265cd482bdecec97d7e211e144d8436`，公网92资源核验通过，26旧ZIP保持哈希，管理器隔离64项通过。

上传期间收到HUD新要求，以0.3.2独立版本加入角色相对八方向文字及主次层级，保留地图任务按钮；10个Lua文件／十组模拟通过，主界面HUD494、任务UI254、导航249、任务解析7083个断言，数据检查仍通过。独立检查16组角色朝向与目标方位、多圈／边界／无效角，字体在70862源定义中存在。游戏未运行，真实视觉、转向和物理点击仍未实测。

最终部署 `20261109T055424Z`，冻结目录 `PersonalAddons/work/navigator-0.3.2-site`。包570444字节、SHA-256 `291afa405730ef3db8be628fdd0bbb6cbeaf21c64d5b58441bb014c1b948b716`，实际HTTPS下载与公开latest一致；管理器0.2.0公网HTTPS／隔离安装、更新、恢复68项通过。保留Chat0.9.3、Professions0.4.6、Manager0.2.0，没有带出暂停中的专业候选。

最终公网94个资源逐字节／哈希通过，27个旧公开ZIP不变，www、chat、studio登录保护及建议只读接口正常。分别见 `navigator-0.3.1-live-verification.json`、`navigator-0.3.2-live-verification.json` 和对应release验收JSON。


## 世界向导 0.3.3 紧凑半透明导航浮窗（2026-11-09）

浮窗固定为300×84，背景不透明度56%，仅保留名称、箭头／相对方向、距离、地图和关闭；去除坐标、长说明、重复状态与悬停提示，到达和跨区状态均不扩展框体。名称和数字保持清晰，文字不随背景变淡；地图任务导航入口及原有目录、任务和导航数据保持不变。

10个Lua文件、10组模拟通过，主界面／HUD538、任务UI254、导航249、任务导航7083项，任务参考累计核验831039返回点。实际角色在非战斗状态重载后，观察威尔海姆修士16米已到达状态，确认小浮窗、透出背景与完整按钮字样；未把按钮物理点击、拖动、转向或跨区行走写为已实测。未发布原始游戏截图。

部署标识20261109T132825Z，冻结目录 `PersonalAddons/work/navigator-0.3.3-site`。包570598字节、14个白名单文件，SHA-256 `cef60b3f44b495baa13a8351525ab3ea2d3ad1ac277df4e68a50eda953a24ca9`；实际HTTPS包与latest、官网版本一致。管理器0.2.0隔离检查64项、公网HTTPS与隔离安装／更新／恢复68项通过。

公网96个资源逐字节／哈希通过，28个旧公开ZIP保持哈希；保留Chat0.9.3、Professions0.4.6及Manager0.2.0，未发布暂停中的专业候选。www、chat、studio登录保护和建议只读接口正常。证据见 `navigator-0.3.3-publish.log`、`navigator-0.3.3-live-verification.json`、`release-navigator-0.3.3-validation.json`。


## 2026-11-11 目标选择与管理器更新

按用户授权发布MyForeverTargets 0.1.37和公开管理器0.2.1，使用独立冻结目录 `PersonalAddons/work/targets-0.1.37-manager-0.2.1-site`，部署标识 `20261111T095854Z`。首页四插件等宽并列，目标选择独立页面、latest/releases、ZIP与校验文件上线。Chat0.9.3、Professions0.4.6、Navigator0.3.3的元数据与所有原29个ZIP保持哈希不变。

108项真实公网HTTPS资源核验通过，包含全部新旧包完整哈希；本机网页／JSON／目标包及大包Range检查通过，浏览器实际下载目标包与发行SHA一致。新版管理器74项真实HTTPS／隔离安装、更新和恢复测试通过，MacUI读到目标0.1.37。Windows与Intel Mac仍只完成交叉构建及包验证，未原生运行。www、chat健康、studio登录保护与建议只读接口正常，无生产留言写入。

详见 `release-targets-0.1.37-validation.json`、`targets-0.1.37-manager-0.2.1-publish.log` 及同名前缀的 `live-server.json`、`live-local.json`。公开管理器0.2.1仅插件管理；用户本机0.3.1保留原行为统计，没有上传到公共目录。


## 目标选择 0.1.46 公开试用版（2026-11-12）

用户明确授权发布当前可用功能。以已实测 0.1.44 源码为基线冻结 0.1.46，未纳入 0.1.45 的原生姓名板缩放探针或 Main/UI 实验接入；本机 0.1.45 继续保留，未用管理器改动运行中的游戏。公开源码在 `PersonalAddons/work/targets-0.1.46-release-root`。

通过冻结生产站点 `PersonalAddons/work/targets-0.1.46-site` 的 `ops/sync_targets_release.py --publish` 发布；部署标识 `20261112T093034Z`。包 179731 字节、28 个白名单文件，SHA-256 `5c5865a8dc8f850bde6b359f5729a7195c48eb49b4ea42c0812002ec521634bf`。23 个 Lua 语法、19 套 9820 项模拟、10 项发版同步回归及独立审查通过。

本机真实公网 HTTPS 逐字节核验 110 个资源，覆盖新旧 ZIP、校验、版本接口、页面、图片与缓存；另有 10 项本机重点核验。公开管理器 0.2.1 的真实 HTTPS／隔离安装、更新、备份和恢复 74 项通过，无需发布本机 0.3.1 管理器。33 个旧 ZIP 保留原字节；聊天 0.9.3、专业 0.4.6、导航 0.3.3 与管理器 0.2.1 保持原版本，私有社区源码沿用线上哈希。www、chat 健康、studio 登录保护、建议只读接口正常，无生产写入测试。

发布说明明确：友方普通技能悬停兼容仅脱战，通过临时选中和恢复完成；同名怪焦点仅脱战按提示多次右键逐次 GUID 核验；战斗中任意怪物自动匹配焦点仍未解决。空原目标合并模式、更多步恢复和敌方／子目标施法尚未完整实测，不将模拟或旧分步成功冒充这些场景通过。

证据：`ops/release-targets-0.1.46-validation.json`、`ops/targets-0.1.46-publish.log`、`ops/targets-0.1.46-live-verification.json`、`ops/targets-0.1.46-external-verification.json` 与 `ops/targets-0.1.46-manager-isolated-live.json`。


## 世界向导 0.4.0 Questie NPC 扩展（2026-11-13）

新增运行时只读 QuestieDB NPC 目录，等 Questie 完成语言和角色修正后分批读取，每 NPC／地图一条；去重保留 427 精选标识，新增任务／其他 NPC 和多种常用服务分类。支持中英文名、副标题、用途与 ID 搜索、收藏及导航；潜行者训练师归盗贼。过滤未知地图、副本区域及映射回室外图的副本别名；多刷新点在开始时固定，隐藏相位只释放自有追踪。保留 300×84、背景 alpha 0.56 HUD 和原有任务入口。未分发 Questie 数据库、私人配置或原始截图。

11 Lua 文件语法及12组模拟通过：Questie目录328、端到端44、UI540、导航249、任务导航7083、任务UI254项，任务参考831039返回点。安装的Questie12.8.0／QuestieDB1.1.0通过50文件真实数据库离线执行，四个缺失NPC样例的搜索、收藏、英文别名与潜行者分类通过；模型地图结果9902参考记录／9006NPC／50地图不作为原生地图覆盖承诺。实际客户端停在角色创建页，本版扩展显示、物理点击、站位、真实相位和导航行程未游戏实测。

部署 `20261113T102916Z`，冻结 `PersonalAddons/work/navigator-0.4.0-site`。包580740字节、15白名单文件，SHA-256 `d7f849601b9a2da73873c48e8960e0e95fdac47bf3ad68e132421b055d993b67`。公开0.2.1管理器冻结源码重新构建后，真实HTTPS与隔离安装／更新／备份恢复71项通过；当前工作区另有65本地／71公网检查，仅为附带证据，没有对真实游戏安装。

公网112资源逐字节／哈希通过，34旧ZIP不变；保留Chat0.9.3、Professions0.4.6、Targets0.1.46、Manager0.2.1，未发布专业实验候选或本机管理器候选。www、chat健康、studio登录保护及建议只读接口正常。证据为 `navigator-0.4.0-publish.log`、`navigator-0.4.0-live-verification.json`、`release-navigator-0.4.0-validation.json` 与work目录的DB／管理器验收记录。


## 世界向导 0.4.1 普通专业训练师（2026-11-13）

新增独立专业训练师用途，含采矿、草药学、剥皮、炼金、锻造、制皮、裁缝、工程学、附魔、急救、烹饪、钓鱼12细类。用Questie TRAINER标记与完整中英文头衔共同识别，兼容初中高级／大师／专精、Junior与NBSP，不将材料或技能书商人误作训练师。原精选6位保留ID、特殊主分类与旧细分，以副成员索引加入专业分类；目录与索引原子发布，不修改数据库。侧栏8用途排布通过，HUD构建及刷新段与0.4.0包一致。

11 Lua文件语法、13组模拟通过：专业训练师319、UI602、Questie目录328、端到端44、导航249、任务导航7083、任务UI254，任务参考831039返回点。真实DB中文/英文全库身份识别均311；模型地图专业305记录为299主分类+6精选副成员，12专业样例的搜索别名、收藏、开始导航、目标读取及源值不变通过；这些不是原生地图或站位承诺。当前角色在游戏中，仅只读截图观察，未重载或做新入口/物理点击/站位/可教技能验收。

部署 `20261113T105612Z`，冻结 `PersonalAddons/work/navigator-0.4.1-site`。包585107字节、15白名单文件，SHA-256 `6ad246ffc2d9505d4a72b8a8e0b72089860f19a6cc0b662e4085e1a23ce82414`。公开管理器0.2.1冻结源码重新构建后，公网HTTPS／fake目录安装、更新、备份恢复71项通过，未安装至真实游戏。

公网114资源逐字节／哈希通过，35旧ZIP不变；Chat0.9.3、Professions0.4.6、Targets0.1.46、Manager0.2.1与私有社区源码保留，未发布专业实验候选或本机管理器候选。www、chat健康、studio登录保护及建议只读接口正常。证据：`navigator-0.4.1-publish.log`、`navigator-0.4.1-live-verification.json`、`release-navigator-0.4.1-validation.json`及work中的专业/管理器检查记录。


## 2026-11-14 星辉 UI / 午夜官网与管理器

用户已明确授权本批合并和发布。四插件与Manager使用各自同步脚本生成版本/历史/首页，单次部署完整冻结站点；可选三个插件由同批GitHub发行提供手动安装。theme.css显式设为no-cache，三份离线预览PNG加入verify_live；历史36个ZIP保持SHA-256。实际部署标识、公网结果见本批后续验证记录，不能只凭本地同步声明上线。
