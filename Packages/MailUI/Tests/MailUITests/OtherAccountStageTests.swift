import MailCore
import Testing

@testable import MailUI

struct OtherAccountStageTests {
    private let found = MailServerSettings(
        imap: MailServer(host: "imap.example.com", port: 993, security: .tls),
        smtp: MailServer(host: "smtp.example.com", port: 587, security: .startTLS),
        username: "dana@example.com")
    private let guess = MailServerSettings(
        imap: MailServer(host: "imap.guess.example", port: 993, security: .tls),
        smtp: MailServer(host: "smtp.guess.example", port: 587, security: .startTLS),
        username: "dana")

    @Test func nextLooksTheServersUp() {
        #expect(OtherAccountStage.account(failure: nil).submitted == .discovering)
    }

    @Test func foundServersAreSignedInToBeforeTheyAreShown() {
        let stage = OtherAccountStage.lookedUp(found, guess: guess)
        #expect(stage == .signingIn(found))
        #expect(stage.shownServers == nil)
        #expect(stage.isBusy)
    }

    @Test func withoutFoundServersTheGuessIsShownToCorrect() {
        let stage = OtherAccountStage.lookedUp(nil, guess: guess)
        #expect(stage == .servers(guess, found: false, failure: nil))
        #expect(stage.shownServers == guess)
        #expect(stage.foundNoServers)
    }

    @Test func aPasswordTheFoundServersRefusedIsAskedForAgain() {
        let refused = OtherAccountStage.Failure.signIn(.refused(.incoming))
        #expect(OtherAccountStage.signingIn(found).failed(refused) == .account(failure: refused))
    }

    @Test(arguments: [
        OtherAccountStage.Failure.signIn(.unreachable(.outgoing)), .signIn(.insecure(.incoming)), .other("Offline"),
    ])
    func foundServersThatDontAnswerAreShownToCorrect(failure: OtherAccountStage.Failure) {
        #expect(OtherAccountStage.signingIn(found).failed(failure) == .servers(found, found: true, failure: failure))
    }

    @Test func aFailedCheckKeepsWhetherTheServersWereFound() {
        let refused = OtherAccountStage.Failure.signIn(.refused(.outgoing))
        let stage = OtherAccountStage.checking(guess, found: false).failed(refused)
        #expect(stage == .servers(guess, found: false, failure: refused))
        #expect(stage.foundNoServers)
    }

    @Test func signInChecksTheServersAsEdited() {
        var edited = guess
        edited.imap.host = "mail.example.com"
        let stage = OtherAccountStage.servers(guess, found: false, failure: .other("Offline")).editing(edited)
        #expect(stage == .servers(edited, found: false, failure: .other("Offline")))
        #expect(stage.submitted == .checking(edited, found: false))
    }

    @Test func serversWithAnEmptyFieldCantBeChecked() {
        var missing = guess
        missing.username = ""
        #expect(OtherAccountStage.servers(missing, found: false, failure: nil).submitted == nil)
    }

    @Test func onlyTheServersStageTakesEdits() {
        #expect(OtherAccountStage.checking(found, found: true).editing(guess) == .checking(found, found: true))
    }
}
