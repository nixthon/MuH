import XCTest
@testable import MuH

final class HostStoreTests: XCTestCase {
    private var persistenceKey = "muh.tests.hosts.\(UUID().uuidString)"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        UserDefaults.standard.removeObject(forKey: persistenceKey + ".corrupt")
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

    func testNewHostIsPersistedImmediately() {
        let store = HostStore(persistenceKey: persistenceKey)
        let host = store.createHost(name: "dev")

        // createHost 必须同步落盘（历史实现带 0.2s 防抖，退出/重启会丢新增 host）
        let reloaded = HostStore(persistenceKey: persistenceKey)

        XCTAssertTrue(reloaded.hosts.contains(where: { $0.id == host.id }))
    }

    func testCorruptPayloadIsBackedUpInsteadOfDiscarded() {
        let corrupt = Data("{not valid json".utf8)
        UserDefaults.standard.set(corrupt, forKey: persistenceKey)

        let store = HostStore(persistenceKey: persistenceKey)

        XCTAssertEqual(store.hosts.count, 1)
        XCTAssertEqual(UserDefaults.standard.data(forKey: persistenceKey + ".corrupt"), corrupt)
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
