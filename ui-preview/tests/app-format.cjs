const assert=require('node:assert/strict');
const fs=require('node:fs');
require('./design-refinement.cjs');
const {run,context,node,docListeners}=require('./interaction-smoke.cjs');
function reset(){run("state=seed();month='2026-10';page='overview';selectedAccount='cash';resetPickerPages();ledgerAdvanced=null;search='';categoryFilter='';filter='all';dateFilter='';ledgerAccountFilter=''");}
function fire(name,target,extra={}){for(const handler of docListeners[name]||[])handler({target,...extra});}
function tap(el){fire('click',{closest:s=>['[data-action]','[data-action="waterfall-info"]'].includes(s)?el:null});}
function appMarkup(markup,label){
  assert.ok(!/<(?:title|select|details)\b|\stitle\s*=|type="(?:date|number|month|time)"/.test(markup),label+' must not expose browser selectors or tooltips');
  assert.ok(!/class="(?:form-note|utility-form-note|utility-footnote|chart-hint|lf-hint|lf-footnote|picker-date-context)/.test(markup),label+' has explanatory copy');
}
reset();
for(const page of ['overview','ledger','accounts','account-detail','reports','categories','investments','budgets','recurring','settings','more']){
  context.__page=page;run('route(__page)');appMarkup(node('#main').innerHTML,page);
}
for(const action of ["openEntry('expense')","openEntry('income')","transfer()","txEdit(state.tx[0].id)","txDetail(state.tx[0].id)","openAccount()","editBudget('total')","newRecurring()","dividend()","holding(state.holdings[0].id)","ledgerSearch()","openLedgerFilters()"]){
  run(action);appMarkup(node('#modal-body').innerHTML,action);assert.equal(run('pickerStack.length'),0,'No form opens a calculator automatically');
}
assert.ok(!run('overview()').includes('id="budget-status"'));
assert.ok(!run('more()').includes('功能入口'));
assert.ok(!run('settings()').includes('來源專案'));
console.log('PASS: every page and primary form uses app controls, with no browser tooltips, native selectors or explanatory footnotes.');

// The selected amount follows its bar; complete weekly facts remain in accessible labels.
reset();
const markup=run("accountWeeklyWaterfall(account('cash'),false)");
const elements=[...markup.matchAll(/<g class="waterfall-item [^"]*"([^>]*data-action="waterfall-info"[^>]*)>/g)].map(match=>{
  const attrs=Object.fromEntries([...match[1].matchAll(/([\w-]+)="([^"]*)"/g)].map(m=>[m[1],m[2]]));
  return {dataset:Object.fromEntries(Object.entries(attrs).filter(([k])=>k.startsWith('data-')).map(([k,v])=>[k.slice(5),v])),attributes:attrs,classList:{toggle(){}},setAttribute(k,v){this.attributes[k]=v;}};
});
assert.equal(elements.length,4);assert.ok(markup.includes('viewBox="0 0 320 120"'));
assert.ok(!markup.includes('waterfall-inspector'));
const originalQuery=context.document.querySelectorAll;
try{
  context.document.querySelectorAll=s=>s==='[data-action="waterfall-info"]'?elements:[];
  tap(elements[0]);
  assert.ok(!node('#waterfall-detail').innerHTML.includes('waterfall-range'));
  assert.ok(elements[0].attributes['aria-label'].includes(run("waterfallDateRange('"+elements[0].dataset.date+"')")));
  assert.ok(node('#waterfall-detail').innerHTML.includes(run('utilitySigned('+elements[0].dataset.delta+')')));
  assert.equal((node('#waterfall-detail').innerHTML.match(/<text /g)||[]).length,1,'Only the selected amount appears above its bar');
  assert.ok(elements[0].attributes['aria-label'].includes('週初 '+Number(elements[0].dataset.before).toLocaleString('zh-TW')));
  assert.equal(elements[0].attributes['aria-pressed'],'true');
  const first=node('#waterfall-detail').innerHTML;
  tap(elements[0]);assert.equal(node('#waterfall-detail').innerHTML,first,'Repeated taps keep the integrated readout');
  tap(elements[3]);
  assert.equal(elements[0].attributes['aria-pressed'],'false');assert.equal(elements[3].attributes['aria-pressed'],'true');
  assert.ok(node('#waterfall-detail').innerHTML.includes(run('utilitySigned('+elements[3].dataset.delta+')')));
  assert.ok(elements[3].attributes['aria-label'].includes('週末 '+Number(elements[3].dataset.after).toLocaleString('zh-TW')));
  assert.ok(elements[3].attributes['aria-label'].includes(elements[3].dataset.count+' 筆'));
  const last=node('#waterfall-detail').innerHTML;
  fire('click',{closest:()=>null});assert.equal(node('#waterfall-detail').innerHTML,last,'Readout does not disappear or resize on outside taps');
  fire('pointerover',{closest:s=>s==='[data-action="waterfall-info"]'?elements[2]:null},{pointerType:'mouse'});
  assert.equal(elements[2].attributes['aria-pressed'],'true');
  fire('focusin',{closest:()=>elements[1]});assert.equal(elements[1].attributes['aria-pressed'],'true');
  assert.ok(!node('#waterfall-detail').innerHTML.includes('<div'));
}finally{context.document.querySelectorAll=originalQuery;}
assert.ok(run("waterfallDetail({date:'2026-09-28',count:2,delta:-300,before:500,after:200},true)").includes('waterfall-value good'));
assert.ok(run("waterfallDetail({date:'2026-09-28',count:2,delta:300,before:500,after:800},true)").includes('waterfall-value bad'));
console.log('PASS: amount-only bar label, accessible full weekly facts, card debt semantics, touch/hover/focus selection and no overlay.');

// The fixed currency column is shared by expense, income, transfer and their detail/edit screens.
reset();
for(const type of ['expense','income','transfer']){
  context.__type=type;
  run("state.tx.push({id:'layout',type:__type,date:'2026-10-04',amount:100000000,account:'bank',to:__type==='transfer'?'cash':undefined,category:__type==='income'?'薪資收入':__type==='expense'?'飲食日常':'轉帳',note:'完整\\n備註'});txDetail('layout')");
  const detail=node('#modal-body').innerHTML;
  assert.ok(detail.includes('<span class="entry-amount-unit">TWD</span><span class="entry-amount-value">'));
  assert.ok(detail.includes('100,000,000'));assert.ok(detail.includes(run("composerDateText('2026-10-04')")));
  assert.ok(detail.includes('完整\n備註'));assert.ok(!detail.includes('data-action="field-calc"'));
  assert.equal(node('#modal-submit').attributes['data-action'],'tx-delete-confirm');
  assert.equal(node('#modal .modal-actions .secondary').attributes['data-action'],'tx-edit');
  run("txEdit('layout')");assert.ok(node('#modal-body').innerHTML.includes('<span class="entry-amount-unit">TWD</span><span class="entry-amount-value">'));
  assert.ok(node('#modal-body').innerHTML.includes('data-action="field-calc"'));assert.equal(run('pickerStack.length'),0);
  run("state.tx=state.tx.filter(t=>t.id!=='layout')");
}
run('state.tx[0].reversed=true;txDetail(state.tx[0].id)');assert.equal(node('#modal .modal-actions .secondary').disabled,true);assert.ok(node('#modal-body').innerHTML.includes('已撤銷'));

// Native validation is disabled; app validation blocks mutation and keeps the dialog open.
reset();run('newRecurring()');
const form=node('#modal-form'),modal=node('#modal'),oldClose=modal.close,oldFormData=context.FormData;
let closes=0,focused=false;
const input={tagName:'INPUT',type:'text',value:'   ',required:true,maxLength:40,labels:[{textContent:'交易名稱'}],attributes:{},classList:{add(){},remove(){}},setAttribute(k,v){this.attributes[k]=v;},removeAttribute(k){delete this.attributes[k];},focus(options){assert.equal(options.preventScroll,true);focused=true;},closest:s=>s==='#modal-form'?form:null};
const count=run('state.recurring.length');
try{
  form.elements=[input];modal.close=()=>closes++;
  context.FormData=class{constructor(){return new Map([['name',input.value],['amount','180'],['account','cash'],['category','飲食日常'],['day','5']]);}};
  const submit=()=>form.listeners.submit({preventDefault(){},target:form});
  submit();assert.equal(closes,0);assert.equal(run('state.recurring.length'),count);assert.equal(node('#modal-error').hidden,false);assert.ok(focused);assert.equal(input.attributes['aria-invalid'],'true');
  input.value='超'.repeat(41);submit();assert.equal(closes,0);assert.ok(node('#modal-error').textContent.includes('40 字'));
  input.value='每月咖啡';fire('input',input);assert.equal(node('#modal-error').hidden,true);assert.ok(!input.attributes['aria-invalid']);
  submit();assert.equal(closes,1);assert.equal(run('state.recurring.length'),count+1);
}finally{form.elements=[];modal.close=oldClose;context.FormData=oldFormData;}
assert.ok(fs.readFileSync('dist/index.html','utf8').includes('id="modal-form" novalidate'));
run('ledgerSearch()');node('#f-keyword').value='便當';let searchFocused=false;node('#f-keyword').focus=()=>searchFocused=true;
fire('click',{closest:s=>s==='[data-action]'?{dataset:{action:'search-input-clear'}}:null});
assert.equal(node('#f-keyword').value,'');assert.ok(searchFocused);
console.log('PASS: fixed currency in create/edit/detail, full record facts and notes, reversed-record controls, inline validation prevents invalid mutations, and app search clears without leaving.');

// More is a single six-tool grid; calculators keep the semantic tone of their source.
reset();
const more=run('more()');
assert.equal((more.match(/class="more-tool-grid"/g)||[]).length,1);
assert.equal((more.match(/class="more-tool"/g)||[]).length,6);
assert.ok(!more.includes('more-tool-family'));
for(const tone of ['expense','income','transfer','neutral']){
  context.__tone=tone;node('#f-amount').value='180';
  run("openFieldCalculator({dataset:{name:'amount',tone:__tone,min:'1'}})");
  assert.equal(node('#picker-page').attributes['data-tone'],tone);
  run('backPickerPage()');
}
run('newRecurring()');assert.ok(node('#modal-body').innerHTML.includes('data-tone="expense"'));
run('dividend()');assert.ok(node('#modal-body').innerHTML.includes('data-tone="income"'));
run("editBudget('total')");assert.ok(node('#modal-body').innerHTML.includes('data-tone="neutral"'));
console.log('PASS: one six-tool More grid and consistent income/expense/transfer/neutral calculator context.');
