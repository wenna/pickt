import Foundation

public struct QuestionFilter {
    public var subject=""; public var grade=""; public var search=""
    public var topics: Set<String>=[]; public var causes: Set<String>=[]
    public var from: Date?; public var to: Date?; public var includeMastered=true
    public var result: Verdict?; public var pendingOnly=false
    public init() {}
    public func validate() throws { if let from=from,let to=to,from>to { throw LibraryError("开始日期不能晚于结束日期") } }
}
extension StudyLibrary {
    public func filteredQuestions(_ filter: QuestionFilter) -> [Question] {
        activeQuestions.filter { q in
            (filter.subject.isEmpty || q.subject==filter.subject) && (filter.grade.isEmpty || q.grade==filter.grade) &&
            (filter.includeMastered || !q.mastered) && (filter.topics.isEmpty || !filter.topics.isDisjoint(with:q.topics)) &&
            (filter.causes.isEmpty || !filter.causes.isDisjoint(with:q.causes)) &&
            (filter.from.map{q.createdAt >= $0} ?? true) && (filter.to.map{q.createdAt < Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:$0))!} ?? true) &&
            (filter.result.map{q.latestResult?.verdict == $0} ?? true) && (!filter.pendingOnly || pendingPaper(for:q.id) != nil) &&
            (filter.search.isEmpty || ([q.text,q.subject,q.grade]+q.topics+q.causes).joined(separator:" ").localizedCaseInsensitiveContains(filter.search))
        }.sorted{$0.createdAt>$1.createdAt}
    }
}
public enum AssetName {
    public static func isValid(_ name: String) -> Bool {
        let parts=name.split(separator:".",omittingEmptySubsequences:false)
        return parts.count==2 && UUID(uuidString:String(parts[0])) != nil && ["jpg","png"].contains(String(parts[1]))
    }
}
public enum AnswerComparison: Equatable {
    case matches,differs,needsReview
    public static func compare(_ answer: String, reference: String) -> AnswerComparison {
        let a=answer.trimmingCharacters(in:.whitespacesAndNewlines),b=reference.trimmingCharacters(in:.whitespacesAndNewlines)
        if ["A","B","C","D"].contains(a.uppercased()),["A","B","C","D"].contains(b.uppercased()) { return a.uppercased()==b.uppercased() ? .matches : .differs }
        guard let lhs=number(a),let rhs=number(b) else { return .needsReview }
        return lhs==rhs ? .matches : .differs
    }
    private static func number(_ value: String) -> Decimal? {
        let s=value.replacingOccurrences(of:"−",with:"-")
        guard s.filter({$0.isNumber}).count<=18,s.range(of:#"^[+-]?\d+(\.\d+)?(/[+-]?\d+(\.\d+)?)?%?$"#,options:.regularExpression) != nil else { return nil }
        let percentage=s.hasSuffix("%"),raw=percentage ? String(s.dropLast()) : s
        let parts=raw.split(separator:"/").map(String.init)
        guard let top=Decimal(string:parts[0],locale:Locale(identifier:"en_US_POSIX")) else { return nil }
        var n=top
        if parts.count==2 { guard let bottom=Decimal(string:parts[1],locale:Locale(identifier:"en_US_POSIX")),bottom != 0 else { return nil };n/=bottom }
        return percentage ? n/100 : n
    }
}
