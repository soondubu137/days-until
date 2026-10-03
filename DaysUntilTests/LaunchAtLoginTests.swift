import AppKit
import ServiceManagement
import Testing
@testable import DaysUntil

@MainActor
private final class LoginServiceStub: LaunchAtLoginService {
    var status: SMAppService.Status = .notRegistered
    var registeredStatus: SMAppService.Status = .enabled
    var registerError: Error?
    var unregisterError: Error?
    var registerCalls = 0
    var unregisterCalls = 0
    var settingsCalls = 0

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        status = registeredStatus
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSettings() { settingsCalls += 1 }
}

@Suite @MainActor
struct LaunchAtLoginTests {
    @Test func enabledOnlyAfterSystemConfirmation() {
        let service = LoginServiceStub()
        let login = LaunchAtLogin(service: service)
        #expect(login.status == .notRegistered)
        login.set(true)
        #expect(login.status == .enabled)
        #expect(login.failure == nil)
        login.set(true)
        #expect(service.registerCalls == 1)
        login.set(false)
        #expect(login.status == .notRegistered)
        #expect(service.unregisterCalls == 1)
    }

    @Test func pendingApprovalIsVisibleAndCanBeCancelled() {
        let service = LoginServiceStub()
        service.registeredStatus = .requiresApproval
        let login = LaunchAtLogin(service: service)
        login.set(true)
        #expect(login.status == .requiresApproval)
        #expect(login.guidance != nil)
        #expect(login.failure == nil)
        login.set(true)
        #expect(service.registerCalls == 1)
        login.openSettings()
        #expect(service.settingsCalls == 1)
        login.toggle()
        #expect(service.unregisterCalls == 1)
        #expect(login.status == .notRegistered)
    }

    @Test func registrationFailurePreservesReasonAndSupportsRetry() {
        let service = LoginServiceStub()
        service.registerError = NSError(domain: "LoginTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Registration denied by macOS."])
        let login = LaunchAtLogin(service: service)
        login.set(true)
        #expect(login.status == .notRegistered)
        #expect(login.failure?.contains("Registration denied by macOS.") == true)
        login.refresh()
        #expect(login.failure != nil)
        service.registerError = nil
        login.retry()
        #expect(service.registerCalls == 2)
        #expect(login.status == .enabled)
        #expect(login.failure == nil)
    }

    @Test func failedDisableKeepsEnabledStatusAndRetriesDisable() {
        let service = LoginServiceStub()
        service.status = .enabled
        service.unregisterError = NSError(domain: "LoginTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Removal denied by macOS."])
        let login = LaunchAtLogin(service: service)
        login.set(false)
        #expect(login.status == .enabled)
        #expect(login.failure?.contains("Removal denied by macOS.") == true)
        service.unregisterError = nil
        login.retry()
        #expect(service.unregisterCalls == 2)
        #expect(service.registerCalls == 0)
        #expect(login.status == .notRegistered)
        #expect(login.failure == nil)
    }

    @Test func externalApprovalAndRevocationRefreshWithoutRegistration() {
        let service = LoginServiceStub()
        service.status = .requiresApproval
        let login = LaunchAtLogin(service: service)
        service.status = .enabled
        login.refresh()
        #expect(login.status == .enabled)
        #expect(login.guidance == nil)
        service.status = .requiresApproval
        login.refresh()
        #expect(login.status == .requiresApproval)
        #expect(login.guidance != nil)
        #expect(service.registerCalls == 0)
    }

    @Test func externalChangeClearsStaleFailure() {
        let service = LoginServiceStub()
        service.registerError = NSError(domain: "LoginTests", code: 3)
        let login = LaunchAtLogin(service: service)
        login.set(true)
        #expect(login.failure != nil)
        service.status = .enabled
        login.refresh()
        #expect(login.failure == nil)
        login.retry()
        #expect(service.registerCalls == 1)
    }

    @Test func missingServiceAndUnconfirmedResultAreNotSuccess() {
        let service = LoginServiceStub()
        service.status = .notFound
        let login = LaunchAtLogin(service: service)
        #expect(login.guidance != nil)
        service.registeredStatus = .notRegistered
        login.set(true)
        #expect(login.status == .notRegistered)
        #expect(login.failure != nil)
    }

    @Test func toggleReadsLatestSystemStatus() {
        let service = LoginServiceStub()
        let login = LaunchAtLogin(service: service)
        service.status = .enabled
        login.toggle()
        #expect(service.registerCalls == 0)
        #expect(service.unregisterCalls == 1)
        #expect(login.status == .notRegistered)
    }

    @Test func menuRefreshesCheckmarkAndOffersSettings() throws {
        let service = LoginServiceStub()
        let login = LaunchAtLogin(service: service)
        let suite = "DaysUntilTests.LoginMenu.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CountdownStore(defaults: defaults)
        let state = PopoverState(store: store, launchAtLogin: login)
        let more = MoreMenu(store: store, state: state)
        for (status, checkmark) in [(SMAppService.Status.enabled, NSControl.StateValue.on), (.requiresApproval, .mixed), (.notRegistered, .off), (.notFound, .off)] {
            service.status = status
            let menu = more.make()
            let item = try #require(menu.items.first { $0.title == login.statusTitle })
            #expect(item.state == checkmark)
            #expect(menu.items.contains { $0.action == NSSelectorFromString("openLoginItemsSettings") })
        }
    }

    @Test func firstSaveKeepsCountdownAndExposesLoginFailure() {
        let service = LoginServiceStub()
        service.registerError = NSError(domain: "LoginTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot register this app."])
        let login = LaunchAtLogin(service: service)
        let suite = "DaysUntilTests.LoginSave.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CountdownStore(defaults: defaults)
        let state = PopoverState(store: store, launchAtLogin: login)
        let countdown = Countdown(name: "Trip", icon: .symbol("airplane"), targetDate: Date().addingTimeInterval(86400), showsTime: false, place: nil, startDate: Date())
        state.draft.openAtLogin = true
        state.save(countdown)
        #expect(store.countdown == countdown)
        #expect(!state.isEditing)
        #expect(login.failure?.contains("Cannot register this app.") == true)
        state.save(countdown)
        #expect(service.registerCalls == 1)
    }
}
