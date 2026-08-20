import XCTest
@testable import MuH

final class HostStoreTests: XCTestCase {
    private var persistenceKey = "muh.tests.hosts.\(UUID().uuidString)"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        super.tearDown()
    }

    func testNewHostDefaultsToStandardShell() {
        let store = HostStore(persistenceKey: persistenceKey)

        let host = store.createHost(name: "dev")

        XCTAssertNil(host.defaultCommand)
        XCTAssertEqual(store.selectedId, host.id)
    }

    func testExplicitCommandSurvivesReload() {
        let store = HostStore(persistenceKey: persistenceKey)
        let host = store.createHost(name: "dev", defaultCommand: "ssh dev")
        store.updateDefaultCommand(hostId: host.id, command: "ssh dev2")

        let reloaded = HostStore(persistenceKey: persistenceKey)

        XCTAssertEqual(reloaded.hosts.first(where: { $0.id == host.id })?.defaultCommand, "ssh dev2")
    }

    func testDeletingSelectedHostSelectsNextHost() {
        let store = HostStore(persistenceKey: persistenceKey)
        let first = store.hosts[0]
        let second = store.createHost(name: "dev")

        store.deleteHost(id: second.id)

        XCTAssertEqual(store.selectedId, first.id)
        XCTAssertFalse(store.hosts.contains(where: { $0.id == second.id }))
    }
}
