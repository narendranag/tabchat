@testable import Tabchat
import XCTest

final class DuplicateAndIncognitoTests: XCTestCase {
    func testDuplicateKeepsServiceAndProfileAndSitsAfterTheOriginal() throws {
        var state = AppState.firstRun()
        let original = state.tabs[1]
        let copy = try XCTUnwrap(state.duplicateTab(original.id, at: "https://discord.com/channels/1"))
        XCTAssertEqual(state.tabs[2].id, copy.id)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.serviceId, original.serviceId)
        XCTAssertEqual(copy.profileId, original.profileId)
        XCTAssertEqual(copy.lastURL, "https://discord.com/channels/1")
        XCTAssertEqual(state.selectedTabId, copy.id)
        XCTAssertEqual(state.profiles.count, 3)
        XCTAssertNil(state.duplicateTab(UUID()))
    }

    func testIncognitoTabHasNoProfileAndIsNotSaved() throws {
        var state = AppState.firstRun()
        let before = state.profiles
        let tab = try state.addTab(service: XCTUnwrap(ServiceCatalog.service(id: "reddit")), incognito: true)
        XCTAssertTrue(tab.incognito)
        XCTAssertEqual(tab.profileId, AppState.incognitoProfile)
        XCTAssertEqual(state.profiles, before)
        XCTAssertFalse(tab.allowSleep)
        let saved = try StateStore.decode(StateStore.encode(state.persisted()))
        XCTAssertFalse(saved.tabs.contains { $0.id == tab.id })
        XCTAssertEqual(saved.selectedTabId, saved.tabs.first?.id)
    }

    func testEphemeralFlagsAreNeverWritten() throws {
        var tab = AppState.firstRun().tabs[0]
        tab.incognito = true
        tab.temporary = true
        let data = try JSONEncoder().encode(tab)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["incognito"])
        XCTAssertNil(json["temporary"])
    }

    func testSplitWithAnIncognitoTabIsClosedOnSave() {
        var state = AppState.firstRun()
        let first = state.tabs[0].id
        state.selectedTabId = first
        let incognito = state.addTab(service: ServiceCatalog.all[0], incognito: true)
        state.openSplit(with: first)
        XCTAssertEqual(state.split?.contains(incognito.id), true)
        let saved = state.persisted()
        XCTAssertNil(saved.split)
        XCTAssertEqual(saved.selectedTabId, first)
    }

    func testTemporaryTabSharesTheProfileAndSitsAfterItsSource() throws {
        var state = AppState.firstRun()
        let source = state.tabs[1]
        let url = try XCTUnwrap(URL(string: "https://example.com/page"))
        let tab = state.addTemporaryTab(url: url, after: source)
        XCTAssertEqual(state.tabs[2].id, tab.id)
        XCTAssertEqual(tab.profileId, source.profileId)
        XCTAssertEqual(tab.startURL, url)
        XCTAssertTrue(tab.temporary)
        XCTAssertEqual(tab.displayName, "example.com")
        XCTAssertFalse(state.persisted().tabs.contains { $0.id == tab.id })
    }
}

final class SchemaV3Tests: XCTestCase {
    func testMigratesVersion2File() throws {
        let chat = UUID()
        let other = UUID()
        let json = """
        {"schemaVersion": 2,
         "profiles": [{"id": "whatsapp-1", "name": "WhatsApp"}, {"id": "reddit", "name": "Reddit"}],
         "tabs": [
           {"id": "\(chat.uuidString)", "serviceId": "whatsapp", "profileId": "whatsapp-1", "colorHex": "2F80ED", "muted": true},
           {"id": "\(other.uuidString)", "serviceId": "reddit", "profileId": "reddit", "colorHex": "27AE60"}],
         "selectedTabId": "\(chat.uuidString)",
         "settings": {"startHidden": true, "showDockBadge": false, "pause": {}}}
        """
        let state = try StateStore.decode(Data(json.utf8))
        XCTAssertEqual(state.schemaVersion, 3)
        XCTAssertEqual(AppState.currentVersion, 3)
        XCTAssertEqual(state.tabs.map(\.allowSleep), [false, true])
        XCTAssertTrue(state.tabs[0].muted)
        XCTAssertNil(state.tabs[0].lastURL)
        XCTAssertNil(state.split)
        XCTAssertTrue(state.settings.startHidden)
        XCTAssertFalse(state.settings.showDockBadge)
        XCTAssertEqual(state.settings.sleepAfterMinutes, 30)
        XCTAssertEqual(state.settings.linkTarget, .defaultBrowser)
        XCTAssertEqual(state.settings.splitRatio, 0.5)
        XCTAssertEqual(state.settings.hiddenServices, [])
        XCTAssertEqual(state.settings.serviceOrder, [])
        XCTAssertEqual(try StateStore.decode(StateStore.encode(state)), state)
    }

    func testNewSettingsRoundTrip() throws {
        var state = AppState.firstRun()
        state.settings.sleepAfterMinutes = 0
        state.settings.linkTarget = .browser("com.apple.Safari")
        state.settings.hiddenServices = ["x"]
        state.settings.serviceOrder = ["reddit", "x"]
        state.tabs[0].lastURL = "https://web.whatsapp.com/x"
        state.tabs[0].allowSleep = true
        XCTAssertEqual(try StateStore.decode(StateStore.encode(state)), state)
    }
}

final class CatalogLayoutTests: XCTestCase {
    private let all = ServiceCatalog.all

    func testDefaultOrderIsTheCatalogOrder() {
        XCTAssertEqual(CatalogLayout.ordered(all, order: []).map(\.id), all.map(\.id))
    }

    func testListedIdsComeFirstAndUnknownOnesAreIgnored() {
        let order = CatalogLayout.ordered(all, order: ["x", "gone", "reddit"]).map(\.id)
        XCTAssertEqual(Array(order.prefix(2)), ["x", "reddit"])
        XCTAssertEqual(order.count, all.count)
        // The rest keep catalog order.
        XCTAssertEqual(Array(order.dropFirst(2)), all.map(\.id).filter { !["x", "reddit"].contains($0) })
    }

    func testHiddenCardsShowOnlyWhileEditing() {
        let hidden = ["teams", "x"]
        XCTAssertFalse(CatalogLayout.visible(all, order: [], hidden: hidden, editing: false).contains { hidden.contains($0.id) })
        XCTAssertEqual(CatalogLayout.visible(all, order: [], hidden: hidden, editing: true).count, all.count)
    }

    func testMoveBeforeTarget() {
        let order = CatalogLayout.moved("x", before: "whatsapp", services: all, order: [])
        XCTAssertEqual(order.first, "x")
        XCTAssertEqual(order.count, all.count)
        XCTAssertEqual(CatalogLayout.moved("x", before: "x", services: all, order: []), all.map(\.id))
        XCTAssertEqual(CatalogLayout.moved("nope", before: "x", services: all, order: []), all.map(\.id))
    }

    func testToggleHidden() {
        XCTAssertEqual(CatalogLayout.toggled("x", in: []), ["x"])
        XCTAssertEqual(CatalogLayout.toggled("x", in: ["x", "reddit"]), ["reddit"])
    }
}
