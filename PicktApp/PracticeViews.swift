import SwiftUI

struct PracticeView:View {
    @EnvironmentObject var store:AppStore
    @State private var tab=0
    @State private var count=5
    @State private var filter=QuestionFilter()
    @State private var selected=Set<UUID>()
    @State private var selectedPapers=Set<UUID>()
    @State private var filtering=false
    @State private var managing=false
    @State private var confirm=false
    var body:some View {NavigationView{VStack{
        Picker("练一练",selection:$tab){Text("选题组卷").tag(0);Text("我的练习卷").tag(1)}.pickerStyle(.segmented).padding(.horizontal)
        if tab==0 {List{
            Section{Button("筛选题目"){filtering=true};Stepper("推荐题数：\(count)",value:$count,in:1...30);Button("帮我选（优先最近做错的题）"){let rows=store.library.filteredQuestions(filter).sorted{($0.latestResult?.verdict == .wrong ? 0:1)<($1.latestResult?.verdict == .wrong ? 0:1)};selected=Set(rows.prefix(count).map(\.id))};Text("已选 \(selected.count) 道；切换筛选保留所选题目").font(.caption)}
            ForEach(store.library.filteredQuestions(filter)){q in Button{if selected.contains(q.id){selected.remove(q.id)}else{selected.insert(q.id)}}label:{HStack{Image(systemName:selected.contains(q.id) ? "checkmark.circle.fill":"circle");VStack(alignment:.leading){Text(q.topics.joined(separator:" · "));Text(q.text.isEmpty ? "图片题目":String(q.text.prefix(70))).foregroundColor(.primary)}}}}
        }.safeAreaInset(edge:.bottom){Button("生成练习卷（\(selected.count) 道）"){let ids=store.library.activeQuestions.filter{selected.contains($0.id)}.map(\.id);Task{if await store.change({try LibraryCommands.createPaper(in:&$0,questionIDs:ids,now:Date())}){selected=[];tab=1}}}.buttonStyle(.borderedProminent).disabled(selected.isEmpty).padding().frame(maxWidth:.infinity).background(.regularMaterial)}}
        else {List{Section{Button(managing ? "完成管理":"批量管理"){managing.toggle();selectedPapers=[]};Text("打印后仍为待完成，纸上做完后打开对应练习卷拍照核对。").font(.footnote)};ForEach(store.library.activePapers.sorted{$0.createdAt>$1.createdAt}){p in if managing{Button{if selectedPapers.contains(p.id){selectedPapers.remove(p.id)}else{selectedPapers.insert(p.id)}}label:{HStack{Image(systemName:selectedPapers.contains(p.id) ? "checkmark.square.fill":"square");paperRow(p)}}.disabled(store.library.paperDeletionReason(p.id) != nil)}else{NavigationLink{PaperDetail(id:p.id)}label:{paperRow(p)}}}}.safeAreaInset(edge:.bottom){if managing{Button("删除所选 \(selectedPapers.count) 份",role:.destructive){confirm=true}.disabled(selectedPapers.isEmpty).padding().frame(maxWidth:.infinity).background(.regularMaterial)}}}
    }.navigationTitle("练一练").sheet(isPresented:$filtering){FilterView(filter:$filter)}.alert("移入最近删除？",isPresented:$confirm){Button("取消",role:.cancel){};Button("删除",role:.destructive){let ids=Array(selectedPapers);Task{if await store.change({try LibraryCommands.deletePapers(in:&$0,ids:ids,now:Date())}){selectedPapers=[]}}}}message:{Text("仅无批改草稿、无确认结果的待完成卷可删除。整批校验，不会部分删除。")}}.navigationViewStyle(.stack)}
    private func paperRow(_ p:Paper)->some View{VStack(alignment:.leading,spacing:6){Text(p.title);Text("\(p.questions.count) 道 · \(p.stage.title)").font(.caption).foregroundColor(.secondary)}}
}

struct PaperDetail:View {
    @EnvironmentObject var store:AppStore
    var id:UUID
    @State private var title=""
    @State private var layoutID:UUID?
    @State private var space=AnswerSpace.medium
    @State private var part=PDFPart.student
    @State private var duplex=false
    @State private var confirm=false
    @State private var working=false
    @State private var output:SharedFile?
    var paper:Paper?{store.library.papers.first{$0.id==id}}
    var body:some View{Group{if let p=paper{List{
        Section("练习卷名称"){TextField("名称",text:$title);Button("保存名称"){let name=title.trimmingCharacters(in:.whitespacesAndNewlines);Task{await store.change{lib in guard !name.isEmpty,name.count<=60,let i=lib.papers.firstIndex(where:{$0.id==id})else{throw LibraryError("名称须为 1 至 60 字")};lib.papers[i].title=name}}};Text("卷序号 \(p.serial) · \(p.stage.title)").font(.caption)}
        Section("打印与 PDF"){
            Picker("排版版本",selection:$layoutID){ForEach(p.layouts){Text("排版 \($0.revision)").tag(Optional($0.id))}}
            Picker("新版本留白",selection:$space){ForEach(AnswerSpace.allCases){Text($0.title).tag($0)}}
            Button("按当前题序创建新排版"){Task{await store.change{lib in guard let i=lib.papers.firstIndex(where:{$0.id==id}),let old=lib.papers[i].layouts.first(where:{$0.id==layoutID})else{throw LibraryError("请选择排版")};let next=PaperLayout(revision:(lib.papers[i].layouts.map(\.revision).max() ?? 0)+1,space:space,questionOrder:old.questionOrder);lib.papers[i].layouts.append(next)};layoutID=paper?.layouts.last?.id}}
            Picker("输出内容",selection:$part){ForEach(PDFPart.allCases){Text($0.title).tag($0)}};Toggle("双面打印（家长页另起一张纸）",isOn:$duplex)
            Button(working ? "生成中…":"预览 / 打印 / 存为 PDF"){makePDF(p)}.disabled(working)
        }
        Section("做完后再拍照核对"){
            if p.draft != nil{NavigationLink("继续核对批改结果"){GradingView(paperID:id)}}else{NavigationLink("拍已完成的练习卷"){GradingStartView(paperID:id)}}
            ForEach(p.attempts){a in NavigationLink{GradingRecordView(paper:p,attempt:a)}label:{Text(a.confirmedAt,style:.date);Text("已确认记录")}}
        }
        Section("卷面题目（历史快照）"){ForEach(p.questions){QuestionContent(question:$0)}}
        Section{if p.deletedAt != nil{Button("恢复练习卷"){Task{await store.change{LibraryCommands.restorePaper(in:&$0,id:id)}}}}else{Button("删除练习卷",role:.destructive){confirm=true}.disabled(store.library.paperDeletionReason(id) != nil);Text(store.library.paperDeletionReason(id) ?? "可移入最近删除，之后可恢复").font(.caption)}}
    }.navigationTitle("练习卷").onAppear{title=p.title;layoutID=layoutID ?? p.layouts.last?.id}.sheet(item:$output){PDFOutputView(file:$0,duplex:duplex)}.alert("删除这份练习卷？",isPresented:$confirm){Button("取消",role:.cancel){};Button("删除",role:.destructive){Task{await store.change{try LibraryCommands.deletePapers(in:&$0,ids:[id],now:Date())}}}}}else{Text("练习卷不存在")}}}
    private func makePDF(_ p:Paper){guard let assets=store.assets,var layout=p.layouts.first(where:{$0.id==layoutID})else{return};working=true;Task{do{layout.placements=try PDFService.makePlan(paper:p,layout:layout,assets:assets);let saved=layout;guard await store.change({lib in guard let i=lib.papers.firstIndex(where:{$0.id==id}),let j=lib.papers[i].layouts.firstIndex(where:{$0.id==saved.id})else{throw LibraryError("排版已变化")};lib.papers[i].layouts[j]=saved})else{working=false;return};let url=try PDFService.write(paper:p,layout:saved,assets:assets,part:part,duplex:duplex);output=SharedFile(url:url)}catch{store.error=error.localizedDescription};working=false}}
}
struct PDFOutputView:View{ @EnvironmentObject var store:AppStore;@Environment(\.dismiss) var dismiss;let file:SharedFile;let duplex:Bool;@State private var sharing=false
    var body:some View{NavigationView{PDFPreview(url:file.url).navigationTitle("A4 预览").toolbar{ToolbarItem(placement:.cancellationAction){Button("关闭"){dismiss()}};ToolbarItemGroup(placement:.bottomBar){Button("打印"){Printer.present(file.url,duplex:duplex){store.error=$0}};Spacer();Button("存储 / 分享 PDF"){sharing=true}}}.sheet(isPresented:$sharing){ShareSheet(url:file.url)}}.navigationViewStyle(.stack)}
}
