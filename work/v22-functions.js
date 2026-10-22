function paperManagementHTML(){
 if(!state.paperManaging)return '';
 const count=matchingPapers().filter(p=>!deletionBlockReason('paper',p)).length;
 return `<p class="paper-delete-help">仅待完成练习卷可批量删除；待核对、已记录卷不可勾选。删除后可从最近删除恢复。</p><div class="paper-management-bar"><button class="text-button" data-action="paper-select-visible" ${!count?'disabled':''}>全选当前可删除（${count}）</button><button class="text-button" data-action="paper-clear-selection">清空选择</button></div>`;
}
function paperDeleteFooterHTML(){
 if(!state.paperManaging)return '';
 const selected=activePapers().filter(p=>state.paperDeleteSelection?.has(p.id)),visible=new Set(matchingPapers().map(p=>p.id)),hidden=selected.filter(p=>!visible.has(p.id)).length;
 return `<div class="sticky-action"><div class="manage-footer"><div class="paper-delete-summary">已选 ${selected.length} 份${hidden?`<small>其中 ${hidden} 份不在当前列表</small>`:''}</div><button class="btn danger" data-action="request-delete-selected-papers" ${!selected.length?'disabled':''}>删除所选练习卷</button></div></div>`;
}
function hasPendingDraft(p){return Boolean(p.gradingDraft&&!p.gradingDraft.committed);}
function hasPaperResults(p){return Boolean(p.completed||(p.attempts||[]).length||Object.keys(p.results||{}).length);}
function deletionBlockReason(kind,item){
 if(!item||item.deletedAt)return '内容已不存在或已移入最近删除，请刷新后重试';
 if(kind==='paper')return hasPendingDraft(item)?'批改待核对，暂不可删除':hasPaperResults(item)?'已记录练习结果，暂不可删除':'';
 if(kind!=='question')return '无法识别要删除的内容';
 if(pendingGradingFor(item.id))return '有批改待核对，暂不可删除';
 const latest=latestResult(item);
 return !latest?'尚未重做，暂不可删除':latest.result==='skip'?'':resultLabel(latest.result)+'，暂不可删除';
}
function deletionCheck(kind,ids){
 const collection=kind==='paper'?data.papers:kind==='question'?data.questions:[],unique=[...new Set(Array.isArray(ids)?ids:[])];
 if(!unique.length)return {items:[],blocked:[{reason:'请先选择要删除的内容'}]};
 const items=unique.map(id=>collection.find(item=>item.id===id));
 return {items,blocked:items.map(item=>({reason:deletionBlockReason(kind,item)})).filter(entry=>entry.reason)};
}
function rejectDeletion(check){
 state.deleteDraft=null;state.deleteSelection=new Set();state.paperDeleteSelection=new Set();render();
 const reasons=cleanTags(check.blocked.map(entry=>entry.reason));
 openModal('暂不能删除',`<p class="subtle">有 ${check.blocked.length} 项不符合删除条件，本次未删除任何内容。请根据最新状态重新选择。</p><ul class="delete-reasons">${reasons.map(reason=>`<li>${escapeHTML(reason)}</li>`).join('')}</ul><button class="btn primary full" data-action="close-modal">知道了</button>`);
 return false;
}
function deleteControl(kind,item,label,full=false){
 const reason=deletionBlockReason(kind,item);
 return `<div class="delete-control ${full?'full':''}"><button class="${full?'btn ghost full':'text-button'} delete-link" data-action="request-delete" data-kind="${kind}" data-id="${escapeHTML(item.id)}" ${reason?'disabled aria-disabled="true"':''}>${label}</button>${reason?`<p class="delete-note">${escapeHTML(reason)}</p>`:''}</div>`;
}
function activeQuestions(){return data.questions.filter(q=>!q.deletedAt);}
function activePapers(){return data.papers.filter(p=>!p.deletedAt);}
function migrateData(stored){const migrated=migrateDataV21Base(stored);let maximum=0;migrated.papers.forEach((p,i)=>{const titleMatch=String(p.title||'').match(/巩固练习\s*(\d+)$/),idMatch=String(p.id||'').match(/-(\d+)$/);const serial=Number(p.serialNumber)||(titleMatch?Number(titleMatch[1]):0)||(idMatch?Number(idMatch[1]):0)||i+1;p.serialNumber=serial;maximum=Math.max(maximum,serial);});migrated.nextPaperSerial=Math.max(maximum+1,Number(stored.nextPaperSerial)||1);migrated.schemaVersion=4;return migrated;}
function libraryQuestions(){return libraryQuestionsV21Base().filter(q=>!q.deletedAt);}
function eligible(){return eligibleV2Base().filter(q=>!q.deletedAt);}
function chosenQuestions(){return state.mode==='manual'?activeQuestions().filter(q=>state.manualSelected.has(q.id)):eligible().slice(0,state.practiceCount);}
function pendingGradingFor(questionId){return activePapers().filter(p=>hasPendingDraft(p)&&(p.gradingDraft.items||[]).some(i=>i.questionId===questionId)).sort((a,b)=>(b.gradingDraft.createdAt||0)-(a.gradingDraft.createdAt||0))[0]||null;}
function generatePaper(){const qs=chosenQuestions();if(!qs.length)return toast('请先选择题目');const serial=data.nextPaperSerial++,subjects=cleanTags(qs.map(q=>q.subject));const p={id:`paper-${Date.now()}-${serial}`,serialNumber:serial,title:`我的${subjects.length===1?subjects[0]:'综合'}巩固练习${serial}`,createdAt:Date.now(),questions:clone(qs),completed:false,results:{},attempts:[],gradingDraft:null};data.papers.push(p);persist();state.practiceSection='papers';state.tab='practice';navigate('preview',{paperId:p.id,paperAnswers:false,space:'medium',gradingAttempt:null});}
function practiceSection(){return state.practiceSection||(activePapers().length?'papers':'compose');}
function practiceTabs(){const section=practiceSection();return `<div class="practice-tabs" aria-label="练一练分区"><button class="${section==='compose'?'active':''}" data-action="practice-section" data-value="compose" aria-pressed="${section==='compose'}">生成练习卷</button><button class="${section==='papers'?'active':''}" data-action="practice-section" data-value="papers" aria-pressed="${section==='papers'}">我的练习卷 <span>${activePapers().length}</span></button></div>`;}
function paperStage(p){return hasPendingDraft(p)?'pending':hasPaperResults(p)?'recorded':'todo';}
function paperStageLabel(p){return paperStage(p)==='pending'?'待核对':paperStage(p)==='recorded'?'已记录':'待完成';}
function matchingPapers(){return activePapers().filter(p=>(!state.paperStatus||state.paperStatus==='all'||paperStage(p)===state.paperStatus)&&(!state.paperSearch||p.title.includes(state.paperSearch))).slice().reverse();}
function paperRows(){
 const ps=matchingPapers();
 if(!ps.length)return `<div class="empty">${icon('practice')}<p>${activePapers().length?'没有符合条件的练习卷':'还没有练习卷，先选几道题吧'}</p><button class="btn soft" style="margin-top:15px" data-action="practice-section" data-value="compose">去选题生成练习卷</button></div>`;
 return ps.map(p=>{const reason=deletionBlockReason('paper',p),selected=state.paperDeleteSelection?.has(p.id)&&!reason;
 return `<article class="paper-tile ${state.paperManaging?'manage-mode':''}">${state.paperManaging?`<button class="paper-select-toggle" data-action="paper-select-delete" data-id="${p.id}" aria-label="${escapeHTML((reason?'不可选择：':'选择练习卷：')+p.title+(reason?'，'+reason:''))}" aria-pressed="${Boolean(selected)}" ${reason?'disabled aria-disabled="true"':''}><span class="check">✓</span></button>`:''}<button class="paper-tile-main" data-action="open-paper" data-id="${p.id}"><span class="paper-icon">${icon('practice')}</span><div>${p.demoSample?`<p class="paper-sample-note">体验示例 · ${escapeHTML(p.demoNote)}</p>`:''}<h3>${escapeHTML(p.title)}</h3><p>${p.questions.length} 道题 · 出卷序号 ${p.serialNumber} · ${p.attempts.length} 次记录</p><span class="tag ${paperStage(p)==='pending'?'orange':paperStage(p)==='recorded'?'gray':''}">${paperStageLabel(p)}</span></div>${icon('chevron')}</button><div class="paper-tile-actions"><button class="text-button" data-action="paper-rename" data-id="${p.id}">修改名称</button>${deleteControl('paper',p,'删除')}</div></article>`;}).join('');
}
function practice(){
 if(!state.paperDeleteSelection)state.paperDeleteSelection=new Set();
 if(practiceSection()==='compose')return practiceV2Base().replace('<div class="mode-switch">',practiceTabs()+'<div class="mode-switch">').replace(/<div class="section-head"><h3>我的练习卷<\/h3>[\s\S]*$/,'');
 return `${appHeader('练一练','先出卷打印，做完后再回来拍照')}${practiceTabs()}${demoSampleBanner()}<div class="paper-manage-heading"><h3>我的练习卷</h3><div class="paper-manage-tools"><button class="btn small soft" data-action="paper-manage">${state.paperManaging?'完成管理':'管理练习卷'}</button><button class="text-button" data-action="open-trash" data-kind="paper">最近删除</button></div></div><div class="search">${icon('search')}<input id="paper-search" type="search" placeholder="搜索练习卷名称" aria-label="搜索练习卷" value="${escapeHTML(state.paperSearch||'')}"></div><div class="chip-row">${[['all','全部'],['todo','待完成'],['pending','待核对'],['recorded','已记录']].map(([v,t])=>`<button class="chip ${(state.paperStatus||'all')===v?'active':''}" data-action="paper-status" data-value="${v}">${t}</button>`).join('')}</div><p class="subtle" id="paper-list-count">共 ${matchingPapers().length} 份 · ${state.paperManaging?'只可勾选待完成卷':'点开练习卷，可打印、拍完成卷或查看记录'}</p><div id="paper-management">${paperManagementHTML()}</div><div id="paper-delete-footer">${paperDeleteFooterHTML()}</div><div id="paper-list" style="margin-top:14px">${paperRows()}</div>`;
}
function preview(){const p=currentPaper();if(!p)return previewV2Base();if(p.deletedAt)return `${appHeader('练习卷已删除','历史结果保留，可从最近删除恢复','practice')}<div class="card"><h3>${escapeHTML(p.title)}</h3><p class="subtle" style="margin:12px 0">这份卷子已移入最近删除，不能继续修改、打印或拍照。恢复后可继续使用。</p><button class="btn primary full" data-action="restore-deleted" data-kind="paper" data-id="${p.id}">恢复这份练习卷</button></div>`;const title=`<button class="paper-title-edit" data-action="rename-paper"><strong>${escapeHTML(p.title)}</strong><span>点击修改名称</span></button><div class="paper-stage-note"><span class="tag">${paperStageLabel(p)}</span><p>${hasPendingDraft(p)?'批改草稿已暂存，可以继续核对。':hasPaperResults(p)?'已保存练习记录，可以重新打印，再做一次。':'第一阶段：预览、打印，再到纸上做题。生成后已经自动保存，不必现在拍照。'}</p></div>`;let html=previewV2Base().replace('<div class="mode-switch">',title+'<div class="mode-switch">');html=html.replace('拍完成卷，记录结果','做完后，拍完成卷核对');return html+`<button class="btn full" style="margin-top:12px" data-action="return-to-papers">稍后再做，回到我的练习卷</button><p class="subtle" style="line-height:1.8;margin:10px 0">做完后：练一练 → 我的练习卷 → 找到这份卷 → 拍完成卷核对。打印窗口打开不代表已经完成练习。</p>${deleteControl('paper',p,'删除这份练习卷',true)}`;}
function cards(qs){
 if(!state.libraryManaging||!qs.length)return cardsV21Base(qs);
 return qs.map(q=>{const reason=deletionBlockReason('question',q),selected=state.deleteSelection?.has(q.id)&&!reason;
 return `<button class="pick-card delete-pick ${selected?'active':''}" data-action="question-select-delete" data-id="${q.id}" aria-pressed="${Boolean(selected)}" ${reason?'disabled aria-disabled="true"':''}><span class="check">✓</span><div>${questionHTML(q)}<div class="tag-row" style="margin-top:8px">${tagsHTML(q.topics)}</div>${lastResultHTML(q)}<small>${escapeHTML(q.subject)} · ${escapeHTML(q.grade)}</small><small class="${reason?'delete-note':'delete-allowed'}">${escapeHTML(reason||'可删除 · 最近确认结果为暂未做')}</small></div></button>`;}).join('');
}
function library(){if(!state.deleteSelection)state.deleteSelection=new Set();const controls=`<div class="library-actions"><button class="btn small soft" data-action="question-manage">${state.libraryManaging?'完成管理':'管理错题'}</button><button class="text-button" data-action="open-trash" data-kind="question">最近删除</button></div>`;let html=libraryV21View().replace('<section class="hero">',controls+demoSampleBanner()+(state.libraryManaging?notice('仅最近确认结果为暂未做、且没有待核对批改的错题可删除。尚未重做不属于暂未做。'):'')+'<section class="hero">');if(state.libraryManaging){const selected=[...state.deleteSelection].filter(id=>activeQuestions().some(q=>q.id===id));html+=`<div class="sticky-action"><div class="manage-footer"><span>已选 ${selected.length} 道</span><button class="btn danger" data-action="request-delete-selected" ${!selected.length?'disabled':''}>删除所选</button></div></div>`;}return html;}
function detail(){const q=data.questions.find(q=>q.id===state.detailId);if(!q)return detailV21View();if(q.deletedAt)return `${appHeader('错题已删除','从最近删除恢复后可继续使用','library')}<div class="card">${questionHTML(q)}<button class="btn primary full" style="margin-top:17px" data-action="restore-deleted" data-kind="question" data-id="${q.id}">恢复这道错题</button></div>`;return detailV21View()+`${deleteControl('question',q,'删除这道错题',true)}`;}
function settings(){return settingsV2Base().replace('<div class="settings-list">','<div class="settings-list"><button data-action="open-trash" data-kind="question"><span>最近删除 · 错题与练习卷</span>'+icon('chevron')+'</button>');}
function gradeResults(){const html=gradeResultsV2Base();return currentPaper()?.deletedAt?notice('所属练习卷已删除，这里仅保留历史批改对照。恢复后可继续使用。')+html:html;}
function requestDelete(kind,ids){
 state.deleteDraft=null;
 const check=deletionCheck(kind,ids);if(check.blocked.length)return rejectDeletion(check);
 state.deleteDraft={kind,ids:check.items.map(item=>item.id)};
 openModal(kind==='paper'?`删除 ${check.items.length} 份待完成练习卷？`:`删除 ${check.items.length} 道暂未做错题？`,`<p class="subtle" style="line-height:1.9">${kind==='paper'?'仅待完成练习卷可删除。所选卷将移入最近删除，题库中的错题和既有练习记录保留。':'这些题最近一次确认结果均为暂未做，且没有待核对批改。删除后不再出现在题库和新组卷选题中；历史练习卷快照、分类和所有结果仍然保留。'}<br><br>可以在最近删除中恢复。本 Demo 不自动永久清理。</p><div class="bottom-actions"><button class="btn" data-action="close-modal">取消</button><button class="btn danger" data-action="confirm-delete">移入最近删除</button></div>`);
 state.modal.deletionConfirmation=true;
}
function softDeleteItems(kind,ids){
 const check=deletionCheck(kind,ids);if(check.blocked.length)return rejectDeletion(check);
 const valid=new Set(check.items.map(item=>item.id)),deletedAt=Date.now();
 check.items.forEach(item=>{item.deletedAt=deletedAt;});
 if(kind==='question'){valid.forEach(id=>{state.manualSelected.delete(id);state.deleteSelection?.delete(id);});state.libraryManaging=false;}
 if(kind==='paper'){state.paperDeleteSelection=new Set();state.paperManaging=false;if(valid.has(state.paperId))state.gradingAttempt=null;}
 state.deleteDraft=null;state.modal=null;persist();
 if(kind==='paper'){state.practiceSection='papers';navigate('practice');}else navigate('library');
 toast('已移入最近删除，可恢复');return true;
}
function restoreDeleted(kind,id){const item=(kind==='paper'?data.papers:data.questions).find(item=>item.id===id);if(!item?.deletedAt)return;item.deletedAt=null;persist();render();toast('已恢复，原有分类与记录保留');}
function trash(){const kind=state.trashKind||'question',qs=data.questions.filter(q=>q.deletedAt),ps=data.papers.filter(p=>p.deletedAt),items=kind==='paper'?ps:qs;return `${appHeader('最近删除','可恢复，本演示不自动永久清理',state.trashBack||'library')}<div class="mode-switch"><button class="${kind==='question'?'active':''}" data-action="trash-kind" data-value="question">错题 ${qs.length}</button><button class="${kind==='paper'?'active':''}" data-action="trash-kind" data-value="paper">练习卷 ${ps.length}</button></div>${notice('删除和恢复各自独立。删除错题不改动历史卷；删除卷子不删除题库和已经确认的结果。')}${items.length?items.slice().reverse().map(item=>`<div class="card"><div style="margin-bottom:13px">${kind==='paper'?`<h3 style="font-size:15px">${escapeHTML(item.title)}</h3><p class="subtle">${item.questions.length} 道题 · 原状态：${paperStageLabel(item)}</p>`:questionHTML(item)}</div><button class="btn soft full" data-action="restore-deleted" data-kind="${kind}" data-id="${item.id}">恢复${kind==='paper'?'练习卷':'错题'}</button></div>`).join(''):'<div class="empty">这里没有最近删除的内容</div>'}`;}
document.addEventListener('click',event=>{const target=event.target.closest('[data-action]');if(!target||target.disabled)return;const {action,value,id,kind}=target.dataset;switch(action){case 'practice-section':state.paperManaging=false;state.paperDeleteSelection=new Set();state.practiceSection=value;state.tab='practice';navigate('practice');break;case 'return-to-papers':state.practiceSection='papers';state.paperStatus='all';state.paperSearch='';navigate('practice');break;case 'paper-status':state.paperStatus=value;render();break;
 case 'paper-manage':state.paperManaging=!state.paperManaging;state.paperDeleteSelection=new Set();render();break;
 case 'paper-select-delete':{const p=data.papers.find(p=>p.id===id),reason=deletionBlockReason('paper',p);if(reason){toast(reason);break;}if(!state.paperDeleteSelection)state.paperDeleteSelection=new Set();state.paperDeleteSelection.has(id)?state.paperDeleteSelection.delete(id):state.paperDeleteSelection.add(id);render();break;}
 case 'paper-select-visible':if(!state.paperDeleteSelection)state.paperDeleteSelection=new Set();matchingPapers().filter(p=>!deletionBlockReason('paper',p)).forEach(p=>state.paperDeleteSelection.add(p.id));render();break;
 case 'paper-clear-selection':state.paperDeleteSelection=new Set();render();break;
 case 'request-delete-selected-papers':requestDelete('paper',[...(state.paperDeleteSelection||new Set())]);break;case 'paper-rename':{const p=data.papers.find(p=>p.id===id&&!p.deletedAt);if(!p)return;state.paperId=p.id;openModal('修改练习卷名称',`<label class="field"><span>名称</span><input id="paper-title" maxlength="24" value="${escapeHTML(p.title)}"></label><p class="subtle">改名不会占用新的出卷序号。</p><button class="btn primary full" style="margin-top:14px" data-action="save-paper-title">保存名称</button>`);break;}case 'add-to-paper':case 'saved-practice':state.practiceSection='compose';render();break;case 'question-manage':state.libraryManaging=!state.libraryManaging;state.deleteSelection=new Set();render();break;case 'question-select-delete':{const q=data.questions.find(q=>q.id===id),reason=deletionBlockReason('question',q);if(reason){toast(reason);break;}state.deleteSelection.has(id)?state.deleteSelection.delete(id):state.deleteSelection.add(id);render();break;}case 'request-delete':requestDelete(kind,[id]);break;case 'request-delete-selected':requestDelete('question',[...(state.deleteSelection||new Set())]);break;case 'confirm-delete':if(state.deleteDraft&&state.modal?.deletionConfirmation)softDeleteItems(state.deleteDraft.kind,state.deleteDraft.ids);break;case 'close-modal':case 'close-modal-render':state.deleteDraft=null;break;case 'backdrop-close':if(event.target===target)state.deleteDraft=null;break;case 'open-trash':state.trashKind=kind||'question';state.trashBack=state.page==='practice'?'practice':'library';navigate('trash');break;case 'trash-kind':state.trashKind=value;render();break;case 'restore-deleted':restoreDeleted(kind,id);break;}});
document.addEventListener('input',event=>{if(event.target.id==='paper-search'){state.paperSearch=event.target.value;document.getElementById('paper-list').innerHTML=paperRows();document.getElementById('paper-list-count').textContent=`共 ${matchingPapers().length} 份`;document.getElementById('paper-management').innerHTML=paperManagementHTML();document.getElementById('paper-delete-footer').innerHTML=paperDeleteFooterHTML();}});
NOTES.practice=['选题与找卷，分开更清楚','顶部随时切换生成练习卷和我的练习卷。',['先生成并打印，再去纸上做题','以后从我的练习卷找回，拍完成卷','名称可改，待完成卷可单个或批量删除'],'试试：生成后返回我的练习卷'];
NOTES.preview=['先打印，做完后再回来','这份卷子已自动保存，现在不需要拍照。',['点击卷名可以直接改名','打印后可退出，纸上做完再回来','同卷重印不占号，新一次拍卷保留历史'],'试试：点“稍后再做”回到卷列表'];
NOTES.trash=['删错了，也能找回来','错题和练习卷分别恢复，保留原有记录。',['移入后从活跃列表隐藏','历史卷与已确认结果不会级联丢失','当前原型不自动永久清理'],'试试：恢复一题或一份卷'];
