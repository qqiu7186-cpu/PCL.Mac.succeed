import Foundation

@MainActor
final class OtherSettingsViewModel: ObservableObject {
    private let settingsExporter: SettingsLogExporting
    private let updateFlowRunner: AppUpdateFlowRunning

    init(
        settingsExporter: SettingsLogExporting = SettingsViewModel.shared,
        updateFlowRunner: AppUpdateFlowRunning? = nil
    ) {
        self.settingsExporter = settingsExporter
        self.updateFlowRunner = updateFlowRunner ?? UpdateService.shared
    }

    func exportLogs() throws -> URL {
        try settingsExporter.exportLogs()
    }

    func checkUpdates() {
        updateFlowRunner.runInteractiveUpdateFlow(manually: true)
    }
}
