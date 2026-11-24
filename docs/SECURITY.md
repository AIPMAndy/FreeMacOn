# 安全设计 / Security model

## 权限边界
- 普通保活使用系统 caffeinate，并绑定 GUI 进程 PID。合盖保活需要管理员批准。
- 使用 macOS 的管理员授权对话框，不收集密码；不写 sudoers、不安装常驻守护服务、不修改 Gatekeeper、SIP、锁屏或防火墙配置。
- 守护进程只运行固定绝对路径的 pmset 命令。授权会运行本地应用二进制作为 root；应仅授权自己编译或来源可信、签名校验通过的应用。预览版没有 Developer ID 公证或第三方安全审计。
- root 在 /var/run/vip.metaver.freemacon 使用单会话锁，并写可读状态。主进程使用随机 UUID 和用户专属 heartbeat 文件；root 只读取其类型、所属 UID 和 mtime，不执行其内容，不写该目录。
- 若初始 SleepDisabled 已开启或读取不可信，则拒绝接管。若外部程序修改该标记，可能与本软件冲突；不要同时开启同类工具。
- 默认保留系统锁屏、温度及低电量策略。温度/电量保护使用操作系统提供的信息，不是物理温度安全保证。

## 恢复路径
守护进程每约 3 秒检查电源、热压力、deadline、心跳和标志；心跳超过 25 秒即停止。检查受进程调度与系统命令耗时影响。守护进程先尝试恢复 pmset -a disablesleep 0，读取结果，最多重试三次；失败保留状态与锁。主程序异常退出时应由独立 watchdog 处理，尚待实机测试。SIGKILL、系统崩溃、管理员权限变动或 pmset 失效可能阻止恢复；不能承诺绝对安全。

若应用已停止且异常仍存在，先结束其他保活工具，再执行：

```bash
sudo pmset -a disablesleep 0
pmset -g
```

验证 SleepDisabled 为 0 或不存在。若仍有残留会话锁，在确认恢复后重启。不要移除正在使用的锁，不要通过禁用 SIP 或安全机制解决问题。

## 卸载
先结束会话并验证恢复，取消菜单中的登录启动选项，然后退出应用。手动将 ~/Applications/FreeMacOn.app 移至废纸篓。没有持续 sudoers 规则或 launch daemon。应用崩溃可能留下临时心跳目录；重启后再清理属于自己的 freemacon.<uid>.<uuid> 临时目录。
