// Codex CLI 传输层：定位可执行文件、构造参数、隔离临时资料并回收子进程。
// 调色与说明书考证共用此层；返回字节由各自的数据模型解码校验。
import Foundation
import Darwin

/// 一次性、可取消的 AI 请求服务，不持有用户项目状态。
struct CodexMixingService: Sendable {
    /// 优先使用用户指定的绝对路径，否则依次检查常见安装目录和 PATH。
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

    /// 为图形界面启动的 CLI 补全可执行目录，去重并排除相对 PATH 项。
    static func environment(
        for executable: URL,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        // Finder/Xcode 的 PATH 可能没有 Homebrew；npm 安装的启动器还需要找到 node。
        // Finder/Xcode launches often omit Homebrew; npm's Codex launcher needs /usr/bin/env node.
        let inherited = (base["PATH"] ?? "").split(separator: ":").map(String.init)
        let paths = [executable.deletingLastPathComponent().path] + inherited
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        environment["PATH"] = paths.filter { $0.hasPrefix("/") && seen.insert($0).inserted }.joined(separator: ":")
        return environment
    }

    /// 显式指定模型、权限、输出结构和临时工作目录，避免继承用户配置中的工具行为。
    static func arguments(
        schema: URL,
        output: URL,
        directory: URL,
        model: AIModelSelection = AIModelSelection(),
        webSearch: Bool = false,
        images: [URL] = []
    ) -> [String] {
        var arguments = ["exec", "--model", model.modelID]
        if model.reasoningEffort != .modelDefault {
            arguments += ["--config", "model_reasoning_effort=\"\(model.reasoningEffort.rawValue)\""]
        }
        // 联网请求开启 JSONL 事件输出，以便验证实际执行过搜索；附图通过独立参数传入。
        if webSearch { arguments.append("--json") }
        for image in images { arguments += ["--image", image.path] }
        return arguments + [
            "--ignore-user-config",
            "--sandbox", "read-only",
            "--config", "approval_policy=\"never\"",
            "--config", webSearch ? "web_search=\"live\"" : "web_search=\"disabled\"",
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

    /// 为一个目标色生成底色、阴影和高光，并验证参考漆与可用颜料范围。
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

    /// 将实体颜料组合请求交给 AI 估计目标色，再解析完整的三色配方。
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

    /// 执行通用结构化请求；返回前检查退出状态、搜索事件与响应大小。
    func request(
        prompt: String,
        schema: Data,
        configuration: AIConfiguration,
        webSearch: Bool = false,
        images: [Data] = [],
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        let configuration = try configuration.validated()
        try Task.checkCancellation()
        guard images.count <= 3, images.allSatisfy({ $0.count <= 12_000_000 }) else {
            throw ManualStudyError.invalid("说明书页面图像过大，请降低分辨率后重试。")
        }
        guard let executable = Self.executableURL(customPath: configuration.executablePath) else {
            throw MixingError.cliNotFound
        }

        // 每个请求使用独立私有目录，结束或抛错后统一删除输入、附图和输出。
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("GoldenMixing-\(UUID().uuidString)")
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: directory) }

        let schemaURL = directory.appendingPathComponent("schema.json")
        let outputURL = directory.appendingPathComponent("recipe.json")
        let promptURL = directory.appendingPathComponent("prompt.txt")
        let logURL = directory.appendingPathComponent("codex.log")
        var imageURLs: [URL] = []
        for (index, data) in images.enumerated() {
            let url = directory.appendingPathComponent("page-\(index + 1).jpg")
            try data.write(to: url)
            imageURLs.append(url)
        }
        try schema.write(to: schemaURL)
        try Data(prompt.utf8).write(to: promptURL)
        guard files.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw MixingError.launchFailed("无法创建临时日志。")
        }

        // 用文件承接输出，避免无人持续读取的管道填满后阻塞子进程。
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
            arguments: Self.arguments(
                schema: schemaURL, output: outputURL, directory: directory,
                model: configuration.model, webSearch: webSearch, images: imageURLs
            ),
            directory: directory,
            input: input,
            log: log,
            logURL: logURL,
            // 启动连接检查可单独限制等待时间；调色与考证仍沿用原推理档位的时限。
            timeout: timeout ?? configuration.model.reasoningEffort.generationTimeout
        )
        try Task.checkCancellation()
        guard status == 0 else {
            throw MixingError.cliFailed(Self.failureMessage(at: logURL, model: configuration.model))
        }
        // 搜索任务必须有完成事件；模型在回答中声称“已搜索”不能替代工具记录。
        if webSearch {
            let events = try Data(contentsOf: logURL)
            guard Self.containsCompletedWebSearch(events) else {
                throw ManualStudyError.invalid("本次 AI 未完成联网检索，未采用返回结果。请检查模型是否支持搜索、更新 Codex 后重试。")
            }
        }
        guard files.fileExists(atPath: outputURL.path) else {
            throw MixingError.invalidRecipe("Codex 没有返回结果，请重试。")
        }
        let size = (try files.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= MixingPalette.maximumResponseBytes else {
            throw MixingError.invalidRecipe("AI 返回内容过长，请重新生成。")
        }
        return try Data(contentsOf: outputURL)
    }

    /// 从 JSONL 日志确认搜索工具完成；此检查只证明执行了检索，不验证每条考证结论。
    /// A research result must be backed by an actual search tool event, not just a claim in its prose.
    static func containsCompletedWebSearch(_ events: Data) -> Bool {
        String(decoding: events, as: UTF8.self).split(separator: "\n").contains { line in
            guard let data = String(line).data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["type"] as? String == "item.completed",
                  let item = event["item"] as? [String: Any],
                  item["type"] as? String == "web_search" else { return false }
            let status = item["status"] as? String
            return status == nil || status == "completed"
        }
    }

    /// 从日志尾部提取有限诊断，将常见认证和额度问题转换为可操作的中文提示。
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

/// 每个请求拥有独立 actor 和子进程；取消完成前等待子进程退出，避免临时文件仍被占用。
/// Each request owns one actor and one child process. Cancellation waits for that child to exit.
actor CodexProcessRunner {
    /// 运行进程并周期检查取消、超时和日志上限；任何失败都会先清理对应子进程。
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
            // 通过可取消的异步短暂等待轮询，不在主线程阻塞等待 CLI 完成。
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
                // 先请求正常终止；短暂宽限后仅强制结束本次请求拥有的进程。
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
