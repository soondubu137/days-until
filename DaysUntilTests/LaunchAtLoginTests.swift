import AppKit
import ServiceManagement
import Testing
@testable import DaysUntil

@MainActor
final class LoginServiceStub: LaunchAtLoginService {
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
        #expect(login.failedRequest == nil)
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
        #expect(login.failedRequest == nil)
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
        #expect(login.failedRequest == true)
        #expect(login.failureReason == "Registration denied by macOS.")
        login.refresh()
        #expect(login.failedRequest == true)
        service.registerError = nil
        login.retry()
        #expect(service.registerCalls == 2)
        #expect(login.status == .enabled)
        #expect(login.failedRequest == nil)
        #expect(login.failureReason == nil)
    }

    @Test func failedDisableKeepsEnabledStatusAndRetriesDisable() {
        let service = LoginServiceStub()
        service.status = .enabled
        service.unregisterError = NSError(domain: "LoginTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Removal denied by macOS."])
        let login = LaunchAtLogin(service: service)
        login.set(false)
        #expect(login.status == .enabled)
        #expect(login.failedRequest == false)
        #expect(login.failureReason == "Removal denied by macOS.")
        service.unregisterError = nil
        login.retry()
        #expect(service.unregisterCalls == 2)
        #expect(service.registerCalls == 0)
        #expect(login.status == .notRegistered)
        #expect(login.failedRequest == nil)
    }

    @Test func externalApprovalAndRevocationRefreshWithoutRegistration() {
        let service = LoginServiceStub()
        service.status = .requiresApproval
        let login = LaunchAtLogin(service: service)
        service.status = .enabled
        login.refresh()
        #expect(login.status == .enabled)
        service.status = .requiresApproval
        login.refresh()
        #expect(login.status == .requiresApproval)
        #expect(service.registerCalls == 0)
    }

    @Test func externalChangeClearsStaleFailure() {
        let service = LoginServiceStub()
        service.registerError = NSError(domain: "LoginTests", code: 3)
        let login = LaunchAtLogin(service: service)
        login.set(true)
        #expect(login.failedRequest == true)
        service.status = .enabled
        login.refresh()
        #expect(login.failedRequest == nil)
        login.retry()
        #expect(service.registerCalls == 1)
    }

    @Test func missingServiceAndUnconfirmedResultAreNotSuccess() {
        let service = LoginServiceStub()
        service.status = .notFound
        let login = LaunchAtLogin(service: service)
        #expect(login.failedRequest == nil)
        service.registeredStatus = .notRegistered
        login.set(true)
        #expect(login.status == .notRegistered)
        #expect(login.failedRequest == true)
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

    @Test func menuRefreshesCheckmark() throws {
        let service = LoginServiceStub()
        let login = LaunchAtLogin(service: service)
        let defaults = MemoryDefaults()
        let store = CountdownStore(defaults: defaults)
        store.countdown = Countdown(name: "Trip", icon: .default, targetDate: Date().addingTimeInterval(86_400),
                                    showsTime: false, place: nil, startDate: Date())
        let state = PopoverState(store: store, launchAtLogin: login)
        let more = MoreMenu(store: store, state: state)
        for (status, checkmark) in [(SMAppService.Status.enabled, NSControl.StateValue.on), (.requiresApproval, .mixed), (.notRegistered, .off), (.notFound, .off)] {
            service.status = status
            let menu = more.make()
            let item = try #require(menu.items.first { $0.title == "Launch at Login" })
            #expect(item.state == checkmark)
            #expect(!menu.items.contains { $0.title == "Login Items Settings…" })
        }
    }

    @Test func menuOffersSettingsOnlyWhileAChangeHasFailed() {
        let service = LoginServiceStub()
        service.registerError = NSError(domain: "LoginTests", code: 5)
        let login = LaunchAtLogin(service: service)
        let defaults = MemoryDefaults()
        let store = CountdownStore(defaults: defaults)
        let more = MoreMenu(store: store, state: PopoverState(store: store, launchAtLogin: login))
        login.set(true)
        let settings = more.make().items.first { $0.title == "Login Items Settings…" }
        #expect(settings != nil)
        if let settings { NSApp.sendAction(settings.action!, to: settings.target, from: settings) }
        #expect(service.settingsCalls == 1)
        service.registerError = nil
        login.retry()
        #expect(!more.make().items.contains { $0.title == "Login Items Settings…" })
    }

    @Test func firstSaveKeepsCountdownAndExposesLoginFailure() {
        let service = LoginServiceStub()
        service.registerError = NSError(domain: "LoginTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot register this app."])
        let login = LaunchAtLogin(service: service)
        let defaults = MemoryDefaults()
        let store = CountdownStore(defaults: defaults)
        let state = PopoverState(store: store, launchAtLogin: login)
        let countdown = Countdown(name: "Trip", icon: .symbol("airplane"), targetDate: Date().addingTimeInterval(86400), showsTime: false, place: nil, startDate: Date())
        state.draft.openAtLogin = true
        state.save(countdown)
        #expect(store.countdown == countdown)
        #expect(!state.isEditing)
        #expect(login.failedRequest == true)
        #expect(login.failureReason == "Cannot register this app.")
        state.save(countdown)
        #expect(service.registerCalls == 1)
    }
}
