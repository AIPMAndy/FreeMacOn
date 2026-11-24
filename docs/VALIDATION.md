# 验收清单

**当前状态**：Linux Swift 6.2.1 策略测试 5/5 通过（电源解析、睡眠读取、保护条件、时长边界、Shell 引号）；v0.1.0 的 macOS 原生 CI 已通过；v0.2.0 新机制须以当前 CI 为准。管理员授权、所有物理行为尚未验证。CI 结果见 [Actions](https://github.com/AIPMAndy/FreeMacOn/actions)。以下均为待验证项目，不是已完成测试。

| 测试 | 通过标准 |
|---|---|
| macOS CI | swift test + scripts/build.sh 成功，签名可验证 |
| 普通保活 | 菜单栏显示活跃，不改变 SleepDisabled |
| 授权取消 | 不启动覆盖，不改变系统状态 |
| 冲突保护 | 已有 SleepDisabled 1 时拒绝开始 |
| 合盖 1 分钟 | 无外接显示器，实际时间日志无明显空档；接电及电池分别测试 |
| 结束会话 | pmset -g 显示禁用睡眠标记为 0 或不存在，实际合盖可睡眠 |
| 超时 | 30 分钟到期自动恢复 |
| 主进程退出或崩溃 | watchdog 检测心跳失效、恢复系统状态 |
| watchdog 单独异常退出 | 独立监督层检测异常，只恢复本会话；若失败必须提示 |
| 锁屏 | 验证合盖前主动锁屏及开盖时仍需认证 |
| 低电量 | 电池≤22% 时结束；不要故意耗尽电池 |
| 热保护 | 用模拟策略测试；不故意制造过热 |
| 拔插电源 | 验证覆盖状态；状态丢失则停止并恢复 |
| GUI 自动化 | 单独验证锁屏、截图、输入、隐藏浏览器窗口的行为 |

## 最小真机测试

电脑放在通风桌面，退出 Amphetamine，先运行 pmset -g。打开独立终端：

```bash
while true; do date '+%Y-%m-%d %H:%M:%S' >> "$HOME/freemacon-lid-test.log"; sleep 5; done
```

在 FreeMacOn 开启 30 分钟合盖保活、确认状态已启用后，合盖 60 秒，开盖检查：

```bash
tail -20 "$HOME/freemacon-lid-test.log"
```

预期每隔约 5 秒有一条记录。Ctrl-C 停止记录终端。结束 FreeMacOn 会话，等待正常状态，验证 pmset -g。若记录断层或恢复失败，不要继续依赖合盖模式；按照安全文档恢复设置。

此测试只验证进程持续运行，不证明所有 AI 工具可以继续操作 GUI。记录 macOS 版本、Mac 机型、接电状态、测试时段和恢复读数；公开分享时请去掉私人数据。

## 一键只读验证

从仓库目录运行 `./scripts/verify-lid.sh`，按提示实际合盖约 60 秒。若最大执行间隔超过 8 秒、时钟异常或样本不足，结果为 INTERRUPTED/INCONCLUSIVE；不要继续依赖合盖模式。PASS 仅表示本次探针未观察到大间隔，前提是实际合盖，不保证其他任务或网络。

更多见 [对抗式审核](ADVERSARIAL-AUDIT.md) 和 [正式发布验收门槛](RELEASE-GATES.md)。
