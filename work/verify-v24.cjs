const {test}=require('node:test');
const assert=require('node:assert/strict');
const {boot,html}=require('./demo-test-harness.cjs');
test('first launch includes two deletable skipped questions and a pending comparison',()=>{
 const a=boot(null,{samples:true});
 assert.equal(a.read("activeQuestions().filter(q=>q.demoSample&&!deletionBlockReason('question',q)).length"),2);
 assert.equal(a.read("activeQuestions().filter(q=>q.demoSample&&pendingGradingFor(q.id)).length"),1);
 assert.equal(a.read("activeQuestions().filter(q=>q.demoSample).every(q=>latestResult(q)?.result==='skip')"),true);
 assert.equal(a.read('practiceCountFor(activeQuestions().find(q=>q.demoSample))'),0);
});
test('first launch includes two todo papers, a recorded paper and a pending paper',()=>{
 const a=boot(null,{samples:true});
 assert.equal(a.read("activePapers().filter(p=>p.demoSample&&paperStage(p)==='todo').length"),2);
 assert.equal(a.read("activePapers().filter(p=>p.demoSample&&paperStage(p)==='recorded').length"),1);
 assert.equal(a.read("activePapers().filter(p=>p.demoSample&&paperStage(p)==='pending').length"),1);
});
test('sample confirmed history points to an actual recorded paper',()=>{
 const a=boot(null,{samples:true});
 assert.equal(a.read("activeQuestions().filter(q=>q.demoSample).length"),3);
 assert.equal(a.read("activeQuestions().filter(q=>q.demoSample).every(q=>{const h=latestResult(q),p=historyPaper(q,h);return p&&p.attempts.some(x=>x.id===h.attemptId&&x.committed);})"),true);
});
test('old data can add samples without replacing edits; adding twice does not duplicate',()=>{
 const base=boot();base.read("data.questions[0].source='我的原数据';persist()");const stored=JSON.parse(base.saved.get('shiti-interactive-demo-v1'));
 const a=boot(stored);assert.match(a.el('screen').innerHTML,/补充体验数据/);
 a.click('load-delete-samples');assert.equal(a.read("data.questions[0].source"),'我的原数据');
 assert.equal(a.read('activeQuestions().length'),11);assert.equal(a.read('activePapers().length'),4);
 const saved=a.read('JSON.stringify(data)');a.click('load-delete-samples');assert.equal(a.read('JSON.stringify(data)'),saved);
 const reloaded=boot(JSON.parse(a.saved.get('shiti-interactive-demo-v1')));assert.equal(reloaded.read('activePapers().length'),4);
});
test('supplementing samples after existing papers preserves names and allocates new serials',()=>{
 const a=boot();a.read("state.mode='manual';state.manualSelected=new Set(['q1']);generatePaper();currentPaper().title='我自己的卷';persist()");a.click('load-delete-samples');
 assert.equal(a.read('data.papers[0].title'),'我自己的卷');
 assert.equal(a.read('new Set(data.papers.map(p=>p.serialNumber)).size'),5);
 a.read("generatePaper()");assert.equal(a.read('currentPaper().serialNumber'),6);
});
function openManage(a){a.read("state.practiceSection='papers';navigate('practice')");a.click('paper-manage');}
test('paper list has a visible management entry and bulk delete action',()=>{
 const a=boot(null,{samples:true});a.read("state.practiceSection='papers';navigate('practice')");assert.match(a.el('screen').innerHTML,/管理练习卷/);
 a.click('paper-manage');assert.match(a.el('screen').innerHTML,/删除所选练习卷/);assert.match(a.el('screen').innerHTML,/全选当前可删除/);
});
test('select visible only checks eligible papers and batch delete moves both into trash',()=>{
 const a=boot(null,{samples:true});openManage(a);a.click('paper-select-visible');assert.equal(a.read('state.paperDeleteSelection.size'),2);
 a.click('request-delete-selected-papers');assert.match(a.el('modal-root').innerHTML,/2 份/);a.click('confirm-delete');
 assert.equal(a.read('data.papers.filter(p=>p.deletedAt).length'),2);assert.equal(a.read('activePapers().length'),2);assert.equal(a.read('activeQuestions().length'),11);
 a.click('open-trash',{kind:'paper'});assert.match(a.el('screen').innerHTML,/恢复练习卷/);
 const deletedId=a.read('data.papers.find(p=>p.deletedAt).id');a.click('restore-deleted',{kind:'paper',id:deletedId});assert.equal(a.read('activePapers().length'),3);
});
test('pending and recorded paper selection is disabled and cannot be forged through events',()=>{
 const a=boot(null,{samples:true});openManage(a);
 const ids=a.read("activePapers().filter(p=>paperStage(p)!=='todo').map(p=>p.id)");
 for(const id of ids){const tag=a.el('screen').innerHTML.match(new RegExp(`<button[^>]*data-action="paper-select-delete"[^>]*data-id="${id}"[^>]*>`))?.[0]||'';assert.match(tag,/disabled/);a.click('paper-select-delete',{id});}
 assert.equal(a.read('state.paperDeleteSelection.size'),0);
});
test('filter changes retain selected papers and disclose hidden selections',()=>{
 const a=boot(null,{samples:true});openManage(a);a.click('paper-select-visible');a.click('paper-status',{value:'recorded'});
 assert.equal(a.read('state.paperDeleteSelection.size'),2);assert.match(a.el('screen').innerHTML,/2 份不在当前列表/);
 a.click('paper-clear-selection');assert.equal(a.read('state.paperDeleteSelection.size'),0);
});
test('search input refreshes visible selection controls and hidden count',()=>{
 const a=boot(null,{samples:true});openManage(a);a.click('paper-select-visible');
 const target={id:'paper-search',value:'不存在的名称'};a.event('input',target);
 assert.match(a.el('paper-management').innerHTML,/0/);assert.match(a.el('paper-delete-footer').innerHTML,/2 份不在当前列表/);
});
test('state change after paper batch confirmation blocks entire batch',()=>{
 const a=boot(null,{samples:true});openManage(a);a.click('paper-select-visible');a.click('request-delete-selected-papers');
 a.read("data.papers.find(p=>state.paperDeleteSelection.has(p.id)).completed=true");a.click('confirm-delete');
 assert.equal(a.read('data.papers.filter(p=>p.deletedAt).length'),0);assert.equal(a.read('state.paperDeleteSelection.size'),0);
});
test('cancel and finish-management clear or preserve data as expected',()=>{
 const a=boot(null,{samples:true});openManage(a);a.click('paper-select-visible');a.click('request-delete-selected-papers');a.click('close-modal');
 assert.equal(a.read('data.papers.filter(p=>p.deletedAt).length'),0);a.click('paper-manage');assert.equal(a.read('state.paperDeleteSelection.size'),0);
});
test('sample shortcut exposes skipped results and batch selection',()=>{
 const a=boot(null,{samples:true});a.click('sample-show-questions');assert.equal(a.read("libraryQuestions().filter(q=>q.demoSample).length"),3);
 a.click('question-manage');assert.equal(a.read("libraryQuestions().filter(q=>!deletionBlockReason('question',q)).length"),2);
});
test('built demo includes the blue theme and iOS-friendly viewport',()=>{
 assert.match(html,/--accent:\s*#246bd4/i);assert.match(html,/viewport/);assert.match(html,/V2\.4/);
 // Primary button white text meets the normal-text contrast threshold.
 const rgb=[36,107,212].map(v=>v/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);
 assert.ok(1.05/(.2126*rgb[0]+.7152*rgb[1]+.0722*rgb[2]+.05)>4.5);
});
