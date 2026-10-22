import Foundation

public enum Verdict: String, Codable, CaseIterable, Identifiable {
    case correct, wrong, skip
    public var id: String { rawValue }
    public var title: String { self == .correct ? "做对了" : self == .wrong ? "再练练" : "暂未做" }
}
public enum PaperStage: String, CaseIterable { case todo, pending, recorded
    public var title: String { self == .todo ? "待完成" : self == .pending ? "待核对" : "已记录" }
}
public struct NormalizedRect: Codable, Equatable {
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1) { self.x=x;self.y=y;self.width=width;self.height=height }
}
public struct QuestionFragment: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var asset: String
    public var originalAsset: String
    public var crop: NormalizedRect
    public init(asset: String, originalAsset: String, crop: NormalizedRect = .init()) { self.asset=asset;self.originalAsset=originalAsset;self.crop=crop }
}
public struct ResultEvent: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var paperID: UUID; public var attemptID: UUID
    public var verdict: Verdict; public var confirmedAt: Date; public var sequence: Int64
    public var recognized: String
}
public struct Question: Codable, Identifiable, Equatable {
    public var id: UUID
    public var subject: String; public var grade: String
    public var topics: [String]; public var causes: [String]
    public var text: String; public var answer: String; public var explanation: String
    public var fragments: [QuestionFragment]
    public var sourceID: UUID?
    public var classificationSource: String
    public var createdAt: Date; public var mastered: Bool; public var deletedAt: Date?
    public var history: [ResultEvent]
    public init(id: UUID = UUID(), subject: String = "数学", grade: String = "六年级", topics: [String] = [], causes: [String] = [], text: String = "", answer: String = "", explanation: String = "", fragments: [QuestionFragment] = [], sourceID: UUID? = nil, classificationSource: String = "用户设置", createdAt: Date = Date()) {
        self.id=id;self.subject=subject;self.grade=grade;self.topics=topics;self.causes=causes;self.text=text;self.answer=answer;self.explanation=explanation;self.fragments=fragments;self.sourceID=sourceID;self.classificationSource=classificationSource;self.createdAt=createdAt;self.mastered=false;self.history=[]
    }
    public var latestResult: ResultEvent? { history.max { $0.confirmedAt == $1.confirmedAt ? $0.sequence < $1.sequence : $0.confirmedAt < $1.confirmedAt } }
    public var practiceCount: Int { history.filter { $0.verdict != .skip }.count }
}
public struct SourceDocument: Codable, Identifiable, Equatable {
    public var id = UUID(); public var title: String; public var pages: [String]; public var createdAt = Date()
    public init(title: String, pages: [String]) { self.title=title;self.pages=pages }
}
public enum AnswerSpace: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    public var id: String { rawValue }
    public var title: String { self == .small ? "少一些" : self == .medium ? "适中" : "多一些" }
    public var points: Double { self == .small ? 65 : self == .medium ? 120 : 190 }
}
public struct PaperLayout: Codable, Identifiable, Equatable {
    public var id = UUID(); public var revision: Int; public var space: AnswerSpace
    public var questionOrder: [UUID]; public var createdAt = Date()
    public init(revision: Int = 1, space: AnswerSpace = .medium, questionOrder: [UUID]) { self.revision=revision;self.space=space;self.questionOrder=questionOrder }
}
public struct GradingItem: Codable, Identifiable, Equatable {
    public var questionID: UUID; public var recognized = ""; public var verdict: Verdict?; public var reviewed = false
    public var note = "请核对作答与参考答案"
    public var id: UUID { questionID }
    public init(questionID: UUID) { self.questionID=questionID }
}
public struct GradingDraft: Codable, Identifiable, Equatable {
    public var id = UUID(); public var layoutID: UUID; public var items: [GradingItem]
    public var photoAssets: [String]; public var createdAt: Date
    public init(layoutID: UUID, items: [GradingItem], photoAssets: [String], createdAt: Date) { self.layoutID=layoutID;self.items=items;self.photoAssets=photoAssets;self.createdAt=createdAt }
}
public struct GradingAttempt: Codable, Identifiable, Equatable {
    public var id: UUID; public var layoutID: UUID; public var items: [GradingItem]
    public var photoAssets: [String]; public var confirmedAt: Date
}
public struct Paper: Codable, Identifiable, Equatable {
    public var id = UUID(); public var serial: Int; public var title: String; public var createdAt: Date
    public var questions: [Question]; public var layouts: [PaperLayout]
    public var attempts: [GradingAttempt] = []; public var draft: GradingDraft?; public var deletedAt: Date?
    public init(serial: Int, title: String, questions: [Question], createdAt: Date) { self.serial=serial;self.title=title;self.questions=questions;self.createdAt=createdAt;self.layouts=[PaperLayout(questionOrder: questions.map(\.id))] }
    public var stage: PaperStage { draft != nil ? .pending : attempts.isEmpty ? .todo : .recorded }
}
public struct StudyLibrary: Codable, Equatable {
    public var schemaVersion = 1
    public var questions: [Question] = []; public var papers: [Paper] = []; public var sources: [SourceDocument] = []
    public var topicCatalog = ["分数运算", "百分数", "比和比例", "圆", "面积与体积", "方程", "应用题", "统计"]
    public var causeCatalog = ["计算出错", "题意没看清", "方法不会", "知识点不熟", "其他"]
    public var nextPaperSerial = 1; public var nextEventSequence: Int64 = 1
    public init() {}
    public var activeQuestions: [Question] { questions.filter { $0.deletedAt == nil } }
    public var activePapers: [Paper] { papers.filter { $0.deletedAt == nil } }
    public func pendingPaper(for questionID: UUID) -> Paper? { activePapers.first { $0.draft?.items.contains(where: { $0.questionID == questionID }) == true } }
    public func questionDeletionReason(_ id: UUID) -> String? {
        guard let q=activeQuestions.first(where:{$0.id==id}) else { return "题目不存在或已删除" }
        if pendingPaper(for:id) != nil { return "有批改待核对，暂不可删除" }
        guard let result=q.latestResult else { return "尚未重做，暂不可删除" }
        return result.verdict == .skip ? nil : "最近结果为\(result.verdict.title)，暂不可删除"
    }
    public func paperDeletionReason(_ id: UUID) -> String? {
        guard let p=activePapers.first(where:{$0.id==id}) else { return "练习卷不存在或已删除" }
        return p.stage == .todo ? nil : "\(p.stage.title)的练习卷不可删除"
    }
    public var referencedAssets: Set<String> {
        var names=Set(sources.flatMap(\.pages))
        for q in questions + papers.flatMap(\.questions) { for f in q.fragments { names.formUnion([f.asset,f.originalAsset]) } }
        for p in papers { names.formUnion(p.draft?.photoAssets ?? []);p.attempts.forEach { names.formUnion($0.photoAssets) } }
        return names
    }
}
public struct LibraryError: LocalizedError { public let message: String; public init(_ message: String) { self.message=message }; public var errorDescription: String? { message } }
