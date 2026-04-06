//
//  MinecraftLaunchManager.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/6.
//

import Foundation
import Core
import Combine

class MinecraftLaunchManager: ObservableObject {
    public static let shared: MinecraftLaunchManager = .init()
    
    @Published public var isLaunching: Bool = false
    @Published public var progress: Double = 0
    @Published public var currentStage: String? = nil
    @Published public var instanceName: String?
    public var isRunning: Bool { coordinator.isRunning }
    public let loadingModel: MyLoadingViewModel = .init(text: "正在启动游戏")
    
    private var task: MyTask<MinecraftLaunchTask.Model>? {
        didSet {
            isLaunching = task != nil
        }
    }
    private var cancellables: [AnyCancellable] = []
    private let coordinator = MinecraftLaunchExecutionCoordinator()
    
    /// 开始启动游戏。
    /// - Parameters:
    ///   - instance: 目标游戏实例。
    ///   - account: 使用的账号。
    ///   - repository: 实例所在的游戏仓库。
    /// - Returns: 一个布尔值，表示是否成功添加任务。
    @MainActor
    public func launch(
        _ instance: MinecraftInstance,
        using account: Account,
        in repository: MinecraftRepository
    ) -> Bool {
        if isLaunching { return false }
        self.loadingModel.text = "正在启动游戏"
        let task: MyTask<MinecraftLaunchTask.Model> = MinecraftLaunchTask.create(for: instance, using: account, in: repository) { launcher, process in
            self.coordinator.attachProcess(process, instance: instance, options: launcher.options, logURL: launcher.logURL, onCancellation: { [weak self] in
                self?.cancel()
            }, onCrash: { [weak self] in
                self?.loadingModel.text = "启动失败"
            })
            self.loadingModel.text = "已启动游戏"
        }
        TaskManager.shared.execute(task: task, display: false) { _ in
            self.task = nil
            self.coordinator.reset()
            self.syncCoordinatorState()
        }
        self.coordinator.begin(instanceName: instance.name, task: task)
        self.task = task
        self.subscribeCoordinator()
        self.syncCoordinatorState()
        return true
    }
    
    /// 取消当前启动任务。
    public func cancel() {
        if let task {
            TaskManager.shared.cancel(task.id)
        }
    }
    
    public func stop() {
        coordinator.stopProcess()
    }
    
    private func subscribeCoordinator() {
        cancellables.removeAll()
        coordinator.$currentStage
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentStage, on: self)
            .store(in: &cancellables)

        coordinator.$progress
            .receive(on: DispatchQueue.main)
            .assign(to: \.progress, on: self)
            .store(in: &cancellables)

        coordinator.$instanceName
            .receive(on: DispatchQueue.main)
            .assign(to: \.instanceName, on: self)
            .store(in: &cancellables)
    }

    private func syncCoordinatorState() {
        currentStage = coordinator.currentStage
        progress = coordinator.progress
        instanceName = coordinator.instanceName
    }
    
    private init() {}
    
}
