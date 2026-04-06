//
//  AccountViewModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/1/15.
//

import SwiftUI
import Combine
import Core

class AccountViewModel: ObservableObject {
    @Published public private(set) var accounts: [Account] = []
    @Published public private(set) var currentAccountId: UUID?
    public var currentAccount: Account? {
        if let currentAccountId {
            return accounts.first(where: { $0.id == currentAccountId })
        }
        return nil
    }
    
    public init() {
        self.accounts = LauncherConfig.shared.accounts
        self.currentAccountId = LauncherConfig.shared.currentAccountId
    }

    private func syncConfig() {
        LauncherConfig.mutate {
            $0.accounts = accounts
            $0.currentAccountId = currentAccountId
        }
    }
    
    /// 请求用户添加账号。
    public func requestAddAccount() {
        Task {
            log("开始请求添加账号")
            guard let idx: Int = await MessageBoxManager.shared.showListAsync(
                title: "选择账号类型",
                items: [
                    .init(image: "IconMicrosoftAccount", imageSize: 32, name: "正版账号", description: nil),
                    .init(image: "IconMicrosoftAccount", imageSize: 32, name: "第三方账号", description: "Authlib-Injector / 外置登录"),
                    .init(image: "IconOfflineAccount", imageSize: 32, name: "离线账号", description: nil)
                ]
            ) else {
                log("用户取消了添加")
                return
            }
            if idx == 0 {
                log("用户选择了添加正版账号")
                await requestAddMicrosoftAccount()
            } else if idx == 1 {
                log("用户选择了添加第三方账号")
                await requestAddThirdPartyAccount()
            } else {
                log("用户选择了添加离线账号")
                await requestAddOfflineAccount()
            }
        }
    }
    
    /// 切换当前账号。
    public func switchAccount(to account: Account) {
        currentAccountId = account.id
        syncConfig()
    }
    
    /// 移除账号。
    /// - Parameter account: 要移除的账号。
    public func remove(account: Account) {
        accounts.removeAll(where: { $0.id == account.id })
        if currentAccount == nil {
            if let firstAccount = accounts.first {
                currentAccountId = firstAccount.id
            } else {
                currentAccountId = nil
            }
        }
        syncConfig()
    }
    
    /// 获取账号皮肤数据。
    public func skinData(for account: Account) async -> Data {
        await SkinService.skinData(for: account)
    }

    public static func skinData(for account: Account) async -> Data {
        await SkinService.skinData(for: account)
    }
    
    private func requestAddMicrosoftAccount() async {
        let service: MicrosoftAuthService = .init()
        let code: MicrosoftAuthService.AuthorizationCode
        log("开始进行微软登录")
        do {
            code = try await service.start()
            log("获取设备码成功")
        } catch {
            err("添加正版账号失败：获取设备码失败：\(error.localizedDescription)")
            hint("添加正版账号失败：获取设备码失败：\(error.localizedDescription)", type: .critical)
            return
        }
        
        let authTask = Task {
            do {
                guard let pollCount = service.pollCount,
                      let pollInterval = service.pollInterval else {
                    err("pollCount 或 pollInterval 未被设置")
                    throw MicrosoftAuthService.Error.internalError
                }
                do {
                    defer {
                        DispatchQueue.main.async {
                            NSApplication.shared.activate(ignoringOtherApps: true)
                            MessageBoxManager.shared.complete(with: .button(id: 1))
                        }
                    }
                    for i in 0..<pollCount {
                        try Task.checkCancellation()
                        log("第 \(i + 1)/\(pollCount) 次轮询")
                        try await Task.sleep(seconds: Double(pollInterval))
                        if try await service.poll() {
                            log("用户完成了授权")
                            break
                        }
                        if i == pollCount - 1 {
                            throw SimpleError("授权超时。")
                        }
                    }
                }
                hint("授权成功！正在完成后续登录步骤……")
                let response = try await service.authenticate()
                let account: MicrosoftAccount = .init(profile: response.profile, accessToken: response.accessToken, refreshToken: response.refreshToken)
                log("添加正版账号成功")
                hint("账号添加成功！", type: .finish)
                await MainActor.run {
                    LauncherConfig.mutate {
                        $0.hasMicrosoftAccount = true
                    }
                    addAccount(account)
                }
            } catch is CancellationError {
            } catch let error as MicrosoftAuthService.Error {
                switch error {
                case .xboxAuthenticationFailed(let code):
                    switch code {
                    case 2148916238:
                        showErrorMessageBox(
                            "Xbox 验证失败",
                            "当前账户为未成年账户，无法通过 Xbox Live 认证。\n请点击下方的“确定”按钮，更改账户年龄后再次尝试登录。",
                            "https://support.microsoft.com/account-billing/837badbc-999e-54d2-2617-d19206b9540a"
                        )
                    case 2148916233:
                        showErrorMessageBox(
                            "Xbox 验证失败",
                            "该微软账户没有关联 Xbox 账户。\n请点击下方的“确定”按钮，关联 Xbox 账户后再次尝试登录。",
                            "https://www.minecraft.net/msaprofile/mygames/editprofile"
                        )
                    default:
                        MessageBoxManager.shared.showText(
                            title: "Xbox 验证失败",
                            content: "发生未知错误。错误代码：\(code)",
                            level: .error
                        )
                    }
                case .apiError(let description):
                    MessageBoxManager.shared.showText(
                        title: "添加正版账号失败",
                        content: "响应体：\(description)",
                        level: .error
                    )
                case .internalError:
                    MessageBoxManager.shared.showText(
                        title: "添加正版账号失败",
                        content: "发生内部错误。\n若要寻求帮助，请将完整日志发送给他人，而不是发送此页面相关的图片。",
                        level: .error
                    )
                case .notPurchased:
                    showErrorMessageBox(
                        "添加正版账号失败",
                        "看起来你还没有购买 Minecraft。\n如果你已购买 Minecraft，请点击下方的“确定”按钮，创建档案后再次尝试登录。",
                        "https://www.minecraft.net/msaprofile/mygames/editprofile"
                    )
                }
            } catch {
                MessageBoxManager.shared.showText(
                    title: "添加正版账号失败",
                    content: "\(error.localizedDescription)\n若要寻求帮助，请将完整日志发送给他人，而不是发送此页面相关的图片。"
                )
                hint("登录失败：\(error.localizedDescription)", type: .critical)
            }
        }
        
        if await MessageBoxManager.shared.showTextAsync(
            title: "添加正版账号",
            content: "请打开 \(code.verificationURL)，然后输入 \(code.code)，随后根据提示完成后续授权步骤。\n点击下方按钮可以一键复制并跳转！",
            .init(id: 1, label: "复制并跳转", type: .highlight) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.code, forType: .string)
                NSWorkspace.shared.open(code.verificationURL)
            },
            .no()
        ) == 0 {
            log("用户取消了授权")
            authTask.cancel()
        }
    }
    
    private func showErrorMessageBox(_ title: String, _ content: String, _ link: String) {
        MessageBoxManager.shared.showText(
            title: title,
            content: content,
            level: .error,
            .no(),
            .yes(type: .highlight)
        ) { result in
            if result == 1 {
                NSWorkspace.shared.open(link.url!)
            }
        }
    }
    
    private func requestAddOfflineAccount() async {
        guard let playerName: String = await MessageBoxManager.shared.showInputAsync(title: "玩家名") else {
            log("用户取消了添加")
            return
        }
        await MainActor.run {
            addAccount(OfflineAccount(name: playerName, uuid: UUIDUtils.uuid(ofOfflinePlayer: playerName)))
        }
    }

    private func requestAddThirdPartyAccount() async {
        guard let rawServer = await MessageBoxManager.shared.showInputAsync(title: "输入验证服务器地址", placeholder: "例如 littleskin.cn/api/yggdrasil")?.trimmingCharacters(in: .whitespacesAndNewlines), !rawServer.isEmpty else {
            log("用户取消了第三方账号添加（服务器地址）")
            return
        }
        guard let accountName = await MessageBoxManager.shared.showInputAsync(title: "输入第三方账号", placeholder: "邮箱或用户名")?.trimmingCharacters(in: .whitespacesAndNewlines), !accountName.isEmpty else {
            log("用户取消了第三方账号添加（账号）")
            return
        }
        guard let password = await MessageBoxManager.shared.showSecureInputAsync(title: "输入第三方账号密码")?.trimmingCharacters(in: .whitespacesAndNewlines), !password.isEmpty else {
            log("用户取消了第三方账号添加（密码）")
            return
        }

        do {
            let apiRoot = try await YggdrasilAuthService.resolveAPIURL(from: rawServer)
            let service = YggdrasilAuthService(apiRoot: apiRoot)
            let metadata = try await service.fetchMetadata()
            let response = try await service.authenticate(username: accountName, password: password)
            let serverName = metadata.meta?.serverName ?? apiRoot.host ?? apiRoot.absoluteString
            let account = ThirdPartyAccount(
                profile: response.profile,
                apiRoot: apiRoot,
                serverName: serverName,
                accountName: accountName,
                accessToken: response.accessToken,
                clientToken: response.clientToken,
                userProperties: response.userProperties
            )
            await MainActor.run {
                LauncherConfig.mutate {
                    $0.hasMicrosoftAccount = true
                }
                addAccount(account)
            }
            hint("第三方账号添加成功！", type: .finish)
        } catch {
            err("添加第三方账号失败：\(error.localizedDescription)")
            MessageBoxManager.shared.showText(
                title: "添加第三方账号失败",
                content: error.localizedDescription,
                level: .error
            )
        }
    }
    
    private func addAccount(_ account: Account) {
        accounts.append(account)
        currentAccountId = account.id
        syncConfig()
    }
}
