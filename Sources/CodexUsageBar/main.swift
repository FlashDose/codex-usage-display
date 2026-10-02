import AppKit
import Foundation

private struct UsageWindow {
    let remainingPercent: Int
    let resetsAt: Date?
}

private struct UsageSnapshot {
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?
    let fetchedAt: Date
}

private enum UsageBarError: LocalizedError {
    case cliNotFound
    case processStart(String)
    case requestTimedOut(String)
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "找不到 Codex CLI。请安装并登录 Codex CLI 后重试。"
        case .processStart(let detail):
            return "无法启动 Codex app-server：\(detail)"
        case .requestTimedOut(let method):
            return "Codex 用量读取超时（\(method)）。"
        case .server(let detail):
            return detail
        case .invalidResponse:
            return "Codex 返回的用量数据格式无法识别。"
        }
    }
}

/// Talks to the local Codex app-server using its newline-delimited JSON protocol.
/// Only account/rateLimits/read is called; no account or thread data is modified.
private final class AppServerUsageReader {
    private struct PendingRequest {
        let method: String
        let completion: (Result<[String: Any], Error>) -> Void
    }

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var buffer = Data()
    private var pending: [Int: PendingRequest] = [:]
    private var nextRequestID = 1
    private var initialized = false
    private var isFetching = false
    private var waitingCompletions: [(Result<UsageSnapshot, Error>) -> Void] = []

    func fetch(completion: @escaping (Result<UsageSnapshot, Error>) -> Void) {
        waitingCompletions.append(completion)
        guard !isFetching else { return }
        isFetching = true

        ensureStarted { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finish(.failure(error))
            case .success:
                self.readRateLimits()
            }
        }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    private func ensureStarted(completion: @escaping (Result<Void, Error>) -> Void) {
        if process?.isRunning == true {
            if initialized {
                completion(.success(()))
            } else {
                initialize(completion: completion)
            }
            return
        }

        guard let executable = Self.codexExecutable() else {
            completion(.failure(UsageBarError.cliNotFound))
            return
        }

        let nextProcess = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        nextProcess.executableURL = executable
        nextProcess.arguments = ["app-server"]
        nextProcess.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        nextProcess.standardInput = stdin
        nextProcess.standardOutput = stdout
        nextProcess.standardError = FileHandle.nullDevice

        process = nextProcess
        inputPipe = stdin
        outputPipe = stdout
        initialized = false
        buffer.removeAll(keepingCapacity: true)

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }

        nextProcess.terminationHandler = { [weak self] terminatedProcess in
            DispatchQueue.main.async {
                guard let self, self.process === terminatedProcess else { return }
                self.process = nil
                self.inputPipe = nil
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self.outputPipe = nil
                self.initialized = false
            }
        }

        do {
            try nextProcess.run()
            initialize(completion: completion)
        } catch {
            process = nil
            inputPipe = nil
            outputPipe = nil
            completion(.failure(UsageBarError.processStart(error.localizedDescription)))
        }
    }

    private func initialize(completion: @escaping (Result<Void, Error>) -> Void) {
        request(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "codex-usage-bar",
                    "title": "Codex Usage Bar",
                    "version": "0.1.0"
                ],
                "capabilities": ["experimentalApi": true]
            ]
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                self.sendNotification(method: "initialized")
                self.initialized = true
                completion(.success(()))
            }
        }
    }

    private func readRateLimits() {
        request(
            method: "account/rateLimits/read",
            params: ["excludeResetCreditDetails": true]
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finish(.failure(error))
            case .success(let response):
                guard let snapshot = Self.parseSnapshot(response) else {
                    self.finish(.failure(UsageBarError.invalidResponse))
                    return
                }
                self.finish(.success(snapshot))
            }
        }
    }

    private func request(
        method: String,
        params: [String: Any],
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        let requestID = nextRequestID
        nextRequestID += 1
        pending[requestID] = PendingRequest(method: method, completion: completion)
        sendMessage(["id": requestID, "method": method, "params": params])

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, let request = self.pending.removeValue(forKey: requestID) else { return }
            request.completion(.failure(UsageBarError.requestTimedOut(request.method)))
            self.resetAfterTimeout()
        }
    }

    private func sendNotification(method: String) {
        sendMessage(["method": method])
    }

    private func sendMessage(_ object: [String: Any]) {
        guard let input = inputPipe?.fileHandleForWriting,
              let data = try? JSONSerialization.data(withJSONObject: object),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        input.write(Data(line.utf8))
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                continue
            }
            handleMessage(object)
        }
    }

    private func handleMessage(_ object: [String: Any]) {
        guard let rawID = object["id"], let requestID = Self.integer(rawID),
              let request = pending.removeValue(forKey: requestID) else { return }

        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Codex app-server 请求失败。"
            request.completion(.failure(UsageBarError.server(message)))
        } else if let result = object["result"] as? [String: Any] {
            request.completion(.success(result))
        } else {
            request.completion(.failure(UsageBarError.invalidResponse))
        }
    }

    private func finish(_ result: Result<UsageSnapshot, Error>) {
        isFetching = false
        let completions = waitingCompletions
        waitingCompletions.removeAll()
        completions.forEach { $0(result) }
    }

    private func resetAfterTimeout() {
        initialized = false
        if let process, process.isRunning { process.terminate() }
        process = nil
        inputPipe = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
    }

    private static func parseSnapshot(_ response: [String: Any]) -> UsageSnapshot? {
        let buckets = response["rateLimitsByLimitId"] as? [String: Any]
        let limits = (buckets?["codex"] as? [String: Any])
            ?? (response["rateLimits"] as? [String: Any])
        guard let limits else { return nil }

        return UsageSnapshot(
            fiveHour: parseWindow(limits["primary"]),
            weekly: parseWindow(limits["secondary"]),
            fetchedAt: Date()
        )
    }

    private static func parseWindow(_ value: Any?) -> UsageWindow? {
        guard let window = value as? [String: Any],
              let usedPercent = integer(window["usedPercent"]) else { return nil }
        let remaining = max(0, min(100, 100 - usedPercent))
        let resetTimestamp = (window["resetsAt"] as? NSNumber)?.doubleValue
        let resetsAt = resetTimestamp.map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(remainingPercent: remaining, resetsAt: resetsAt)
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        return number.intValue
    }

    private static func codexExecutable() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["CODEX_CLI_PATH"], FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let embeddedCLI = "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        var candidates = [
            "/Applications/ChatGPT.app/\(embeddedCLI)",
            "\(home)/Applications/ChatGPT.app/\(embeddedCLI)",
            "/Applications/Codex.app/\(embeddedCLI)",
            "\(home)/Applications/Codex.app/\(embeddedCLI)",
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        candidates.append(contentsOf: (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" })

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}

private final class UsageStatusView: NSView {
    private var fiveHourText = "—"
    private var weeklyText = "—"
    private var countdownText = "↻ —"

    override var isFlipped: Bool { true }

    // Keep the status bar button responsible for clicks and its menu.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(fiveHour: String, weekly: String, countdown: String) {
        fiveHourText = fiveHour
        weeklyText = weekly
        countdownText = countdown
        needsDisplay = true
    }

    var preferredWidth: CGFloat {
        let lines = measuredLines(for: bounds.height > 0 ? bounds.height : 24)
        let resetWidth = lines.reset.size().width
        let usageWidth = lines.usage.size().width
        // The reset line starts at the usage line's left edge.
        return max(36, ceil(max(usageWidth, 2 * resetWidth - usageWidth) + 12))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let lines = measuredLines(for: bounds.height)
        let reset = lines.reset
        let usage = lines.usage
        let overlap = lines.overlap
        let resetSize = reset.size()
        let usageSize = usage.size()
        let contentHeight = resetSize.height + usageSize.height - overlap
        let topY = (bounds.height - contentHeight) / 2
        let usageX = (bounds.width - usageSize.width) / 2
        reset.draw(in: NSRect(
            x: usageX,
            y: topY,
            width: resetSize.width,
            height: resetSize.height
        ))
        usage.draw(in: NSRect(
            x: usageX,
            y: topY + resetSize.height - overlap,
            width: usageSize.width,
            height: usageSize.height
        ))
    }

    private func measuredLines(for height: CGFloat) -> (reset: NSAttributedString, usage: NSAttributedString, overlap: CGFloat) {
        let overlap: CGFloat = 3
        let availableHeight = max(1, height - 1)
        let resetFontSize = min(11, max(8, height * 0.34))
        let usageFontSize = min(15, height * 0.52)
        var reset = resetLine(fontSize: resetFontSize)
        var usage = usageLine(fontSize: usageFontSize)
        let naturalHeight = reset.size().height + usage.size().height - overlap
        if naturalHeight > availableHeight {
            let scale = availableHeight / naturalHeight
            reset = resetLine(fontSize: resetFontSize * scale)
            usage = usageLine(fontSize: usageFontSize * scale)
        }
        return (reset, usage, overlap)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func resetLine(fontSize: CGFloat) -> NSAttributedString {
        NSAttributedString(string: countdownText, attributes: [
            .font: NSFont.menuBarFont(ofSize: fontSize),
            .foregroundColor: NSColor.labelColor
        ])
    }

    private func usageLine(fontSize: CGFloat) -> NSAttributedString {
        let valuesFont = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let line = NSMutableAttributedString(string: fiveHourText, attributes: [
            .font: valuesFont,
            .foregroundColor: NSColor.labelColor
        ])
        line.append(NSAttributedString(string: "  ", attributes: [
            .font: valuesFont,
            .foregroundColor: NSColor.labelColor
        ]))
        line.append(NSAttributedString(string: weeklyText, attributes: [
            .font: valuesFont,
            .foregroundColor: NSColor.systemTeal
        ]))
        return line
    }
}

@main
private enum CodexUsageBarMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let reader = AppServerUsageReader()
    private var statusItem: NSStatusItem!
    private var statusView: UsageStatusView!
    private var fiveHourItem: NSMenuItem!
    private var fiveHourResetItem: NSMenuItem!
    private var weeklyItem: NSMenuItem!
    private var weeklyResetItem: NSMenuItem!
    private var updatedItem: NSMenuItem!
    private var errorItem: NSMenuItem!
    private var snapshot: UsageSnapshot?
    private var lastError: String?
    private var refreshTimer: Timer?
    private var countdownTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let statusButton = statusItem.button!
        statusButton.title = ""
        statusView = UsageStatusView(frame: statusButton.bounds)
        statusView.autoresizingMask = [.width, .height]
        statusButton.addSubview(statusView)

        let menu = NSMenu()
        menu.delegate = self
        fiveHourItem = disabledItem("5 小时剩余：读取中…")
        fiveHourResetItem = disabledItem("重置时间：—")
        weeklyItem = disabledItem("每周剩余：读取中…")
        weeklyResetItem = disabledItem("重置时间：—")
        updatedItem = disabledItem("上次更新：—")
        errorItem = disabledItem("")
        menu.addItem(disabledItem("Codex 用量"))
        menu.addItem(fiveHourItem)
        menu.addItem(fiveHourResetItem)
        menu.addItem(weeklyItem)
        menu.addItem(weeklyResetItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(updatedItem)
        menu.addItem(errorItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "立即刷新", action: #selector(refreshNow(_:)), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        updateDisplay()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
            }
        }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.updateDisplay()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        countdownTimer?.invalidate()
        reader.stop()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    @objc private func refreshNow(_ sender: Any?) {
        refresh()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func refresh() {
        errorItem.title = "正在更新用量…"
        errorItem.isHidden = false
        reader.fetch { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                self.snapshot = value
                self.lastError = nil
            case .failure(let error):
                self.lastError = error.localizedDescription
            }
            self.updateDisplay()
        }
    }

    private func updateDisplay() {
        let fiveHour = snapshot?.fiveHour
        let weekly = snapshot?.weekly
        statusView.update(
            fiveHour: fiveHour.map { "\($0.remainingPercent)%" } ?? "—",
            weekly: weekly.map { "\($0.remainingPercent)%" } ?? "—",
            countdown: "↻ \(remainingResetTime(fiveHour?.resetsAt))"
        )
        statusItem.length = statusView.preferredWidth
        statusView.frame = statusItem.button?.bounds ?? statusView.frame

        if let fiveHour, let weekly {
            statusItem.button?.toolTip = "5 小时剩余 \(fiveHour.remainingPercent)%，每周剩余 \(weekly.remainingPercent)%。5 小时额度将在 \(formattedDate(fiveHour.resetsAt)) 重置（约 \(remainingResetTime(fiveHour.resetsAt)) 后）"
            fiveHourItem.title = "5 小时剩余：\(fiveHour.remainingPercent)%"
        } else {
            statusItem.button?.toolTip = lastError ?? "正在读取 Codex 用量"
            fiveHourItem.title = "5 小时剩余：\(fiveHour.map { "\($0.remainingPercent)%" } ?? "暂无数据")"
        }
        weeklyItem.attributedTitle = NSAttributedString(
            string: "每周剩余：\(weekly.map { "\($0.remainingPercent)%" } ?? "暂无数据")",
            attributes: [.foregroundColor: NSColor.systemTeal]
        )

        fiveHourResetItem.title = "重置时间：\(formattedDate(fiveHour?.resetsAt))"
        weeklyResetItem.title = "重置时间：\(formattedDate(weekly?.resetsAt))"
        if let fetchedAt = snapshot?.fetchedAt {
            updatedItem.title = "上次更新：\(Self.timeFormatter.string(from: fetchedAt))"
        } else {
            updatedItem.title = "上次更新：—"
        }
        errorItem.title = lastError ?? ""
        errorItem.isHidden = lastError == nil
    }

    private func remainingResetTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let secondsRemaining = date.timeIntervalSinceNow
        guard secondsRemaining > 0 else { return "0m" }
        let totalMinutes = Int(ceil(secondsRemaining / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return Self.dateFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
