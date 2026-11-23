import XCTest
@testable import EntermCore

final class LocalizationTests: XCTestCase {
    override func setUp() {
        Loc.useForTesting([
            "Kapat": "Close",
            "Ekip %@: %@": "Team %@: %@",
            "%@ Kapatılsın mı?": "Close %@?",
            "%@ dosyada %@ değişiklik": "%2$@ changes in %1$@ files",
            "İşlemci En Çok %%%@": "CPU Up To %%%@",
            "%@ %@": "never",
            "Her Gün %02d:%02d": "Daily %02d:%02d",
            "%.1f Saat Sonra": "In %.1f Hr",
        ])
    }

    func testDirect() {
        XCTAssertEqual(L("Kapat"), "Close")
        XCTAssertEqual(L("Bilinmeyen"), "Bilinmeyen")
    }

    func testPatternsCarryTheParts() {
        XCTAssertEqual(L("Ekip Arayüz: claude, codex"), "Team Arayüz: claude, codex")
        XCTAssertEqual(L("couchsubs Kapatılsın mı?"), "Close couchsubs?")
        XCTAssertEqual(L("3 dosyada 12 değişiklik"), "12 changes in 3 files")
        XCTAssertEqual(L("İşlemci En Çok %40"), "CPU Up To %40")
        XCTAssertEqual(L("Her Gün 09:30"), "Daily 09:30")
        XCTAssertEqual(L("2.5 Saat Sonra"), "In 2.5 Hr")
    }

    func testTooGeneralPatternIsIgnored() {
        XCTAssertEqual(L("iki kelime"), "iki kelime")
    }
}
