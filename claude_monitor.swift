import Cocoa
import SwiftUI
import Combine

// MARK: - Config Manager

struct MonitorConfig: Codable {
    var tts_provider: String
    var elevenlabs: ElevenLabsConfig
    var say: SayConfig
    var announce: AnnounceConfig

    struct ElevenLabsConfig: Codable {
        var env_file: String
        var voice_id: String?
        var model: String
        var stability: Double
        var similarity_boost: Double
        var voice_design_prompt: String?
        var voice_design_name: String?
    }
    struct SayConfig: Codable {
        var voice: String
        var rate: Int
    }
    struct AnnounceConfig: Codable {
        var enabled: Bool
        var on_done: Bool
        var on_attention: Bool
        var on_start: Bool
        var volume: Double
    }
    struct SavedVoice: Codable {
        var id: String
        var name: String
    }
    var voices: [SavedVoice]?
}

// MARK: - ElevenLabs Voice Info

struct ElevenLabsVoice: Identifiable {
    let id: String
    let name: String
}

struct ElevenLabsVoicesResponse: Codable {
    struct Voice: Codable {
        let voice_id: String
        let name: String
        let category: String?
    }
    let voices: [Voice]
}

class VoiceFetcher: ObservableObject {
    @Published var voices: [ElevenLabsVoice] = []
    @Published var hasFetched = false
    private var apiKey: String?

    func loadAPIKey(envFilePath: String) {
        let expanded = (envFilePath as NSString).expandingTildeInPath
        guard let content = try? String(contentsOfFile: expanded, encoding: .utf8) else { return }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ELEVENLABS_API_KEY=") {
                apiKey = String(trimmed.dropFirst("ELEVENLABS_API_KEY=".count))
                break
            }
        }
    }

    func fetchVoices() {
        guard let apiKey = apiKey, !apiKey.isEmpty else { return }
        guard let url = URL(string: "https://api.elevenlabs.io/v1/voices") else { return }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data = data,
                  let response = try? JSONDecoder().decode(ElevenLabsVoicesResponse.self, from: data) else {
                return
            }
            // Only show user's own voices (cloned, generated, professional), not premade
            let voices = response.voices
                .filter { $0.category != "premade" }
                .map { ElevenLabsVoice(id: $0.voice_id, name: $0.name) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self?.voices = voices
                self?.hasFetched = true
            }
        }.resume()
    }

    func name(for voiceId: String) -> String? {
        voices.first(where: { $0.id == voiceId })?.name
    }

    func resolveVoiceName(id: String, completion: @escaping (String?) -> Void) {
        guard let apiKey = apiKey, !apiKey.isEmpty else { completion(nil); return }
        guard let url = URL(string: "https://api.elevenlabs.io/v1/voices/\(id)") else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String else {
                completion(nil)
                return
            }
            completion(name)
        }.resume()
    }

    /// Design a voice from a text prompt, save it, and return the voice_id + name
    func designVoice(prompt: String, name: String, completion: @escaping (String?, String?) -> Void) {
        guard let apiKey = apiKey, !apiKey.isEmpty else { completion(nil, nil); return }
        guard let designURL = URL(string: "https://api.elevenlabs.io/v1/text-to-voice/design") else { completion(nil, nil); return }

        // Step 1: Generate preview
        var request = URLRequest(url: designURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "voice_description": prompt,
            "text": "Hello. A session just finished — your project is done and ready for review. Another session needs your attention, it looks like there is a permission prompt waiting. Everything else is still running smoothly.",
            "model_id": "eleven_multilingual_ttv_v2",
            "guidance_scale": 8,
            "quality": 0.9
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let previews = json["previews"] as? [[String: Any]],
                  let first = previews.first,
                  let generatedId = first["generated_voice_id"] as? String else {
                completion(nil, nil)
                return
            }

            // Step 2: Save as permanent voice
            self?.saveDesignedVoice(generatedId: generatedId, name: name, prompt: prompt, completion: completion)
        }.resume()
    }

    private func saveDesignedVoice(generatedId: String, name: String, prompt: String, completion: @escaping (String?, String?) -> Void) {
        guard let apiKey = apiKey, !apiKey.isEmpty else { completion(nil, nil); return }
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-voice") else { completion(nil, nil); return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "voice_name": name,
            "voice_description": prompt,
            "generated_voice_id": generatedId,
            "labels": ["source": "claude-monitor"]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let voiceId = json["voice_id"] as? String else {
                completion(nil, nil)
                return
            }
            let voiceName = json["name"] as? String ?? name
            completion(voiceId, voiceName)
        }.resume()
    }
}

class ConfigManager: ObservableObject {
    @Published var config: MonitorConfig?
    let voiceFetcher = VoiceFetcher()

    static let configPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/monitor/config.json"
    }()

    init() {
        load()
        // Kick off voice fetch
        if let envFile = config?.elevenlabs.env_file {
            voiceFetcher.loadAPIKey(envFilePath: envFile)
            voiceFetcher.fetchVoices()
        }
    }

    func load() {
        guard let data = FileManager.default.contents(atPath: Self.configPath),
              let decoded = try? JSONDecoder().decode(MonitorConfig.self, from: data) else { return }
        self.config = decoded
    }

    func setVoice(_ voiceId: String) {
        config?.elevenlabs.voice_id = voiceId
        save()
    }

    func toggleVoice() {
        config?.announce.enabled.toggle()
        save()
    }

    var voiceEnabled: Bool {
        config?.announce.enabled ?? true
    }

    func save() {
        guard let config = config else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: URL(fileURLWithPath: Self.configPath))
    }

    var currentVoiceId: String {
        config?.elevenlabs.voice_id ?? ""
    }

    func voiceName(for id: String) -> String? {
        if let saved = config?.voices?.first(where: { $0.id == id }) {
            return saved.name
        }
        return voiceFetcher.name(for: id)
    }

    var allVoices: [ElevenLabsVoice] {
        var combined: [ElevenLabsVoice] = []
        var seenIds = Set<String>()
        if let saved = config?.voices {
            for v in saved {
                combined.append(ElevenLabsVoice(id: v.id, name: v.name))
                seenIds.insert(v.id)
            }
        }
        for v in voiceFetcher.voices {
            if !seenIds.contains(v.id) {
                combined.append(v)
            }
        }
        return combined
    }

    func addVoice(id: String, name: String) {
        var voices = config?.voices ?? []
        if !voices.contains(where: { $0.id == id }) {
            voices.append(MonitorConfig.SavedVoice(id: id, name: name))
            config?.voices = voices
            save()
        }
    }
}

// MARK: - Session Model

struct SessionInfo: Codable, Identifiable {
    let session_id: String
    var status: String
    var project: String
    var cwd: String
    var terminal: String
    var terminal_session_id: String
    var started_at: String
    var updated_at: String
    var last_prompt: String

    var id: String { session_id }

    enum CodingKeys: String, CodingKey {
        case session_id, status, project, cwd, terminal, terminal_session_id, started_at, updated_at, last_prompt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        session_id = try c.decode(String.self, forKey: .session_id)
        status = (try? c.decode(String.self, forKey: .status)) ?? "unknown"
        project = (try? c.decode(String.self, forKey: .project)) ?? "unknown"
        cwd = (try? c.decode(String.self, forKey: .cwd)) ?? ""
        terminal = (try? c.decode(String.self, forKey: .terminal)) ?? ""
        terminal_session_id = (try? c.decode(String.self, forKey: .terminal_session_id)) ?? ""
        started_at = (try? c.decode(String.self, forKey: .started_at)) ?? ""
        updated_at = (try? c.decode(String.self, forKey: .updated_at)) ?? ""
        last_prompt = (try? c.decode(String.self, forKey: .last_prompt)) ?? ""
    }

    var statusColor: Color {
        switch status {
        case "starting":  return .gray
        case "working":   return .cyan
        case "done":      return .green
        case "attention": return .orange
        default:          return .gray
        }
    }

    var statusIcon: String {
        switch status {
        case "starting":  return "circle.dotted"
        case "working":   return "circle.fill"
        case "done":      return "checkmark.circle.fill"
        case "attention": return "exclamationmark.triangle.fill"
        default:          return "circle"
        }
    }

    var elapsedString: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Try with fractional seconds first, then without
        var date = formatter.date(from: started_at)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: started_at)
        }
        guard let start = date else { return "" }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < 60 { return "\(Int(elapsed))s" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        return "\(Int(elapsed / 3600))h \(Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60))m"
    }

    var isStale: Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: updated_at)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: updated_at)
        }
        guard let updated = date else { return false }
        return Date().timeIntervalSince(updated) > 600 // 10 minutes
    }
}

// MARK: - Permission Model

struct PermissionInfo: Codable {
    let tool_name: String
    let display: String
    let tool_input: String
    let timestamp: String
    let pid: String?  // legacy, kept for decode compat

    var toolIcon: String {
        switch tool_name {
        case "Bash":  return "terminal"
        case "Edit":  return "pencil"
        case "Write": return "doc.badge.plus"
        case "Read":  return "doc.text"
        case "Glob":  return "magnifyingglass"
        case "Grep":  return "text.magnifyingglass"
        default:      return "gearshape"
        }
    }
}

// MARK: - Permission Socket Server

class PermissionSocketServer {
    static let shared = PermissionSocketServer()
    private let socketPath = "/tmp/claude-monitor.sock"
    private var serverFd: Int32 = -1
    private let queue = DispatchQueue(label: "monitor.socket", qos: .userInteractive)
    // Map session_id -> client file descriptor (kept open, waiting for response)
    private var pendingClients: [String: Int32] = [:]
    private let lock = NSLock()

    func start() {
        // Clean up stale socket
        unlink(socketPath)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            NSLog("[ClaudeMonitor] Socket: failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let raw = UnsafeMutableRawPointer(ptr)
                raw.copyMemory(from: cstr, byteCount: min(strlen(cstr) + 1, 104))
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            NSLog("[ClaudeMonitor] Socket: bind failed: %d", errno)
            Darwin.close(serverFd)
            return
        }

        guard listen(serverFd, 5) == 0 else {
            NSLog("[ClaudeMonitor] Socket: listen failed")
            Darwin.close(serverFd)
            return
        }

        NSLog("[ClaudeMonitor] Socket: listening on %@", socketPath)

        // Accept connections in background
        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    private func acceptLoop() {
        while serverFd >= 0 {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverFd, sockPtr, &clientLen)
                }
            }
            guard clientFd >= 0 else { continue }

            // Handle each client in its own dispatch
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                self?.handleClient(fd: clientFd)
            }
        }
    }

    private func handleClient(fd: Int32) {
        // Read the request
        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = read(fd, &buffer, buffer.count)
        guard bytesRead > 0 else {
            Darwin.close(fd)
            return
        }

        let data = Data(buffer[0..<bytesRead])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "permission_request",
              let sessionId = json["session_id"] as? String else {
            Darwin.close(fd)
            return
        }

        NSLog("[ClaudeMonitor] Socket: permission request from session %@", sessionId)

        // Store the client fd — keep the connection open until user responds
        lock.lock()
        // Close any existing pending client for this session
        if let old = pendingClients[sessionId] {
            Darwin.close(old)
        }
        pendingClients[sessionId] = fd
        lock.unlock()
    }

    func respond(sessionId: String, decision: String) {
        lock.lock()
        guard let fd = pendingClients.removeValue(forKey: sessionId) else {
            lock.unlock()
            NSLog("[ClaudeMonitor] Socket: no pending client for session %@", sessionId)
            return
        }
        lock.unlock()

        let response = "{\"decision\":\"\(decision)\"}"
        let bytes = Array(response.utf8)
        bytes.withUnsafeBufferPointer { ptr in
            _ = write(fd, ptr.baseAddress!, ptr.count)
        }
        Darwin.close(fd)
        NSLog("[ClaudeMonitor] Socket: sent %@ to session %@", decision, sessionId)
    }

    func stop() {
        if serverFd >= 0 {
            Darwin.close(serverFd)
            serverFd = -1
        }
        unlink(socketPath)
        lock.lock()
        for (_, fd) in pendingClients {
            Darwin.close(fd)
        }
        pendingClients.removeAll()
        lock.unlock()
    }
}

// MARK: - Session Reader (polls directory)

class SessionReader: ObservableObject {
    @Published var sessions: [SessionInfo] = []
    @Published var permissions: [String: PermissionInfo] = [:]
    private var timer: Timer?
    private var livenessTimer: Timer?

    let sessionsDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/monitor/sessions"
    }()

    init() {
        readSessions()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.readSessions()
        }
        livenessTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pruneDeadSessions()
        }
    }

    func respondToPermission(sessionId: String, decision: String) {
        // Send response through the socket server
        PermissionSocketServer.shared.respond(sessionId: sessionId, decision: decision)

        // Remove the permission card
        let permFile = "\(sessionsDir)/\(sessionId).permission"
        try? FileManager.default.removeItem(atPath: permFile)
    }

    /// Remove session files whose TTY no longer has any processes (terminal tab closed)
    func pruneDeadSessions() {
        let currentSessions = sessions
        guard !currentSessions.isEmpty else { return }

        // Build map: ttyName -> [session_id]
        var ttyMap: [String: [String]] = [:]
        for session in currentSessions {
            guard !session.terminal_session_id.isEmpty else { continue }
            if session.terminal == "terminal" {
                let ttyName = session.terminal_session_id.replacingOccurrences(of: "/dev/", with: "")
                ttyMap[ttyName, default: []].append(session.session_id)
            }
        }
        guard !ttyMap.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            // Single shell command checks all TTYs at once
            let ttys = ttyMap.keys.joined(separator: " ")
            let script = "for tty in \(ttys); do ps -t \"$tty\" -o pid= 2>/dev/null | head -1 | grep -q . || echo \"$tty\"; done"

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", script]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let deadTTYs = Set(output.split(separator: "\n").map(String.init))

                for tty in deadTTYs {
                    if let sids = ttyMap[tty] {
                        for sid in sids {
                            let path = "\(self.sessionsDir)/\(sid).json"
                            try? FileManager.default.removeItem(atPath: path)
                            // Clean up orphaned permission files
                            try? FileManager.default.removeItem(atPath: "\(self.sessionsDir)/\(sid).permission")
                            NSLog("[ClaudeMonitor] Pruned session %@ — TTY %@ gone", sid, tty)
                        }
                    }
                }
            } catch {}
        }
    }

    func readSessions() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else {
            DispatchQueue.main.async { self.sessions = []; self.permissions = [:] }
            return
        }

        var loaded: [SessionInfo] = []
        var loadedPerms: [String: PermissionInfo] = [:]

        for file in files {
            if file.hasSuffix(".json") {
                let path = "\(sessionsDir)/\(file)"
                guard let data = fm.contents(atPath: path) else { continue }
                do {
                    let session = try JSONDecoder().decode(SessionInfo.self, from: data)
                    loaded.append(session)
                } catch {
                    NSLog("[ClaudeMonitor] Failed to decode %@: %@", file, error.localizedDescription)
                }
            } else if file.hasSuffix(".permission") {
                let sessionId = String(file.dropLast(".permission".count))
                let path = "\(sessionsDir)/\(file)"
                guard let data = fm.contents(atPath: path) else { continue }
                if let perm = try? JSONDecoder().decode(PermissionInfo.self, from: data) {
                    loadedPerms[sessionId] = perm
                }
            }
        }

        // Sort: attention first, then working, then starting, then done
        let order: [String: Int] = ["attention": 0, "working": 1, "starting": 2, "done": 3]
        loaded.sort { (order[$0.status] ?? 9) < (order[$1.status] ?? 9) }

        DispatchQueue.main.async {
            self.sessions = loaded
            self.permissions = loadedPerms
        }
    }

    func discoverSessions() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", """
        SESSIONS_DIR="$HOME/.claude/monitor/sessions"
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        for pid in $(ps -eo pid=,comm= | awk '/claude/ && !/claude_monitor/ && !/awk/ {print $1}'); do
            tty_name=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
            [ -z "$tty_name" ] || [ "$tty_name" = "??" ] && continue
            grep -rlq "/dev/$tty_name" "$SESSIONS_DIR" 2>/dev/null && continue
            cwd=$(lsof -p "$pid" -d cwd -Fn 2>/dev/null | tail -1 | cut -c2-)
            [ -z "$cwd" ] && continue
            project=$(basename "$cwd")
            sid="discovered-${tty_name}"
            jq -n --arg sid "$sid" --arg project "$project" --arg cwd "$cwd" --arg term_sid "/dev/$tty_name" --arg now "$NOW" '{session_id:$sid,status:"working",project:$project,cwd:$cwd,terminal:"terminal",terminal_session_id:$term_sid,started_at:$now,updated_at:$now,last_prompt:""}' > "$SESSIONS_DIR/$sid.json.tmp" && mv "$SESSIONS_DIR/$sid.json.tmp" "$SESSIONS_DIR/$sid.json"
        done
        """]
        try? task.run()
        task.waitUntilExit()
        readSessions()
    }
}

// MARK: - Terminal Switcher

func switchToSession(_ session: SessionInfo) {
    NSLog("[ClaudeMonitor] switchToSession: terminal=\(session.terminal) tty=\(session.terminal_session_id) project=\(session.project)")
    if session.terminal == "iterm2" && !session.terminal_session_id.isEmpty {
        switchToITerm2(sessionId: session.terminal_session_id)
    } else if session.terminal == "terminal" && !session.terminal_session_id.isEmpty {
        switchToTerminal(ttyPath: session.terminal_session_id)
    } else {
        NSLog("[ClaudeMonitor] falling back to cwd switch (no terminal info)")
        switchByTerminalCwd(cwd: session.cwd)
    }
}

func switchToITerm2(sessionId: String) {
    // sessionId format from ITERM_SESSION_ID: "w0t0p0:GUID"
    let parts = sessionId.split(separator: ":")
    guard parts.count >= 2 else {
        if let appleScript = NSAppleScript(source: "tell application \"iTerm2\" to activate") {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
        return
    }
    let uniqueId = String(parts[1])

    let script = """
    tell application "iTerm2"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if unique id of s is "\(uniqueId)" then
                        select t
                        return
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    """

    if let appleScript = NSAppleScript(source: script) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
}

func switchToTerminal(ttyPath: String) {
    // Match Terminal.app tab by its tty device path
    let script = """
    tell application "Terminal"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                if tty of t is "\(ttyPath)" then
                    set selected tab of w to t
                    set index of w to 1
                    return
                end if
            end repeat
        end repeat
    end tell
    """

    if let appleScript = NSAppleScript(source: script) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
}

func switchByTerminalCwd(cwd: String) {
    // Fallback: just activate the terminal app
    if let appleScript = NSAppleScript(source: "tell application \"Terminal\" to activate") {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
}

// MARK: - Session Killer

func killSession(_ session: SessionInfo) {
    var ttyName: String?

    if session.terminal == "terminal" && !session.terminal_session_id.isEmpty {
        ttyName = session.terminal_session_id.replacingOccurrences(of: "/dev/", with: "")
    } else if session.terminal == "iterm2" && !session.terminal_session_id.isEmpty {
        let parts = session.terminal_session_id.split(separator: ":")
        if parts.count >= 2 {
            let uniqueId = String(parts[1])
            let script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if unique id of s is "\(uniqueId)" then
                                return tty of s
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                let result = appleScript.executeAndReturnError(&error)
                if let tty = result.stringValue {
                    ttyName = tty.replacingOccurrences(of: "/dev/", with: "")
                }
            }
        }
    }

    if let tty = ttyName {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "pkill -TERM -t \(tty) -f claude 2>/dev/null"]
        try? task.run()
    }

    // Clean up session file after delay
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let sessionFile = "\(home)/.claude/monitor/sessions/\(session.session_id).json"
    DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
        try? FileManager.default.removeItem(atPath: sessionFile)
    }
}

// MARK: - Pulsing Dot View

struct PulsingDot: View {
    let color: Color
    let isPulsing: Bool

    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .shadow(color: color.opacity(0.6), radius: isPulsing ? 4 : 0)
            .onAppear {
                if isPulsing {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        scale = 1.4
                    }
                }
            }
            .onChange(of: isPulsing) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        scale = 1.4
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scale = 1.0
                    }
                }
            }
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: SessionInfo
    var onKill: (() -> Void)? = nil
    @State private var isHovered = false
    @State private var isKilling = false

    var body: some View {
        HStack(spacing: 8) {
            PulsingDot(
                color: session.statusColor,
                isPulsing: session.status == "working"
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(session.project)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundColor(session.isStale ? .gray : .white)
                        .lineLimit(1)

                    Text(session.status)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(session.statusColor.opacity(session.isStale ? 0.5 : 0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(session.statusColor.opacity(session.isStale ? 0.05 : 0.15))
                        )

                    Spacer()

                    if onKill != nil {
                        ZStack {
                            if isKilling {
                                PulsingDot(color: .red, isPulsing: true)
                            } else if isHovered {
                                Button {
                                    isKilling = true
                                    onKill?()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.35))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(width: 28, height: 28)
                    }

                    Text(session.elapsedString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray)
                }

                if !session.last_prompt.isEmpty {
                    Text(session.last_prompt)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Permission Action View

struct PermissionActionView: View {
    let permission: PermissionInfo
    let sessionId: String
    let reader: SessionReader
    let onTerminal: () -> Void
    @State private var responding: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Tool name header with icon
            HStack(spacing: 5) {
                Image(systemName: permission.toolIcon)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                Text(permission.tool_name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
            }

            // Command/detail text
            Text(permission.display)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(permission.display)

            if let action = responding {
                // Processing indicator
                HStack(spacing: 6) {
                    PulsingDot(color: action == "allow" ? .green : action == "deny" ? .red : .gray, isPulsing: true)
                    Text(action == "allow" ? "Allowing..." : action == "deny" ? "Denying..." : "Switching...")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            } else {
            // Action buttons
            HStack(spacing: 8) {
                Button {
                    responding = "allow"
                    reader.respondToPermission(sessionId: sessionId, decision: "allow")
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Allow")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green.opacity(0.4))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    responding = "deny"
                    reader.respondToPermission(sessionId: sessionId, decision: "deny")
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Deny")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.4))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    responding = "terminal"
                    reader.respondToPermission(sessionId: sessionId, decision: "terminal")
                    onTerminal()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right.square")
                            .font(.system(size: 9))
                        Text("Terminal")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.15))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            } // else
        }
        .padding(.leading, 28)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.05))
    }
}

// MARK: - Header Bar

// MARK: - Settings Popover

struct SettingsPopover: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var voiceFetcher: VoiceFetcher
    var sessionReader: SessionReader?
    @State private var pastedVoiceId: String? = nil
    @State private var refreshed = false
    @State private var isGenerating = false
    @State private var generateResult: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Refresh sessions
            Button {
                sessionReader?.discoverSessions()
                refreshed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { refreshed = false }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: refreshed ? "checkmark" : "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(refreshed ? .green : .white.opacity(0.4))
                    Text(refreshed ? "Refreshed" : "Refresh sessions")
                        .font(.system(size: 11))
                        .foregroundColor(refreshed ? .green.opacity(0.8) : .white.opacity(0.6))
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Divider().background(Color.white.opacity(0.1))

            // Master toggle
            Button {
                configManager.toggleVoice()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: configManager.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 10))
                        .foregroundColor(configManager.voiceEnabled ? .cyan : .gray)
                    Text(configManager.voiceEnabled ? "Voice on" : "Voice off")
                        .font(.system(size: 11))
                        .foregroundColor(configManager.voiceEnabled ? .white : .white.opacity(0.4))
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if configManager.voiceEnabled {
                Divider().background(Color.white.opacity(0.1))

                // Current voice display
                if let name = configManager.voiceName(for: configManager.currentVoiceId) {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.cyan)
                        Spacer()
                        Text(String(configManager.currentVoiceId.prefix(8)))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.2))
                    }
                }

                Text("Voice")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .textCase(.uppercase)

                if voiceFetcher.hasFetched || !(configManager.config?.voices ?? []).isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(configManager.allVoices) { voice in
                                let isSelected = configManager.currentVoiceId == voice.id
                                Button {
                                    configManager.setVoice(voice.id)
                                    pastedVoiceId = nil
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(isSelected ? Color.cyan : Color.white.opacity(0.15))
                                            .frame(width: 6, height: 6)
                                        Text(voice.name)
                                            .font(.system(size: 11))
                                            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                } else {
                    Text("Loading voices...")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }

                Divider().background(Color.white.opacity(0.1))

                // Paste voice ID from clipboard
                Button {
                    if let pasted = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !pasted.isEmpty {
                        configManager.setVoice(pasted)
                        pastedVoiceId = String(pasted.prefix(20))
                        // Resolve name and persist to voice list
                        let voiceId = pasted
                        if let existing = configManager.voiceName(for: voiceId) {
                            configManager.addVoice(id: voiceId, name: existing)
                        } else {
                            voiceFetcher.resolveVoiceName(id: voiceId) { name in
                                DispatchQueue.main.async {
                                    configManager.addVoice(id: voiceId, name: name ?? "Voice \(String(voiceId.prefix(8)))")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                        Text("Paste voice ID")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if let pasted = pastedVoiceId {
                    Text("Set to \(pasted)...")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.green.opacity(0.6))
                }

                // Generate voice from design prompt
                if let prompt = configManager.config?.elevenlabs.voice_design_prompt, !prompt.isEmpty {
                    Divider().background(Color.white.opacity(0.1))

                    Button {
                        guard !isGenerating else { return }
                        isGenerating = true
                        generateResult = nil
                        let voiceName = configManager.config?.elevenlabs.voice_design_name ?? "claude-monitor"
                        voiceFetcher.designVoice(prompt: prompt, name: voiceName) { voiceId, name in
                            DispatchQueue.main.async {
                                isGenerating = false
                                if let voiceId = voiceId, let name = name {
                                    configManager.setVoice(voiceId)
                                    configManager.addVoice(id: voiceId, name: name)
                                    generateResult = name
                                    voiceFetcher.fetchVoices()
                                } else {
                                    generateResult = "failed"
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isGenerating {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 10, height: 10)
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 9))
                                    .foregroundColor(.purple.opacity(0.6))
                            }
                            Text(isGenerating ? "Generating..." : "Generate voice")
                                .font(.system(size: 10))
                                .foregroundColor(isGenerating ? .purple.opacity(0.4) : .purple.opacity(0.6))
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isGenerating)

                    if let result = generateResult {
                        Text(result == "failed" ? "Generation failed" : "Created \"\(result)\"")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(result == "failed" ? .red.opacity(0.6) : .green.opacity(0.6))
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 200)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
    }
}

struct HeaderBar: View {
    let sessions: [SessionInfo]
    @ObservedObject var configManager: ConfigManager
    var sessionReader: SessionReader?
    @State private var showSettings = false

    var attentionCount: Int { sessions.filter { $0.status == "attention" }.count }
    var workingCount: Int { sessions.filter { $0.status == "working" }.count }
    var doneCount: Int { sessions.filter { $0.status == "done" }.count }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                Text("Claude")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            HStack(spacing: 8) {
                if attentionCount > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        Text("\(attentionCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }
                if workingCount > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(Color.cyan).frame(width: 6, height: 6)
                        Text("\(workingCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                }
                if doneCount > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("\(doneCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }

                Text("\(sessions.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))

                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.2))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    SettingsPopover(configManager: configManager, voiceFetcher: configManager.voiceFetcher, sessionReader: sessionReader)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Main Content View

struct MonitorContentView: View {
    @ObservedObject var reader: SessionReader
    @ObservedObject var configManager: ConfigManager
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // Header — always visible, drag to move
            HeaderBar(sessions: reader.sessions, configManager: configManager, sessionReader: reader)

            if isExpanded && !reader.sessions.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.1))

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(reader.sessions) { session in
                            Button {
                                switchToSession(session)
                            } label: {
                                SessionRowView(session: session, onKill: { killSession(session) })
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if let perm = reader.permissions[session.id] {
                                PermissionActionView(
                                    permission: perm,
                                    sessionId: session.id,
                                    reader: reader,
                                    onTerminal: { switchToSession(session) }
                                )
                            }

                            if session.id != reader.sessions.last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.05))
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                    .background(ScrollbarStyler())
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }
}

// MARK: - Custom Thin Scrollbar

class ThinScroller: NSScroller {
    override class func scrollerWidth(for controlSize: ControlSize, scrollerStyle: Style) -> CGFloat {
        return 5
    }

    override func drawKnob() {
        var knobRect = rect(for: .knob)
        knobRect = NSRect(
            x: bounds.width - 4,
            y: knobRect.origin.y + 2,
            width: 3,
            height: max(knobRect.height - 4, 8)
        )
        let path = NSBezierPath(roundedRect: knobRect, xRadius: 1.5, yRadius: 1.5)
        NSColor.white.withAlphaComponent(0.2).setFill()
        path.fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Transparent track — no background
    }
}

struct ScrollbarStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setFrameSize(.zero)
        DispatchQueue.main.async {
            var superview = view.superview
            while let sv = superview {
                if let scrollView = sv as? NSScrollView {
                    scrollView.scrollerStyle = .overlay
                    scrollView.hasVerticalScroller = true
                    scrollView.autohidesScrollers = true
                    let scroller = ThinScroller()
                    scroller.controlSize = .mini
                    scrollView.verticalScroller = scroller
                    break
                }
                superview = sv.superview
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - NSVisualEffectView wrapper

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Floating Panel

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = true
        self.ignoresMouseEvents = false
    }

    func restorePosition() {
        if let x = UserDefaults.standard.object(forKey: "monitorX") as? Double,
           let y = UserDefaults.standard.object(forKey: "monitorY") as? Double {
            self.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            // Top-right, below menu bar
            let x = screenFrame.maxX - 296
            let y = screenFrame.maxY - 60
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    func savePosition() {
        UserDefaults.standard.set(self.frame.origin.x, forKey: "monitorX")
        UserDefaults.standard.set(self.frame.origin.y, forKey: "monitorY")
    }
}

// MARK: - Click-through Hosting View

class ClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Ensure no default background peeks through rounded corners
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
    }
}

// MARK: - Window Drag Handle (NSViewRepresentable)

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleNSView { DragHandleNSView() }
    func updateNSView(_ nsView: DragHandleNSView, context: Context) {}

    class DragHandleNSView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel!
    let reader = SessionReader()
    let configManager = ConfigManager()
    var sizeObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Start the Unix socket server for permission responses
        PermissionSocketServer.shared.start()

        panel = FloatingPanel()

        let hostingView = ClickHostingView(
            rootView: MonitorContentView(reader: reader, configManager: configManager)
        )
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 280, height: 40))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.contentView = hostingView

        panel.restorePosition()
        panel.orderFrontRegardless()

        // Auto-resize panel to fit content
        sizeObserver = hostingView.publisher(for: \.fittingSize)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] newSize in
                guard let self = self, let panel = self.panel else { return }
                let origin = panel.frame.origin
                // Grow downward from top edge, lock width to prevent horizontal shift
                let topY = origin.y + panel.frame.height
                let lockedWidth = panel.frame.width
                let newOrigin = NSPoint(x: origin.x, y: topY - newSize.height)
                panel.setFrame(
                    NSRect(origin: newOrigin, size: NSSize(width: lockedWidth, height: newSize.height)),
                    display: true,
                    animate: false
                )
            }

        // Save position on drag
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.panel.savePosition()
        }
    }
}

// MARK: - Main Entry Point

@main
struct ClaudeMonitorApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
