# 匿名建议服务

纯 Python 标准库 HTTP + SQLite。免登录；昵称可不填，默认「匿名玩家」。只保存公开昵称、正文、楼层、时间、幂等提交标识；响应不包含网络来源。

## API

- `GET /api/suggestions?before=<id>&limit=20`：倒序楼层分页，limit 1–50，返回 `{items, has_more, next_before}`。每项只有 `{id,nickname,body,created_at}`；时间为 UTC ISO 8601，展示时由浏览器转换。
- `POST /api/suggestions`：JSON `{nickname?,body,website:"",request_id:UUID}`；昵称最多24字符，正文1–2000字符。首次返回201 `{item}`；同UUID/同内容重试返回200同一项；同UUID不同内容409。
- 错误为 `{error:{code,message}}`，限流响应429并附 `Retry-After`。正文最大16 KiB；只允许精确本站 Origin/Host，不开放CORS。
- `/health` 只供内部健康检查。主入口仅代理 `/api/suggestions`，不暴露健康、数据库或后台管理接口。

正文按纯文字原样存储与JSON返回。前端必须用 `textContent` 渲染昵称与正文，不能将其送入 `innerHTML`。HTML标签也只是留言文字。

## 反滥用与持久化

默认每个来源至少间隔30秒，每滚动小时5次、24小时20次；全站滚动24小时1000次，总记录10000条。每日轮换HMAC来源标识，限流跨午夜连续计算；不存原始IP，来源哈希约24小时后清理（后台最多5分钟清理延迟）。不记录HTTP访问日志或提交正文日志。只有部署时指定的主Caddy容器IP可传入 `X-Forwarded-For`，Caddy覆盖该头为真实连接来源，外部伪造值不被信任。

`DATA_DIR` 中存 `suggestions.sqlite3`、SQLite WAL/SHM和 `abuse.key`。发布时使用固定命名Docker卷 `myforeverchat-community-data`，与静态public目录和服务源码发布目录分离；服务以UID10001运行，源文件与容器文件系统只读，无宿主机公开端口。

## 本地验证

```bash
python3 community/test_server.py
python3 ops/dev_preview.py
```

集成测试只使用临时目录SQLite和loopback HTTP。开发预览同样使用临时数据库；退出预览不会修改生产留言。公网验收仅GET列表及内部健康检查，不发布测试建议。

## 本机管理命令

在服务器确认 `current.json` 中当前社区容器后执行：

```bash
docker exec <当前社区容器名> python3 /app/admin.py delete <楼层ID>
docker exec <当前社区容器名> python3 /app/admin.py backup /data/backup-YYYYMMDD.sqlite3
```

删除工具清除该条昵称/正文并隐藏楼层；保留已消耗的编号与请求标识，避免旧请求重放重新生成。没有公网管理员页面或删除API。backup使用SQLite在线备份接口，不能只复制正在写入的单个数据库文件。

## 发布与回退

`ops/deploy.py` 分别上传公开站点包和仅含 `server.py`/`admin.py` 的私有服务包。复用服务器现有官方Python3.12 slim镜像，无pip依赖、无额外收费资源。部署创建新服务容器并挂载相同数据卷，先做内部健康检查；再热加载主域路由并验证公开GET和旧chat服务。成功后停止旧社区容器，保留其源码与容器供回退；失败恢复旧入口并删除新候选容器，数据卷不删除、不回滚。

服务部署位置：`/var/www/myforeverchat-community/releases/<发布标识>`；当前记录 `current.json`；私有一致性数据库备份与旧服务记录在 `backups/<发布标识>`。首次发布前为空，不创建假留言。

回退服务时先启动旧记录中的社区容器，再恢复同发布备份的主Caddy配置并热加载，恢复旧 `current.json`；两版继续使用同一数据库，因此新留言不会因代码回退丢失。本实现只有向前兼容的建表/索引初始化；今后如需破坏性数据库迁移，必须另做迁移与回退方案，不能直接沿用此流程。恢复数据库备份会影响备份之后的留言，应与普通代码回退分开处理。

## 收款配置发布检查

`community-config.json` 的 `donation.enabled` 必须是布尔值。关闭时可留空二维码；启用时1、5、20、100四档必须各有非空专属码或可用通用码。所有头像和码只能引用 `public/assets/` 下真实存在的JPEG/PNG/WebP图片，禁止外链、穿越和脚本。该检查只能验证文件与配置完整，收款人及金额含义仍需与用户提供的原码核对；不能拿示例图代替收款码。

本次已收到并纳入发布素材的四张真实支付宝收款截图为 `donation-1.jpg`、`donation-5.jpg`、`donation-20.png`、`donation-100.jpg`，各自对应金额。保留原图像素，仅20元PNG清除了元信息；`qr_presentation: "alipay-screenshot"` 只控制网页显示裁切，不重新生成二维码。后续站点或插件发版应保留已核验的金额映射与图片，不把配置重置为空模板；需要停用赞助时才显式设 `enabled: false`。

发布校验同时检查JPEG/PNG/WebP的扩展名与实际文件签名；公网验收比较整张原图字节及SHA-256，并核对对应MIME类型。检查配置/展示不会发起付款。
