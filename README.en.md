# FreeMacOn

Close your Mac. Keep AI working.

[Product website](https://aipmandy.github.io/FreeMacOn/) · [中文](README.md)

A native menu bar utility targeting macOS 13+ for coding agents and long-running jobs. **Developer preview: v0.1.0 macOS CI passed; v0.2.0 has new recovery logic. Check current CI. Admin authorization and physical closed-lid behavior remain unverified.**

- Idle keep-awake via caffeinate -i -w, no admin grant.
- Timed closed-lid override (30 min, 2/4/8 hours) using pmset, with a per-session macOS administrator prompt.
- A short-lived watchdog and independent rollback supervisor check battery (stop at ≤22% on battery), thermal state, deadline, app heartbeat and override readback.
- No permanent sudoers modification, network requests or telemetry. No automatic session on login.

On a Mac with Xcode Command Line Tools, run:

```bash
git clone https://github.com/AIPMAndy/FreeMacOn.git
cd FreeMacOn
./scripts/install.sh
```

End other keep-awake sessions first. Test a short supervised session on a ventilated surface before relying on it. Never place a running laptop in a bag. Read [validation](docs/VALIDATION.md) and [security](docs/SECURITY.md).

If FreeMacOn has stopped and normal sleep has not returned, end competing utilities, then run sudo pmset -a disablesleep 0 and pmset -g. Reboot after restoring the setting if a stale lock remains. Hardware, OS behavior and GUI automation are not guaranteed.

Run swift test and python3 -m unittest discover -s Tests/Adversarial -v for non-privileged policy and simulated fault tests. Run scripts/verify-lid.sh for supervised gap detection; scripts/run-awake.sh binds ordinary idle keep-awake to a command. See GitHub Releases for any CI-built universal developer preview. Read [adversarial audit](docs/ADVERSARIAL-AUDIT.md) and [release gates](docs/RELEASE-GATES.md). Build using ./scripts/build.sh on macOS; output is ad-hoc signed, not notarized. See GitHub Actions for CI results.

Independent MIT implementation. Research references are in [中文 README](README.md).

**AI Chief Andy** · WeChat: AIPMAndy · [Website](https://metaver.vip/) · [Company](https://www.a6no1.cn/) · [X](https://x.com/AIPMAndy) · [Telegram](https://t.me/AIPMAndy)
