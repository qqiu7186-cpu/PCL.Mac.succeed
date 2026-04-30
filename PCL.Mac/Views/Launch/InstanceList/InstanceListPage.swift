//
//  InstanceListPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/29.
//

import SwiftUI
import Core

struct InstanceListPage: View {
    @EnvironmentObject private var instanceViewModel: InstanceManager
    @EnvironmentObject private var viewModel: InstanceListViewModel
    @State private var query: String = ""
    @FocusState private var searchFocused: Bool
    private let target: RepositoryRouteTarget
    @ObservedObject private var repository: MinecraftRepository
    
    init(target: RepositoryRouteTarget) {
        self.target = target
        self.repository = InstanceManager.shared.repository(matching: target.repositoryPath) ?? .init(name: target.name, url: URL(fileURLWithPath: target.repositoryPath))
    }
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.color5.opacity(0.55), Color.color7.opacity(0.9), Color.color8],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                if repository.instances != nil {
                    ScrollView {
                        VStack(spacing: 8) {
                            searchBar
                                .padding(.top, 12)

                            if let errorInstances = repository.errorInstances, !errorInstances.isEmpty {
                                MyCard("错误实例（\(errorInstances.count)）", foldable: false, padding: 14) {
                                    VStack(spacing: 0) {
                                        ForEach(errorInstances, id: \.name) { instance in
                                            MyListItem(.init(image: "RedstoneBlock", name: instance.name, description: instance.message))
                                        }
                                    }
                                }
                            }

                            if filteredRegularInstances.isEmpty && filteredModdedInstances.isEmpty {
                                MyCard("实例列表", foldable: false, padding: 14) {
                                    emptyState
                                }
                            } else {
                                if !filteredRegularInstances.isEmpty {
                                    sectionCard(title: "常规实例", instances: filteredRegularInstances, cardIndex: 1)
                                }

                                if !filteredModdedInstances.isEmpty {
                                    sectionCard(
                                        title: "可安装 Mod",
                                        instances: filteredModdedInstances,
                                        cardIndex: filteredRegularInstances.isEmpty ? 1 : 2
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                    }
                } else {
                    MyLoading(viewModel: viewModel.loadingViewModel, showCard: false)
                }
            }
        }
        .onAppear {
            if repository.instances != nil { return }
            viewModel.reloadAsync(repository)
        }
        .id(target.id)
    }

    private var filteredRegularInstances: [MinecraftInstance] {
        filteredInstances.filter { $0.modLoader == nil }
    }

    private var filteredModdedInstances: [MinecraftInstance] {
        filteredInstances.filter { $0.modLoader != nil }
    }

    private var filteredInstances: [MinecraftInstance] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let allInstances = repository.instances ?? []
        guard !keyword.isEmpty else {
            return allInstances.sorted(by: compareInstance(lhs:rhs:))
        }

        return allInstances
            .filter {
                $0.name.localizedCaseInsensitiveContains(keyword) ||
                $0.version.id.localizedCaseInsensitiveContains(keyword) ||
                ($0.modLoader?.description.localizedCaseInsensitiveContains(keyword) ?? false)
            }
            .sorted(by: compareInstance(lhs:rhs:))
    }
    
    private func compareInstance(lhs: MinecraftInstance, rhs: MinecraftInstance) -> Bool {
        if lhs.modLoader == rhs.modLoader {
            return lhs.version > rhs.version
        }
        return (lhs.modLoader?.index ?? -1) > (rhs.modLoader?.index ?? -1)
    }
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image("IconSearch")
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(Color.color1)

            ZStack(alignment: .leading) {
                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .font(.custom("PCLEnglish", size: 14))
                    .foregroundStyle(Color.color1)
                    .focused($searchFocused)

                if query.isEmpty {
                    Text("搜索游戏实例")
                        .font(.custom("PCLEnglish", size: 14))
                        .foregroundStyle(Color.colorGray3)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.color6, lineWidth: 1)
                )
        )
    }

    private func sectionCard(title: String, instances: [MinecraftInstance], cardIndex: Int) -> some View {
        MyCard("\(title)（\(instances.count)）", folded: false, padding: 14) {
            VStack(spacing: 0) {
                ForEach(instances, id: \.name) { instance in
                    InstanceSelectionRow(
                        instance: instance,
                        selected: isCurrentSelection(instance)
                    ) {
                        instanceViewModel.switchInstance(to: instance, repository)
                        AppRouter.shared.removeLast()
                    }
                }
            }
        }
        .cardIndex(cardIndex)
    }

    private func isCurrentSelection(_ instance: MinecraftInstance) -> Bool {
        instanceViewModel.currentRepository == repository && instanceViewModel.currentInstance == instance
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            MyText(query.isEmpty ? "这个目录里还没有可用实例。" : "没有找到匹配的实例。", size: 13)
            MyText(query.isEmpty ? "你可以在左侧添加目录，或导入整合包后再来这里选择。" : "试试搜索实例名、版本号，或者模组加载器名称。", size: 11.5, color: .colorGray3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InstanceSelectionRow: View {
    private let name: String
    private let version: MinecraftVersion
    private let iconName: String
    private let selected: Bool
    private let onTap: () -> Void
    @State private var hovered: Bool = false
    
    init(instance: MinecraftInstance, selected: Bool, onTap: @escaping () -> Void) {
        self.name = instance.name
        self.version = instance.version
        self.selected = selected
        self.onTap = onTap
        if let modLoader = instance.modLoader {
            self.iconName = modLoader.icon
        } else {
            self.iconName = "GrassBlock"
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                MyText(name, size: 13)
                MyText(version.id, size: 11, color: .colorGray3)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(selected ? Color.color2.opacity(0.12) : (hovered ? Color.color2.opacity(0.08) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: onTap)
        .animation(.easeInOut(duration: 0.12), value: hovered)
        .animation(.easeInOut(duration: 0.12), value: selected)
    }
}
