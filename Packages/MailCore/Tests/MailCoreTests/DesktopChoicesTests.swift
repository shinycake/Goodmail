import MailCore
import Testing

struct DesktopChoicesTests {
    @Test func deleteMovesToTrashByDefault() {
        #expect(DeleteKeyAction.standard == .trash)
        #expect(DeleteKeyAction.trash.action(in: .inbox) == .trash)
    }

    @Test func deleteCanArchiveInstead() {
        #expect(DeleteKeyAction.archive.action(in: .inbox) == .archive)
    }

    @Test(arguments: DeleteKeyAction.allCases)
    func deleteInTrashIsForGood(_ choice: DeleteKeyAction) {
        #expect(choice.action(in: .trash) == .deleteForever)
    }

    @Test(arguments: DeleteKeyAction.allCases)
    func deleteInSpamTrashes(_ choice: DeleteKeyAction) {
        #expect(choice.action(in: .spam) == .trash, "archiving spam would change nothing")
    }

    @Test func storedNamesAreStable() {
        #expect(DeleteKeyAction(rawValue: "trash") == .trash)
        #expect(DeleteKeyAction(rawValue: "archive") == .archive)
    }

    @Test(arguments: [
        (LoginItemStatus.notRegistered, OpenAtLogin.off), (.enabled, .on), (.requiresApproval, .needsApproval),
        (.notFound, .unavailable),
    ])
    func theSystemStatusSetsTheState(_ status: LoginItemStatus, _ state: OpenAtLogin) {
        #expect(OpenAtLogin(status) == state)
    }

    @Test func approvalPendingShowsOnSoItCanBeTurnedOff() {
        #expect(OpenAtLogin.needsApproval.isOn)
        #expect(OpenAtLogin.needsApproval.change(toggling: false) == .unregister)
        #expect(OpenAtLogin.needsApproval.change(toggling: true) == nil)
    }

    @Test func turningOnAndOffAsksTheSystem() {
        #expect(OpenAtLogin.off.change(toggling: true) == .register)
        #expect(OpenAtLogin.on.change(toggling: false) == .unregister)
        #expect(OpenAtLogin.off.change(toggling: false) == nil)
        #expect(OpenAtLogin.on.change(toggling: true) == nil)
    }

    @Test func aFailedChangeCanBeTriedAgain() {
        let failed = OpenAtLogin.failed(message: "no")
        #expect(!failed.isOn)
        #expect(failed.change(toggling: true) == .register)
    }

    @Test func anUnavailableLoginItemCannotChange() {
        #expect(OpenAtLogin.unavailable.change(toggling: true) == nil)
        #expect(OpenAtLogin.unavailable.change(toggling: false) == nil)
    }
}
