import SwiftUI

struct QuestionContent:View {
    var question:Question
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            ForEach(question.fragments) { AssetImage(name:$0.asset).frame(maxHeight:320) }
            if question.fragments.isEmpty || !question.text.isEmpty { Text(question.text.isEmpty ? "图片题目" : question.text).font(.body).textSelection(.enabled) }
        }
    }
}
struct LibraryView:View {
    @EnvironmentObject var store:AppStore
    @State private var filter=QuestionFilter()
    @State private var result="all"
    @State private var managing=false
    @State private var selected=Set<UUID>()
    @State private var filterSheet=false
    @State private var settings=false
    @State private var confirm=false
    private var rows:[Question] { store.library.filteredQuestions(filter) }
    var body:some View {
        NavigationView {
            List {
                Section {
                    HStack { Button(managing ? "完成管理" : "管理错题") { managing.toggle();selected=[] };Spacer();NavigationLink("最近删除") { TrashView() } }
                    HStack { Picker("最近结果",selection:$result) { Text("全部结果").tag("all");Text("再练练").tag("wrong");Text("暂未做").tag("skip");Text("做对了").tag("correct");Text("待核对").tag("pending") };Button("筛选") { filterSheet=true } }
                    if managing { Text("仅最近确认结果为暂未做且无待核对批改的题可删除。").font(.footnote).foregroundColor(.secondary) }
                }
                if rows.isEmpty { EmptyHint(title:"还没有符合条件的题",detail:"拍试卷收录错题，或调整筛选条件。",icon:"books.vertical") }
                ForEach(rows) { q in
                    if managing {
                        Button { if selected.contains(q.id){selected.remove(q.id)}else{selected.insert(q.id)} } label: {
                            HStack(alignment:.top) { Image(systemName:selected.contains(q.id) ? "checkmark.square.fill" : "square");questionRow(q); }
                        }.disabled(store.library.questionDeletionReason(q.id) != nil)
                    } else { NavigationLink { QuestionDetail(id:q.id) } label: { questionRow(q) } }
                }
            }.listStyle(.insetGrouped).navigationTitle("我的错题本")
            .searchable(text:$filter.search,prompt:"搜索题干、知识点或错因")
            .toolbar { Button { settings=true } label: { Image(systemName:"gearshape") }.accessibilityLabel("家长设置") }
            .safeAreaInset(edge:.bottom) { if managing { HStack { Text("已选 \(selected.count) 道");Spacer();Button("删除所选",role:.destructive){confirm=true}.disabled(selected.isEmpty) }.padding().background(.regularMaterial) } }
            .onChange(of:result) { value in filter.result=Verdict(rawValue:value);filter.pendingOnly=value=="pending";filter.includeMastered=true }
            .sheet(isPresented:$filterSheet) { FilterView(filter:$filter) }
            .sheet(isPresented:$settings) { SettingsView() }
            .alert("将 \(selected.count) 道题移入最近删除？",isPresented:$confirm) { Button("取消",role:.cancel){};Button("删除",role:.destructive){let ids=Array(selected);Task{if await store.change({try LibraryCommands.deleteQuestions(in:&$0,ids:ids,now:Date())}){selected=[]}}} } message:{Text("历史卷和练习记录保留，删除后可恢复。")}
        }.navigationViewStyle(.stack)
    }
    @ViewBuilder private func questionRow(_ q:Question) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(q.topics.joined(separator:" · ")).font(.caption).foregroundColor(Theme.blue)
            QuestionContent(question:q)
            Text("\(q.subject) · \(q.grade) · \(q.mastered ? "已掌握" : "待巩固")").font(.caption).foregroundColor(.secondary)
            Text(q.latestResult.map{"最近："+$0.verdict.title} ?? "尚未重做").font(.caption)
            if store.library.pendingPaper(for:q.id) != nil { Text("批改待核对").font(.caption).foregroundColor(.orange) }
            if managing,let reason=store.library.questionDeletionReason(q.id) { Text(reason).font(.caption).foregroundColor(.secondary) }
        }.padding(.vertical,8)
    }
}

struct QuestionDetail:View {
    @EnvironmentObject var store:AppStore
    var id:UUID
    @State private var editing=false
    @State private var answer=false
    @State private var confirm=false
    var question:Question? { store.library.questions.first{$0.id==id} }
    var body:some View {
        Group { if let q=question {
            List {
                Section { QuestionContent(question:q);Text("\(q.subject) · \(q.grade)");Text("知识点："+q.topics.joined(separator:"、"));Text("错因："+q.causes.joined(separator:"、"));Text("分类来源："+q.classificationSource).font(.footnote).foregroundColor(.secondary);Button("编辑分类与参考答案"){editing=true} }
                Section {
                    Button(answer ? "收起参考答案" : "展开参考答案"){answer.toggle()}
                    if answer { Text(q.answer.isEmpty ? "尚未添加答案" : q.answer);Text(q.explanation).foregroundColor(.secondary) }
                    Toggle("已掌握",isOn:Binding(get:{q.mastered},set:{value in Task{await store.change{lib in guard let i=lib.questions.firstIndex(where:{$0.id==id})else{return};lib.questions[i].mastered=value}}}))
                }
                if let paper=store.library.pendingPaper(for:id) { Section("待核对") { NavigationLink(paper.title){GradingView(paperID:paper.id)} } }
                Section("练习与未作答记录 · 有效练习 \(q.practiceCount) 次") {
                    if q.history.isEmpty { Text("尚未重做").foregroundColor(.secondary) }
                    ForEach(q.history.sorted{$0.confirmedAt>$1.confirmedAt}) { event in
                        VStack(alignment:.leading) { Text(event.verdict.title);Text(event.confirmedAt,style:.date).font(.caption);if event.verdict == .skip { Text("未计入练习次数").font(.caption).foregroundColor(.secondary) };if let paper=store.library.papers.first(where:{$0.id==event.paperID}){NavigationLink("查看所属练习卷"){PaperDetail(id:paper.id)}} }
                    }
                }
                if let sourceID=q.sourceID,let source=store.library.sources.first(where:{$0.id==sourceID}) { Section("来源试卷") { NavigationLink(source.title){SourceDetail(source:source)} } }
                Section { if q.deletedAt != nil { Button("恢复错题"){Task{await store.change{LibraryCommands.restoreQuestion(in:&$0,id:id)}}} } else { Button("删除错题",role:.destructive){confirm=true}.disabled(store.library.questionDeletionReason(id) != nil);if let reason=store.library.questionDeletionReason(id){Text(reason).font(.footnote).foregroundColor(.secondary)} } }
            }.navigationTitle("错题详情").sheet(isPresented:$editing){QuestionEditor(question:q){updated in await store.change{lib in guard let i=lib.questions.firstIndex(where:{$0.id==id})else{throw LibraryError("题目不存在")};lib.questions[i]=updated;LibraryCommands.updateCatalogs(in:&lib)}}}
            .alert("删除这道错题？",isPresented:$confirm){Button("取消",role:.cancel){};Button("移入最近删除",role:.destructive){Task{await store.change{try LibraryCommands.deleteQuestions(in:&$0,ids:[id],now:Date())}}} } message:{Text("历史资料保留，可从最近删除恢复。")}
        } else { Text("找不到这道题") } }
    }
}

struct QuestionEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State var question:Question
    var save:(Question) async -> Bool
    @State private var newTopic=""
    @State private var newCause=""
    @State private var saving=false
    var body:some View {
        NavigationView { Form {
            Section("题目") { QuestionContent(question:question);TextEditor(text:$question.text).frame(minHeight:80) }
            Section("分类建议可修改") { TextField("科目",text:$question.subject);TextField("年级",text:$question.grade);Text(question.classificationSource).font(.caption).foregroundColor(.secondary) }
            Section("知识点 · 可多选") { tagGrid(Array(Set(store.library.topicCatalog+question.topics)).sorted(),selected:$question.topics);HStack{TextField("自定义知识点",text:$newTopic);Button("添加"){add(&question.topics,text:&newTopic)}} }
            Section("这次错在哪里 · 可选填") { tagGrid(Array(Set(store.library.causeCatalog+question.causes)).sorted(),selected:$question.causes);HStack{TextField("自己填写错因",text:$newCause);Button("添加"){add(&question.causes,text:&newCause)}} }
            Section("家长参考答案") { TextField("参考答案（可稍后补）",text:$question.answer);TextField("解析",text:$question.explanation) }
        }.navigationTitle("保存错题").toolbar{ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button(saving ? "保存中…" : "保存"){saving=true;let updated=question;Task{if await save(updated){dismiss()};saving=false}}.disabled(saving || question.subject.trimmingCharacters(in:.whitespaces).isEmpty || (question.fragments.isEmpty && question.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty))}} }.navigationViewStyle(.stack)
    }
    private func add(_ values:inout[String],text:inout String){let cleaned=text.trimmingCharacters(in:.whitespacesAndNewlines);if !cleaned.isEmpty && !values.contains(cleaned){values.append(cleaned)};text=""}
    private func tagGrid(_ values:[String],selected:Binding<[String]>) -> some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:95))],alignment:.leading){ForEach(values,id:\.self){value in Button{if selected.wrappedValue.contains(value){selected.wrappedValue.removeAll{$0==value}}else{selected.wrappedValue.append(value)}}label:{Text(value).font(.subheadline).frame(maxWidth:.infinity,minHeight:44).padding(.horizontal,4).background(selected.wrappedValue.contains(value) ? Theme.blue.opacity(0.15) : Color.secondary.opacity(0.07)).cornerRadius(9)}.buttonStyle(.plain).foregroundColor(selected.wrappedValue.contains(value) ? Theme.blue : .primary)}}
    }
}

struct FilterView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    @Binding var filter:QuestionFilter
    @State private var draft=QuestionFilter()
    @State private var dateRange=false
    @State private var from=Calendar.current.startOfDay(for:Date())
    @State private var to=Date()
    @State private var error=""
    var body:some View {
        NavigationView { Form {
            Section{Picker("科目",selection:$draft.subject){Text("全部").tag("");ForEach(Array(Set(store.library.activeQuestions.map(\.subject))).sorted(),id:\.self){Text($0).tag($0)}};Picker("年级",selection:$draft.grade){Text("全部").tag("");ForEach(Array(Set(store.library.activeQuestions.map(\.grade))).sorted(),id:\.self){Text($0).tag($0)}};Toggle("包含已掌握",isOn:$draft.includeMastered)}
            Section("知识点 · 同项任一匹配"){ForEach(store.library.topicCatalog,id:\.self){value in Toggle(value,isOn:Binding(get:{draft.topics.contains(value)},set:{if $0{draft.topics.insert(value)}else{draft.topics.remove(value)}}))}}
            Section("错因 · 同项任一匹配"){ForEach(store.library.causeCatalog,id:\.self){value in Toggle(value,isOn:Binding(get:{draft.causes.contains(value)},set:{if $0{draft.causes.insert(value)}else{draft.causes.remove(value)}}))}}
            Section("加入时间"){Toggle("限定日期",isOn:$dateRange);if dateRange{DatePicker("开始（含）",selection:$from,displayedComponents:.date);DatePicker("结束（含）",selection:$to,displayedComponents:.date)};if !error.isEmpty{Text(error).foregroundColor(.red)}}
            Button("重置条件"){draft=QuestionFilter();dateRange=false}
        }.navigationTitle("筛选题目").toolbar{ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("应用"){draft.from=dateRange ? Calendar.current.startOfDay(for:from) : nil;draft.to=dateRange ? Calendar.current.startOfDay(for:to) : nil;do{try draft.validate();filter=draft;dismiss()}catch{self.error=error.localizedDescription}}}}.onAppear{draft=filter;dateRange=filter.from != nil;from=filter.from ?? from;to=filter.to ?? to} }.navigationViewStyle(.stack)
    }
}

struct SourceDetail:View {
    var source:SourceDocument
    var body:some View { ScrollView{VStack{ForEach(source.pages,id:\.self){AssetImage(name:$0)}}.padding()}.navigationTitle(source.title) }
}
