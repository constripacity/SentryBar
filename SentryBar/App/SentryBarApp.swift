import SwiftUI

@main
struct SentryBarApp: App {
    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var ruleStore = ConnectionRuleStore()
    @StateObject private var systemVM: SystemViewModel
    @StateObject private var networkVM: NetworkViewModel
    @StateObject private var notificationLog: NotificationLog

    init() {
        let settings = SettingsViewModel()
        let rules = ConnectionRuleStore()
        let log = NotificationLog()
        _settingsVM = StateObject(wrappedValue: settings)
        _ruleStore = StateObject(wrappedValue: rules)
        _notificationLog = StateObject(wrappedValue: log)
        _systemVM = StateObject(wrappedValue: SystemViewModel(appSettings: settings.appSettings, notificationLog: log))
        _networkVM = StateObject(wrappedValue: NetworkViewModel(appSettings: settings.appSettings, ruleStore: rules, notificationLog: log))
    }

    var body: some Scene {
        // MenuBarExtra creates a menubar-only app (no dock icon, no window)
        MenuBarExtra {
            MenuBarView(systemVM: systemVM, networkVM: networkVM, settingsVM: settingsVM, ruleStore: ruleStore, notificationLog: notificationLog)
                .frame(width: 360, height: 480)
        } label: {
            // Menubar icon + status indicator
            StatusIconView(systemVM: systemVM, networkVM: networkVM)
        }
        .menuBarExtraStyle(.window) // Shows as a dropdown panel, not a menu
    }
}
