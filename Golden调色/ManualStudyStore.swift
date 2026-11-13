// 说明书考证的文件存储与导入下载入口。
// 存档使用项目 UUID 分隔，actor 串行处理读取与写入，避免同一存档交叉更新。
import Foundation

/// 管理考证存档；大体积 PDF 保存在 Application Support 中，不写入偏好设置。
actor ManualStudyStore {
    /// 正常界面共享的存储实例；测试可自行创建并注入临时目录。
    static let shared = ManualStudyStore()
    /// 原始 PDF 上限为 30 MB；编码后的 JSON 另有 50 MB 上限。
    static let maximumPDFBytes = 30_000_000
    private let root: URL?

    /// 注入根目录可隔离单元测试；未指定时采用应用的默认存档位置。
    init(root: URL? = nil) {
        self.root = root
    }

    /// 没有存档时返回 nil；文件损坏或版本不兼容时抛错，保留原文件。
    func load(projectID: UUID) throws -> ManualStudyArchive? {
        let url = try archiveURL(projectID: projectID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 50_000_000 else {
            throw ManualStudyError.invalid("已保存的说明书数据过大，无法读取。原文件已保留。")
        }
        let archive = try JSONDecoder().decode(ManualStudyArchive.self, from: Data(contentsOf: url))
        guard archive.formatVersion == 1 else {
            throw ManualStudyError.invalid("此说明书由其他版本保存，请使用兼容版本打开。原文件已保留。")
        }
        return archive
    }

    /// 将 PDF 与结果作为同一个快照原子写入，避免页标记与原文不一致。
    func save(_ archive: ManualStudyArchive, projectID: UUID) throws {
        guard (archive.pdfData?.count ?? 0) <= Self.maximumPDFBytes else {
            throw ManualStudyError.invalid("说明书 PDF 超过 30 MB，请先压缩或拆分。")
        }
        let url = try archiveURL(projectID: projectID)
        let data = try JSONEncoder().encode(archive)
        guard data.count <= 50_000_000 else {
            throw ManualStudyError.invalid("说明书与标注数据过大，无法保存。")
        }
        // A single atomic archive keeps the original PDF and its page references together.
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// 创建仅当前用户可访问的目录，并用项目 UUID 生成稳定文件名。
    private func archiveURL(projectID: UUID) throws -> URL {
        let directory: URL
        if let root {
            directory = root
        } else {
            #if DEBUG
            // 自动化测试按进程使用临时目录，避免触碰真实项目的说明书。
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("GoldenManualUITests-\(ProcessInfo.processInfo.processIdentifier)")
            } else {
                directory = try defaultDirectory()
            }
            #else
            directory = try defaultDirectory()
            #endif
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        return directory.appendingPathComponent(projectID.uuidString).appendingPathExtension("json")
    }

    /// 获取用户 Application Support 下的专用考证目录。
    private func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("Golden调色/ManualStudies", isDirectory: true)
    }

    /// 在文件选择器授予的访问范围内读取本地 PDF，并及时释放访问权限。
    static func importPDF(at url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximumPDFBytes else {
            throw ManualStudyError.invalid("请选择不超过 30 MB 的 PDF 文件。")
        }
        return try Data(contentsOf: url)
    }

    /// 流式下载候选文件，限制耗时和实际字节数；PDF 格式由 ManualPDF.open 后续校验。
    static func downloadPDF(from url: URL) async throws -> Data {
        guard ManualStudyURL.webURL(url.absoluteString) != nil else {
            throw ManualStudyError.invalid("说明书地址必须是 HTTP 或 HTTPS 网页地址。")
        }
        // 使用临时会话，不持久保存下载缓存与 Cookie。
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 180
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw ManualStudyError.invalid("说明书下载失败。请打开来源网页下载后，再导入 PDF。")
        }
        guard response.expectedContentLength <= Int64(maximumPDFBytes) else {
            throw ManualStudyError.invalid("说明书超过 30 MB，请下载后压缩或拆分再导入。")
        }
        var data = Data()
        data.reserveCapacity(min(max(0, Int(response.expectedContentLength)), maximumPDFBytes))
        // 不能只信任 Content-Length；下载过程中仍逐步执行大小和取消检查。
        for try await byte in bytes {
            data.append(byte)
            if data.count % 65_536 == 0 { try Task.checkCancellation() }
            guard data.count <= maximumPDFBytes else {
                throw ManualStudyError.invalid("说明书超过 30 MB，已停止下载。")
            }
        }
        try Task.checkCancellation()
        return data
    }
}
