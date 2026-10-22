const {test}=require('node:test');
const assert=require('node:assert/strict');
const {boot}=require('./demo-test-harness.cjs');
function fixture(){
 const app=boot();
 app.read(`data.questions.find(q=>q.id==='q3').history=[{date:'2026-10-21',result:'skip',recordedAt:1792584000000}];state.mode='manual';state.manualSelected=new Set(['q3']);generatePaper();`);
 return app;
}
function isDeleted(app,kind,id){return app.read(`Boolean(data.${kind==='paper'?'papers':'questions'}.find(i=>i.id===${JSON.stringify(id)})?.deletedAt)`);}
function pending(app){app.read(`currentPaper().gradingDraft={id:'draft',createdAt:1792670400000,committed:false,items:[{questionId:'q3',verdict:'skip'}]};`);}
for(const [name,history,allowed] of [
 ['unattempted',[],false],
 ['correct',[{result:'correct',recordedAt:2000}],false],
 ['wrong',[{result:'wrong',recordedAt:2000}],false],
 ['confirmed skip',[{result:'skip',recordedAt:2000}],true],
 ['old skip then wrong',[{result:'skip',recordedAt:1000},{result:'wrong',recordedAt:2000}],false],
 ['wrong then skip',[{result:'wrong',recordedAt:1000},{result:'skip',recordedAt:2000}],true],
 ['unsorted latest wrong',[{result:'wrong',recordedAt:2000},{result:'skip',recordedAt:1000}],false]
])test(`question deletion: ${name}`,()=>{
 const app=fixture();app.read(`data.questions.find(q=>q.id==='q3').history=${JSON.stringify(history)};softDeleteItems('question',['q3']);`);
 assert.equal(isDeleted(app,'question','q3'),allowed);
});
test('pending grading blocks a skipped question even when draft verdict is skip',()=>{
 const app=fixture();pending(app);app.read(`requestDelete('question',['q3'])`);assert.equal(app.read('state.deleteDraft==null'),true);
 app.read(`softDeleteItems('question',['q3'])`);assert.equal(isDeleted(app,'question','q3'),false);
});
test('committed and legacy deleted grading drafts do not block skipped question',()=>{
 for(const patch of ['currentPaper().gradingDraft.committed=true','currentPaper().deletedAt=123']){
  const app=fixture();pending(app);app.read(patch);app.read(`softDeleteItems('question',['q3'])`);assert.equal(isDeleted(app,'question','q3'),true);
 }
});
for(const [name,patch,allowed] of [
 ['new paper','',true],
 ['print only',`buildPrintHTML(currentPaper(),'all',false);`,true],
 ['pending draft',`currentPaper().gradingDraft={committed:false,items:[]};`,false],
 ['recorded',`currentPaper().completed=true;`,false],
 ['confirmed attempts despite stale completed flag',`currentPaper().attempts=[{id:'saved',committed:true,items:[]}];`,false],
 ['legacy results despite stale completed flag',`currentPaper().results={q3:'skip'};`,false],
 ['recorded reprint',`currentPaper().completed=true;buildPrintHTML(currentPaper(),'student',false);`,false]
])test(`paper deletion: ${name}`,()=>{
 const app=fixture(),id=app.read('state.paperId');app.read(patch);app.read(`softDeleteItems('paper',[state.paperId])`);assert.equal(isDeleted(app,'paper',id),allowed);
});
test('mixed eligibility rejects whole batch and explains count',()=>{
 const app=fixture();app.read(`requestDelete('question',['q3','q1'])`);assert.equal(app.read('state.deleteDraft==null'),true);
 app.read(`softDeleteItems('question',['q3','q1'])`);assert.equal(isDeleted(app,'question','q3'),false);assert.equal(isDeleted(app,'question','q1'),false);
 assert.match(app.el('modal-root').innerHTML,/1/);
});
test('missing or previously deleted batch item rejects entire batch',()=>{
 for(const id of ['missing','q1']){
  const app=fixture();if(id==='q1')app.read('data.questions[0].deletedAt=123');
  app.read(`softDeleteItems('question',['q3',${JSON.stringify(id)}])`);assert.equal(isDeleted(app,'question','q3'),false);
 }
});
test('question eligibility is rechecked after confirmation opens',()=>{
 const app=fixture();app.click('request-delete',{kind:'question',id:'q3'});assert.ok(app.read('state.deleteDraft'));
 app.read(`data.questions.find(q=>q.id==='q3').history.push({result:'wrong',recordedAt:Date.now()})`);app.click('confirm-delete');
 assert.equal(isDeleted(app,'question','q3'),false);assert.equal(app.read('state.deleteDraft==null'),true);
});
test('paper pending draft acquired after confirmation prevents deletion',()=>{
 const app=fixture(),id=app.read('state.paperId');app.click('request-delete',{kind:'paper',id});pending(app);app.click('confirm-delete');assert.equal(isDeleted(app,'paper',id),false);
});
test('stale batch confirmation cannot partially delete',()=>{
 const app=fixture();app.read(`data.questions.find(q=>q.id==='q4').history=[{result:'skip',recordedAt:1000}];requestDelete('question',['q3','q4']);data.questions.find(q=>q.id==='q4').history.push({result:'correct',recordedAt:2000});`);
 app.click('confirm-delete');assert.equal(isDeleted(app,'question','q3'),false);assert.equal(isDeleted(app,'question','q4'),false);
});
function actionTag(html,action,id){return html.match(new RegExp(`<button[^>]*data-action="${action}"[^>]*data-id="${id}"[^>]*>`))?.[0]||'';}
test('manage view disables ineligible questions and shows latest result and reason',()=>{
 const app=fixture();app.read(`navigate('library')`);app.click('question-manage');const html=app.el('screen').innerHTML;
 assert.match(actionTag(html,'question-select-delete','q1'),/disabled/);assert.doesNotMatch(actionTag(html,'question-select-delete','q3'),/disabled/);
 assert.match(html,/暂未做/);assert.match(html,/暂不可删除/);
 app.click('question-select-delete',{id:'q1'});assert.equal(app.read("state.deleteSelection.has('q1')"),false);
});
test('question detail and paper list and preview disable blocked delete buttons',()=>{
 const app=fixture();app.read(`navigate('detail',{detailId:'q1'})`);assert.match(actionTag(app.el('screen').innerHTML,'request-delete','q1'),/disabled/);
 app.read(`currentPaper().completed=true;state.practiceSection='papers';navigate('practice')`);let id=app.read('state.paperId');assert.match(actionTag(app.el('screen').innerHTML,'request-delete',id),/disabled/);
 app.read(`navigate('preview')`);assert.match(actionTag(app.el('screen').innerHTML,'request-delete',id),/disabled/);
});
test('stale legacy paper status still renders recorded',()=>{
 const app=fixture();app.read(`currentPaper().results={q3:'skip'}`);assert.equal(app.read('paperStage(currentPaper())'),'recorded');
});
test('valid deletion retains histories and paper snapshot; restore re-evaluates state',()=>{
 const app=fixture(),snapshot=app.read('JSON.stringify(currentPaper().questions)'),history=app.read("JSON.stringify(data.questions.find(q=>q.id==='q3').history)");
 app.read(`softDeleteItems('question',['q3'])`);assert.equal(app.read('JSON.stringify(currentPaper().questions)'),snapshot);
 app.read(`restoreDeleted('question','q3')`);assert.equal(app.read("JSON.stringify(data.questions.find(q=>q.id==='q3').history)"),history);
 pending(app);app.read(`softDeleteItems('question',['q3'])`);assert.equal(isDeleted(app,'question','q3'),false);
});
test('legacy trash restores pending paper and original history without enabling deletion',()=>{
 const app=fixture();pending(app);app.read('currentPaper().deletedAt=123;persist()');const restored=boot(JSON.parse(app.saved.get('shiti-interactive-demo-v1'))),id=restored.read('data.papers[0].id');
 restored.read(`restoreDeleted('paper',${JSON.stringify(id)});state.paperId=${JSON.stringify(id)};`);assert.equal(restored.read('paperStage(currentPaper())'),'pending');assert.ok(restored.read("pendingGradingFor('q3')"));
 restored.read(`softDeleteItems('paper',[state.paperId]);softDeleteItems('question',['q3']);`);assert.equal(isDeleted(restored,'paper',id),false);assert.equal(isDeleted(restored,'question','q3'),false);
});
test('closing confirmation invalidates old delete draft',()=>{
 const app=fixture();app.click('request-delete',{kind:'question',id:'q3'});app.click('close-modal');app.click('confirm-delete');assert.equal(isDeleted(app,'question','q3'),false);
});
