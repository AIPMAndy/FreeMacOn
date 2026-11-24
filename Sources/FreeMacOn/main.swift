#if os(macOS)
import AppKit
import Foundation
import Darwin
import FreeMacOnCore
import ServiceManagement
import CryptoKit

let lockPath = "/var/run/vip.metaver.freemacon"
let statusPath = lockPath + "/status"
let pmset = "/usr/bin/pmset"
let fm = FileManager.default

struct CommandResult { let code: Int32; let output: String }
// Bound each subprocess, including failures, without waiting for pipe EOF from descendants.
// An unlinked, mode-0600 temporary file avoids pipe-buffer deadlocks.
func run(_ path: String, _ args: [String], timeout: TimeInterval = 5) -> CommandResult {
    var name = Array("/private/var/tmp/freemacon-command.XXXXXX".utf8CString)
    let fd = name.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
    guard fd >= 0 else { return CommandResult(code: -1, output: "Cannot create command output file") }
    _ = name.withUnsafeBufferPointer { unlink($0.baseAddress!) }
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    let process = Process(), done = DispatchSemaphore(value: 0)
    process.executableURL = URL(fileURLWithPath: path); process.arguments = args
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = file; process.standardError = file
    process.environment = path == pmset ? ["LC_ALL": "C", "LANG": "C", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"] : ProcessInfo.processInfo.environment.merging(["LC_ALL": "C", "LANG": "C"]) { _, new in new }
    process.terminationHandler = { _ in done.signal() }
    do { try process.run() } catch { return CommandResult(code: -1, output: error.localizedDescription) }
    if done.wait(timeout: .now() + timeout) == .timedOut {
        if process.isRunning { process.terminate() }
        if done.wait(timeout: .now() + 1) == .timedOut {
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            _ = done.wait(timeout: .now() + 1)
        }
        return CommandResult(code: -2, output: "Command timed out")
    }
    do {
        try file.seek(toOffset: 0)
        let data = try file.read(upToCount: 65536) ?? Data()
        return CommandResult(code: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    } catch { return CommandResult(code: -1, output: error.localizedDescription) }
}
func currentSleep() -> Bool? { let r = run(pmset, ["-g"]); return r.code == 0 ? Policy.sleepDisabled(r.output) : nil }
func currentPower() -> Power { let r = run(pmset, ["-g", "batt"]); return r.code == 0 ? Policy.power(r.output) : .unknown }
func isHot() -> Bool { let state = ProcessInfo.processInfo.thermalState; return state == .serious || state == .critical }
func heartbeatPath(_ uid: uid_t, _ token: UUID) -> String { "/var/tmp/freemacon.\(uid).\(token.uuidString)/heartbeat" }
func heartbeatTime(_ path: String, owner: uid_t) -> Date? {
    var info = stat()
    guard lstat(path, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_uid == owner else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9)
}
func rootStatus() -> String? { try? String(contentsOfFile: statusPath, encoding: .utf8) }
func publishStatus(_ value: String) -> Bool {
    do { try value.write(toFile: statusPath, atomically: true, encoding: .utf8); return true } catch { return false }
}
func clearRootLock() {
    // Only remove these two known, root-owned objects; never recurse as root.
    _ = unlink(statusPath); _ = rmdir(lockPath)
}
final class StopSignal {
    private let lock = NSLock(); private var stopped = false
    func set() { lock.lock(); stopped = true; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
func watchdog(_ args: [String]) -> Int32 {
    // No persistent privileged daemon or sudoers rule. Only fixed, local power commands.
    guard geteuid() == 0, args.count == 4, let uid = uid_t(args[0]), uid != 0,
          let token = UUID(uuidString: args[1]), let minutes = Int(args[2]), Policy.validClosedMinutes(minutes),
          let startEpoch = TimeInterval(args[3]), startEpoch.isFinite else { return 2 }
    let start = Date(timeIntervalSince1970: startEpoch), deadline = start.addingTimeInterval(Double(minutes * 60))
    guard abs(Date().timeIntervalSince(start)) < 300 else { return 2 }
    let hb = heartbeatPath(uid, token), prefix = token.uuidString
    guard Policy.stopReason(now: Date(), deadline: deadline, heartbeat: heartbeatTime(hb, owner: uid), power: currentPower(), hot: isHot()) == nil else { return 3 }
    guard mkdir(lockPath, 0o755) == 0 else { return 4 }
    // chmod explicitly in case the administrator environment has a restrictive umask.
    _ = chmod(lockPath, 0o755)
    guard currentSleep() == false,
          Policy.stopReason(now: Date(), deadline: deadline, heartbeat: heartbeatTime(hb, owner: uid), power: currentPower(), hot: isHot()) == nil else { clearRootLock(); return 5 }
    guard publishStatus("\(prefix):starting") else { clearRootLock(); return 6 }
    _ = chmod(statusPath, 0o644)
    let stop = StopSignal()
    let signals = [SIGTERM, SIGINT, SIGHUP].map { number -> DispatchSourceSignal in
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler { stop.set() }; source.resume(); return source
    }
    defer { signals.forEach { $0.cancel() } }
    // Mark ownership before attempting a change: even partial failures trigger rollback.
    let monotonicDeadline = ProcessInfo.processInfo.systemUptime + max(0, min(Double(minutes * 60), deadline.timeIntervalSinceNow))
    let changed = run(pmset, ["-a", "disablesleep", "1"])
    var reason = "activationFailed"
    if changed.code == 0, currentSleep() == true, publishStatus("\(prefix):active") {
        _ = chmod(statusPath, 0o644)
        reason = "stopped"
        while !stop.get() {
            if ProcessInfo.processInfo.systemUptime >= monotonicDeadline { reason = "deadline"; break }
            if let guardrail = Policy.stopReason(now: Date(), deadline: deadline, heartbeat: heartbeatTime(hb, owner: uid), power: currentPower(), hot: isHot(), overrideOK: currentSleep() == true) { reason = guardrail.rawValue; break }
            Thread.sleep(forTimeInterval: 3)
        }
    }
    _ = publishStatus("\(prefix):restoring:\(reason)"); _ = chmod(statusPath, 0o644)
    for _ in 0..<3 {
        if currentSleep() == false { clearRootLock(); return 0 }
        _ = run(pmset, ["-a", "disablesleep", "0"])
        if currentSleep() == false { clearRootLock(); return 0 }
        Thread.sleep(forTimeInterval: 2)
    }
    // Preserve visible failure state instead of claiming successful recovery.
    _ = publishStatus("\(prefix):recoveryRequired"); _ = chmod(statusPath, 0o644)
    return 7
}

// The system shell is a second, independent rollback layer. It snapshots the approved
// executable into a root-owned directory and checks the digest before running it as root.
// No persistent service, extra authorization rule or executable from a mutable path is used.
let supervisorScript = #"""
set -u
umask 077
export PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C LANG=C
unset ENV BASH_ENV CDPATH
binary=$1
expected=$2
uid=$3
token=$4
minutes=$5
started=$6
lock=/var/run/vip.metaver.freemacon
status=$lock/status
stage=$(/usr/bin/mktemp -d /private/var/run/vip.metaver.freemacon-helper.XXXXXX) || exit 10
cleanup() { /bin/rm -f "$stage/helper" "$stage/probe"; /bin/rmdir "$stage" 2>/dev/null || :; }
trap cleanup EXIT
/usr/bin/install -m 0500 "$binary" "$stage/helper" || exit 11
actual=$(/usr/bin/shasum -a 256 "$stage/helper" | /usr/bin/awk '{print $1}')
[ "$actual" = "$expected" ] || exit 12
owned() {
  [ -f "$status" ] || return 1
  case "$(/bin/cat "$status" 2>/dev/null)" in "$token":*) return 0;; *) return 1;; esac
}
bounded() {
  "$@" &
  child=$!
  ( /bin/sleep 6; kill -TERM "$child" 2>/dev/null || :; /bin/sleep 1; kill -KILL "$child" 2>/dev/null || : ) &
  timer=$!
  wait "$child"; rc=$?
  kill "$timer" 2>/dev/null || :
  wait "$timer" 2>/dev/null || :
  return "$rc"
}
restored() {
  bounded /usr/bin/pmset -g > "$stage/probe" 2>&1 || return 1
  /usr/bin/awk '
    /^System-wide power settings:|^Currently in use:|^Active Profiles:/ { header=1 }
    $1=="SleepDisabled" || $1=="disablesleep" { seen=1; if(NF!=2 || $2!="0") bad=1 }
    $1=="sleep" && $2 ~ /^[0-9]+$/ { profile=1 }
    END { exit !(header && !bad && (seen || profile)) }
  ' "$stage/probe"
}
# A normal watchdog exit clears the owned lock. An abnormal exit may not.
# Check the exact session token before every action; never touch another session.
"$stage/helper" --watchdog "$uid" "$token" "$minutes" "$started"
result=$?
if owned; then
  for attempt in 1 2 3; do
    owned || exit "$result"
    if restored; then
      /bin/rm -f "$status"
      /bin/rmdir "$lock" 2>/dev/null || :
      exit 0
    fi
    bounded /usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1 || :
    if owned && restored; then
      /bin/rm -f "$status"
      /bin/rmdir "$lock" 2>/dev/null || :
      exit 0
    fi
    /bin/sleep 2
  done
  if owned; then
    printf '%s:recoveryRequired' "$token" > "$status"
    /bin/chmod 0644 "$status"
  fi
fi
exit "$result"
"""#

func approvedDigest(_ path: String) -> String? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var tickTimer: Timer?
    var caffeinate: Process?
    var deadline: Date?
    var token: UUID?
    var hb: String?
    var awaiting = false
    var stopping = false
    var stoppingSince: Date?
    var menuOpen = false
    var activationDeadline: Date?
    var lastMessage = ""
    var quitAfterStop = false
    var displayedPower: Power = .unknown
    var displayedSleep: Bool?
    var chinese: Bool { Locale.preferredLanguages.first?.hasPrefix("zh") ?? false }
    func tr(_ zh: String, _ en: String) -> String { chinese ? zh : en }
    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.imagePosition = .imageLeading
        item.menu = menu
        menu.delegate = self
        tickTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tickTimer!, forMode: .common)
        refreshStatus(); rebuild()
    }
    func refreshStatus() { displayedPower = currentPower(); displayedSleep = currentSleep() }
    var isClosed: Bool { token != nil }
    var isRunning: Bool { caffeinate?.isRunning == true }
    var ownedStatus: String? {
        guard let token, let s = rootStatus(), s.hasPrefix(token.uuidString + ":") else { return nil }
        return s
    }
    func add(_ title: String, _ action: Selector? = nil, tag: Int = 0, enabled: Bool = true) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self; entry.tag = tag; entry.isEnabled = enabled; menu.addItem(entry)
    }
    func timeLeft() -> String {
        guard let deadline else { return tr("无限期", "Until stopped") }
        let n = max(0, Int(ceil(deadline.timeIntervalSinceNow / 60)))
        return "\(n / 60)h \(n % 60)m"
    }
    func menuWillOpen(_ menu: NSMenu) { refreshStatus(); rebuild(); menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; rebuild() }
    func rebuild() {
        if menuOpen { return }
        menu.autoenablesItems = false; menu.removeAllItems()
        let locked = fm.fileExists(atPath: lockPath)
        let active = ownedStatus?.hasSuffix(":active") == true && isRunning && !stopping
        let busy = isClosed || isRunning || awaiting || stopping
        let icon = active || isRunning ? "bolt.circle.fill" : "bolt.circle"
        let symbol = NSImage(systemSymbolName: icon, accessibilityDescription: "FreeMacOn")
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let image = symbol?.withSymbolConfiguration(configuration) ?? symbol
        image?.isTemplate = true
        item.button?.image = image
        item.button?.title = busy ? " " + timeLeft() : ""
        let state: String
        if rootStatus()?.hasSuffix(":recoveryRequired") == true { state = tr("⚠ 必须手动恢复睡眠", "⚠ Manual recovery required") }
        else if stopping { state = tr("正在恢复睡眠…", "Restoring sleep…") }
        else if awaiting { state = tr("等待授权 / 验证…", "Authorizing / verifying…") }
        else if active { state = tr("合盖保活已启用", "Closed-lid override active") }
        else if isRunning { state = tr("普通保活已启用", "Idle keep-awake active") }
        else if locked || displayedSleep != false { state = tr("发现睡眠覆盖或未恢复的会话", "Existing override or unrecovered session") }
        else { state = tr("正常睡眠", "Normal sleep policy") }
        add("FreeMacOn · \(state)", enabled: false)
        if !lastMessage.isEmpty { add(lastMessage, enabled: false) }
        switch displayedPower {
        case .ac: add(tr("电源：已接入", "Power: AC"), enabled: false)
        case .battery(let level): add(tr("电池：\(level)% · 22% 自动停止", "Battery: \(level)% · stop at 22%"), enabled: false)
        case .unknown: add(tr("电源状态未知", "Power state unknown"), enabled: false)
        }
        menu.addItem(.separator())
        add(tr("普通保活 · 不合盖", "Keep awake · lid open"), #selector(startNormal(_:)), tag: 0, enabled: !busy && !locked)
        add(tr("合盖保活 · 30 分钟", "Closed lid · 30 min"), #selector(startClosed(_:)), tag: 30, enabled: !busy && !locked)
        add(tr("合盖保活 · 2 小时", "Closed lid · 2 hours"), #selector(startClosed(_:)), tag: 120, enabled: !busy && !locked)
        add(tr("合盖保活 · 4 小时", "Closed lid · 4 hours"), #selector(startClosed(_:)), tag: 240, enabled: !busy && !locked)
        add(tr("合盖保活 · 8 小时", "Closed lid · 8 hours"), #selector(startClosed(_:)), tag: 480, enabled: !busy && !locked)
        add(tr("结束会话", "End session"), #selector(endSession), enabled: busy)
        menu.addItem(.separator())
        add(tr("开机登录时启动（仅启动应用）", "Launch at login (app only)"), #selector(toggleLogin))
        menu.items.last?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        add(tr("一分钟合盖验证指南", "One-minute lid verification"), #selector(verificationGuide))
        add(tr("恢复说明 / 自检", "Recovery / diagnostics"), #selector(diagnostics))
        add(tr("关于 FreeMacOn", "About FreeMacOn"), #selector(about))
        add(tr("退出", "Quit"), #selector(quit))
    }
    func alert(_ title: String, _ text: String) { NSApp.activate(ignoringOtherApps: true); let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal() }
    func launchCaffeinate() -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-i", "-w", String(getpid())]
        do { try p.run(); caffeinate = p; return true } catch { lastMessage = error.localizedDescription; return false }
    }
    func safeToStart() -> Bool {
        refreshStatus()
        if fm.fileExists(atPath: lockPath) || displayedSleep != false { lastMessage = tr("已有睡眠覆盖或无法验证，请先恢复", "Existing sleep override or unknown state; recover first"); return false }
        if Policy.stopReason(now: Date(), deadline: nil, heartbeat: nil, power: displayedPower, hot: isHot(), requiresHeartbeat: false) != nil { lastMessage = tr("电量、温度或电源状态不满足要求", "Battery, temperature or power check failed"); return false }
        return true
    }
    @objc func startNormal(_ sender: NSMenuItem) {
        guard !isRunning, !isClosed, safeToStart() else { rebuild(); return }
        lastMessage = ""; deadline = nil; _ = launchCaffeinate(); rebuild()
    }
    @objc func startClosed(_ sender: NSMenuItem) {
        guard !isRunning, !isClosed, Policy.validClosedMinutes(sender.tag), safeToStart() else { rebuild(); return }
        let a = NSAlert(); a.messageText = tr("启用合盖保活？", "Enable closed-lid keep awake?")
        a.informativeText = tr("将暂时修改系统级睡眠设置，需要管理员授权。请放在通风桌面，不要装入包中；退出、低电量、高温或到期将尝试恢复。不要同时运行其他保活工具。", "This temporarily changes a system-wide setting and requires administrator authorization. Keep the Mac ventilated, never in a bag. Exit, low battery, high temperature or timeout attempts to restore sleep. Do not use another keep-awake tool simultaneously.")
        a.addButton(withTitle: tr("继续", "Continue")); a.addButton(withTitle: tr("取消", "Cancel")); NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let t = UUID(), path = heartbeatPath(getuid(), t), dir = (path as NSString).deletingLastPathComponent
        guard mkdir(dir, 0o700) == 0, fm.createFile(atPath: path, contents: Data(), attributes: [.posixPermissions: 0o600]) else { lastMessage = tr("创建会话失败", "Cannot create session"); rebuild(); return }
        let started = Date(); token = t; hb = path; deadline = started.addingTimeInterval(Double(sender.tag * 60)); awaiting = true; activationDeadline = started.addingTimeInterval(120); lastMessage = ""
        guard launchCaffeinate() else { finishLocal(); rebuild(); return }
        guard let executable = Bundle.main.executablePath, let digest = approvedDigest(executable) else {
            lastMessage = tr("无法验证应用文件", "Cannot verify application executable"); finishLocal(); rebuild(); return
        }
        let args = ["/bin/sh", "-c", supervisorScript, "freemacon-supervisor", executable, digest, String(getuid()), t.uuidString, String(sender.tag), String(started.timeIntervalSince1970)]
        let command = "/usr/bin/nohup " + args.map(Policy.shellQuote).joined(separator: " ") + " </dev/null >/dev/null 2>&1 &"
        // Pass the command as an AppleScript argv item, not interpolated script source.
        let script = "on run argv\n do shell script (item 1 of argv) with administrator privileges\nend run"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = run("/usr/bin/osascript", ["-e", script, command], timeout: 125)
            DispatchQueue.main.async {
                guard let self, self.token == t else { return }
                if result.code != 0 { self.lastMessage = self.tr("授权取消或失败", "Authorization canceled or failed"); self.requestStop() }
                self.rebuild()
            }
        }
        rebuild()
    }
    func requestStop() {
        if let hb { _ = unlink(hb) }
        if isClosed { if !stopping { stoppingSince = Date() }; stopping = true; awaiting = false } else { finishLocal() }
    }
    func finishLocal() {
        if let hb { _ = unlink(hb); _ = rmdir((hb as NSString).deletingLastPathComponent) }
        if let p = caffeinate, p.isRunning { p.terminate() }
        caffeinate = nil; token = nil; hb = nil; deadline = nil; awaiting = false; stopping = false; stoppingSince = nil; activationDeadline = nil
    }
    @objc func endSession() { requestStop(); tick() }
    func tick() {
        // Avoid spawning pmset continuously when the app is idle. Refresh on menu open.
        guard isClosed || caffeinate != nil || quitAfterStop else { return }
        displayedPower = currentPower()
        if isClosed {
            let status = ownedStatus
            if status?.hasSuffix(":recoveryRequired") == true { finishLocal(); lastMessage = tr("恢复失败，请查看恢复说明", "Recovery failed; see diagnostics") }
            else if stopping {
                // If authorization was canceled before the helper acquired the lock, the removed heartbeat prevents activation.
                if status == nil && !fm.fileExists(atPath: lockPath) { finishLocal(); lastMessage = currentSleep() == false ? tr("会话已结束", "Session ended") : tr("请验证系统睡眠", "Verify system sleep") }
                else if let stoppingSince, Date().timeIntervalSince(stoppingSince) > 45 { finishLocal(); lastMessage = tr("恢复确认超时，请查看恢复说明", "Recovery confirmation timed out; see diagnostics") }
            } else if !isRunning || Policy.stopReason(now: Date(), deadline: deadline, heartbeat: nil, power: displayedPower, hot: isHot(), requiresHeartbeat: false) != nil { requestStop() }
            else if status?.contains(":restoring:") == true { requestStop() }
            else if awaiting && status?.hasSuffix(":active") == true { awaiting = false }
            else if awaiting && (activationDeadline?.timeIntervalSinceNow ?? -1) <= 0 { lastMessage = tr("授权或验证超时", "Authorization or verification timed out"); requestStop() }
            else if !awaiting && status?.hasSuffix(":active") != true { requestStop() }
            if !stopping, let hb { do { try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: hb) } catch { requestStop() } }
        } else if caffeinate != nil && !isRunning {
            finishLocal(); lastMessage = tr("保活进程已退出", "Keep-awake process exited")
        } else if isRunning {
            if Policy.stopReason(now: Date(), deadline: nil, heartbeat: nil, power: displayedPower, hot: isHot(), requiresHeartbeat: false) != nil { finishLocal(); lastMessage = tr("保护机制已停止会话", "Guardrail stopped session") }
        }
        if !isClosed && caffeinate == nil { displayedSleep = currentSleep() }
        rebuild()
        if quitAfterStop && !isClosed {
            quitAfterStop = false
            if displayedSleep == false && !fm.fileExists(atPath: lockPath) { NSApp.terminate(nil) }
            else { alert(tr("请先确认恢复睡眠", "Confirm sleep recovery"), tr("恢复尚未确认。请打开恢复说明。", "Recovery is not verified. Open Recovery / diagnostics.")) }
        }
    }
    @objc func toggleLogin() {
        do { if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() } }
        catch { alert(tr("登录项设置失败", "Login item failed"), error.localizedDescription) }
        rebuild()
    }
    @objc func verificationGuide() {
        if let url = URL(string: "https://github.com/AIPMAndy/FreeMacOn/blob/main/docs/VALIDATION.md") { NSWorkspace.shared.open(url) }
    }
    @objc func diagnostics() {
        let state = run(pmset, ["-g"])
        alert(tr("恢复与自检", "Recovery and diagnostics"), tr("先结束其他保活工具。若 FreeMacOn 已停止但睡眠仍被禁用，请在终端执行：", "End other keep-awake tools first. If FreeMacOn has stopped but sleep remains disabled, run in Terminal:") + "\n\nsudo pmset -a disablesleep 0\npmset -g\n\n" + tr("若守护锁仍存在，恢复设置后重启 Mac。", "If a stale watchdog lock remains, reboot after restoring the setting.") + "\n\n" + state.output)
    }
    @objc func about() { alert("FreeMacOn 0.2.0", tr("合上 Mac，让 AI 继续工作。\nAI 酋长 Andy · 星觉科技\n独立开源实现 · MIT\nhttps://metaver.vip/\n预览版：尚需 Mac 真机合盖与恢复测试。", "Close your Mac. Keep AI working.\nAI Chief Andy · MIT\nhttps://metaver.vip/\nPreview: physical lid and recovery testing required.")) }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isClosed { quitAfterStop = true; requestStop(); rebuild(); return .terminateCancel }
        finishLocal(); return .terminateNow
    }
}
let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--watchdog" { exit(watchdog(Array(args.dropFirst()))) }
if args.first == "--diagnostics" { print(run(pmset, ["-g"]).output); exit(0) }
if args.first == "--version" { print("FreeMacOn 0.2.0"); exit(0) }
if args.first == "--self-test" {
    let sample = "FreeMacOn-self-test"
    let quick = run("/usr/bin/printf", ["%s", sample], timeout: 3)
    let started = ProcessInfo.processInfo.systemUptime
    let slow = run("/bin/sleep", ["5"], timeout: 0.2)
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    let ok = quick.code == 0 && quick.output == sample && slow.code == -2 && elapsed < 3
    print("Non-privileged command runner self-test: \(ok ? "PASS" : "FAIL")")
    exit(ok ? 0 : 1)
}
if args.first == "--check" {
    let setting: String = currentSleep().map { $0 ? "disabled" : "normal" } ?? "unknown"
    let power: String
    switch currentPower() { case .ac: power = "AC"; case .battery(let n): power = "battery \(n)%"; case .unknown: power = "unknown" }
    print("FreeMacOn 0.2.0\nSleep: \(setting)\nPower: \(power)\nThermal guard: \(isHot() ? "stop" : "clear")\nSession lock: \(fm.fileExists(atPath: lockPath) ? "present" : "absent")")
    exit(setting == "unknown" ? 2 : 0)
}
guard geteuid() != 0 else { fputs("Do not run the GUI as root.\n", stderr); exit(2) }
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
#else
import Foundation
print("FreeMacOn is a macOS menu bar application. Run scripts/build.sh on macOS.")
#endif
