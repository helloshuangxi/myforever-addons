# 我的无限插件下载与更新网站

公开地址：[afabiaoge.xyz](https://afabiaoge.xyz/)。仅 `public/` 是发布目录。当前独立维护 MyForeverChat、MyForeverProfessions、MyForeverNavigator 与 MyForeverTargets，发版时同步下载包、版本号、更新记录和相关使用说明，遵循游戏根目录 `AGENTS.md`。用户已授权相应插件的上线及管理器下载更新流程，无需为同范围常规发布重复确认。商业技能助手尚未获准上线的本机候选仍须保留在发布目录之外。

## 内容维护

- `public/index.html`：四个插件并列、同等展示的官网首页。`release:catalog` 区块由任一发版脚本读取各自元数据生成，每张卡片独立显示版本、日期、大小和下载地址；不要手工写死版本。
- `public/chat/index.html`：聊天插件的功能介绍、安装、使用、脱敏截图和更新记录；八组 `release:*` 区块由聊天发布脚本维护。
- `public/professions/index.html`：商业技能助手详情页，独立维护功能、安装、脱敏截图和更新记录；五组 `release:*` 区块由专业发布脚本维护。
- `public/navigator/` 与 `public/targets/`：世界向导和目标选择的独立详情页、`latest.json`、`releases.json`。各自的五组 `release:*` 区块由对应发布脚本维护；目标页面使用标明用途的匿名界面示意。
- `public/releases.json` 与 `public/professions/releases.json`：各自的版本数据源，保存当前与历史更新说明、发行包地址、体积与 SHA-256。
- `public/latest.json` 与 `public/professions/latest.json`：由各自同步脚本生成，供手动检查更新，不表示游戏内自动安装。聊天插件既有根路径 JSON 和下载链接继续兼容；旧首页的安装、更新等锚点由 `portal.js` 转到 `/chat/`。
- `public/downloads/`：带版本号的原始 ZIP 和 `.zip.sha256`。同版本、同文件名不能更换内容；代码变化必须发新版本。
- `public/assets/chat-*.jpg` 和 `public/assets/professions-*.jpg`：两个插件的真实客户端脱敏截图。界面变化时按实际更新；逐张检查姓名、正文、摘要、联系人、通知、提示与背景。详情页缩略图、放大预览和大图链接均使用脱敏后的同一文件。不能把原始截图放进 `public/`。

## 同步与发布

从本目录执行，使用已经生成并检查过的 ZIP，以及真实更新说明 JSON。聊天插件使用：

```bash
python3 ops/sync_release.py --zip /绝对路径/已检查的发行包.zip --notes /绝对路径/更新说明.json --dry-run
python3 ops/sync_release.py --zip /绝对路径/已检查的发行包.zip --notes /绝对路径/更新说明.json --publish
```

`--dry-run` 不写文件、不联网。省略 `--dry-run` / `--publish` 时仅同步本地。`--publish` 顺序执行同步、`verify_site.py`、部署、`verify_live.py`；任一步失败就停止。没有额外第三方依赖。

更新说明 JSON 的字段如下，填写实际日期、兼容性、变更和验证结论；版本与 Interface 由 ZIP 内 TOC 读取，可选填写 `version` / `compatibility.interface` 以做一致性检查：

```json
{
  "published_at": "实际发布日期（YYYY-MM-DD）",
  "channel": "trial",
  "compatibility": {
    "product": "国服魔兽世界：无限",
    "client": "实际适配的客户端版本"
  },
  "changes": ["本版真实变更"],
  "validation": ["已做的验证，以及仍未完成的验证"],
  "package_note": "可选：包内附带内容说明"
}
```

`channel` 必须明确为 `trial`（试用）或 `stable`（正式）。新版本必须提供验证说明，不能自动继承旧版已测结论。脚本保留旧记录且不重复；拒绝低版本、同版不同哈希、覆盖同名包，以及含 WTF / SavedVariables / 隐私路径、穿越路径、符号链接或重复成员的 ZIP。

同步会更新首页对应卡片、详情页下载入口、版本/体积/日期/兼容性、校验值、最新更新点、历史与 sitemap，并保留其他插件的独立版本信息。功能介绍、安装使用方法、验证说明和截图仍须按实际变更审查。公开目录的所有 ZIP 必须登记在版本数据里，测试包不得混入。

```bash
python3 ops/test_sync_release.py
python3 ops/test_sync_professions_release.py
python3 ops/test_sync_navigator_release.py
python3 ops/test_sync_targets_release.py
python3 ops/verify_site.py
python3 -m http.server 8765 --bind 127.0.0.1 --directory public
```

测试使用临时目录模拟新版本与异常包，不修改真实插件源码，不往真实 `public/` 放测试版。同步现有版本可使用该版本的 `latest.json` 作 notes；重复执行应显示 `changed_files: []`。

## 发布基础设施

复用现有服务器和 Caddy，不新增付费资源。独立静态容器只读挂载版本目录，热切换 `current`；部署脚本备份主入口配置并在失败时回滚。`www` 永久跳转主域。细节与恢复操作见 [ops/DEPLOYMENT.md](ops/DEPLOYMENT.md)。

网站首次制作的文案与视觉记录保存在 `COPY.md`、`DESIGN.md` 和 `.taste-skill/`。这些记录与 `ops/` 均不上传。

## 匿名建议与作者资料

网站的建议列表由独立 `community/` 标准库Python/SQLite服务持久保存。任何人都可直接留言，昵称可空；按楼层展示。`community-config.json` 保存作者头像/游戏资料和真实收款二维码配置。缺失的收款码保持为空，前端明确提示，不生成替代码；金额专用码与通用码分别配置。

本地完整预览使用 `python3 ops/dev_preview.py`（隔离临时数据库）；服务集成测试使用 `python3 community/test_server.py`。部署仍用同一 `ops/deploy.py`，分别上传静态文件和私有后端，数据库保持在独立Docker持久卷。发布前运行 `verify_site.py` 检查头像与二维码安全路径、禁止源代码/数据库混入public。公网验证只读取建议列表，避免产生测试留言。维护与删除单条建议见 [community/README.md](community/README.md)。

## 商业技能助手

商业技能助手位于 `/professions/`，与聊天插件在首页并列。它独立维护 `public/professions/latest.json` 和 `releases.json`，不改变聊天插件现有 `/latest.json` 与下载入口。安装包同样保存在 `public/downloads/`，旧文件不可覆盖。使用专用同步脚本，后续每次交付更新都按同样流程发布：

```bash
python3 ops/sync_professions_release.py --zip ../dist/MyForeverProfessions-0.3.1-Trial.zip --notes ops/release-professions-0.3.1.json --dry-run
python3 ops/sync_professions_release.py --zip ../dist/MyForeverProfessions-0.3.1-Trial.zip --notes ops/release-professions-0.3.1.json --publish
```

发版内容应如实区分模拟检查、游戏内函数验证、真实鼠标操作和待测项；首次公开版本为 v0.3.1 试用版。页面未使用未经脱敏的游戏截图。公开站点校验同时核对两个插件的元数据、下载和 SHA-256。


## Windows / macOS 插件管理器

`public/manager/` 是独立桌面管理器下载页，首页提供入口；四个游戏插件的卡片、版本和手动下载保持独立。管理器读取其版本内置目录对应的独立 `latest.json`，在玩家首次选择的无限客户端目录中安装选中的插件。它不是游戏内插件，运行期间可定时检查更新。旧管理器不会因网站新增插件而自动增加目录，支持范围以管理器发行说明为准。

管理器发行数据在 `manager/latest.json` 与 `manager/releases.json`，三个平台包放在 `manager/downloads/`。平台标识分别是 `win-x64`、`osx-arm64`、`osx-x64`。同版本包禁止换字节；更新程序代码需升级管理器版本，不需要改动游戏插件的版本。

```bash
python3 ops/sync_manager_release.py \
  --windows ../dist/MyForeverManager-0.1.0-Trial-win-x64.zip \
  --mac-arm64 ../dist/MyForeverManager-0.1.0-Trial-osx-arm64.zip \
  --mac-x64 ../dist/MyForeverManager-0.1.0-Trial-osx-x64.zip \
  --notes ops/release-manager-0.1.0.json --dry-run
```

将 `--dry-run` 换成 `--publish` 后依次同步、校验、部署并核验公网。notes 必须包含 `version`、`channel`、`published_at`、`changes`、`validation`；每次如实写明 Windows、Apple 芯片 Mac、Intel Mac 的不同验证范围。不能将交叉编译成功表述为对应系统实测通过。

包根目录包含 `README.txt`、`LICENSE.txt` 与 `manager-release.json`（仅 `name`、`version`、`platform` 三个字段）；Windows 包根目录为 `MyForeverManager.exe`，Mac 包为 `MyForeverManager.app/Contents/MacOS/MyForeverManager`，并保留可执行权限。同步脚本检查版本身份、PE / Mach-O 平台架构、macOS Info.plist、CRC、体积上限、私密路径、重复成员与符号链接，生成 SHA-256 校验文件。包不包含玩家配置或任何游戏数据。Mac 本地签名和未公证、Windows 未签名情况应如实告知。

```bash
python3 ops/test_sync_manager_release.py
python3 ops/verify_site.py
```

管理器页的 `release:manager-*` 区块由同步脚本生成，勿手改下载版本、文件名或校验值。更新截图必须来自实际程序并脱敏；页面当前采用流程说明，不放模拟程序截图。

## 世界向导与管理器 0.2.0（2026-11-08）

世界向导详情页在 `/navigator/`，独立维护 `navigator/latest.json`、`navigator/releases.json` 与版本化 ZIP。后续发版从本目录执行：

```bash
python3 ops/sync_navigator_release.py --zip ../dist/MyForeverNavigator-<版本>-Trial.zip --notes ops/release-navigator-<版本>.json --dry-run
python3 ops/sync_navigator_release.py --zip ../dist/MyForeverNavigator-<版本>-Trial.zip --notes ops/release-navigator-<版本>.json --publish
```

`sync_release.py`、`sync_professions_release.py` 与导航同步脚本都会保留第三张卡片；公共校验和部署缓存规则已覆盖导航页面、版本接口、历史和下载包。导航验证如实区分模拟检查与实机按钮显示，不把坐标资料核对写成完整游戏验证。

管理器 0.2.0 内置三插件目录，读取上述导航接口。0.1.0 的目录是程序内白名单，无法通过修改官网让旧程序自动多出第三项；旧用户需要下载 0.2.0 替换管理器。保留原游戏目录、自动更新设置与勾选，新插件不自动替旧用户勾选。管理器自身不自动升级，游戏插件继续按原有检查和自动更新设置工作。

## 目标选择（2026-11-11）

目标选择独立维护 `/targets/` 页面、`targets/latest.json`、`targets/releases.json` 和版本化 ZIP。使用已审查的源码包与真实验证说明：

```bash
python3 ops/sync_targets_release.py --zip ../dist/MyForeverTargets-<版本>-Trial.zip --notes ops/release-targets-<版本>.json --dry-run
python3 ops/sync_targets_release.py --zip ../dist/MyForeverTargets-<版本>-Trial.zip --notes ops/release-targets-<版本>.json --publish
```

四个游戏插件的同步脚本都会从各自元数据生成首页全部卡片。目标页面、样式与 JSON 采用 `no-cache`；版本 ZIP 采用不可变缓存。本地和公网校验器均检查目标版本、历史、TOC、链接与 SHA-256。管理器需更新为包含目标选择目录的版本，不能仅更改官网便声称旧管理器已支持。

目标首发的验证说明必须区分用户实测与模拟检查。友方脱战普通技能采用短暂切换目标并恢复的方案；敌方及敌人的目标施法仍待验证，原生 `@mouseover` 识别尚未解决。不得宣称战斗中悬停施法或同名怪物精确施法已通过。目标页面的匿名界面示意不能写作游戏截图。


## 目标选择 0.1.46 公开试用版（2026-11-12）

用户明确授权发布当前可用功能。以已实测 0.1.44 源码为基线冻结 0.1.46，未纳入 0.1.45 的原生姓名板缩放探针或 Main/UI 实验接入；本机 0.1.45 继续保留，未用管理器改动运行中的游戏。公开源码在 `PersonalAddons/work/targets-0.1.46-release-root`。

通过冻结生产站点 `PersonalAddons/work/targets-0.1.46-site` 的 `ops/sync_targets_release.py --publish` 发布；部署标识 `20261112T093034Z`。包 179731 字节、28 个白名单文件，SHA-256 `5c5865a8dc8f850bde6b359f5729a7195c48eb49b4ea42c0812002ec521634bf`。23 个 Lua 语法、19 套 9820 项模拟、10 项发版同步回归及独立审查通过。

本机真实公网 HTTPS 逐字节核验 110 个资源，覆盖新旧 ZIP、校验、版本接口、页面、图片与缓存；另有 10 项本机重点核验。公开管理器 0.2.1 的真实 HTTPS／隔离安装、更新、备份和恢复 74 项通过，无需发布本机 0.3.1 管理器。33 个旧 ZIP 保留原字节；聊天 0.9.3、专业 0.4.6、导航 0.3.3 与管理器 0.2.1 保持原版本，私有社区源码沿用线上哈希。www、chat 健康、studio 登录保护、建议只读接口正常，无生产写入测试。

发布说明明确：友方普通技能悬停兼容仅脱战，通过临时选中和恢复完成；同名怪焦点仅脱战按提示多次右键逐次 GUID 核验；战斗中任意怪物自动匹配焦点仍未解决。空原目标合并模式、更多步恢复和敌方／子目标施法尚未完整实测，不将模拟或旧分步成功冒充这些场景通过。

证据：`ops/release-targets-0.1.46-validation.json`、`ops/targets-0.1.46-publish.log`、`ops/targets-0.1.46-live-verification.json`、`ops/targets-0.1.46-external-verification.json` 与 `ops/targets-0.1.46-manager-isolated-live.json`。
