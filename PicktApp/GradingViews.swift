import SwiftUI
import VisionKit

struct GradingStartView:View {
    @EnvironmentObject var store:AppStore
    var paperID:UUID
    @State private var layoutID:UUID?
    @State private var importer:ImportKind?
    @State private var started=false
    var body:some View{Group{if let p=store.library.papers.first(where:{$0.id==paperID}){Form{
        Section("对应纸上练习卷"){Text(p.title);Picker("打印版本",selection:$layoutID){ForEach(p.layouts){Text("排版 \($0.revision)").tag(Optional($0.id))}};Text("请与纸上页脚的排版版本核对。拍照不会直接写入学习结果。").font(.footnote)}
        Section{Button("拍已完成试卷"){importer=VNDocumentCameraViewController.isSupported ? .scanner:.camera};Button("从相册导入完成卷"){importer = .album};Button("人工核对（不附照片）"){begin([])}}
        NavigationLink(destination:GradingView(paperID:paperID),isActive:$started){EmptyView()}
    }.onAppear{layoutID=layoutID ?? p.layouts.last?.id}}else{Text("卷不存在")}}.navigationTitle("记录完成卷").sheet(item:$importer){kind in ImageImporter(kind:kind){images in importer=nil;if !images.isEmpty{begin(images)}}failure:{store.error=$0;importer=nil}}}
    private func begin(_ images:[UIImage]){guard let layout=layoutID else{return};do{let names=try images.map{try store.saveImage($0)};Task{if await store.change({try LibraryCommands.beginGrading(in:&$0,paperID:paperID,layoutID:layout,photoAssets:names,now:Date())}){started=true}}}catch{store.error=error.localizedDescription}}
}
struct GradingView:View {
    @EnvironmentObject var store:AppStore
    var paperID:UUID
    @State private var confirm=false
    var paper:Paper?{store.library.papers.first{$0.id==paperID}}
    var body:some View{Group{if let p=paper,let draft=p.draft{List{
        Section{Text("逐题查看作答，核对后选择结果。识别建议不会自动入库。").font(.footnote);Text("已核对 \(draft.items.filter(\.reviewed).count) / \(draft.items.count)");Text("草稿每题保存，返回后可继续核对。").font(.caption)}
        ForEach(Array(draft.items.enumerated()),id:\.element.id){index,item in NavigationLink{GradingItemView(paperID:paperID,questionID:item.questionID)}label:{HStack{Text("第 \(index+1) 题");Spacer();Text(item.reviewed ? (item.verdict?.title ?? "待核对"):"待核对")}}}
        Button("确认全部结果并入库"){confirm=true}.disabled(!draft.items.allSatisfy{$0.reviewed && $0.verdict != nil})
    }.alert("确认保存本次批改？",isPresented:$confirm){Button("取消",role:.cancel){};Button("确认入库"){Task{await store.change{try LibraryCommands.confirmGrading(in:&$0,paperID:paperID,attemptID:draft.id,now:Date())}}}}message:{Text("暂未做不计错，也不计入有效练习次数。")}}else{Text("本次批改已记录，可返回练习卷查看。")}}.navigationTitle("核对批改结果")}
}
struct GradingItemView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    var paperID:UUID,questionID:UUID
    @State private var recognized=""
    @State private var verdict:Verdict?
    @State private var page=0
    @State private var rect=NormalizedRect()
    @State private var processing=false
    @State private var suggestion=""
    var paper:Paper?{store.library.papers.first{$0.id==paperID}}
    var body:some View{Group{if let p=paper,let draft=p.draft,let q=p.questions.first(where:{$0.id==questionID}){ScrollView{VStack(alignment:.leading,spacing:16){
        QuestionContent(question:q);Text("参考答案："+(q.answer.isEmpty ? "尚未提供，请人工判断":q.answer));Text(q.explanation).font(.footnote)
        if !draft.photoAssets.isEmpty{Picker("完成卷照片",selection:$page){ForEach(draft.photoAssets.indices,id:\.self){Text("第 \($0+1) 页").tag($0)}};if draft.photoAssets.indices.contains(page),let url=store.imageURL(draft.photoAssets[page]),let image=UIImage(contentsOfFile:url.path){CropCanvas(image:image,rect:$rect).frame(height:360);Text("框选本题作答区（单指框选，双指缩放）").font(.caption);Button(processing ? "识别中…":"识别所选作答区"){guard let crop=image.cropped(rect)else{return};processing=true;Task{do{recognized=try await OCRService.recognize(crop);verdict=nil;switch AnswerComparison.compare(recognized,reference:q.answer){case .matches:suggestion="数值或选项相符，请核对后确认";case .differs:suggestion="数值或选项不同，请核对";case .needsReview:suggestion="未能可靠比较，请人工核对"}}catch{store.error=error.localizedDescription};processing=false}}.disabled(processing)}}
        Text("作答识别文本（可修改）").font(.headline);TextEditor(text:Binding(get:{recognized},set:{if recognized != $0{recognized=$0;verdict=nil;suggestion="作答已修改，请重新确认结果"}})).frame(height:100).border(Color.secondary.opacity(0.2));Text(suggestion).font(.footnote).foregroundColor(.secondary)
        Text("人工确认结果").font(.headline);ForEach(Verdict.allCases){value in Button{verdict=value}label:{Label(value.title,systemImage:verdict==value ? "checkmark.circle.fill":"circle").frame(minHeight:44)}}
        Button("保存本题核对结果"){let text=recognized,result=verdict;Task{let ok=await store.change{lib in guard let i=lib.papers.firstIndex(where:{$0.id==paperID}),var current=lib.papers[i].draft,current.id==draft.id,let j=current.items.firstIndex(where:{$0.questionID==questionID})else{throw LibraryError("草稿已变化，请重新打开")};current.items[j].recognized=text;current.items[j].verdict=result;current.items[j].reviewed=true;try LibraryCommands.saveDraft(in:&lib,paperID:paperID,draft:current)};if ok{dismiss()}}}.buttonStyle(.borderedProminent).disabled(verdict==nil || processing)
    }.padding()}.onAppear{if let item=draft.items.first(where:{$0.questionID==questionID}){recognized=item.recognized;verdict=item.verdict}}}else{Text("草稿不存在")}}.navigationTitle("逐题核对")}
}
struct GradingRecordView:View{var paper:Paper;var attempt:GradingAttempt
    var body:some View{List{Section{Text(attempt.confirmedAt,style:.date);Text("已确认记录 · 保留当时卷面快照")};ForEach(attempt.items){item in Section{if let q=paper.questions.first(where:{$0.id==item.questionID}){QuestionContent(question:q)};Text(item.verdict?.title ?? "");Text(item.recognized)}};Section("完成卷照片"){ForEach(attempt.photoAssets,id:\.self){AssetImage(name:$0)}}}.navigationTitle("练习记录")}
}
