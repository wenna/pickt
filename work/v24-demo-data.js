// Demo fixtures only. Native App first launch must start with the user's own data.
function freshData(){return addDeletionSamples(freshDataV2Base());}
function addDeletionSamples(dataset){
 if(dataset.deletionSampleVersion===1)return dataset;
 const now=Date.now(),confirmedAt=now-2*86400000;
 let serial=Math.max(Number(dataset.nextPaperSerial)||1,1,...dataset.papers.map(p=>(Number(p.serialNumber)||0)+1));
 const sampleQuestions=[['a','ratio','比和比例'],['b','circle','圆'],['pending','percent','百分数']].map(([suffix,stem,topic],index)=>{
  const id='demo-delete-v24-q-'+suffix,existing=dataset.questions.find(q=>q.id===id);
  if(existing)return existing;
  const original=dataset.questions.find(q=>q.stem===stem)||SEED_QUESTIONS.find(q=>q.stem===stem);
  const q=normalizeQuestion({...clone(original),id,topics:[topic],causes:['方法不会'],subject:'数学',grade:'六年级',source:'删除体验示例 · '+(suffix==='pending'?'另有批改待核对':'已确认暂未做'),status:'pending',addedAt:localDate(-3),history:[],demoSample:true});
  dataset.questions.push(q);return q;
 });
 function paper(suffix,questions,note){
  const id='demo-delete-v24-paper-'+suffix,existing=dataset.papers.find(p=>p.id===id);
  if(existing)return existing;
  const sequence=serial++,p={id,serialNumber:sequence,title:`我的数学巩固练习${sequence}`,createdAt:now,questions:clone(questions),completed:false,results:{},attempts:[],gradingDraft:null,demoSample:true,demoNote:note};
  dataset.papers.push(p);return p;
 }
 const recorded=paper('recorded',sampleQuestions,'已记录示例 · 不可删除');
 const attempt={id:'demo-delete-v24-attempt',date:localDate(-2),source:'photo-demo',createdAt:confirmedAt,confirmedAt,committed:true,photoCount:1,items:sampleQuestions.map(q=>({questionId:q.id,recognized:'未作答（模拟）',suggested:'skip',verdict:'skip',reviewed:true,reason:'示例已核对，确认当次未作答'}))};
 if(!recorded.attempts.some(a=>a.id===attempt.id)){
  recorded.attempts.push(attempt);recorded.completed=true;
  for(const q of sampleQuestions){recorded.results[q.id]='skip';if(!q.history.some(h=>h.attemptId===attempt.id))q.history.push({date:attempt.date,result:'skip',recordedAt:confirmedAt,source:'photo-demo',attemptId:attempt.id,paperId:recorded.id,countsAsPractice:false});}
  recorded.questions=clone(sampleQuestions);
 }
 const waiting=paper('pending',[sampleQuestions[2]],'待核对示例 · 不可删除');
 waiting.gradingDraft={id:'demo-delete-v24-draft',date:localDate(-1),source:'photo-demo',createdAt:now-86400000,committed:false,photoCount:1,items:[{questionId:sampleQuestions[2].id,recognized:'字迹不清，等待核对',suggested:null,verdict:null,reviewed:false,reason:'示例批改尚未确认'}]};
 paper('todo-a',[dataset.questions[0],sampleQuestions[0]],'待完成示例 · 可批量删除');
 paper('todo-b',[dataset.questions[1]||sampleQuestions[1],sampleQuestions[1]],'待完成示例 · 可批量删除');
 dataset.nextPaperSerial=serial;dataset.deletionSampleVersion=1;
 return dataset;
}
function demoSampleBanner(){return `<aside class="demo-sample-banner"><strong>体验示例 · 删除与恢复</strong><p>${data.deletionSampleVersion===1?'已备好暂未做错题、待完成卷，以及不可删除的对照样例。':'可补充 3 道错题和 4 份练习卷，体验可删除与不可删除的区别；保留已有内容。'}</p><div>${data.deletionSampleVersion!==1?'<button class="btn small primary" data-action="load-delete-samples">补充体验数据</button>':'<button class="text-button" data-action="sample-show-questions">看暂未做错题</button><button class="text-button" data-action="sample-show-papers">看待完成练习卷</button>'}</div></aside>`;}
document.addEventListener('click',event=>{
 const target=event.target.closest('[data-action]');if(!target||target.disabled)return;
 switch(target.dataset.action){
  case 'load-delete-samples':if(data.deletionSampleVersion===1)return;addDeletionSamples(data);persist();render();toast('已补充体验示例，原有数据保留');break;
  case 'sample-show-questions':state.subject='数学';state.filter='all';state.resultFilter='skip';state.topic='全部';state.search='';state.libraryManaging=false;navigate('library');break;
  case 'sample-show-papers':state.practiceSection='papers';state.paperStatus='todo';state.paperSearch='';navigate('practice');break;
 }
});
