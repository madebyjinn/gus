import Foundation
import Security

/// Who answers a question you ask Gus. Apple Intelligence on this Mac is the default; the rest are opt-in
/// from Settings › Advanced: your own OpenAI or Claude API key, or the Codex / Claude Code you already
/// have installed and signed in (which answer on that subscription). Sums, conversions, weather and
/// reminders never leave the Mac whichever is picked: only a question you send goes to the service.
enum Engine: String, CaseIterable, Identifiable {
    case apple, openai, claude, codex, claudeCode
    var id: String { rawValue }

    /// The name on the ask row and the chat pill.
    var name: String {
        switch self {
        case .apple: return "Apple Intelligence"
        case .openai: return "ChatGPT"
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        }
    }

    /// The name in the picker.
    var choice: String {
        switch self {
        case .apple: return "Apple Intelligence"
        case .openai: return "OpenAI API key"
        case .claude: return "Claude API key"
        case .codex: return "Codex on this Mac"
        case .claudeCode: return "Claude Code on this Mac"
        }
    }

    var symbol: String { self == .apple ? "apple.intelligence" : "sparkles" }

    /// Whoever is behind it, the one you talk to is Gus.
    static let persona = "Gus"

    static let instructions = "You are Gus, a friendly otter butler and helpful assistant inside a Mac launcher. Answer in at most three short sentences unless asked for more. Plain text, no markdown."
}

/// API keys live in the login Keychain, never in preferences.
enum Keychain {
    private static let service = "com.madebyjinn.gus"

    static func read(_ account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func write(_ account: String, _ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

struct EngineError: Error { let message: String }

/// One conversation with a hosted model. Holds what's been said so a follow-up has its context.
actor RemoteChat {
    private var openAIInput: [[String: Any]] = []
    private var claudeMessages: [[String: Any]] = []
    private var transcript: [(String, String)] = []

    func reply(to question: String, engine: Engine, key: String, model: String) async throws -> String {
        let text: String
        switch engine {
        case .openai: text = try await openAI(question, key: key, model: model)
        case .claude: text = try await claude(question, key: key, model: model)
        case .codex, .claudeCode: text = try await cli(question, engine: engine)
        case .apple: throw EngineError(message: "Apple Intelligence answers on this Mac.")
        }
        transcript.append((question, text))
        return text
    }

    // MARK: OpenAI (Responses API)

    private func openAI(_ question: String, key: String, model: String) async throws -> String {
        openAIInput.append(["role": "user", "content": question])
        let body: [String: Any] = ["model": model, "instructions": Engine.instructions, "input": openAIInput]
        let json = try await post("https://api.openai.com/v1/responses", headers: ["Authorization": "Bearer \(key)"], body: body, who: "OpenAI")
        var text = ""
        for item in json["output"] as? [[String: Any]] ?? [] where item["type"] as? String == "message" {
            for part in item["content"] as? [[String: Any]] ?? [] where part["type"] as? String == "output_text" {
                text += part["text"] as? String ?? ""
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { openAIInput.removeLast(); throw EngineError(message: "ChatGPT sent back an empty answer.") }
        openAIInput.append(["role": "assistant", "content": text])
        return text
    }

    // MARK: Claude (Messages API)

    private func claude(_ question: String, key: String, model: String) async throws -> String {
        claudeMessages.append(["role": "user", "content": question])
        var body: [String: Any] = ["model": model, "max_tokens": 16000, "system": Engine.instructions, "messages": claudeMessages]
        var headers = ["x-api-key": key, "anthropic-version": "2026-10-21"]
        let current = ["claude-opus-5", "claude-sonnet-5", "claude-haiku-5", "claude-fable-5", "claude-mythos-5"].contains { model.hasPrefix($0) }
        // A launcher wants a quick answer: the current models think as little as the question needs.
        if current { body["output_config"] = ["effort": "low"] }
        // If the model declines on policy grounds, let the API hand the question to its fallback model.
        if ["claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-2", "claude-fable-5-1"].contains(model) {
            body["fallbacks"] = "default"
            headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
        }
        let json: [String: Any]
        do { json = try await post("https://api.anthropic.com/v1/messages", headers: headers, body: body, who: "Claude") }
        catch { claudeMessages.removeLast(); throw error }
        let content = json["content"] as? [[String: Any]] ?? []
        if json["stop_reason"] as? String == "refusal" {
            claudeMessages.removeLast()
            throw EngineError(message: "Claude declined to answer that.")
        }
        let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { claudeMessages.removeLast(); throw EngineError(message: "Claude sent back an empty answer.") }
        // The whole content goes back as it came (thinking and fallback blocks included), as the API expects.
        claudeMessages.append(["role": "assistant", "content": content])
        return text
    }

    private func post(_ url: String, headers: [String: String], body: [String: Any], who: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw EngineError(message: "Couldn't reach \(who). Check the connection (or a firewall blocking Gus).") }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let detail = (json["error"] as? [String: Any])?["message"] as? String
            switch status {
            case 401, 403: throw EngineError(message: "\(who) didn't accept that API key. Check it in Settings › Advanced.")
            case 404: throw EngineError(message: detail ?? "\(who) doesn't know that model. Check it in Settings › Advanced.")
            case 429: throw EngineError(message: detail ?? "\(who) is rate limiting this key. Try again in a moment.")
            default: throw EngineError(message: detail ?? "\(who) couldn't answer that (error \(status)).")
            }
        }
        return json
    }

    // MARK: Installed command-line tools

    /// Where the tool is, if it's installed. GUI apps don't get the shell's PATH, so the usual places are checked.
    nonisolated static func tool(_ engine: Engine) -> String? {
        let home = NSHomeDirectory()
        let places: [String]
        switch engine {
        case .codex:
            places = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", home + "/.local/bin/codex", home + "/.npm-global/bin/codex",
                      "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
                      "/Applications/Codex.app/Contents/Resources/codex"]
        case .claudeCode:
            places = [home + "/.local/bin/claude", home + "/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                      home + "/.npm-global/bin/claude"]
        default: return nil
        }
        return places.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func cli(_ question: String, engine: Engine) async throws -> String {
        guard let path = Self.tool(engine) else { throw EngineError(message: "\(engine.name) isn't installed on this Mac.") }
        // These tools start fresh each time, so a follow-up carries the conversation with it.
        var prompt = ""
        if !transcript.isEmpty {
            prompt += "The conversation so far:\n"
            for (q, a) in transcript { prompt += "User: \(q)\nYou: \(a)\n" }
            prompt += "\nThe user now says:\n"
        }
        prompt += question
        // An empty folder to stand in, and no permission to run commands or change files: it only answers.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gus-ask", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: out) }
        let args: [String]
        switch engine {
        case .codex:
            prompt = Engine.instructions + " Answer from what you know; don't run commands or read files.\n\n" + prompt
            args = ["exec", "--skip-git-repo-check", "--ephemeral", "-s", "read-only", "-C", dir.path, "-o", out.path, "-"]
        default:
            args = ["-p", "--restricted", "--strict-mcp-config", "--no-session-persistence", "--output-format", "text",
                    "--append-system-prompt", Engine.instructions + " Answer from what you know; don't use tools."]
        }
        let result = try await Self.run(path, args, input: prompt, in: dir)
        var text = result.output
        if engine == .codex { text = (try? String(contentsOf: out, encoding: .utf8)) ?? "" }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !text.isEmpty else {
            let why = (result.error + "\n" + result.output).lowercased()
            if why.contains("log in") || why.contains("login") || why.contains("not logged") || why.contains("unauthorized") || why.contains("401") {
                throw EngineError(message: "\(engine.name) isn't signed in. Open it once in Terminal and sign in.")
            }
            throw EngineError(message: "\(engine.name) couldn't answer that.")
        }
        return text
    }

    private nonisolated static func run(_ path: String, _ args: [String], input: String, in dir: URL) async throws -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        env["PATH"] = [env["PATH"] ?? "/usr/bin:/bin", "/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin"].joined(separator: ":")
        // Gus may itself have been started from one of these tools; don't let that leak into the child.
        for key in env.keys where key.hasPrefix("CLAUDE") || key.hasPrefix("CODEX") { env[key] = nil }
        process.environment = env
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { done in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { try process.run() } catch {
                        done.resume(throwing: EngineError(message: "Couldn't start \((path as NSString).lastPathComponent)."))
                        return
                    }
                    stdin.fileHandleForWriting.write(Data(input.utf8))
                    try? stdin.fileHandleForWriting.close()
                    var errData = Data()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async { errData = stderr.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    group.wait()
                    process.waitUntilExit()
                    done.resume(returning: (process.terminationStatus, String(data: outData, encoding: .utf8) ?? "",
                                            String(data: errData, encoding: .utf8) ?? ""))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
