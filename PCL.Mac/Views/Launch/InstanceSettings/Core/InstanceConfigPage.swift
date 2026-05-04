import SwiftUI
import Core
import AppKit
import Darwin

struct InstanceConfigPage: View {
    @StateObject private var viewModel: InstanceConfigViewModel
    @StateObject private var loadingVM: MyLoadingViewModel = .init(text: "加载中")

    init(id: String) {
        self._viewModel = .init(wrappedValue: .init(id: id))
    }

    var body: some View {
        InstanceSettingsScrollPage {
            if viewModel.loaded, let instance = viewModel.instance {
                InstanceSettingsInfoBanner(text: "这些设置只对该游戏实例生效，不影响其他实例。")

                InstanceSettingsSectionCard("启动选项") {
                    VStack(alignment: .leading, spacing: 12) {
                        InstanceSettingsFieldRow("版本隔离") {
                            Button(action: chooseVersionIsolationMode) {
                                InstanceSettingsInputBox(text: viewModel.versionIsolationEnabled ? "开启" : "关闭", showsChevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                        InstanceSettingsFieldRow("应用显示名称") {
                            advancedSingleLineField(text: windowTitleBinding, placeholder: viewModel.windowTitleFollowsGlobal ? instance.name : "输入自定义窗口标题")
                                .disabled(viewModel.windowTitleFollowsGlobal)
                                .opacity(viewModel.windowTitleFollowsGlobal ? 0.65 : 1)
                        }
                        InstanceSettingsCheckboxRow(title: "使用实例名作为窗口标题", isOn: windowTitleFollowsBinding)
                        MyText("该选项会在下次启动时影响 macOS 中的应用 / Dock 显示名称。Minecraft 实际游戏窗口标题由游戏自身的 GLFW 窗口控制，启动器无法直接覆盖。", size: 11.5, color: .colorGray3)
                            .padding(.leading, 112)
                        InstanceSettingsFieldRow("自定义信息") {
                            advancedSingleLineField(text: customInfoBinding, placeholder: "显示在概览页的实例备注")
                        }
                        InstanceSettingsFieldRow("游戏 Java") {
                            Button(action: chooseJavaRuntime) {
                                InstanceSettingsInputBox(text: viewModel.javaDescription, showsChevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                        InstanceSettingsCheckboxRow(title: "自动选择合适的 Java", isOn: autoSelectJavaBinding)
                        if !viewModel.javaSelectionHint.isEmpty {
                            MyText(viewModel.javaSelectionHint, size: 11.5, color: .colorGray3)
                                .padding(.leading, 112)
                        }
                    }
                }

                InstanceSettingsSectionCard("游戏内存") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(MinecraftInstance.Config.MemoryMode.allCases, id: \.self) { mode in
                            InstanceSettingsRadioRow(title: mode.title, selected: viewModel.memoryMode == mode) {
                                viewModel.setMemoryMode(mode)
                            }
                        }

                        HStack {
                            Slider(value: heapSizeBinding, in: 512...memoryUpperBound, step: 256)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 4)
                        .disabled(viewModel.memoryMode != .custom)
                        .opacity(viewModel.memoryMode == .custom ? 1 : 0.5)

                        InstanceSettingsInputBox(text: viewModel.memoryMode == .custom ? "自定义：\(viewModel.jvmHeapSize) MB" : "自动调节（当前按默认值处理）")

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                MyText("已使用内存", size: 11, color: .colorGray3)
                                Spacer()
                                MyText("游戏分配", size: 11, color: .colorGray3)
                            }
                            GeometryReader { geometry in
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(Color.color3)
                                        .frame(width: geometry.size.width * systemUsedMemoryRatio, height: 3)
                                    Rectangle()
                                        .fill(Color.color5)
                                        .frame(width: geometry.size.width * allocatedMemoryRatio, height: 3)
                                    Rectangle()
                                        .fill(Color.colorGray6)
                                        .frame(width: geometry.size.width * freeMemoryRatio, height: 3)
                                }
                            }
                            .frame(height: 3)
                            HStack {
                                MyText(usedMemoryText, size: 12)
                                Spacer()
                                MyText(allocatedMemoryText, size: 12)
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                InstanceSettingsSectionCard("服务器") {
                    VStack(alignment: .leading, spacing: 12) {
                        InstanceSettingsFieldRow("自动进入服务器") {
                            advancedSingleLineField(text: serverEntryBinding, placeholder: "服务器地址[:端口]，例如 mc.example.com:25565")
                        }
                        MyText("启动时会自动附加 --server / --port 参数。留空则不处理。", size: 11.5, color: .colorGray3)
                            .padding(.leading, 112)
                    }
                }

                InstanceSettingsSectionCard("高级启动选项", folded: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        InstanceSettingsFieldRow("JVM 参数头部") {
                            advancedTextEditor(text: jvmArgsBinding, placeholder: "例如 -Dfile.encoding=UTF-8 -XX:+UseStringDeduplication", height: 80)
                        }
                        InstanceSettingsFieldRow("游戏参数尾部") {
                            advancedSingleLineField(text: gameArgsBinding, placeholder: "例如 --fullscreen")
                        }
                        InstanceSettingsFieldRow("Classpath 头部附加") {
                            advancedSingleLineField(text: classpathPrefixBinding, placeholder: "多个条目可用空格分隔")
                        }
                        InstanceSettingsFieldRow("启动前执行命令") {
                            advancedSingleLineField(text: launchPrecommandBinding, placeholder: "使用 zsh -lc 执行，失败会中止启动")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            InstanceSettingsCheckboxRow(title: "关闭资源完整性校验", isOn: disableValidationBinding)
                            InstanceSettingsCheckboxRow(title: "跟随启动器网络代理设置", isOn: followProxySettingsBinding)
                            InstanceSettingsCheckboxRow(title: "启用 log4j 调试日志", isOn: useLog4jConfigBinding)
                        }
                        .padding(.top, 2)
                    }
                }

                InstanceSettingsCenterActionButton(title: "全局设置", systemImage: "arrow.right") {
                    AppRouter.shared.setRoot(.settings)
                }
            } else {
                MyLoading(viewModel: loadingVM, showCard: false)
            }
        }
        .task(id: viewModel.id) {
            do {
                try await viewModel.load()
            } catch {
                await MainActor.run {
                    loadingVM.fail(with: "加载失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private var totalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024
    }

    private var memoryUpperBound: Double {
        max(4096, Double(Int(totalMemoryGB * 1024)))
    }

    private var usedMemoryText: String {
        String(format: "%.1f GB / %.1f GB", systemUsedMemoryGB + effectiveAllocatedMemoryGB, totalMemoryGB)
    }

    private var allocatedMemoryText: String {
        String(format: "%.1f GB", effectiveAllocatedMemoryGB)
    }

    private var effectiveAllocatedMemoryGB: Double {
        let heapMB: Double
        switch viewModel.memoryMode {
        case .custom:
            heapMB = Double(Int(viewModel.jvmHeapSize) ?? 4096)
        case .global, .auto:
            heapMB = 4096
        }
        return min(heapMB / 1024, totalMemoryGB)
    }

    private var systemUsedMemoryGB: Double {
        let pageSize = vm_kernel_page_size
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return 0
        }

        let usedPages = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count)
        let usedBytes = usedPages * UInt64(pageSize)
        return min(Double(usedBytes) / 1024 / 1024 / 1024, totalMemoryGB)
    }

    private var systemUsedMemoryRatio: Double {
        min(systemUsedMemoryGB / totalMemoryGB, 1)
    }

    private var allocatedMemoryRatio: Double {
        let remaining = max(1 - systemUsedMemoryRatio, 0)
        return min(effectiveAllocatedMemoryGB / totalMemoryGB, remaining)
    }

    private var freeMemoryRatio: Double {
        max(1 - systemUsedMemoryRatio - allocatedMemoryRatio, 0)
    }

    private var heapSizeBinding: Binding<Double> {
        Binding(
            get: { Double(Int(viewModel.jvmHeapSize) ?? 4096) },
            set: {
                let heap = UInt64($0.rounded())
                viewModel.jvmHeapSize = String(Int(heap))
                viewModel.setHeapSize(heap)
            }
        )
    }

    private func chooseJavaRuntime() {
        let runtimes = viewModel.javaList()
        MessageBoxManager.shared.showList(
            title: "切换 Java",
            items: runtimes.map { .init(name: $0.description, description: $0.executableURL.path) }
        ) { index in
            guard let index else { return }
            do {
                try viewModel.switchJava(to: runtimes[index])
            } catch {
                hint("切换 Java 失败：\(error.localizedDescription)", type: .critical)
            }
        }
    }

    private func chooseVersionIsolationMode() {
        let currentEnabled = viewModel.versionIsolationEnabled
        MessageBoxManager.shared.showList(
            title: "版本隔离",
            items: [
                .init(name: "开启", description: "存档、模组、配置等内容保存在当前实例目录中。"),
                .init(name: "关闭", description: "运行目录改为游戏仓库，多个实例可共享运行时内容。")
            ]
        ) { index in
            guard let index else { return }
            let enabled = index == 0
            if enabled != currentEnabled {
                viewModel.setVersionIsolationEnabled(enabled)
            }
        }
    }

    private func advancedSingleLineField(text: Binding<String>) -> some View {
        advancedSingleLineField(text: text, placeholder: nil)
    }

    private func advancedSingleLineField(text: Binding<String>, placeholder: String?) -> some View {
        ZStack(alignment: .leading) {
            if let placeholder, text.wrappedValue.isEmpty {
                MyText(placeholder, size: 12, color: .colorGray3)
                    .padding(.horizontal, 10)
                    .allowsHitTesting(false)
            }

            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.custom("PCLEnglish", size: 12))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 10)
        }
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.color6, lineWidth: 1)
                )
        )
    }

    private func advancedTextEditor(text: Binding<String>, placeholder: String, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            configuredTextEditor(text: text)

            if text.wrappedValue.isEmpty {
                MyText(placeholder, size: 12, color: .colorGray3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.color6, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func configuredTextEditor(text: Binding<String>) -> some View {
        if #available(macOS 13.0, *) {
            TextEditor(text: text)
                .font(.custom("PCLEnglish", size: 12))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .foregroundStyle(Color.black)
                .background(Color.clear)
        } else {
            LegacyPlainTextEditor(text: text)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
    }
}

private struct LegacyPlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = NSFont(name: "PCLEnglish", size: 12) ?? .systemFont(ofSize: 12)
        textView.textColor = .black

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = NSFont(name: "PCLEnglish", size: 12) ?? .systemFont(ofSize: 12)
        textView.textColor = .black
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private extension InstanceConfigPage {
    var windowTitleFollowsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.windowTitleFollowsGlobal },
            set: { viewModel.setWindowTitleFollowsGlobal($0) }
        )
    }

    var versionIsolationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.versionIsolationEnabled },
            set: { viewModel.setVersionIsolationEnabled($0) }
        )
    }

    var windowTitleBinding: Binding<String> {
        Binding(
            get: { viewModel.customWindowTitle },
            set: { viewModel.setCustomWindowTitle($0) }
        )
    }

    var customInfoBinding: Binding<String> {
        Binding(
            get: { viewModel.customInfo },
            set: { viewModel.setCustomInfo($0) }
        )
    }

    var autoSelectJavaBinding: Binding<Bool> {
        Binding(
            get: { viewModel.autoSelectJava },
            set: { viewModel.setAutoSelectJava($0) }
        )
    }

    var serverEntryBinding: Binding<String> {
        Binding(
            get: { viewModel.serverEntry },
            set: { viewModel.setServerEntry($0) }
        )
    }

    var jvmArgsBinding: Binding<String> {
        Binding(
            get: { viewModel.jvmArgs },
            set: { viewModel.setJVMArguments($0) }
        )
    }

    var gameArgsBinding: Binding<String> {
        Binding(
            get: { viewModel.gameArgs },
            set: { viewModel.setGameArguments($0) }
        )
    }

    var classpathPrefixBinding: Binding<String> {
        Binding(
            get: { viewModel.classpathPrefix },
            set: { viewModel.setClasspathPrefix($0) }
        )
    }

    var launchPrecommandBinding: Binding<String> {
        Binding(
            get: { viewModel.launchPrecommand },
            set: { viewModel.setLaunchPrecommand($0) }
        )
    }

    var disableValidationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.disableValidation },
            set: { viewModel.setDisableValidation($0) }
        )
    }

    var followProxySettingsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.followProxySettings },
            set: { viewModel.setFollowProxySettings($0) }
        )
    }

    var useLog4jConfigBinding: Binding<Bool> {
        Binding(
            get: { viewModel.useLog4jConfig },
            set: { viewModel.setUseLog4jConfig($0) }
        )
    }
}
