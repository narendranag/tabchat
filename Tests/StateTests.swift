@testable import Tabchat
import XCTest

final class StateTests: XCTestCase {
    private func tempStore() -> StateStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return StateStore(directory: dir)
    }

    func testRoundTrip() throws {
        let store = tempStore()
        XCTAssertNil(try store.load())
        let state = AppState.firstRun()
        try store.save(state)
        XCTAssertEqual(try store.load(), state)
    }

    func testWritesSchemaVersion() throws {
        let data = try StateStore.encode(AppState())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, AppState.currentVersion)
    }

    func testRejectsNewerSchema() throws {
        var state = AppState()
        state.schemaVersion = AppState.currentVersion + 1
        let data = try StateStore.encode(state)
        XCTAssertThrowsError(try StateStore.decode(data)) {
            XCTAssertEqual($0 as? StateStoreError, .unsupportedVersion(AppState.currentVersion + 1))
        }
    }

    func testMicrosoftServicesShareAProfile() throws {
        var state = AppState()
        let teams = try state.addTab(service: XCTUnwrap(ServiceCatalog.service(id: "teams")))
        let outlook = try state.addTab(service: XCTUnwrap(ServiceCatalog.service(id: "outlook-work")))
        let personal = try state.addTab(service: XCTUnwrap(ServiceCatalog.service(id: "outlook-personal")))
        XCTAssertEqual(teams.profileId, outlook.profileId)
        XCTAssertNotEqual(teams.profileId, personal.profileId)
    }

    func testSecondAccountGetsNewProfile() throws {
        var state = AppState()
        let service = try XCTUnwrap(ServiceCatalog.service(id: "whatsapp"))
        let first = state.addTab(service: service)
        let second = state.addTab(service: service, newAccount: true)
        XCTAssertNotEqual(first.profileId, second.profileId)
        XCTAssertEqual(second.displayName, "WhatsApp 2")
        XCTAssertEqual(state.profiles.count, 2)
    }

    func testMoveAndRemove() {
        var state = AppState.firstRun()
        let ids = state.tabs.map(\.id)
        state.moveTab(ids[3], before: ids[0])
        XCTAssertEqual(state.tabs.first?.id, ids[3])
        state.selectedTabId = ids[3]
        state.removeTab(ids[3])
        XCTAssertEqual(state.tabs.count, ids.count - 1)
        XCTAssertNotEqual(state.selectedTabId, ids[3])
    }

    func testURLInput() {
        XCTAssertEqual(URLInput.normalize("example.com")?.absoluteString, "https://example.com")
        XCTAssertNil(URLInput.normalize("not a url"))
        XCTAssertNil(URLInput.normalize("javascript:alert(1)"))
    }
}

final class StateMigrationTests: XCTestCase {
    func testMigratesVersion1File() throws {
        let tabId = UUID()
        let json = """
        {"schemaVersion": 1,
         "profiles": [{"id": "discord-1", "name": "Discord"}],
         "tabs": [{"id": "\(tabId.uuidString)", "serviceId": "discord", "profileId": "discord-1", "colorHex": "2F80ED"}],
         "selectedTabId": "\(tabId.uuidString)"}
        """
        let state = try StateStore.decode(Data(json.utf8))
        XCTAssertEqual(state.schemaVersion, AppState.currentVersion)
        XCTAssertEqual(state.tabs.map(\.id), [tabId])
        XCTAssertEqual(state.selectedTabId, tabId)
        XCTAssertFalse(state.tabs[0].muted)
        XCTAssertEqual(state.settings, AppSettings())
        XCTAssertTrue(state.settings.showDockBadge)
        // The upgraded file saves as the current version and reads back the same.
        XCTAssertEqual(try StateStore.decode(StateStore.encode(state)), state)
    }

    func testRestoreTabPutsItBackInPlace() {
        var state = AppState.firstRun()
        let removed = state.tabs[1]
        state.removeTab(removed.id)
        XCTAssertEqual(state.tabs.count, 3)
        state.restoreTab(removed, at: 1)
        XCTAssertEqual(state.tabs[1], removed)
        XCTAssertEqual(state.selectedTabId, removed.id)
        // Restoring twice does nothing, and an out-of-range index appends.
        state.restoreTab(removed, at: 0)
        XCTAssertEqual(state.tabs.count, 4)
        var other = AppState()
        other.restoreTab(removed, at: 9)
        XCTAssertEqual(other.tabs, [removed])
    }
}
