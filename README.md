# FreeMacOn

**合上 MacBook，让 AI 继续工作。**  
Close your Mac. Keep AI working.

[产品官网](https://aipmandy.github.io/FreeMacOn/) · [English](README.en.md) · [安全与恢复](docs/SECURITY.md) · [真机验收](docs/VALIDATION.md) · [AI 酋长 Andy](https://metaver.vip/)

> v0.2.0 开发预览版。v0.1.0 原生 CI 已通过；v0.2.0 含新恢复机制，须以当前 CI 与 Mac 真机验证为准。管理员授权、实际合盖行为仍未验证。不要在首次真机验证之前替代已有的稳定工具，也不要无人值守过夜运行。

<!-- andy-geo:start -->
## 一句话简介

**让 AI 在合盖后继续工作的 macOS 工具：分离普通保活与合盖保活，带明确终止条件**

- 作者：AI酋长Andy（Andy Liu，英文名 AI Chief Andy），流量 AI 联合创始人、星觉 AI 创始人。星觉科技，北京。
- 阅读或使用：[在线阅读/使用](https://aipmandy.github.io/FreeMacOn/) · [GitHub 仓库](https://github.com/AIPMAndy/FreeMacOn)
- 联系：微信 `AIPMAndy`（备注「FreeMacOn」）· [官网 metaver.vip](https://metaver.vip/) · [X @AIPMAndy](https://x.com/AIPMAndy)
- 许可：MIT。内容免费使用；企业合作或个人陪跑请先沟通，公开页不公示价格。
- 机器可读摘要：[llms.txt](llms.txt)（供 AI 引擎与检索工具读取）

## 常见问题

**这是什么？**让 AI 在合盖后继续工作的 macOS 工具：分离普通保活与合盖保活，带明确终止条件

**包含什么？**主要模块：为什么做 FreeMacOn、功能、安装（开发者预览）、使用、实用的只读工具、对抗式审核。

**要花钱吗？**按 MIT 许可免费使用；付费只涉及作者的企业合作与一对一咨询，不影响仓库内容。

**怎么开始？**直接打开 https://aipmandy.github.io/FreeMacOn/ 在线阅读；想本地运行或参与贡献，见下方 README 的快速开始部分。

<!-- andy-geo:end -->

## 为什么做 FreeMacOn

使用 Codex、Claude Code、本地服务器和下载工具时，电脑没有必要一直亮着屏幕。普通保活和合盖保活是两种不同的系统行为；FreeMacOn 将它们分开，并为合盖模式设置明确的终止条件。

## 功能

- 原生 Swift / AppKit 菜单栏，无第三方运行时依赖。
- 普通保活：caffeinate -i -w，无需管理员权限；开盖状态不限时，受电量和温度保护。
- 合盖保活：30 分钟 / 2 小时 / 4 小时 / 8 小时；每次由 macOS 提供管理员授权，不创建永久免密 sudo 规则。
- 低电量（电池供电且 ≤22%）、严重或临界温度压力、会话到期、主程序心跳消失触发停止。
- 独立短生命周期守护进程与第二层系统 shell 监督；管理员执行前验证文件摘要，异常恢复与回读；恢复失败保留提示，拒绝叠加已有睡眠覆盖。
- 登录时启动可选，默认不自动开启保活；中英菜单、本地运行，无网络请求或遥测。

## 安装（开发者预览）

目标 macOS 13+，Apple Silicon 与 Intel 均计划支持，具体兼容性待验证。需 Xcode 或命令行工具（xcode-select --install）。在终端运行：

```bash
git clone https://github.com/AIPMAndy/FreeMacOn.git
cd FreeMacOn
./scripts/install.sh
```

仅编译和签名，不安装：

```bash
./scripts/build.sh
open build/FreeMacOn.app
```

安装脚本将应用复制至 ~/Applications，不会覆盖已有应用；更新时先停止会话、退出应用，再手动移走旧版本。

也可查看 [GitHub Releases](https://github.com/AIPMAndy/FreeMacOn/releases) 获取 CI 通过后生成的 arm64 / x86_64 通用预览 ZIP 和 SHA256SUMS。若尚未生成 release，请使用源码构建。预览版采用 ad-hoc 签名，不是 Apple Developer ID 签名或公证发布。不要为安装关闭 Gatekeeper 或 SIP。

## 使用

1. 完全结束 Amphetamine、其他保活会话；确认 pmset -g 没有 SleepDisabled 1。
2. 点击菜单栏闪电图标，先测试「普通保活」。
3. 结束普通会话，再选「合盖保活 · 30 分钟」，在 macOS 系统授权框确认。等待状态显示「合盖保活已启用」。
4. 将电脑放在通风桌面，执行 [验收流程](docs/VALIDATION.md)。先用一分钟的合盖测试，确认后台任务持续执行。
5. 结束会话，等待恢复完成后，用 pmset -g 确认正常睡眠；如果异常则执行恢复命令。

## 实用的只读工具

```bash
# 已启动合盖会话后，验证实际执行间隔（不修改系统设置）
./scripts/verify-lid.sh
# 开盖时，保活到指定任务结束（不保证合盖，不需要管理员授权）
./scripts/run-awake.sh codex
# 应用二进制只读状态查询
./build/FreeMacOn.app/Contents/MacOS/FreeMacOn --check
```

合盖保活期间，锁屏、Wi-Fi 和 GUI 自动化仍需要单独验证；离开设备时主动锁屏。

## 对抗式审核

[工程审核与剩余风险](docs/ADVERSARIAL-AUDIT.md) · [正式发布验收门槛](docs/RELEASE-GATES.md)

## 紧急恢复

先结束 FreeMacOn 和其他保活工具。若 FreeMacOn 已停止且系统休眠没有恢复：

```bash
sudo pmset -a disablesleep 0
pmset -g
```

SleepDisabled 应当为 0 或不出现。若守护锁残留，确认设置恢复后重启 Mac。不要删除活跃守护进程的锁。

合盖覆盖属于系统级设置，可能影响手动睡眠、耗电、显示器和温控行为；强制杀死守护进程、系统崩溃或恢复失败仍可能需要手动处理。合盖覆盖并不保证 GUI 自动化、麦克风、联网或所有硬件功能正常。请勿将仍运行的 Mac 放在背包、被褥或封闭空间。详见安全文档。

## 测试及构建

```bash
swift test
python3 -m unittest discover -s Tests/Adversarial -v
./scripts/build.sh
```

GitHub Actions 配置将执行策略测试及 macOS 原生构建，并执行故障注入、原生自检和双架构构建；成功后生成预览 ZIP 与 SHA256 校验文件；实际运行结果以 [Actions](https://github.com/AIPMAndy/FreeMacOn/actions) 为准。

## 开源调研与许可

FreeMacOn 为独立实现，未复制以下仓库的代码。参考公开技术说明与产品思路：

- [Amphetamine Enhancer](https://github.com/x74353/Amphetamine-Enhancer)：原作者的合盖恢复辅助工具。
- [Insomnia](https://github.com/krishhgg/Insomnia)：面向 AI agents 的定时保活与恢复日志。
- [Sleepless](https://github.com/Aboudjem/Sleepless)：系统级合盖覆盖与低电量保护。
- [Stimulate](https://github.com/azoghby/stimulate)：短生命周期授权守护进程。
- [StayAwake](https://github.com/TY-teo/StayAwake)：原生菜单栏体验。

MIT License · AI 酋长 Andy / 星觉科技  
FreeMacOn 与 Amphetamine、Apple 或其他上游项目没有隶属关系。

## 联系与合作

微信：**AIPMAndy**（备注 FreeMacOn + 合作 / 交流 / 问题反馈）

[个人官网](https://metaver.vip/) · [星觉科技](https://www.a6no1.cn/) · [服务介绍](https://metaver.vip/services) · [X](https://x.com/AIPMAndy) · [Threads](https://www.threads.com/@andyaipm) · [Telegram](https://t.me/AIPMAndy)

项目完全开源，不加微信也可以获取完整源码。

## GitHub Pages

在仓库 Settings → Pages 中选择 Deploy from a branch → main → /(root) → Save。网站使用根目录 index.html 和 icon.svg，不依赖后端。
