import Foundation

public enum LibraryCommands {
    public static func addQuestion(in library: inout StudyLibrary, question: Question) throws {
        guard !library.questions.contains(where:{$0.id==question.id}) else { throw LibraryError("题目已保存") }
        library.questions.insert(question,at:0);updateCatalogs(in:&library)
    }
    public static func updateCatalogs(in library: inout StudyLibrary) {
        library.topicCatalog=Array(Set(library.topicCatalog + library.questions.flatMap(\.topics))).filter{!$0.isEmpty}.sorted()
        library.causeCatalog=Array(Set(library.causeCatalog + library.questions.flatMap(\.causes))).filter{!$0.isEmpty}.sorted()
    }
    @discardableResult public static func createPaper(in library: inout StudyLibrary, questionIDs: [UUID], now: Date) throws -> UUID {
        var seen=Set<UUID>()
        let ids=questionIDs.filter { seen.insert($0).inserted }
        let selected=ids.compactMap { id in library.activeQuestions.first{$0.id==id} }
        guard !ids.isEmpty,selected.count==ids.count else { throw LibraryError("请选择有效题目后再生成") }
        let subjects=Set(selected.map(\.subject)),subject=subjects.count==1 ? selected[0].subject : "综合"
        guard library.nextPaperSerial>0,library.nextPaperSerial<Int.max else { throw LibraryError("出卷序号已超出支持范围") }
        let paper=Paper(serial:library.nextPaperSerial,title:"我的\(subject)巩固练习\(library.nextPaperSerial)",questions:selected,createdAt:now)
        library.papers.append(paper);library.nextPaperSerial+=1;return paper.id
    }
    public static func deleteQuestions(in library: inout StudyLibrary, ids: [UUID], now: Date) throws {
        guard !ids.isEmpty else { throw LibraryError("请先选择题目") }
        let reasons=Set(ids.compactMap{library.questionDeletionReason($0)})
        guard reasons.isEmpty else { throw LibraryError("本次未删除任何题目："+reasons.sorted().joined(separator:"；")) }
        for i in library.questions.indices where ids.contains(library.questions[i].id) { library.questions[i].deletedAt=now }
    }
    public static func deletePapers(in library: inout StudyLibrary, ids: [UUID], now: Date) throws {
        guard !ids.isEmpty else { throw LibraryError("请先选择练习卷") }
        let reasons=Set(ids.compactMap{library.paperDeletionReason($0)})
        guard reasons.isEmpty else { throw LibraryError("本次未删除任何练习卷："+reasons.sorted().joined(separator:"；")) }
        for i in library.papers.indices where ids.contains(library.papers[i].id) { library.papers[i].deletedAt=now }
    }
    public static func restoreQuestion(in library: inout StudyLibrary, id: UUID) { if let i=library.questions.firstIndex(where:{$0.id==id}) { library.questions[i].deletedAt=nil } }
    public static func restorePaper(in library: inout StudyLibrary, id: UUID) { if let i=library.papers.firstIndex(where:{$0.id==id}) { library.papers[i].deletedAt=nil } }
    public static func beginGrading(in library: inout StudyLibrary, paperID: UUID, layoutID: UUID, photoAssets: [String], now: Date) throws {
        guard let i=library.papers.firstIndex(where:{$0.id==paperID && $0.deletedAt==nil}) else { throw LibraryError("练习卷不存在") }
        guard library.papers[i].draft==nil else { throw LibraryError("请先继续核对现有草稿") }
        guard library.papers[i].layouts.contains(where:{$0.id==layoutID}) else { throw LibraryError("找不到对应的打印版本") }
        library.papers[i].draft=GradingDraft(layoutID:layoutID,items:library.papers[i].questions.map{GradingItem(questionID:$0.id)},photoAssets:photoAssets,createdAt:now)
    }
    public static func saveDraft(in library: inout StudyLibrary, paperID: UUID, draft: GradingDraft) throws {
        guard let i=library.papers.firstIndex(where:{$0.id==paperID && $0.deletedAt==nil}), let previous=library.papers[i].draft,previous.id==draft.id,previous.layoutID==draft.layoutID else { throw LibraryError("批改草稿已变化，请重新打开") }
        guard Set(draft.items.map(\.questionID))==Set(library.papers[i].questions.map(\.id)),draft.items.count==library.papers[i].questions.count else { throw LibraryError("草稿题目与原卷不一致") }
        library.papers[i].draft=draft
    }
    public static func confirmGrading(in library: inout StudyLibrary, paperID: UUID, attemptID: UUID, now: Date) throws {
        guard let i=library.papers.firstIndex(where:{$0.id==paperID && $0.deletedAt==nil}) else { throw LibraryError("练习卷不存在") }
        if library.papers[i].attempts.contains(where:{$0.id==attemptID}) { return }
        guard let draft=library.papers[i].draft,draft.id==attemptID else { throw LibraryError("批改草稿已变化") }
        guard !draft.items.isEmpty,draft.items.allSatisfy({$0.verdict != nil && $0.reviewed}),Set(draft.items.map(\.questionID))==Set(library.papers[i].questions.map(\.id)),draft.items.count==library.papers[i].questions.count else { throw LibraryError("请逐题核对并确认结果，不能遗漏题目") }
        guard Set(draft.items.map(\.questionID)).isSubset(of:Set(library.questions.map(\.id))),library.nextEventSequence>0,library.nextEventSequence < Int64.max-Int64(draft.items.count) else { throw LibraryError("题目关联或结果序号损坏，未保存本次批改") }
        for item in draft.items {
            if let qIndex=library.questions.firstIndex(where:{$0.id==item.questionID}),let verdict=item.verdict {
                library.questions[qIndex].history.append(ResultEvent(paperID:paperID,attemptID:attemptID,verdict:verdict,confirmedAt:now,sequence:library.nextEventSequence,recognized:item.recognized))
                library.nextEventSequence+=1
                if verdict == .wrong { library.questions[qIndex].mastered=false }
            }
        }
        library.papers[i].attempts.append(GradingAttempt(id:draft.id,layoutID:draft.layoutID,items:draft.items,photoAssets:draft.photoAssets,confirmedAt:now))
        library.papers[i].draft=nil
    }
    public static func validate(_ library: StudyLibrary) throws {
        guard library.schemaVersion==1 else { throw LibraryError("资料格式版本不支持，请先更新 App") }
        guard Set(library.questions.map(\.id)).count==library.questions.count,Set(library.papers.map(\.id)).count==library.papers.count,Set(library.papers.map(\.serial)).count==library.papers.count,library.nextPaperSerial > (library.papers.map(\.serial).max() ?? 0),library.nextEventSequence > (library.questions.flatMap(\.history).map(\.sequence).max() ?? 0) else { throw LibraryError("资料标识或序号损坏，已停止保存") }
        guard library.referencedAssets.allSatisfy(AssetName.isValid) else { throw LibraryError("资料包含无效图片路径") }
        for p in library.papers {
            let ids=Set(p.questions.map(\.id))
            let layouts=Set(p.layouts.map(\.id))
            guard !ids.isEmpty,ids.count==p.questions.count,ids.isSubset(of:Set(library.questions.map(\.id))),!p.layouts.isEmpty,layouts.count==p.layouts.count,p.layouts.allSatisfy({$0.revision>0 && Set($0.questionOrder)==ids && $0.questionOrder.count==ids.count}),Set(p.attempts.map(\.id)).count==p.attempts.count else { throw LibraryError("练习卷排版或题目关联损坏") }
            func validItems(_ items:[GradingItem])->Bool { items.count==ids.count && Set(items.map(\.questionID))==ids }
            if let draft=p.draft { guard layouts.contains(draft.layoutID),validItems(draft.items),!p.attempts.contains(where:{$0.id==draft.id}) else { throw LibraryError("批改草稿关联损坏") } }
            for attempt in p.attempts { guard layouts.contains(attempt.layoutID),validItems(attempt.items),attempt.items.allSatisfy({$0.verdict != nil && $0.reviewed}) else { throw LibraryError("已确认批改记录损坏") } }
        }
    }
}
