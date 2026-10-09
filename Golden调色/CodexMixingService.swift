import Foundation
import Darwin

struct CodexMixingService: Sendable {
    static func executableURL(customPath: String = "") -> URL? {
        let customPath = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let searchPath = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .filter { $0.hasPrefix("/") }
            .map { String($0) + "/codex" }
        let paths = customPath.isEmpty
            ? ["/opt/homebrew/bin/codex", "/usr/local/bin/codex",
               home.appendingPathComponent(".local/bin/codex").path] + searchPath
            : [(customPath as NSString).expandingTildeInPath]
        return paths.first { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func environment(
        for executable: URL,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        // Finder/Xcode launches often omit Homebrew; npm's Codex launcher needs /usr/bin/env node.
        let inherited = (base["PATH"] ?? "").split(separator: ":").map(String.init)
        let paths = [executable.deletingLastPathComponent().path] + inherited
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        environment["PATH"] = paths.filter { $0.hasPrefix("/") && seen.insert($0).inserted }.joined(separator: ":")
        return environment
    }

    static func arguments(
        schema: URL,
        output: URL,
        directory: URL,
        model: AIModelSelection = AIModelSelection()
    ) -> [String] {
        var arguments = ["exec", "--model", model.modelID]
        if model.reasoningEffort != .modelDefault {
            arguments += ["--config", "model_reasoning_effort=\"\(model.reasoningEffort.rawValue)\""]
        }
        return arguments + [
            "--ignore-user-config",
            "--sandbox", "read-only",
            "--config", "approval_policy=\"never\"",
            "--config", "web_search=\"disabled\"",
            "--config", "project_doc_max_bytes=0",
            "--disable", "shell_tool",
            "--disable", "unified_exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "--color", "never",
            "--cd", directory.path,
            "--output-schema", schema.path,
            "--output-last-message", output.path,
            "-"
        ]
    }

    func generate(
        for target: MixingTarget,
        referencePaint: PaintReference? = nil,
        paintSet: MixingPaintSet = .defaultSelection,
        configuration: AIConfiguration = AIConfiguration()
    ) async throws -> MixingPalette {
        let configuration = try configuration.validated()
        try paintSet.validateForGeneration()
        try referencePaint?.validate(target: target)
        let data = try await request(
            prompt: MixingPalette.prompt(for: target, referencePaint: referencePaint, paintSet: paintSet),
            schema: MixingPalette.outputSchema(paintSet: paintSet),
            configuration: configuration
        )
        return try MixingPalette.decode(data, for: target, model: configuration.model, paintSet: paintSet, referencePaint: referencePaint)
    }

    func generate(
        from blend: ColorBlendRequest,
        paintSet: MixingPaintSet = .defaultSelection,
        configuration: AIConfiguration = AIConfiguration()
    ) async throws -> MixingPalette {
        let configuration = try configuration.validated()
        try paintSet.validateForGeneration()
        let data = try await request(
            prompt: blend.prompt(paintSet: paintSet),
            schema: ColorBlendRequest.outputSchema(paintSet: paintSet),
            configuration: configuration
        )
        return try blend.decodePalette(data, model: configuration.model, paintSet: paintSet)
    }

    private func request(prompt: String, schema: Data, configuration: AIConfiguration) async throws -> Data {
        try Task.checkCancellation()
        guard let executable = Self.executableURL(customPath: configuration.executablePath) else {
            throw MixingError.cliNotFound
        }

        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("GoldenMixing-\(UUID().uuidString)")
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: directory) }

        let schemaURL = directory.appendingPathComponent("schema.json")
        let outputURL = directory.appendingPathComponent("recipe.json")
        let promptURL = directory.appendingPathComponent("prompt.txt")
        let logURL = directory.appendingPathComponent("codex.log")
        try schema.write(to: schemaURL)
        try Data(prompt.utf8).write(to: promptURL)
        guard files.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw MixingError.launchFailed("无法创建临时日志。")
        }

        // File handles avoid a full stdout/stderr pipe blocking the child process.
        let input = try FileHandle(forReadingFrom: promptURL)
        let log = try FileHandle(forWritingTo: logURL)
        defer {
            try? input.close()
            try? log.close()
        }

        let runner = CodexProcessRunner()
        let status = try await runner.run(
            executable: executable,
            arguments: Self.arguments(schema: schemaURL, output: outputURL, directory: directory, model: configuration.model),
            directory: directory,
            input: input,
            log: log,
            logURL: logURL,
            timeout: configuration.model.reasoningEffort.generationTimeout
        )
        try Task.checkCancellation()
        guard status == 0 else {
            throw MixingError.cliFailed(Self.failureMessage(at: logURL, model: configuration.model))
        }
        guard files.fileExists(atPath: outputURL.path) else {
            throw MixingError.invalidRecipe("Codex 没有返回调色结果，请重试。")
        }
        let size = (try files.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= MixingPalette.maximumResponseBytes else {
            throw MixingError.invalidRecipe("AI 返回内容过长，请重新生成。")
        }
        return try Data(contentsOf: outputURL)
    }

    private static func failureMessage(at url: URL, model: AIModelSelection) -> String {
        // Read only the tail; never load an unbounded CLI log into the interface.
        let handle = try? FileHandle(forReadingFrom: url)
        defer { try? handle?.close() }
        let end = (try? handle?.seekToEnd()) ?? 0
        try? handle?.seek(toOffset: end > 4_096 ? end - 4_096 : 0)
        let data = (try? handle?.read(upToCount: 4_096)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        let lower = text.lowercased()
        if lower.contains("not logged in") || lower.contains("unauthorized") || lower.contains("401")
            || lower.contains("refresh_token") || lower.contains("authentication") {
            return "Codex 登录已失效或尚未登录。请在终端执行 codex login 后重试。"
        }
        if lower.contains("usage limit") || lower.contains("quota") || lower.contains("rate limit") {
            return "Codex 的使用额度或请求频率已达到限制，请稍后重试或检查当前账户。"
        }
        let detail = text.split(separator: "\n").suffix(8).joined(separator: "\n")
        return detail.isEmpty
            ? "Codex 调用失败，请检查登录状态和网络后重试。"
            : "Codex 调用失败（\(model.summary)）：\n\(String(detail.suffix(1_600)))"
    }
}

/// Each request owns one actor and one child process. Cancellation waits for that child to exit.
actor CodexProcessRunner {
    func run(
        executable: URL,
        arguments: [String],
        directory: URL,
        input: FileHandle,
        log: FileHandle,
        logURL: URL,
        timeout: TimeInterval = 240
    ) async throws -> Int32 {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = CodexMixingService.environment(for: executable)
        process.currentDirectoryURL = directory
        process.standardInput = input
        process.standardOutput = log
        process.standardError = log

        do {
            try process.run()
        } catch {
            throw MixingError.launchFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw MixingError.timedOut(after: timeout) }
                let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber)?.intValue ?? 0
                guard size < 2_000_000 else {
                    throw MixingError.cliFailed("Codex 输出异常过多，已停止请求，请检查 CLI 配置。")
                }
                try await Task.sleep(nanoseconds: 150_000_000)
            }
            try Task.checkCancellation()
            return process.terminationStatus
        } catch {
            if process.isRunning {
                process.terminate()
                // A child may ignore SIGTERM. Reap only this request's process before deleting its files.
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                        process.waitUntilExit()
                        continuation.resume()
                    }
                }
            }
            throw error
        }
    }
}
