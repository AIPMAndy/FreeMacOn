# FreeMacOn

Close your Mac. Keep AI working.

[Product website](https://aipmandy.github.io/FreeMacOn/) · [中文](README.md)

A native menu bar utility targeting macOS 13+ for coding agents and long-running jobs. **Developer preview: policy tests passed on Linux; macOS compilation, admin authorization and physical closed-lid behavior have not yet been verified.**

- Idle keep-awake via caffeinate -i -w, no admin grant.
- Timed closed-lid override (30 min, 2/4/8 hours) using pmset, with a per-session macOS administrator prompt.
- Independent watchdog checks battery (stop at ≤22% on battery), thermal state, deadline, app heartbeat and override readback.
- No permanent sudoers modification, network requests or telemetry. No automatic session on login.

On a Mac with Xcode Command Line Tools, run:

```bash
git clone https://github.com/AIPMAndy/FreeMacOn.git
cd FreeMacOn
./scripts/install.sh
```

End other keep-awake sessions first. Test a short supervised session on a ventilated surface before relying on it. Never place a running laptop in a bag. Read [validation](docs/VALIDATION.md) and [security](docs/SECURITY.md).

If FreeMacOn has stopped and normal sleep has not returned, end competing utilities, then run sudo pmset -a disablesleep 0 and pmset -g. Reboot after restoring the setting if a stale lock remains. Hardware, OS behavior and GUI automation are not guaranteed.

Run swift test for non-privileged policy tests. Build using ./scripts/build.sh on macOS; output is ad-hoc signed, not notarized. See GitHub Actions for CI results.

Independent MIT implementation. Research references are in [中文 README](README.md).

**AI Chief Andy** · WeChat: AIPMAndy · [Website](https://metaver.vip/) · [Company](https://www.a6no1.cn/) · [X](https://x.com/AIPMAndy) · [Telegram](https://t.me/AIPMAndy)
