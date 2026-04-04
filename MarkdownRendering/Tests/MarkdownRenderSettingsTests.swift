import XCTest
@testable import MarkdownRendering

final class MarkdownRenderSettingsTests: XCTestCase {
    func testDefaultSettingsUseMediumSizeAndSystemFont() {
        let settings = MarkdownRenderSettings.default
        XCTAssertEqual(settings.textSizeLevel, .medium)
        XCTAssertEqual(settings.fontFamily, .system)
    }

    func testMediumScaleFactorIsOne() {
        XCTAssertEqual(TextSizeLevel.medium.scaleFactor, 1.0)
    }

    func testExtraSmallScaleFactorIsPointEight() {
        XCTAssertEqual(TextSizeLevel.extraSmall.scaleFactor, 0.80)
    }

    func testExtraExtraExtraLargeScaleFactorIsOnePointFiveFive() {
        XCTAssertEqual(TextSizeLevel.extraExtraExtraLarge.scaleFactor, 1.55)
    }

    func testTextSizeLevelHasSevenCases() {
        XCTAssertEqual(TextSizeLevel.allCases.count, 7)
    }

    func testScaleFactorsIncreaseMonotonically() {
        let factors = TextSizeLevel.allCases.map(\.scaleFactor)
        for i in 1..<factors.count {
            XCTAssertGreaterThan(factors[i], factors[i - 1])
        }
    }

    func testFontFamilyHasThreeCases() {
        XCTAssertEqual(FontFamily.allCases.count, 3)
    }

    func testSettingsRoundTripsThroughCodable() throws {
        let original = MarkdownRenderSettings(
            textSizeLevel: .extraLarge,
            fontFamily: .serif
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MarkdownRenderSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testFontFamilySystemReturnsSystemFont() {
        let font = FontFamily.system.font(ofSize: 15, weight: .regular)
        XCTAssertEqual(font.pointSize, 15)
        XCTAssertFalse(font.isFixedPitch)
    }

    func testFontFamilyMonospacedReturnsFixedPitchFont() {
        let font = FontFamily.monospaced.font(ofSize: 15, weight: .regular)
        XCTAssertEqual(font.pointSize, 15)
        XCTAssertTrue(font.isFixedPitch)
    }

    func testFontFamilySerifReturnsFontWithSerifDesign() {
        let font = FontFamily.serif.font(ofSize: 15, weight: .regular)
        XCTAssertEqual(font.pointSize, 15)
        XCTAssertFalse(font.isFixedPitch)
        // Serif font should differ from system font
        let systemFont = FontFamily.system.font(ofSize: 15, weight: .regular)
        XCTAssertNotEqual(font.fontName, systemFont.fontName)
    }

    func testFontFamilyPreservesWeight() {
        let bold = FontFamily.system.font(ofSize: 15, weight: .semibold)
        XCTAssertTrue(bold.fontDescriptor.symbolicTraits.contains(.bold))
    }
}

final class MarkdownSettingsStoreTests: XCTestCase {
    private let testSuiteName = "com.test.MarkdownSettingsStoreTests.\(UUID().uuidString)"

    override func tearDown() {
        if let defaults = UserDefaults(suiteName: testSuiteName) {
            defaults.removePersistentDomain(forName: testSuiteName)
        }
        super.tearDown()
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: testSuiteName)!
    }

    func testDefaultSettingsWhenNothingStored() {
        let store = MarkdownSettingsStore(defaults: makeDefaults())
        XCTAssertEqual(store.settings, .default)
    }

    func testSettingsPersistAcrossInstances() {
        let defaults = makeDefaults()
        let store1 = MarkdownSettingsStore(defaults: defaults)
        store1.settings = MarkdownRenderSettings(textSizeLevel: .large, fontFamily: .serif)

        let store2 = MarkdownSettingsStore(defaults: defaults)
        XCTAssertEqual(store2.settings.textSizeLevel, .large)
        XCTAssertEqual(store2.settings.fontFamily, .serif)
    }

    func testCorruptedDataFallsBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(Data([0xFF, 0xFE]), forKey: "renderSettings")

        let store = MarkdownSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings, .default)
    }
}
