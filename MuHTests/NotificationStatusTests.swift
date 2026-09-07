import XCTest
@testable import MuH

final class NotificationStatusTests: XCTestCase {
    func testNewBlockedAgentTakesPriority() {
        XCTAssertEqual(
            notificationKind(
                oldTitle: "dev: ◐○",
                newTitle: "dev: ×◐○",
                notifyOnBlocked: true,
                notifyOnCompleted: true
            ),
            .blocked
        )
    }

    func testFinishedWorkingAgentsNotifyWhenAllDone() {
        XCTAssertEqual(
            notificationKind(
                oldTitle: "dev: ◐◐",
                newTitle: "dev: ✓✓",
                notifyOnBlocked: true,
                notifyOnCompleted: true
            ),
            .completed
        )
    }

    func testWorkingToIdleTransitionNotifiesCompletion() {
        XCTAssertEqual(
            notificationKind(
                oldTitle: "dev: ◐",
                newTitle: "dev: idle",
                notifyOnBlocked: true,
                notifyOnCompleted: true
            ),
            .completed
        )
        XCTAssertEqual(
            notificationKind(
                oldTitle: "dev: ◐",
                newTitle: "dev: ○",
                notifyOnBlocked: true,
                notifyOnCompleted: true
            ),
            .completed
        )
    }

    func testWorkingToBlockedTransitionNotifiesBlocked() {
        XCTAssertEqual(
            notificationKind(
                oldTitle: "dev: ◐",
                newTitle: "dev: ×",
                notifyOnBlocked: true,
                notifyOnCompleted: true
            ),
            .blocked
        )
    }

    func testStillWorkingDoesNotNotifyCompletion() {
        XCTAssertNil(
            notificationKind(
                oldTitle: "dev: ◐◐",
                newTitle: "dev: ◐",
                notifyOnBlocked: true,
                notifyOnCompleted: true
            )
        )
    }

    func testNoNotificationForUnchangedStatus() {
        XCTAssertNil(
            notificationKind(
                oldTitle: "dev: ✓◐",
                newTitle: "dev: ✓◐",
                notifyOnBlocked: true,
                notifyOnCompleted: true
            )
        )
    }

    func testDisabledNotificationKindsReturnNil() {
        XCTAssertNil(
            notificationKind(
                oldTitle: "dev: ◐",
                newTitle: "dev: ×✓",
                notifyOnBlocked: false,
                notifyOnCompleted: false
            )
        )
    }

    func testInitialAgentStatusTitleIsDetectedAsBaseline() {
        XCTAssertTrue(isAgentStatusTitle("dev: ×✓◐"))
        XCTAssertTrue(isAgentStatusTitle("dev: idle"))
        XCTAssertFalse(isAgentStatusTitle("bash"))
    }

    func testInitialAgentStatusIsSuppressedOncePerSession() {
        let store = HostTitleStore()
        let hostId = UUID()

        XCTAssertFalse(store.shouldSuppressInitialStatus(hostId: hostId, title: "bash"))
        XCTAssertTrue(store.shouldSuppressInitialStatus(hostId: hostId, title: "dev: ×"))
        XCTAssertFalse(store.shouldSuppressInitialStatus(hostId: hostId, title: "dev: ×"))
    }

    func testPendingNotificationHostSurvivesUntilConsumed() {
        let navigation = NotificationNavigationState()
        let firstHostId = UUID()
        let secondHostId = UUID()

        navigation.requestHostSelection(firstHostId)
        XCTAssertEqual(navigation.pendingHostId, firstHostId)

        navigation.consumeHostSelection(secondHostId)
        XCTAssertEqual(navigation.pendingHostId, firstHostId)

        navigation.consumeHostSelection(firstHostId)
        XCTAssertNil(navigation.pendingHostId)
    }
}
