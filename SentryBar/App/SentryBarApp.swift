import SwiftUI

@main
struct SentryBarApp: App {
    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var ruleStore = ConnectionRuleStore()
    @StateObject private var systemVM: SystemViewModel
    @StateObject private var networkVM: NetworkViewModel
    @StateObject private var notificationLog: NotificationLog
    @StateObject private var remoraVM: RemoraViewModel

    init() {
        let settings = SettingsViewModel()
        let rules = ConnectionRuleStore()
        let log = NotificationLog()
        _settingsVM = StateObject(wrappedValue: settings)
        _ruleStore = StateObject(wrappedValue: rules)
        _notificationLog = StateObject(wrappedValue: log)
        _systemVM = StateObject(wrappedValue: SystemViewModel(appSettings: settings.appSettings, notificationLog: log))
        _networkVM = StateObject(wrappedValue: NetworkViewModel(appSettings: settings.appSettings, ruleStore: rules, notificationLog: log))
        _remoraVM = StateObject(wrappedValue: RemoraViewModel(appSettings: settings.appSettings, notificationLog: log))
    }

    var body: some Scene {
        // MenuBarExtra creates a menubar-only app (no dock icon, no window)
        MenuBarExtra {
            MenuBarView(systemVM: systemVM, networkVM: networkVM, settingsVM: settingsVM, ruleStore: ruleStore, notificationLog: notificationLog, remoraVM: remoraVM)
                .frame(width: 360, height: 480)
                .onAppear {
                    settingsVM.checkForUpdates()
                }
        } label: {
            // Menubar icon + status indicator
            StatusIconView(systemVM: systemVM, networkVM: networkVM, appSettings: settingsVM.appSettings, remoraVM: remoraVM)
        }
        .menuBarExtraStyle(.window) // Shows as a dropdown panel, not a menu
    }
}
