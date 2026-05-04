import SwiftUI
import AppKit

struct UpdateSettingsPage: View {
    @StateObject private var viewModel: UpdateSettingsViewModel = .init()

    var body: some View {
        CardContainer {
            MyCard("更新设置", foldable: false) {
                VStack(alignment: .leading, spacing: 12) {
                    configLine(label: "更新通道") {
                        channelMenu
                    }

                    configLine(label: "自动检查更新") {
                        statusText(viewModel.automaticallyChecksForUpdates ? "已开启" : "已关闭")
                    }

                    configLine(label: "自动下载更新") {
                        statusText(viewModel.automaticallyDownloadsUpdates ? "已开启" : (viewModel.allowsAutomaticDownloads ? "已关闭" : "当前不可用"))
                    }

                    configLine(label: "用户标识") {
                        HStack(spacing: 10) {
                            MyText(viewModel.userIDDescription, size: 12, color: .color1)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(viewModel.userIDDescription, forType: .string)
                                hint("已复制用户标识。", type: .finish)
                            } label: {
                                Image(.iconCopy)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                    .foregroundStyle(Color.color3)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.color3.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                VStack(spacing: 10) {
                    InstanceSettingsCheckboxRow(title: "启动器启动后自动检查更新", isOn: Binding(
                        get: { viewModel.automaticallyChecksForUpdates },
                        set: { viewModel.setAutomaticallyChecksForUpdates($0) }
                    ))

                    InstanceSettingsCheckboxRow(title: "在后台自动下载可用更新", isOn: Binding(
                        get: { viewModel.automaticallyDownloadsUpdates },
                        set: { viewModel.setAutomaticallyDownloadsUpdates($0) }
                    ))
                    .opacity(viewModel.allowsAutomaticDownloads ? 1 : 0.5)
                }

                if !viewModel.canUseSparkle {
                    MyText("当前未检测到完整的 Sparkle 配置，因此这里只能触发旧版更新链路；等公钥与 feed 全部配置完成后，这里会自动切换到 Sparkle。", size: 11.5, color: .colorGray3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
            }

            MyCard("当前版本", foldable: false) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.color3.opacity(0.12))
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(.iconRefresh)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundStyle(Color.color3)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        MyText(viewModel.currentVersionDescription, size: 16)
                        MyText(viewModel.currentStatusDescription, size: 12, color: .colorGray3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 20)

                    MyButton("再次检查") {
                        viewModel.checkForUpdates()
                    }
                    .frame(width: 120)
                }
            }
        }
    }

    private var channelMenu: some View {
        Menu {
            ForEach(UpdateSettingsViewModel.ChannelOption.allCases) { option in
                Button {
                    viewModel.selectChannel(option)
                } label: {
                    if viewModel.selectedChannel == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(viewModel.selectedChannel.title)
                        .font(.custom("PCLEnglish", size: 12))
                        .foregroundStyle(Color.black)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.color6, lineWidth: 1)
                        )
                )
                MyText(viewModel.selectedChannel.description, size: 11.5, color: .colorGray3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(.black)
    }

    @ViewBuilder
    private func configLine(label: String, @ViewBuilder body: () -> some View) -> some View {
        HStack(spacing: 20) {
            MyText(label)
                .frame(width: 140, alignment: .leading)
            HStack {
                Spacer(minLength: 0)
                body()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func statusText(_ text: String) -> some View {
        MyText(text, size: 12, color: .color1)
    }
}
