import SwiftUI

@main
struct SentryBarApp: App {
    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var ruleStore = ConnectionRuleStore()
    @StateObject private var systemVM: SystemViewModel
    @StateObject private var networkVM: NetworkViewModel

    init() {
        let settings = SettingsViewModel()
        let rules = ConnectionRuleStore()
        _settingsVM = StateObject(wrappedValue: settings)
        _ruleStore = StateObject(wrappedValue: rules)
        _systemVM = StateObject(wrappedValue: SystemViewModel(appSettings: settings.appSettings))
        _networkVM = StateObject(wrappedValue: NetworkViewModel(appSettings: settings.appSettings, ruleStore: rules))
    }

    var body: some Scene {
        // MenuBarExtra creates a menubar-only app (no dock icon, no window)
        MenuBarExtra {
            MenuBarView(systemVM: systemVM, networkVM: networkVM, settingsVM: settingsVM, ruleStore: ruleStore)
                .frame(width: 360, height: 480)
        } label: {
            // Menubar icon + status indicator
            StatusIconView(systemVM: systemVM, networkVM: networkVM)
        }
        .menuBarExtraStyle(.window) // Shows as a dropdown panel, not a menu
    }
}
