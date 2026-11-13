import Testing
import UIKit

@testable import MailUI

@MainActor
struct AccessibilitySizesTests {
    private func stack(at category: UIContentSizeCategory) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [UILabel(), UILabel()])
        stack.traitOverrides.preferredContentSizeCategory = category
        stack.stacksVerticallyAtAccessibilitySizes()
        stack.updateTraitsIfNeeded()
        return stack
    }

    @Test func sideBySideAtStandardSizes() {
        let stack = stack(at: .extraExtraExtraLarge)
        #expect(stack.axis == .horizontal)
        #expect(stack.alignment == .firstBaseline)
    }

    @Test func oneUnderTheOtherAtAccessibilitySizes() {
        let stack = stack(at: .accessibilityMedium)
        #expect(stack.axis == .vertical)
        #expect(stack.alignment == .leading)
    }

    @Test func followsTheSettingAsItChanges() {
        let stack = stack(at: .large)
        stack.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        stack.updateTraitsIfNeeded()
        #expect(stack.axis == .vertical)
        stack.traitOverrides.preferredContentSizeCategory = .large
        stack.updateTraitsIfNeeded()
        #expect(stack.axis == .horizontal)
    }
}
