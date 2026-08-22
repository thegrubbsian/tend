import SwiftData
import Testing
import UserNotifications

@testable import Tend
@testable import TendCore

@MainActor
@Suite("Journal routing model")
struct JournalRoutingModelTests {
  @Test("cold routing starts on Today with Journal overview prepared")
  func coldRoutingDefaultsAreStable() {
    let routing = ShellRoutingModel()

    #expect(routing.selection == .today)
    #expect(routing.journalRoute == .overview)
  }

  @Test("Journal route preparation stores only stable scalar identity")
  func journalRoutePreparationIsIdentitySafeAndIdempotent() throws {
    let routing = ShellRoutingModel(selection: .goals)
    let day = try localDate("2026-03-08")
    let entryID = uuid("a1000000-0000-0000-0000-000000000001")

    routing.prepareJournalRoute(.compose(day))
    #expect(routing.selection == .goals)
    #expect(routing.journalRoute == .compose(day))

    routing.prepareJournalRoute(.entry(entryID))
    routing.prepareJournalRoute(.entry(entryID))
    #expect(routing.selection == .goals)
    #expect(routing.journalRoute == .entry(entryID))

    routing.prepareJournalRoute(.overview)
    #expect(routing.journalRoute == .overview)
  }

  @Test("Today Journal invitation prepares one idempotent compose destination")
  func todayJournalInvitationRoutesOnce() async throws {
    let routing = ShellRoutingModel(selection: .today)
    let day = try localDate("2026-03-08")

    let first = routing.beginJournalRequest(on: day)
    #expect(routing.selection == .today)
    #expect(routing.journalRoute == .compose(day))
    #expect(await routing.completeSelectionRequest(first))
    #expect(routing.selection == .journal)

    let repeated = routing.beginJournalRequest(on: day)
    #expect(await routing.completeSelectionRequest(repeated))
    #expect(routing.selection == .journal)
    #expect(routing.journalRoute == .compose(day))
  }

  @Test("a later tab request supersedes a registered Journal invitation")
  func laterTabRequestWinsOverJournalInvitation() async throws {
    let routing = ShellRoutingModel(selection: .today)
    let day = try localDate("2026-03-08")

    let journal = routing.beginJournalRequest(on: day)
    let goals = routing.beginSelectionRequest(.goals)

    #expect(!(await routing.completeSelectionRequest(journal)))
    #expect(await routing.completeSelectionRequest(goals))
    #expect(routing.selection == .goals)
    #expect(routing.journalRoute == .compose(day))
  }

  @Test("entry routes resolve exact identity and missing identity returns to overview")
  func entryRoutesResolveOrReturnToOverview() throws {
    let context = ModelContext(try TendModelContainer.inMemory())
    let day = try localDate("2026-03-08")
    let entry = JournalEntry(
      id: uuid("a2000000-0000-0000-0000-000000000001"),
      day: day,
      body: "Body",
      createdAt: Date(timeIntervalSince1970: 1),
      editedAt: Date(timeIntervalSince1970: 1)
    )
    context.insert(entry)
    try context.save()
    let query = JournalEntryQuery(context: context)
    let routing = ShellRoutingModel()

    routing.prepareJournalRoute(.entry(entry.id))
    #expect(try routing.resolveJournalEntry(using: query) === entry)
    #expect(routing.journalRoute == .entry(entry.id))

    let missingID = uuid("a2000000-0000-0000-0000-000000000002")
    routing.prepareJournalRoute(.entry(missingID))
    #expect(try routing.resolveJournalEntry(using: query) == nil)
    #expect(routing.journalRoute == .overview)

    routing.prepareJournalRoute(.compose(day))
    #expect(try routing.resolveJournalEntry(using: query) == nil)
    #expect(routing.journalRoute == .compose(day))
  }

  @Test("query corruption remains a failure and preserves route identity")
  func queryCorruptionDoesNotInventRouteRecovery() throws {
    let context = ModelContext(try TendModelContainer.inMemory())
    let day = try localDate("2026-03-08")
    let first = JournalEntry(
      id: uuid("a3000000-0000-0000-0000-000000000001"),
      day: day,
      body: "First",
      createdAt: Date(timeIntervalSince1970: 1),
      editedAt: Date(timeIntervalSince1970: 1)
    )
    let second = JournalEntry(
      id: uuid("a3000000-0000-0000-0000-000000000002"),
      day: day,
      body: "Second",
      createdAt: Date(timeIntervalSince1970: 2),
      editedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(first)
    context.insert(second)
    try context.save()
    let routing = ShellRoutingModel()
    routing.prepareJournalRoute(.entry(first.id))

    #expect(throws: JournalEntryQueryError.self) {
      _ = try routing.resolveJournalEntry(using: JournalEntryQuery(context: context))
    }
    #expect(routing.journalRoute == .entry(first.id))
  }

  @Test("unguarded and repeated destination requests commit deterministically")
  func unguardedDestinationRequestsCommit() async {
    let routing = ShellRoutingModel()

    #expect(await routing.requestSelection(.goals))
    #expect(routing.selection == .goals)
    #expect(await routing.requestSelection(.goals))
    #expect(routing.selection == .goals)
    #expect(await routing.requestSelection(.habits))
    #expect(routing.selection == .habits)
  }

  @Test("a failed navigation guard blocks selection and preserves Journal route")
  func failedGuardBlocksNavigation() async throws {
    let day = try localDate("2026-03-08")
    let routing = ShellRoutingModel(selection: .goals)
    routing.prepareJournalRoute(.compose(day))
    var callCount = 0
    let token = routing.installNavigationGuard {
      callCount += 1
      return false
    }

    #expect(!(await routing.requestSelection(.habits)))
    #expect(routing.selection == .goals)
    #expect(routing.journalRoute == .compose(day))
    #expect(callCount == 1)

    routing.removeNavigationGuard(token)
    #expect(await routing.requestSelection(.habits))
    #expect(routing.selection == .habits)
    #expect(routing.journalRoute == .compose(day))
  }

  @Test("a successful navigation guard commits once and preserves Journal route")
  func successfulGuardCommitsNavigation() async throws {
    let day = try localDate("2026-03-08")
    let routing = ShellRoutingModel(selection: .today)
    routing.prepareJournalRoute(.compose(day))
    var callCount = 0
    _ = routing.installNavigationGuard {
      callCount += 1
      return true
    }

    #expect(await routing.requestSelection(.goals))
    #expect(routing.selection == .goals)
    #expect(routing.journalRoute == .compose(day))
    #expect(callCount == 1)
  }

  @Test("stale guard tokens cannot remove a replacement guard")
  func staleGuardRemovalIsIdentitySafe() async {
    let routing = ShellRoutingModel()
    let first = routing.installNavigationGuard { true }
    var replacementCalls = 0
    _ = routing.installNavigationGuard {
      replacementCalls += 1
      return false
    }

    routing.removeNavigationGuard(first)

    #expect(!(await routing.requestSelection(.goals)))
    #expect(routing.selection == .today)
    #expect(replacementCalls == 1)
  }

  @Test("a replacement guard cancels a suspended request")
  func replacementGuardCannotBeBypassed() async {
    let routing = ShellRoutingModel()
    let probe = NavigationGuardProbe()
    _ = routing.installNavigationGuard { await probe.wait() }
    let request = Task { await routing.requestSelection(.goals) }
    await probe.waitUntilPending()
    var replacementCalls = 0
    _ = routing.installNavigationGuard {
      replacementCalls += 1
      return false
    }

    probe.resume(with: true)

    #expect(!(await request.value))
    #expect(routing.selection == .today)
    #expect(!(await routing.requestSelection(.goals)))
    #expect(replacementCalls == 1)
  }

  @Test("the latest concurrent destination request wins")
  func latestDestinationRequestWins() async {
    let routing = ShellRoutingModel()
    let probe = NavigationGuardProbe()
    _ = routing.installNavigationGuard { await probe.wait() }

    let first = Task { await routing.requestSelection(.goals) }
    await probe.waitUntilPending()
    #expect(await routing.requestSelection(.today))
    probe.resume(with: true)

    #expect(!(await first.value))
    #expect(routing.selection == .today)
  }

  @Test("synchronously registered requests preserve tap order")
  func selectionRequestRegistrationMakesLatestTapWin() async {
    let routing = ShellRoutingModel()
    let first = routing.beginSelectionRequest(.goals)
    let second = routing.beginSelectionRequest(.habits)

    #expect(!(await routing.completeSelectionRequest(first)))
    #expect(await routing.completeSelectionRequest(second))
    #expect(routing.selection == .habits)
  }

  @Test("strict Tend notifications use guarded Today routing")
  func notificationsHonorOwnershipAndNavigationGuard() async {
    let routing = ShellRoutingModel(selection: .habits)
    let delegate = ReminderNotificationDelegate(routing: routing)
    let token = routing.installNavigationGuard { false }

    await delegate.route(ownedReminderRequest())
    #expect(routing.selection == .habits)

    routing.removeNavigationGuard(token)
    await delegate.route(ownedReminderRequest())
    #expect(routing.selection == .today)

    await routing.requestSelection(.habits)
    await delegate.route(foreignReminderRequest())
    #expect(routing.selection == .habits)
  }

  @Test("the shell exposes Journal after Habits")
  func shellDestinationOrderIncludesJournal() {
    #expect(ShellDestination.allCases == [.today, .goals, .habits, .journal])
  }

  private func ownedReminderRequest() -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.categoryIdentifier = ReminderPendingRequest.requiredCategoryIdentifier
    content.userInfo = [ReminderPendingRequest.ownershipKey: true]
    return UNNotificationRequest(
      identifier: "\(ReminderPlanner.identifierPrefix)journal-routing",
      content: content,
      trigger: nil
    )
  }

  private func foreignReminderRequest() -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.categoryIdentifier = ReminderPendingRequest.requiredCategoryIdentifier
    content.userInfo = [ReminderPendingRequest.ownershipKey: true]
    return UNNotificationRequest(
      identifier: "another.app.reminder",
      content: content,
      trigger: nil
    )
  }

  private func localDate(_ value: String) throws -> LocalDate {
    try LocalDate(validating: value)
  }

  private func uuid(_ value: String) -> UUID {
    UUID(uuidString: value)!
  }
}

@MainActor
private final class NavigationGuardProbe {
  private var continuation: CheckedContinuation<Bool, Never>?

  func wait() async -> Bool {
    await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilPending() async {
    while continuation == nil {
      await Task.yield()
    }
  }

  func resume(with result: Bool) {
    continuation?.resume(returning: result)
    continuation = nil
  }
}
