const fs=require('fs'),vm=require('vm');
const html=fs.readFileSync('outputs/shiti-demo.html','utf8');
const source=html.match(/<script>([\s\S]*?)<\/script>/)[1];
function boot(stored=null,options={}){
 const elements=new Map(),events={},saved=new Map();if(stored)saved.set('shiti-interactive-demo-v1',JSON.stringify(stored));
 function el(id){if(!elements.has(id))elements.set(id,{innerHTML:'',textContent:'',value:'',checked:false,hidden:false,scrollTop:0,classList:{toggle(){}},addEventListener(){},querySelector(){return null;},querySelectorAll(){return []},appendChild(){},focus(){},click(){},remove(){}});return elements.get(id);}
 const document={getElementById:el,addEventListener(t,h){const previous=events[t];events[t]=previous?event=>{previous(event);h(event)}:h;},querySelector(){return null},querySelectorAll(){return []},createElement(){return el('created')}};
 const context=vm.createContext({document,localStorage:{getItem:k=>saved.get(k)||null,setItem:(k,v)=>saved.set(k,v)},console,setTimeout:()=>0,clearTimeout(){},window:{print(){}},URL,Date,Set,Map});
 Object.defineProperty(context,'top',{value:context,writable:false,configurable:false,enumerable:true});vm.runInContext(source,context);
 // Existing business-flow checks use the original eight-question fixture.
 // Sample-data checks opt into the unmodified first-launch experience.
 if(!stored&&!options.samples)vm.runInContext("data.questions=data.questions.filter(q=>!q.demoSample);data.papers=data.papers.filter(p=>!p.demoSample);data.nextPaperSerial=1;delete data.deletionSampleVersion;state=initialState();render();",context);
 return {el,saved,read:code=>vm.runInContext(code,context),event(type,target){events[type]({target})},click(action,extra={}){events.click({target:{closest(){return {dataset:{action,...extra},disabled:false}}}})}};
}

module.exports={boot,html};
