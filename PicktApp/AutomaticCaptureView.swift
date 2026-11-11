import SwiftUI

struct CaptureFlow:View {
    @EnvironmentObject var store:AppStore
    @State var images:[UIImage]
    var finish:()->Void
    @State private var session=CaptureSession()
    @State private var page=0
    @State private var confirmUpload=false
    @State private var settings=false
    @State private var work:Task<Void,Never>?
    @State private var processing=false
    @State private var error:String?
    @State private var crop:CaptureEdit?
    @State private var questions:[Question]=[]
    @State private var retainedDrafts:[UUID:Question]=[:]
    @State private var batchClassification=false
    @State private var manual=false
    @State private var reviewing=false
    @State private var editingQuestion:Question?
    @State private var source=SourceDocument(title:"拍摄试卷",pages:[])
    @State private var assets:[Int:String]=[:]
    private var visible:[CaptureCandidate]{session.candidates.filter{$0.pieces.contains(where:{$0.page==page})}}
    var body:some View {
        NavigationView{VStack(spacing:8){
            if reviewing{review}else{capture}
            if let error=error{Text(error).font(.footnote).foregroundColor(.red).padding(.horizontal)}
        }.navigationTitle(reviewing ? "分类并保存":"从试卷中选错题").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.cancellationAction){Button(reviewing ? "返回选题":"完成"){if reviewing{reviewing=false}else{work?.cancel();finish()}}.disabled(processing)};ToolbarItem(placement:.navigationBarTrailing){Button("识别设置"){settings=true}.disabled(processing)}}
        .safeAreaInset(edge:.bottom){bottomBar}
        }.navigationViewStyle(.stack)
        .fullScreenCover(isPresented:$manual){ManualCaptureFlow(images:images){manual=false}}
        .sheet(isPresented:$batchClassification){QuestionEditor(question:Question(text:"仅统一分类，不修改题图、文字与答案")){q in
            for i in questions.indices{questions[i].subject=q.subject;questions[i].grade=q.grade;questions[i].topics=q.topics;questions[i].causes=q.causes;retainedDrafts[questions[i].id]=questions[i]};return true
        }}
        .sheet(isPresented:$settings){NavigationView{ModelSettingsView().toolbar{Button("完成"){settings=false}}}}
        .sheet(item:$crop){edit in CaptureRectEditor(image:images[edit.page],rect:edit.rect){rect in
            if let id=edit.candidateID,let index=session.candidates.firstIndex(where:{$0.id==id}){session.candidates[index].pieces[edit.piece].rect=rect}
            else{let q=CaptureCandidate(page:edit.page,number:"手动 \(session.candidates.count+1)",text:"",regions:[rect]);session.append([q]);session.selected.insert(q.id)}
            crop=nil
        }}
        .sheet(item:$editingQuestion){q in QuestionEditor(question:q){updated in if let i=questions.firstIndex(where:{$0.id==updated.id}){questions[i]=updated;retainedDrafts[updated.id]=updated};return true}}
        .alert("发送当前第 \(page+1) 页至智谱？",isPresented:$confirmUpload){Button("取消",role:.cancel){};Button("确认上传并分题"){recognize()}}message:{Text("将发送上方所见整页图像（包括手写内容）。如有姓名学校，请取消并使用已遮盖的照片重新导入。仅调用 GLM-4.6V-Flash；官方当前标价免费，请核对最新政策。结果需人工核对，不自动判题。")}
        .onDisappear{work?.cancel()}
    }
    private var capture:some View{VStack(spacing:8){
        Picker("当前页",selection:$page){ForEach(images.indices,id:\.self){Text("第 \($0+1) 页").tag($0)}}.pickerStyle(.menu).disabled(processing)
        HStack{Button(processing ? "正在分题…":"自动分题"){confirmUpload=true}.buttonStyle(.borderedProminent).disabled(processing || !visible.isEmpty)
            Button("补框"){crop=CaptureEdit(page:page)}.buttonStyle(.bordered).disabled(processing)
            Button("合并"){session.merge()}.disabled(processing || session.selected.count<2)
        }
        Text("图上只显示题框；在右栏点＋多选。调整范围与文字后再保存。已有候选框时不重复请求，避免覆盖选择。").font(.caption).foregroundColor(.secondary).padding(.horizontal)
        HStack(alignment:.top,spacing:8){CapturePageImage(image:images[page],candidates:visible,selected:session.selected,page:page)
            ScrollView{VStack(spacing:12){ForEach(visible){q in controls(q)}}}.frame(width:76)
        }.padding(.horizontal,8)
        Button("手动逐题收录 / 遮盖笔迹"){manual=true}.font(.footnote).disabled(processing)
        if processing{Button("取消请求"){work?.cancel()}}
    }}
    private func controls(_ q:CaptureCandidate)->some View{
        VStack(spacing:3){Text(q.number).font(.caption).lineLimit(3)
            Button{session.toggle(q.id)}label:{Text(session.selected.contains(q.id) ? "✓":"＋").font(.title2).frame(width:52,height:44)}.buttonStyle(.borderedProminent).accessibilityLabel("选择或取消题目 \(q.number)")
            ForEach(Array(q.pieces.enumerated()).filter{$0.element.page==page},id:\.offset){i,piece in Button("调整\(q.pieces.count>1 ? String(i+1):"")"){crop=CaptureEdit(candidateID:q.id,piece:i,page:page,rect:piece.rect)}.frame(minHeight:44)}
            if !q.originals.isEmpty{Button("取消合并"){session.unmerge(q.id)}.frame(minHeight:44)}
            Button("移除框",role:.destructive){session.remove(q.id)}.font(.caption).frame(minHeight:44)
        }.disabled(processing)
    }
    private var review:some View{List{
        Text("逐题编辑只更新本次草稿，最后点“保存全部”。科目/年级为默认设置，知识点为本地关键词建议，可修改。答案可以稍后补充。").font(.footnote)
        Button("统一设置本次全部题目的分类"){batchClassification=true}
        ForEach(questions){q in VStack(alignment:.leading){QuestionContent(question:q);Text("\(q.subject) · \(q.grade) · \(q.topics.joined(separator:"、"))").font(.caption);Button("编辑分类、文字与答案"){editingQuestion=q}}}
    }}
    private var bottomBar:some View{HStack{
        Text(reviewing ? "\(questions.count) 道待保存":"已选 \(session.selected.count) 道").font(.subheadline)
        Spacer()
        Button(processing ? "处理中…":reviewing ? "保存全部":"下一步：分类"){if reviewing{save()}else{prepare()}}.buttonStyle(.borderedProminent).disabled(processing || (reviewing ? questions.isEmpty:session.selected.isEmpty))
    }.padding().background(.regularMaterial)}
    private func recognize(){
        let current=page,image=images[page];processing=true;error=nil
        work=Task{defer{processing=false};do{let result=try await CloudSegmentation.recognize(image,page:current);try Task.checkCancellation();session.append(result)}catch is CancellationError{}catch{if !Task.isCancelled{self.error=error.localizedDescription}}}
    }
    private func prepare(){
        processing=true;error=nil
        work=Task{defer{processing=false};do{
            for q in questions{retainedDrafts[q.id]=q}
            let previous=retainedDrafts
            var next:[Question]=[]
            for candidate in session.candidates where session.selected.contains(candidate.id){
                try Task.checkCancellation()
                var q=previous[candidate.id] ?? Question(id:candidate.id,text:candidate.text,classificationSource:"智谱视觉文字或手动题图；科目/年级默认六年级数学，知识点为本地关键词建议，均需确认")
                q.fragments=[]
                for piece in candidate.pieces{
                    guard let image=images[piece.page].cropped(piece.rect)else{throw LibraryError("题框太小，请调整后重试")}
                    let original:String;if let old=assets[piece.page]{original=old}else{original=try store.saveImage(images[piece.page]);assets[piece.page]=original}
                    q.fragments.append(QuestionFragment(asset:try store.saveImage(image),originalAsset:original,crop:piece.rect))
                }
                if previous[candidate.id]==nil{q.topics=OCRService.suggestedTopics(q.text)};next.append(q)
            }
            questions=next;reviewing=true
        }catch{self.error=error.localizedDescription}}
    }
    private func save(){
        guard !questions.isEmpty else{return};processing=true
        do{for index in images.indices where assets[index]==nil{assets[index]=try store.saveImage(images[index])}}
        catch{self.error=error.localizedDescription;processing=false;return}
        let batch=questions;var document=source;document.pages=assets.sorted{$0.key<$1.key}.map(\.value)
        work=Task{defer{processing=false};if await store.change({lib in
            if !lib.sources.contains(where:{$0.id==document.id}){lib.sources.append(document)}
            for var q in batch{q.sourceID=document.id;try LibraryCommands.addQuestion(in:&lib,question:q)}
        }){questions=[];session=CaptureSession();finish()}}
    }
}
private struct CaptureEdit:Identifiable {
    var token=UUID()
    var id:UUID{token}
    var candidateID:UUID?;var piece:Int=0;var page:Int;var rect=NormalizedRect()

}
private struct CaptureRectEditor:View {
    @Environment(\.dismiss) var dismiss
    var image:UIImage
    @State var rect:NormalizedRect
    var apply:(NormalizedRect)->Void
    var body:some View{NavigationView{VStack{Text("框内拖动移动，圆点缩放；双指缩放原图。请包含完整题干、选项与图形。").font(.caption);CropCanvas(image:image,rect:$rect);Button("使用此范围"){apply(rect);dismiss()}.buttonStyle(.borderedProminent)}.padding().navigationTitle("调整题框").toolbar{Button("取消"){dismiss()}}}.navigationViewStyle(.stack)}
}
private struct CapturePageImage:View {
    var image:UIImage;var candidates:[CaptureCandidate];var selected:Set<UUID>;var page:Int
    var body:some View{GeometryReader{g in
        let scale=min(g.size.width/image.size.width,g.size.height/image.size.height)
        let size=CGSize(width:image.size.width*scale,height:image.size.height*scale)
        ZStack(alignment:.topLeading){Image(uiImage:image).resizable().frame(width:size.width,height:size.height)
            ForEach(candidates){q in ForEach(Array(q.pieces.enumerated()).filter{$0.element.page==page},id:\.offset){_,p in
                Rectangle().stroke(selected.contains(q.id) ? Color.blue:Color.gray,lineWidth:selected.contains(q.id) ? 2:1)
                    .frame(width:p.rect.width*size.width,height:p.rect.height*size.height).offset(x:p.rect.x*size.width,y:p.rect.y*size.height)
            }}
        }.frame(width:g.size.width,height:g.size.height,alignment:.topLeading)
    }}
}
