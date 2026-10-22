const fs=require('fs'),vm=require('vm');
const script=fs.readFileSync('outputs/shiti-demo.html','utf8').match(/<script>([\s\S]*?)<\/script>/)[1];
const elements=new Map(),events={},saved=new Map();
function el(id){if(!elements.has(id))elements.set(id,{innerHTML:'',textContent:'',value:'',checked:false,hidden:false,scrollTop:0,classList:{toggle(){}},addEventListener(){},querySelector(){return null;},querySelectorAll(){return []},appendChild(){},focus(){},click(){},remove(){}});return elements.get(id);}
const document={getElementById:el,addEventListener(t,h){events[t]=h;},querySelector(){return null;},querySelectorAll(){return []},createElement(){return el('created');}};
const context=vm.createContext({document,localStorage:{getItem:k=>saved.get(k)||null,setItem:(k,v)=>saved.set(k,v)},console,setTimeout:()=>0,clearTimeout(){},window:{print(){}},URL,Date,Set,Map});
// Browsers reserve window.top as a non-configurable, read-only global property.
Object.defineProperty(context,'top',{value:context,writable:false,configurable:false,enumerable:true});
vm.runInContext(script,context);
const read=source=>vm.runInContext(source,context);
function click(action,extra={}){events.click({target:{closest(){return {dataset:{action,...extra},disabled:false}}}});}
function verify(condition,label){if(!condition)throw Error(label);console.log('PASS '+label);}
verify(el('screen').innerHTML.includes('共 4 道'),'initial pending count');
verify(el('app-nav').innerHTML.includes('拍试卷'),'initial bottom navigation populated');
verify(el('brand-icon').innerHTML.includes('<svg'),'brand icon initialized');
verify(el('companion-note').innerHTML.includes('错题本，不只是收藏夹'),'companion content initialized');
click('go',{page:'scan'});verify(el('screen').innerHTML.includes('模拟拍摄一张试卷'),'bottom scan navigation opens scan screen');
click('sample-scan');click('scan-pick',{id:'s1'});click('scan-pick',{id:'s2'});click('scan-next');
el('save-subject').value='数学';el('save-grade').value='六年级';el('save-topic').value='per-question';el('save-cause').value='计算出错';click('save-scan');
verify(read('data.questions.length')===8,'save two selected questions');
click('save-scan');verify(read('data.questions.length')===8,'no duplicate save');
click('saved-practice');verify(read('chosenQuestions().length')===2,'practice with newly saved questions');
click('generate-paper');verify(read('currentPaper().questions.length')===2,'paper snapshot has selected questions');
verify(!el('screen').innerHTML.includes('答案：4/5'),'student preview hides answers');
click('start-review');click('review-result',{value:'correct'});click('review-next');click('review-result',{value:'wrong'});click('review-next');
verify(read('currentPaper().completed'),'review completion');
verify(read('data.questions[0].history.length')===1,'history updated');
read('finishReview()');verify(read('data.questions[0].history.length')===1,'completed review not counted twice');
read("navigate('practice');state.mode='auto';state.practiceTopics=new Set(['方程']);state.includeMastered=false;render()");
verify(read('chosenQuestions().length')===0,'empty topic does not use unrelated questions');
read('state.includeMastered=true;render()');verify(read('chosenQuestions().length')===1,'include mastered option');
read('state.paperId=data.papers[0].id;state.paperAnswers=false;preparePrint()');verify(!el('print-root').innerHTML.includes('答案：'),'student print hides answers');
read('state.paperAnswers=true;preparePrint()');verify(el('print-root').innerHTML.includes('答案：4/5'),'parent print includes answers');
verify(saved.has('shiti-interactive-demo-v1'),'storage state written');
read("navigate('detail',{detailId:data.questions[0].id,answer:false})");verify(!el('screen').innerHTML.includes('参考答案：'),'detail answer hidden initially');
const copy=JSON.parse(saved.get('shiti-interactive-demo-v1'));verify(copy.questions.length===8&&copy.papers[0].completed,'persisted state contains questions and completed paper');
console.log('State smoke checks passed. Browser DOM/layout/printing were not exercised.');
