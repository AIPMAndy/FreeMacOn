# FreeMacOn v0.2.0 对抗式工程审核

审核基线：main @ 07f223aed366f83fc2f7f6acb74fcf169cce8240。旧版 macOS 构建和 Pages 部署成功；无正式 release，未获真机验证。本报告区分源码修复、模拟验证、CI 与真机验证，不能以单元测试替代真实合盖证据。

## 威胁模型与反例

| 优先级 | 旧版反例 | v0.2.0 处理 | 剩余风险 |
|---|---|---|---|
| P0 | watchdog 遭 SIGKILL，系统级睡眠覆盖残留 | 独立系统 shell 监督层等待 helper 退出；仅持有匹配会话锁时尝试恢复、回读和保留失败状态 | 两层同时被杀、断电、系统级故障、真实 pmset 异常仍需手动恢复 |
| P0 | pmset 卡死、管道 EOF 被后代进程持有 | 有界等待、输出临时文件、超时终止/强杀；监督层有独立有界命令 | 不可中断的内核 I/O 和系统故障无法由应用完全解决 |
| P0 | 管理员授权后执行文件被替换 | 复制至 root 独占临时目录，SHA256 匹配已授权时计算的摘要后执行 | 不是独立签名信任链；仍应自编译或验证可信来源 |
| P0 | 半截或矛盾 pmset 输出被当成恢复成功 | 未知/矛盾状态拒绝接管，不确认恢复 | macOS 不同输出格式需要真实设备样本 |
| P0 | 用户误把“覆盖已启用”当作真实合盖成功 | 只读 75 秒 probe、明确兼容性与结果边界 | 仍需真实合盖、网络、GUI 测试 |
| P1 | 每 3 秒在空闲时启动多个进程 | 空闲不再轮询，菜单打开时刷新 | 活跃会话仍有查询开销，尚需实测 CPU/功耗 |
| P1 | 点击退出必须再次操作或不知道恢复状态 | 请求停止后确认恢复再退出；异常显示警告 | 系统关机流程、强制退出需真机验证 |
| P1 | 仅 Actions artifact，缺少方便下载路径 | 双架构构建、SHA256、CI 成功后发布不可覆盖的预览 release | ad-hoc 签名无 Apple 公证，Gatekeeper 可能提示；未公证不是正式发布 |
| P1 | AI 任务结束后仍可能继续普通保活 | 新增非特权、绑定命令的 run-awake.sh | 不保证合盖，不替代任务自身重试 |
| P1 | 关盖后可能不锁屏、Wi-Fi/GUI 失败 | 明确区分防休眠与锁屏/网络/GUI，保留系统设置 | 必须检验锁屏；敏感场景手动锁屏；不得绕过系统安全 |

## 验证策略

- Swift policy：已存在 5 个测试，新增 3 个对抗测试（截断/冲突读数、异常电量、心跳边界）。
- Python fault injection：直接提取生产 supervisor shell，仅在测试副本替换路径，模拟正常、SIGKILL、外部会话、恢复失败、读回未知、文件篡改和前置崩溃等 8 项。不会使用 sudo 或真实 pmset。
- Native self-test：构建后的应用使用只读 printf/sleep 验证命令正常返回与超时处理。
- CI：macOS 构建 arm64 + x86_64，签名验证、包校验、模拟测试；不更改 CI 主机电源设置。
- 真机：仍待 macOS 13/14/15/26、Apple Silicon/Intel、电池/AC、外接显示器、锁屏和网络验证。不能声称已经通过。

## 不做的事情

不添加免密 sudo、不关闭 SIP/Gatekeeper、不禁用锁屏、不自动从热保护状态恢复合盖模式、不默认无期限合盖、不声称支持任何 Mac 或任何 GUI agent。开发者预览不得冒充正式公证软件。

## 竞争方向

Apple 的 idle assertion 不保证合盖运行；同类开源项目提供不同程度的 watchdog、菜单栏、命令行和电源保护。FreeMacOn 的差异化目标是可自检、可复现故障注入、可恢复、用户不必信任黑盒，而不是靠宣传称全球第一。参见 [Apple IOKit docs](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)、[Stimulate](https://github.com/azoghby/stimulate)、[Awake](https://github.com/Illyism/awake)。

详细验收门槛见 [RELEASE-GATES.md](RELEASE-GATES.md)。