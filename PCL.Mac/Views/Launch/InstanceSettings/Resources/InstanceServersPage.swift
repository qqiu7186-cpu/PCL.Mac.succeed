import SwiftUI
import Core
import UniformTypeIdentifiers
import AppKit
import zlib
import Network

struct InstanceServersPage: View {
    private static let refreshDebounceInterval: TimeInterval = 2

    fileprivate enum ServerState: Equatable {
        case unknown
        case pinging
        case online(latency: Int, onlinePlayers: Int?, maxPlayers: Int?, motd: String?)
        case offline
    }

    fileprivate struct ServerEntry: Identifiable {
        let id: String
        var name: String
        var address: String
        var icon: NSImage?
        var state: ServerState = .unknown
    }

    let id: String
    private let serverButtonWidth: CGFloat = 130
    @State private var instance: MinecraftInstance?
    @State private var errorMessage: String?
    @State private var hasServersDat: Bool = false
    @State private var servers: [ServerEntry] = []
    @State private var lastRefreshAt: Date = .distantPast

    var body: some View {
        InstanceSettingsBackground {
            if let instance {
                let serversDat = instance.runningDirectory.appending(path: "servers.dat")
                if servers.isEmpty {
                    InstanceSettingsEmptyStateCard(
                        title: "暂时没有服务器",
                        description: "暂时没有找到服务器，在游戏内添加服务器或点击下方按钮添加新服务器。",
                        primaryTitle: "刷新服务器信息",
                        secondaryTitle: "添加新服务器",
                        tertiaryTitle: nil,
                        primaryAction: {
                            triggerRefresh(for: serversDat, withHint: true)
                        },
                        secondaryAction: {
                            Task { await addServer() }
                        },
                        tertiaryAction: nil
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            MyCard("快捷操作", foldable: false) {
                                HStack(spacing: 12) {
                                    MyButton("刷新所有服务器") {
                                        triggerRefresh(for: serversDat, withHint: true)
                                    }
                                    .frame(width: serverButtonWidth)
                                    MyButton("添加新服务器") {
                                        Task { await addServer() }
                                    }
                                    .frame(width: serverButtonWidth)
                                    Spacer(minLength: 0)
                                }
                                .frame(height: 35)
                                if let errorMessage {
                                    MyText(errorMessage, size: 11.5, color: .red)
                                        .padding(.top, 8)
                                }
                            }

                            MyCard("", foldable: false, titled: false, padding: 14) {
                                ForEach(servers) { server in
                                    MyListItem { hovered in
                                        HStack(spacing: 0) {
                                            Color.clear
                                                .frame(width: 6)

                                            ServerIconView(image: server.icon)
                                                .padding(.trailing, 7)

                                            VStack(alignment: .leading, spacing: 2) {
                                                MyText(server.name, size: 13)
                                                HStack(spacing: 6) {
                                                    signalView(for: server)
                                                    MyText(statusDetailText(for: server), size: 11, color: .colorGray3)
                                                        .lineLimit(1)
                                                }
                                            }
                                            .frame(width: 190, alignment: .leading)

                                            Spacer(minLength: 0)

                                            ServerMotdView(text: serverSubtitle(server))
                                                .frame(width: 320, alignment: .center)
                                                .padding(.trailing, 10)

                                            HStack(spacing: 10) {
                                                InstanceSettingsHoverActionButton(systemImage: "play", color: .color3, help: "连接 / 设为自动进入服务器") {
                                                    setAutoJoinServer(server.address)
                                                }
                                                Menu {
                                                    Button("刷新") {
                                                        Task { await refreshServer(server.id) }
                                                    }
                                                    Button("复制地址") {
                                                        copyServerAddress(server.address)
                                                    }
                                                    Button("详情") {
                                                        Task { await showServerDetails(server) }
                                                    }
                                                    Button("编辑") {
                                                        Task { await editServer(server) }
                                                    }
                                                    Divider()
                                                    Button("移除", role: .destructive) {
                                                        Task { await removeServer(server) }
                                                    }
                                                } label: {
                                                    Image(systemName: "gearshape")
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundColor(.black)
                                                }
                                                .tint(.black)
                                                .menuStyle(.borderlessButton)
                                                .fixedSize()
                                            }
                                            .frame(width: 60, alignment: .trailing)
                                        }
                                        .frame(height: 44)
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 2)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                    }
                }
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"), showCard: false)
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
            if let instance {
                refreshServersDatState(instance.runningDirectory.appending(path: "servers.dat"))
            }
        }
    }

    private func triggerRefresh(for path: URL, withHint: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshAt) >= Self.refreshDebounceInterval else {
            if withHint {
                hint("请勿频繁刷新！", type: .info)
            }
            return
        }
        lastRefreshAt = now
        if withHint {
            hint("正在刷新服务器列表，请稍候...", type: .info)
        }
        refreshServersDatState(path)
    }

    private func refreshServersDatState(_ path: URL) {
        hasServersDat = FileManager.default.fileExists(atPath: path.path)
        guard hasServersDat else {
            servers = []
            errorMessage = "暂时没有服务器，请在游戏内添加后再刷新。"
            return
        }

        do {
            servers = try parseServersDat(at: path)
            errorMessage = nil
            Task {
                await refreshAllServers()
            }
        } catch {
            servers = []
            errorMessage = "读取 servers.dat 失败：\(error.localizedDescription)"
        }
    }

    private func exportServersDat(from path: URL) {
        guard FileManager.default.fileExists(atPath: path.path) else {
            errorMessage = "未找到 servers.dat。"
            return
        }
        let panel = NSSavePanel()
        panel.title = "导出 servers.dat"
        panel.nameFieldStringValue = "servers.dat"
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: path, to: destination)
            hint("导出成功", type: .finish)
            errorMessage = nil
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importServersDat(to path: URL) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data]
        panel.title = "导入 servers.dat"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        guard source.lastPathComponent.lowercased() == "servers.dat" else {
            errorMessage = "请选择名为 servers.dat 的文件。"
            hint("导入失败：请选择 servers.dat", type: .critical)
            return
        }
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
            try FileManager.default.copyItem(at: source, to: path)
            hint("导入成功", type: .finish)
            refreshServersDatState(path)
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func resetServersDat(at path: URL) {
        do {
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
            hint("已重置 servers.dat", type: .finish)
            hasServersDat = false
            servers = []
            errorMessage = nil
        } catch {
            errorMessage = "重置失败：\(error.localizedDescription)"
        }
    }

    private func openServersDirectory(_ instance: MinecraftInstance) {
        NSWorkspace.shared.open(instance.runningDirectory)
        errorMessage = "已打开实例目录，请在游戏内添加服务器，或导入 servers.dat。"
    }

    private func setAutoJoinServer(_ address: String) {
        guard let instance else { return }
        instance.setAutoJoinServer(address)
        hint("已将自动进入服务器设置为 \(address)", type: .finish)
    }

    private func addServer() async {
        guard let name = await MessageBoxManager.shared.showInputAsync(title: "编辑服务器信息", initialContent: "Minecraft服务器", placeholder: "请输入新的服务器名称：")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              let address = await MessageBoxManager.shared.showInputAsync(title: "编辑服务器信息", initialContent: "", placeholder: "请输入新的服务器地址：")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty else {
            return
        }
        let newServer = ServerEntry(id: UUID().uuidString, name: name, address: address, icon: nil)
        servers.append(newServer)
        do {
            try saveServersDat()
            hint("已添加服务器", type: .finish)
            await refreshServer(newServer.id)
        } catch {
            servers.removeLast()
            errorMessage = "保存 servers.dat 失败：\(error.localizedDescription)"
            hint(errorMessage ?? "保存 servers.dat 失败", type: .critical)
        }
    }

    private func editServer(_ server: ServerEntry) async {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        guard let name = await MessageBoxManager.shared.showInputAsync(title: "编辑服务器信息", initialContent: server.name, placeholder: "请输入新的服务器名称：")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              let address = await MessageBoxManager.shared.showInputAsync(title: "编辑服务器信息", initialContent: server.address, placeholder: "请输入新的服务器地址：")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty else {
            return
        }
        let previous = servers[index]
        servers[index].name = name
        servers[index].address = address
        do {
            try saveServersDat()
            hint("服务器信息已更新", type: .finish)
            await refreshServer(server.id)
        } catch {
            servers[index] = previous
            errorMessage = "保存 servers.dat 失败：\(error.localizedDescription)"
            hint(errorMessage ?? "保存 servers.dat 失败", type: .critical)
        }
    }

    private func removeServer(_ server: ServerEntry) async {
        let confirmed = await MessageBoxManager.shared.showConfirmAsync(
            title: "移除服务器确认",
            content: "你确定要移除服务器 \(server.name) 吗？\n'\(server.address)' 将从列表中移除，且无法恢复。",
            level: .error,
            cancelLabel: "取消",
            confirmLabel: "确认",
            confirmType: .red
        )
        guard confirmed, let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        let removed = servers.remove(at: index)
        do {
            try saveServersDat()
            hint("服务器已移除", type: .finish)
        } catch {
            servers.insert(removed, at: index)
            errorMessage = "保存 servers.dat 失败：\(error.localizedDescription)"
            hint(errorMessage ?? "保存 servers.dat 失败", type: .critical)
        }
    }

    private func showServerDetails(_ server: ServerEntry) async {
        let status: String
        switch server.state {
        case .unknown:
            status = "未知"
        case .pinging:
            status = "正在连接..."
        case .offline:
            status = "服务器离线"
        case let .online(latency, onlinePlayers, maxPlayers, motd):
            let playerText = if let onlinePlayers, let maxPlayers {
                "\(onlinePlayers) / \(maxPlayers)"
            } else {
                "???"
            }
            status = "在线（\(latency)ms，\(playerText)）\n\(motd ?? "")"
        }
        await MessageBoxManager.shared.showAlertAsync(
            title: "服务器详情",
            content: "名称：\(server.name)\n地址：\(server.address)\n状态：\(status)"
        )
    }

    private func parseServersDat(at path: URL) throws -> [ServerEntry] {
        let data = try Data(contentsOf: path)
        let decompressed = try gunzip(data)
        var reader = NBTReader(data: decompressed)
        return try reader.parseServersList()
    }

    private func copyServerAddress(_ address: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        hint("已复制服务器地址：\(address)", type: .finish)
    }

    private func serverSubtitle(_ server: ServerEntry) -> String {
        switch server.state {
        case let .online(_, onlinePlayers, maxPlayers, motd):
            let playerText = if let onlinePlayers, let maxPlayers {
                "\(onlinePlayers) / \(maxPlayers)"
            } else {
                "???"
            }
            if let motd, !motd.isEmpty {
                return "\(playerText) · \(motd)"
            }
            return "\(server.address) · \(playerText)"
        default:
            return server.address
        }
    }

    private func statusText(for server: ServerEntry) -> String {
        switch server.state {
        case .unknown:
            return "等待检测"
        case .pinging:
            return "正在连接..."
        case .offline:
            return "服务器离线"
        case let .online(latency, onlinePlayers, maxPlayers, _):
            if let onlinePlayers, let maxPlayers {
                return "\(latency)ms · \(onlinePlayers) / \(maxPlayers)"
            }
            return "\(latency)ms"
        }
    }

    private func statusDetailText(for server: ServerEntry) -> String {
        switch server.state {
        case .unknown:
            return "等待检测"
        case .pinging:
            return "正在连接"
        case .offline:
            return "离线"
        case let .online(_, onlinePlayers, maxPlayers, _):
            if let onlinePlayers, let maxPlayers {
                return "\(onlinePlayers) / \(maxPlayers)"
            }
            return "???"
        }
    }

    private func statusColor(for server: ServerEntry) -> Color {
        switch server.state {
        case .online:
            return .green
        case .pinging:
            return .color3
        case .offline:
            return .colorGray3
        case .unknown:
            return .colorGray3
        }
    }

    @ViewBuilder
    private func signalView(for server: ServerEntry) -> some View {
        switch server.state {
        case .unknown, .pinging, .offline:
            ServerSignalBars(level: signalLevel(for: server), color: statusColor(for: server), offline: server.state == .offline)
        case .online:
            ServerSignalBars(level: signalLevel(for: server), color: .green, offline: false)
        }
    }

    private func signalLevel(for server: ServerEntry) -> Int {
        switch server.state {
        case .unknown:
            return 0
        case .pinging:
            return 0
        case .offline:
            return -1
        case let .online(latency, _, _, _):
            switch latency {
            case 0..<100: return 5
            case 100..<300: return 4
            case 300..<600: return 3
            case 600..<1000: return 2
            default: return 1
            }
        }
    }

    private func refreshAllServers() async {
        let limiter = AsyncRefreshLimiter(limit: 5)
        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                group.addTask {
                    await limiter.acquire()
                    await refreshServer(server.id)
                    await limiter.release()
                }
            }
        }
    }

    private func refreshServer(_ id: String) async {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        await MainActor.run {
            servers[index].state = .pinging
        }
        let result = await MinecraftServerStatusService.fetchStatus(for: servers[index].address)
        await MainActor.run {
            guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
            servers[index].state = result.state
            if servers[index].icon == nil, let icon = result.icon {
                servers[index].icon = icon
            }
        }
    }

    private func saveServersDat() throws {
        guard let instance else { return }
        let path = instance.runningDirectory.appending(path: "servers.dat")
        let data = try NBTWriter.makeServersDat(from: servers)
        try data.write(to: path, options: .atomic)
        refreshServersDatState(path)
    }
}

private struct ServerSignalBars: View {
    let level: Int
    let color: Color
    let offline: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 0.8)
                    .fill(fillColor(for: index))
                    .frame(width: 3.2, height: [6, 9, 12, 15, 18][index])
            }
        }
        .frame(width: 22, height: 18, alignment: .bottomLeading)
    }

    private func fillColor(for index: Int) -> Color {
        guard !offline else { return Color.colorGray3.opacity(index == 0 ? 0.9 : 0.35) }
        return index < level ? color : Color.colorGray3.opacity(0.35)
    }
}

private struct ServerMotdView: View {
    let text: String

    var body: some View {
        if let richText = formattedText {
            richText
                .font(.system(size: 11.5))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        } else {
            MyText("服务器离线", size: 11.5, color: .colorGray3)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    private var formattedText: Text? {
        let parsed = MinecraftMotdParser.parse(text)
        guard !parsed.isEmpty else { return nil }
        return parsed.dropFirst().reduce(parsed[0]) { partial, next in partial + next }
    }
}

private enum MinecraftMotdParser {
    static func parse(_ input: String) -> [Text] {
        let sanitized = input.replacingOccurrences(of: "\u{00A7}", with: "§")
            .replacingOccurrences(of: "\\n", with: "\n")
        guard !sanitized.isEmpty else { return [] }

        var result: [Text] = []
        var buffer = ""
        var currentColor: Color = .colorGray3

        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(Text(buffer).foregroundColor(currentColor))
            buffer = ""
        }

        var index = sanitized.startIndex
        while index < sanitized.endIndex {
            let character = sanitized[index]
            if character == "§" {
                let next = sanitized.index(after: index)
                guard next < sanitized.endIndex else { break }
                flush()
                currentColor = color(for: sanitized[next]) ?? currentColor
                index = sanitized.index(after: next)
                continue
            }
            buffer.append(character)
            index = sanitized.index(after: index)
        }
        flush()
        return result
    }

    private static func color(for code: Character) -> Color? {
        switch code.lowercased().first {
        case "0": return .black
        case "1": return Color(red: 0.0, green: 0.0, blue: 0.67)
        case "2": return Color(red: 0.0, green: 0.67, blue: 0.0)
        case "3": return Color(red: 0.0, green: 0.67, blue: 0.67)
        case "4": return Color(red: 0.67, green: 0.0, blue: 0.0)
        case "5": return Color(red: 0.67, green: 0.0, blue: 0.67)
        case "6": return Color(red: 1.0, green: 0.67, blue: 0.0)
        case "7": return Color.gray
        case "8": return Color(red: 0.33, green: 0.33, blue: 0.33)
        case "9": return Color(red: 0.33, green: 0.33, blue: 1.0)
        case "a": return Color(red: 0.33, green: 1.0, blue: 0.33)
        case "b": return Color(red: 0.33, green: 1.0, blue: 1.0)
        case "c": return Color(red: 1.0, green: 0.33, blue: 0.33)
        case "d": return Color(red: 1.0, green: 0.33, blue: 1.0)
        case "e": return Color(red: 1.0, green: 1.0, blue: 0.33)
        case "f", "r": return .white
        default: return nil
        }
    }
}

private actor AsyncRefreshLimiter {
    private let limit: Int
    private var running: Int = 0

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    func acquire() async {
        while running >= limit {
            try? await Task.sleep(seconds: 0.05)
        }
        running += 1
    }

    func release() async {
        running = max(running - 1, 0)
    }
}

private enum MinecraftServerStatusService {
    private static let timeoutSeconds: Double = 5

    struct Result {
        let state: InstanceServersPage.ServerState
        let icon: NSImage?
    }

    private struct StatusResponse: Decodable {
        struct Players: Decodable {
            let online: Int?
            let max: Int?
        }

        struct Description: Decodable {
            let text: String?
            let extra: [Description]?
        }

        let players: Players?
        let description: Description?
        let favicon: String?
    }

    static func fetchStatus(for address: String) async -> Result {
        guard let endpoint = parseAddress(address) else {
            return .init(state: .offline, icon: nil)
        }

        return await withTaskGroup(of: Result.self) { group in
            group.addTask {
                let start = Date()
                let connection = NWConnection(host: endpoint.host, port: endpoint.port, using: .tcp)
                let queue = DispatchQueue(label: "pclmac.serverping")
                connection.start(queue: queue)

                defer { connection.cancel() }

                do {
                    try await waitUntilReady(connection)
                    try await sendHandshake(connection, host: endpoint.rawHost, port: endpoint.port)
                    try await sendStatusRequest(connection)
                    let packet = try await receivePacket(connection)

                    let latency = max(Int(Date().timeIntervalSince(start) * 1000), 1)
                    let json = try JSONDecoder.shared.decode(StatusResponse.self, from: packet)
                    let motd = flatten(description: json.description)
                    let icon = decodeServerIcon(json.favicon)
                    return .init(
                        state: .online(latency: latency, onlinePlayers: json.players?.online, maxPlayers: json.players?.max, motd: motd),
                        icon: icon
                    )
                } catch {
                    return .init(state: .offline, icon: nil)
                }
            }

            group.addTask {
                do {
                    try await Task.sleep(seconds: timeoutSeconds)
                } catch {
                }
                return .init(state: .offline, icon: nil)
            }

            let first = await group.next() ?? .init(state: .offline, icon: nil)
            group.cancelAll()
            return first
        }
    }

    private struct Endpoint {
        let rawHost: String
        let host: NWEndpoint.Host
        let port: NWEndpoint.Port
    }

    private static func parseAddress(_ address: String) -> Endpoint? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        let host = parts[0]
        let port = parts.count > 1 ? UInt16(parts[1]) ?? 25565 : 25565
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        return .init(rawHost: host, host: .init(host), port: nwPort)
    }

    private static func waitUntilReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let lock = NSLock()
            var resumed = false

            func resumeOnce(_ action: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                connection.stateUpdateHandler = nil
                action()
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce {
                        continuation.resume(returning: ())
                    }
                case .failed(let error):
                    resumeOnce {
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    resumeOnce {
                        continuation.resume(throwing: CancellationError())
                    }
                default:
                    break
                }
            }
        }
    }

    private static func sendHandshake(_ connection: NWConnection, host: String, port: NWEndpoint.Port) async throws {
        var payload = Data()
        payload.append(varInt: 0)
        payload.append(varInt: 47)
        payload.append(minecraftString: host)
        payload.append(contentsOf: [UInt8((port.rawValue >> 8) & 0xff), UInt8(port.rawValue & 0xff)])
        payload.append(varInt: 1)
        try await sendPacket(connection, payload: payload)
    }

    private static func sendStatusRequest(_ connection: NWConnection) async throws {
        var payload = Data()
        payload.append(varInt: 0)
        try await sendPacket(connection, payload: payload)
    }

    private static func sendPacket(_ connection: NWConnection, payload: Data) async throws {
        var packet = Data()
        packet.append(varInt: payload.count)
        packet.append(payload)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private static func receivePacket(_ connection: NWConnection) async throws -> Data {
        let lengthPrefix = try await receiveVarIntBytes(connection)
        var reader = ByteReader(data: lengthPrefix)
        let length = try reader.readVarInt()
        let body = try await receiveExactly(connection, count: length)
        var bodyReader = ByteReader(data: body)
        _ = try bodyReader.readVarInt()
        return try bodyReader.readMinecraftStringData()
    }

    private static func receiveVarIntBytes(_ connection: NWConnection) async throws -> Data {
        var data = Data()
        while data.count < 5 {
            let chunk = try await receiveChunk(connection, minimum: 1, maximum: 1)
            data.append(chunk)
            if let last = data.last, (last & 0x80) == 0 {
                return data
            }
        }
        throw SimpleError("服务器响应格式无效。")
    }

    private static func receiveExactly(_ connection: NWConnection, count: Int) async throws -> Data {
        guard count >= 0 else {
            throw SimpleError("服务器响应中的长度无效。")
        }
        var data = Data()
        while data.count < count {
            let chunk = try await receiveChunk(connection, minimum: 1, maximum: count - data.count)
            data.append(chunk)
        }
        return data
    }

    private static func receiveChunk(_ connection: NWConnection, minimum: Int, maximum: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: minimum, maximumLength: maximum) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: SimpleError("服务器连接已关闭。"))
                } else {
                    continuation.resume(throwing: SimpleError("未收到服务器响应。"))
                }
            }
        }
    }

    private static func flatten(description: StatusResponse.Description?) -> String? {
        guard let description else { return nil }
        let current = description.text ?? ""
        let children = description.extra?.compactMap(flatten(description:)).joined() ?? ""
        let result = current + children
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : result
    }

    private static func decodeServerIcon(_ favicon: String?) -> NSImage? {
        guard let favicon else { return nil }
        let base64 = favicon.replacingOccurrences(of: "data:image/png;base64,", with: "")
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }
}

private struct ByteReader {
    let data: Data
    var offset: Int = 0

    mutating func readVarInt() throws -> Int {
        var value = 0
        var position = 0
        while true {
            guard offset < data.count else { throw SimpleError("读取服务器响应失败。") }
            let byte = Int(data[offset])
            offset += 1
            value |= (byte & 0x7F) << position
            if (byte & 0x80) == 0 { return value }
            position += 7
            if position >= 35 { throw SimpleError("服务器响应格式无效。") }
        }
    }

    mutating func readMinecraftStringData() throws -> Data {
        let length = try readVarInt()
        guard length >= 0, offset + length <= data.count else {
            throw SimpleError("服务器响应中的字符串长度无效。")
        }
        defer { offset += length }
        return data.subdata(in: offset..<(offset + length))
    }
}

private extension Data {
    mutating func append(varInt value: Int) {
        var value = UInt32(value)
        repeat {
            var temp = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                temp |= 0x80
            }
            append(temp)
        } while value != 0
    }

    mutating func append(minecraftString value: String) {
        let utf8 = Data(value.utf8)
        append(varInt: utf8.count)
        append(utf8)
    }
}

private struct ServerIconView: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.78))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "server.rack")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.colorGray2)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct NBTReader {
    enum ReaderError: LocalizedError {
        case invalidFormat(String)

        var errorDescription: String? {
            switch self {
            case .invalidFormat(let message): return message
            }
        }
    }

    enum Tag {
        case end
        case byte(UInt8)
        case string(String)
        case list([Tag])
        case compound([String: Tag])
    }

    let data: Data
    var offset: Int = 0

    mutating func parseServersList() throws -> [InstanceServersPage.ServerEntry] {
        let rootType = try readUInt8()
        guard rootType == 10 else {
            throw ReaderError.invalidFormat("servers.dat 根标签不是 Compound。")
        }
        _ = try readString()
        guard case let .compound(root) = try readPayload(type: rootType),
              let serversTag = root["servers"],
              case let .list(entries) = serversTag else {
            return []
        }

        return entries.compactMap { entry in
            guard case let .compound(compound) = entry,
                  case let .string(name) = compound["name"],
                  case let .string(address) = compound["ip"] else {
                return nil
            }
            let icon: NSImage?
            if case let .string(iconString) = compound["icon"] {
                icon = decodeServerIcon(iconString)
            } else {
                icon = nil
            }
            return .init(id: address, name: name, address: address, icon: icon)
        }
    }

    private mutating func readPayload(type: UInt8) throws -> Tag {
        switch type {
        case 0:
            return .end
        case 1:
            return .byte(try readUInt8())
        case 8:
            return .string(try readString())
        case 9:
            let childType = try readUInt8()
            let count = Int(try readInt32())
            var items: [Tag] = []
            items.reserveCapacity(max(count, 0))
            for _ in 0..<max(count, 0) {
                items.append(try readPayload(type: childType))
            }
            return .list(items)
        case 10:
            var compound: [String: Tag] = [:]
            while true {
                let childType = try readUInt8()
                if childType == 0 { break }
                let name = try readString()
                compound[name] = try readPayload(type: childType)
            }
            return .compound(compound)
        case 2:
            _ = try readInt16()
            return .end
        case 3:
            _ = try readInt32()
            return .end
        case 4:
            _ = try readInt64()
            return .end
        case 5:
            _ = try readInt32()
            return .end
        case 6:
            _ = try readInt64()
            return .end
        case 7:
            let count = Int(try readInt32())
            try skip(count)
            return .end
        case 11:
            let count = Int(try readInt32())
            try skip(count * 4)
            return .end
        case 12:
            let count = Int(try readInt32())
            try skip(count * 8)
            return .end
        default:
            throw ReaderError.invalidFormat("servers.dat 包含不支持的 NBT 标签类型：\(type)")
        }
    }

    private mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else { throw ReaderError.invalidFormat("读取 servers.dat 越界。") }
        defer { offset += 1 }
        return data[offset]
    }

    private mutating func readInt16() throws -> Int16 {
        let bytes = try readBytes(count: 2)
        return Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
    }

    private mutating func readInt32() throws -> Int32 {
        let bytes = try readBytes(count: 4)
        return Int32(bitPattern: UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
    }

    private mutating func readInt64() throws -> Int64 {
        let bytes = try readBytes(count: 8)
        return Int64(bitPattern:
            UInt64(bytes[0]) << 56 |
            UInt64(bytes[1]) << 48 |
            UInt64(bytes[2]) << 40 |
            UInt64(bytes[3]) << 32 |
            UInt64(bytes[4]) << 24 |
            UInt64(bytes[5]) << 16 |
            UInt64(bytes[6]) << 8 |
            UInt64(bytes[7])
        )
    }

    private mutating func readString() throws -> String {
        let length = Int(try readInt16())
        let bytes = try readBytes(count: length)
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw ReaderError.invalidFormat("servers.dat 中存在无效字符串。")
        }
        return string
    }

    private mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw ReaderError.invalidFormat("读取 servers.dat 越界。")
        }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    private mutating func skip(_ count: Int) throws {
        _ = try readBytes(count: count)
    }

    private func decodeServerIcon(_ iconString: String) -> NSImage? {
        let base64 = iconString.replacingOccurrences(of: "data:image/png;base64,", with: "")
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }
}

private enum NBTWriter {
    static func makeServersDat(from servers: [InstanceServersPage.ServerEntry]) throws -> Data {
        var data = Data()
        data.append(10)
        appendString("", to: &data)
        data.append(9)
        appendString("servers", to: &data)
        data.append(10)
        appendInt32(Int32(servers.count), to: &data)

        for server in servers {
            data.append(8)
            appendString("name", to: &data)
            appendString(server.name, to: &data)
            data.append(8)
            appendString("ip", to: &data)
            appendString(server.address, to: &data)
            data.append(0)
        }

        data.append(0)
        return try gzip(data)
    }

    private static func appendString(_ string: String, to data: inout Data) {
        let utf8 = Data(string.utf8)
        appendInt16(Int16(utf8.count), to: &data)
        data.append(utf8)
    }

    private static func appendInt16(_ value: Int16, to data: inout Data) {
        data.append(UInt8((UInt16(bitPattern: value) >> 8) & 0xff))
        data.append(UInt8(UInt16(bitPattern: value) & 0xff))
    }

    private static func appendInt32(_ value: Int32, to data: inout Data) {
        let raw = UInt32(bitPattern: value)
        data.append(UInt8((raw >> 24) & 0xff))
        data.append(UInt8((raw >> 16) & 0xff))
        data.append(UInt8((raw >> 8) & 0xff))
        data.append(UInt8(raw & 0xff))
    }
}

private func gunzip(_ data: Data) throws -> Data {
    guard !data.isEmpty else { return data }

    var stream = z_stream()
    var status: Int32 = Z_OK
    let chunkSize = 64 * 1024
    var output = Data()

    var input = Array(data)
    status = input.withUnsafeMutableBufferPointer { inputBuffer in
        guard let baseAddress = inputBuffer.baseAddress else {
            return Z_DATA_ERROR
        }
        stream.next_in = UnsafeMutablePointer(baseAddress)
        stream.avail_in = uInt(inputBuffer.count)

        let initStatus = inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { return initStatus }
        defer { inflateEnd(&stream) }

        repeat {
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            let inflateStatus = buffer.withUnsafeMutableBufferPointer { outputBuffer -> Int32 in
                guard let outputBase = outputBuffer.baseAddress else { return Z_BUF_ERROR }
                stream.next_out = UnsafeMutablePointer(outputBase)
                stream.avail_out = uInt(outputBuffer.count)
                let status = inflate(&stream, Z_NO_FLUSH)
                let produced = outputBuffer.count - Int(stream.avail_out)
                output.append(outputBuffer.baseAddress!, count: produced)
                return status
            }
            status = inflateStatus
        } while status == Z_OK

        return status
    }

    guard status == Z_STREAM_END else {
        throw NBTReader.ReaderError.invalidFormat(status == Z_OK ? "初始化 GZip 解压失败。" : "解压 servers.dat 失败。")
    }

    return output
}

private func gzip(_ data: Data) throws -> Data {
    guard !data.isEmpty else { return data }

    var stream = z_stream()
    var output = Data()
    let chunkSize = 64 * 1024
    var input = Array(data)

    let status = input.withUnsafeMutableBufferPointer { inputBuffer -> Int32 in
        guard let inputBase = inputBuffer.baseAddress else { return Z_DATA_ERROR }
        stream.next_in = UnsafeMutablePointer(inputBase)
        stream.avail_in = uInt(inputBuffer.count)

        let initStatus = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 16 + MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { return initStatus }
        defer { deflateEnd(&stream) }

        var flush = Z_NO_FLUSH
        repeat {
            if stream.avail_in == 0 { flush = Z_FINISH }
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            let result = buffer.withUnsafeMutableBufferPointer { outputBuffer -> Int32 in
                guard let outputBase = outputBuffer.baseAddress else { return Z_BUF_ERROR }
                stream.next_out = UnsafeMutablePointer(outputBase)
                stream.avail_out = uInt(outputBuffer.count)
                let status = deflate(&stream, flush)
                let produced = outputBuffer.count - Int(stream.avail_out)
                output.append(outputBuffer.baseAddress!, count: produced)
                return status
            }
            if result == Z_STREAM_END { return result }
            if result != Z_OK { return result }
        } while flush != Z_FINISH

        return Z_STREAM_END
    }

    guard status == Z_STREAM_END else {
        throw NBTReader.ReaderError.invalidFormat("压缩 servers.dat 失败。")
    }
    return output
}
