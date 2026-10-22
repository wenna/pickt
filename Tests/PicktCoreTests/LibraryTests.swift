import XCTest
@testable import PicktCore

final class LibraryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_656_000)
    func question(_ subject: String = "数学") -> Question {
        Question(subject: subject, grade: "六年级", topics: ["分数"], causes: ["计算出错"], text: "1/2 + 1/2", answer: "1")
    }
    func library() -> StudyLibrary {
        var value = StudyLibrary(); value.questions = [question(), question("英语")]; return value
    }
    func skippedLibrary() throws -> StudyLibrary {
        var value = library()
        let paperID = try LibraryCommands.createPaper(in: &value, questionIDs: [value.questions[0].id], now: now)
        try LibraryCommands.beginGrading(in: &value, paperID: paperID, layoutID: value.papers[0].layouts[0].id, photoAssets: [], now: now)
        var draft = try XCTUnwrap(value.papers[0].draft)
        draft.items[0].verdict = .skip; draft.items[0].reviewed = true
        try LibraryCommands.saveDraft(in: &value, paperID: paperID, draft: draft)
        try LibraryCommands.confirmGrading(in: &value, paperID: paperID, attemptID: draft.id, now: now)
        return value
    }
    func testEmptyLibraryHasNoSamples() { XCTAssertTrue(StudyLibrary().questions.isEmpty); XCTAssertEqual(StudyLibrary().nextPaperSerial, 1) }
    func testIndependentSequenceAndCrossSubjectNames() throws {
        var value = library()
        _ = try LibraryCommands.createPaper(in: &value, questionIDs: [value.questions[0].id], now: now)
        _ = try LibraryCommands.createPaper(in: &value, questionIDs: [value.questions[1].id], now: now)
        XCTAssertEqual(value.papers.map(\.title), ["我的数学巩固练习1", "我的英语巩固练习2"])
        XCTAssertEqual(value.nextPaperSerial, 3)
    }
    func testEmptyAndMissingSelectionDoNotConsumeSequence() {
        var value = library()
        XCTAssertThrowsError(try LibraryCommands.createPaper(in: &value, questionIDs: [], now: now))
        XCTAssertThrowsError(try LibraryCommands.createPaper(in: &value, questionIDs: [UUID()], now: now))
        XCTAssertEqual(value.nextPaperSerial, 1); XCTAssertTrue(value.papers.isEmpty)
    }
    func testQuestionSnapshotDoesNotChangeWithBankEdits() throws {
        var value = library(); _ = try LibraryCommands.createPaper(in: &value, questionIDs: [value.questions[0].id], now: now)
        value.questions[0].answer = "changed"; value.questions[0].topics = ["changed"]
        XCTAssertEqual(value.papers[0].questions[0].answer, "1"); XCTAssertEqual(value.papers[0].questions[0].topics, ["分数"])
    }
    func testUnattemptedCorrectWrongQuestionsCannotDelete() throws {
        var value = try skippedLibrary(); let id = value.questions[0].id
        XCTAssertNil(value.questionDeletionReason(id))
        for verdict in [Verdict.correct, .wrong] {
            value.questions[0].history[0].verdict = verdict
            XCTAssertThrowsError(try LibraryCommands.deleteQuestions(in: &value, ids: [id], now: now))
            XCTAssertNil(value.questions[0].deletedAt)
        }
        value.questions[0].history = []
        XCTAssertThrowsError(try LibraryCommands.deleteQuestions(in: &value, ids: [id], now: now))
    }
    func testMixedQuestionBatchIsAllOrNothing() throws {
        var value = try skippedLibrary()
        XCTAssertThrowsError(try LibraryCommands.deleteQuestions(in: &value, ids: value.questions.map(\.id), now: now))
        XCTAssertTrue(value.questions.allSatisfy { $0.deletedAt == nil })
    }
    func testSkipDoesNotCountAsPracticeAndCanRestore() throws {
        var value = try skippedLibrary(); let id = value.questions[0].id
        try LibraryCommands.deleteQuestions(in: &value, ids: [id], now: now)
        XCTAssertNotNil(value.questions[0].deletedAt)
        LibraryCommands.restoreQuestion(in: &value, id: id)
        XCTAssertEqual(value.questions[0].history.count, 1); XCTAssertEqual(value.questions[0].practiceCount, 0)
        XCTAssertEqual(value.papers[0].stage, .recorded)
    }
    func testNewPendingDraftBlocksQuestionAndPaperDeletion() throws {
        var value = try skippedLibrary(); let qID = value.questions[0].id
        let pID = try LibraryCommands.createPaper(in: &value, questionIDs: [qID], now: now)
        XCTAssertNil(value.paperDeletionReason(pID))
        try LibraryCommands.beginGrading(in: &value, paperID: pID, layoutID: value.papers[1].layouts[0].id, photoAssets: [], now: now)
        XCTAssertNotNil(value.questionDeletionReason(qID)); XCTAssertEqual(value.papers[1].stage, .pending)
        XCTAssertThrowsError(try LibraryCommands.deletePapers(in: &value, ids: [pID], now: now))
    }
    func testMixedPaperBatchAndMissingItemAreAtomic() throws {
        var value = try skippedLibrary()
        let todoID = try LibraryCommands.createPaper(in: &value, questionIDs: [value.questions[1].id], now: now)
        XCTAssertThrowsError(try LibraryCommands.deletePapers(in: &value, ids: value.papers.map(\.id), now: now))
        XCTAssertThrowsError(try LibraryCommands.deletePapers(in: &value, ids: [todoID, UUID()], now: now))
        XCTAssertTrue(value.papers.allSatisfy { $0.deletedAt == nil })
        try LibraryCommands.deletePapers(in: &value, ids: [todoID], now: now)
        LibraryCommands.restorePaper(in: &value, id: todoID)
        XCTAssertEqual(value.papers.last?.stage, .todo); XCTAssertEqual(value.nextPaperSerial, 3)
    }
    func testConfirmationIsIdempotent() throws {
        var value = try skippedLibrary(); let pID = value.papers[0].id, aID = value.papers[0].attempts[0].id
        try LibraryCommands.confirmGrading(in: &value, paperID: pID, attemptID: aID, now: now)
        XCTAssertEqual(value.papers[0].attempts.count, 1); XCTAssertEqual(value.questions[0].history.count, 1)
    }
    func testUnresolvedDraftCannotCommit() throws {
        var value = library(); let id = try LibraryCommands.createPaper(in: &value, questionIDs: [value.questions[0].id], now: now)
        try LibraryCommands.beginGrading(in: &value, paperID: id, layoutID: value.papers[0].layouts[0].id, photoAssets: [], now: now)
        XCTAssertThrowsError(try LibraryCommands.confirmGrading(in: &value, paperID: id, attemptID: value.papers[0].draft!.id, now: now))
        XCTAssertTrue(value.questions[0].history.isEmpty); XCTAssertNotNil(value.papers[0].draft)
    }
    func testLatestResultUsesDateThenSequence() throws {
        var value = try skippedLibrary(); var old = value.questions[0].history[0]
        old.confirmedAt = now.addingTimeInterval(-1); old.sequence = 100; old.verdict = .wrong
        value.questions[0].history.append(old)
        XCTAssertEqual(value.questions[0].latestResult?.verdict, .skip)
    }
    func testFiltersUseORWithinAndAcrossDimensions() {
        var value = library(); value.questions[0].topics = ["分数", "应用题"]
        var filter = QuestionFilter(); filter.subject = "数学"; filter.topics = ["分数", "百分数"]; filter.causes = ["计算出错"]
        XCTAssertEqual(value.filteredQuestions(filter).map(\.id), [value.questions[0].id])
        filter.causes = ["题意没看清"]; XCTAssertTrue(value.filteredQuestions(filter).isEmpty)
    }
    func testInvertedDateFilterIsRejected() {
        var filter = QuestionFilter(); filter.from = now; filter.to = now.addingTimeInterval(-1)
        XCTAssertThrowsError(try filter.validate())
    }
    func testNumericComparisonAndUnsupportedInput() {
        XCTAssertEqual(AnswerComparison.compare("0.5", reference: "1/2"), .matches)
        XCTAssertEqual(AnswerComparison.compare("3/4", reference: "1/2"), .differs)
        XCTAssertEqual(AnswerComparison.compare("证明过程", reference: "略"), .needsReview)
        XCTAssertEqual(AnswerComparison.compare("", reference: "1"), .needsReview)
        XCTAssertEqual(AnswerComparison.compare("1", reference: ""), .needsReview)
    }
    func testUnsafeResourceNamesRejected() {
        XCTAssertFalse(AssetName.isValid("../secret.jpg")); XCTAssertFalse(AssetName.isValid("C:/a.jpg"))
        XCTAssertFalse(AssetName.isValid("folder/a.jpg")); XCTAssertTrue(AssetName.isValid(UUID().uuidString + ".jpg"))
    }
}
