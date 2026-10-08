const assert=require('node:assert/strict');
require('./record-management.cjs');
const {run,context,node,docListeners,windowListeners}=require('./interaction-smoke.cjs');

// Exercise the same history callbacks as system Back, including modal and child sheets.
let entries=[],cursor=-1;
const clone=value=>JSON.parse(JSON.stringify(value));
const pop=()=>{for(const callback of windowListeners.popstate||[])callback({state:clone(entries[cursor])});};
context.history={replaceState(value){if(cursor<0)cursor=0;entries[cursor]=clone(value);},pushState(value){entries=entries.slice(0,cursor+1);entries[++cursor]=clone(value);},back(){if(cursor>0){cursor--;pop();}}};
function reset(){entries=[];cursor=-1;run("state=seed();modalSession=null;overlayHistory=false;ignoredHistoryEvents=0;resetPickerPages();route('overview',{replace:true})");}
reset();
run("changePageMonth(-1);selectHeat(16);document.querySelector('.shell').scrollTop=230;route('ledger')");
assert.equal(run('month'),'2026-10');
run("ledgerAdvanced={...defaultLedgerFilters(),types:['income']};search='薪資';document.querySelector('.shell').scrollTop=408;route('more');route('investments');changePageMonth(1);navigateBack()");
assert.equal(run('page'),'more');assert.equal(run('month'),'2026-10');
run('navigateBack()');assert.equal(run('page'),'ledger');assert.equal(run('search'),'薪資');assert.equal(run('ledgerAdvanced.types[0]'),'income');assert.equal(node('.shell').scrollTop,408);
context.history.back();assert.equal(run('page'),'overview');assert.equal(run('month'),'2026-09');assert.equal(run('heatDay'),16);assert.equal(node('.shell').scrollTop,230);
cursor++;pop();assert.equal(run('page'),'ledger');assert.equal(run('search'),'薪資');
run("route('investments')");assert.equal(run('month'),'2026-11');run("route('settings')");assert.equal(run('month'),'2026-10');
run("route('accounts');selectedAccount='bank';route('account-detail');changePageMonth(-1);navigateBack();selectedAccount='cash';route('account-detail')");assert.equal(run('selectedAccount'),'cash');assert.equal(run('month'),'2026-10');
run("navigateBack();selectedAccount='bank';route('account-detail')");assert.equal(run('selectedAccount'),'bank');assert.equal(run('month'),'2026-09');
run("openEntry();showPickerPage({kind:'options',title:'帳戶',render:()=>''})");
context.history.back();assert.equal(run('pickerStack.length'),0);assert.equal(run('modalSession.active'),true);
context.history.back();assert.equal(run('modalSession.active'),false);assert.equal(run('page'),'account-detail');
run('openEntry();dismissModal()');assert.equal(run('ignoredHistoryEvents'),0);assert.equal(entries[cursor].overlay,undefined);
console.log('PASS: independent page/account periods, search/filter/day/scroll restoration; system Back, forward and nested sheet closure.');

// Minimal form DOM population, so drafts read real named controls rather than hand-fed state.
const body=node('#modal-body');let markup=body.innerHTML;
const decode=s=>String(s).replaceAll('&quot;','"').replaceAll('&#39;',"'").replaceAll('&lt;','<').replaceAll('&gt;','>').replaceAll('&amp;','&');
Object.defineProperty(body,'innerHTML',{configurable:true,get:()=>markup,set:value=>{
 markup=value;const controls=[];
 for(const match of value.matchAll(/<input\b([^>]*)>|<textarea\b([^>]*)>([\s\S]*?)<\/textarea>/g)){
  const attrs=Object.fromEntries([...String(match[1]||match[2]).matchAll(/([\w-]+)="([^"]*)"/g)].map(m=>[m[1],decode(m[2])]));if(!attrs.id)continue;
  const el=node('#'+attrs.id);Object.assign(el,{name:attrs.name||'',tagName:match[1]?'INPUT':'TEXTAREA',type:attrs.type||'text',value:match[1]?attrs.value||'':decode(match[3]||''),isConnected:true});el.defaultValue=el.value;controls.push(el);
 }
 node('#modal-form').elements=controls;
}});
node('#modal-form').reset=()=>{for(const el of node('#modal-form').elements||[])el.value=el.defaultValue;};
reset();run("openEntry('expense');document.querySelector('#f-note').value='尚未完成的午餐';document.querySelector('#f-amount').value='345';editCalcExpression='345';editCalcDirty=true;dismissModal()");
assert.equal(run('state.formDrafts.entry.fields.note'),'尚未完成的午餐');assert.equal(run('state.formDrafts.entry.record.amount'),345);
run('resumeEntry()');assert.equal(node('#f-note').value,'尚未完成的午餐');assert.equal(node('#f-amount').value,'345');assert.equal(run('editCalcExpression'),'345');
run("switchRecordType('income');document.querySelector('#f-category').value='其他收入';storeCurrentDraft();dismissModal();resumeEntry()");assert.equal(run('recordComposer.type'),'income');assert.equal(node('#f-note').value,'尚未完成的午餐');
context.__values=new Map(Object.entries({amount:'345',account:'cash',date:'2026-10-04',category:'其他收入',note:'完成'}));
run('modalHandler(__values);dismissModal({saved:true})');assert.equal(run('state.formDrafts.entry'),undefined);assert.equal(run('state.tx.at(-1).amount'),345);
run("txEdit(state.tx[0].id);document.querySelector('#f-note').value='編輯中的備註';dismissModal();txEdit(state.tx[0].id)");assert.equal(node('#f-note').value,'編輯中的備註');run('dismissModal()');
run("openAccount();document.querySelector('#f-name').value='新帳戶草稿';dismissModal();openAccount()");assert.equal(node('#f-name').value,'新帳戶草稿');run('discardCurrentDraft();resetCurrentDraft()');assert.equal(node('#f-name').value,'');assert.equal(run('state.formDrafts["account-new"]'),undefined);
run('dismissModal();openEntry();dismissModal()');assert.equal(run('state.formDrafts.entry'),undefined);
console.log('PASS: expense/income switch, edit and account drafts resume; successful submit clears only its draft; untouched and discarded forms do not create drafts.');

reset();run("globalThis.undoId=state.tx[0].id;globalThis.cashBefore=balance(account('cash'));globalThis.txBefore=JSON.stringify(state.tx);removeRecordWithUndo(undoId)");
assert.equal(run('state.tx.some(t=>t.id===undoId)'),false);assert.ok(node('#toast').innerHTML.includes('復原'));assert.ok(run('settings()').includes('undo-delete'));
run('undoDeletedRecord()');assert.equal(run('JSON.stringify(state.tx)'),run('txBefore'));assert.equal(run("balance(account('cash'))"),run('cashBefore'));assert.equal(run('state.undoDelete'),undefined);
run('undoDeletedRecord()');assert.equal(run('JSON.stringify(state.tx)'),run('txBefore'));
run("ledgerAdvanced={...defaultLedgerFilters(),types:['expense'],accounts:['bank'],min:'100',sources:['manual']};search='餐';removeFilterGroup('amount')");
assert.equal(run('ledgerAdvanced.min'),'');assert.equal(run('ledgerAdvanced.accounts[0]'),'bank');assert.equal(run('ledgerAdvanced.sources[0]'),'manual');assert.equal(run('search'),'餐');
run("removeFilterGroup('type')");assert.equal(run('ledgerAdvanced.types.length'),0);assert.equal(run('ledgerAdvanced.accounts[0]'),'bank');
run("openLedgerFilters()");assert.ok(node('#modal-body').innerHTML.includes('lf-primary-type'));assert.ok(node('#modal-body').innerHTML.includes('lf-primary-date'));assert.ok(run('ledgerFilterPages.advanced.body').includes('金額區間'));assert.ok(run('ledgerFilterPages.amount.body').includes('lf-amount-open'));run('dismissModal()');
console.log('PASS: deletion undo restores exact order and balances, survives toast dismissal; removing one filter preserves the rest.');

reset();run("state.holdings=[{id:'0050',name:'測試',openingQty:10,openingCost:100,qty:10,cost:100,price:10,dividend:0}];state.tx=[];commitLedgerTransactions([{id:'sell',type:'investment',amount:75,date:'2026-10-03',account:'bank',investment:{holding:'0050',side:'sell',qty:5}}])");
assert.equal(run('portfolioFacts().realized'),25);assert.equal(run('state.holdings[0].qty'),5);assert.equal(run('state.holdings[0].cost'),50);
run('removeRecordWithUndo("sell")');assert.equal(run('portfolioFacts().realized'),0);run('undoDeletedRecord()');assert.equal(run('portfolioFacts().realized'),25);
context.__quotes=[{Code:'0050',ClosingPrice:'15.25',Change:'0.25',Date:'1151006'}];run('applyQuoteImport(__quotes)');assert.equal(run('state.holdings[0].price'),15.25);assert.equal(run('holdingPreviousClose(state.holdings[0])'),15);assert.equal(run('state.holdings[0].quoteDate'),'2026-10-06');assert.equal(run('investmentToday().change'),1.25);
assert.ok(run('investments()').includes('匯入收盤'));assert.ok(run('quoteStatus(state.holdings[0])').includes('2026-10-06'));
context.__old=[{Code:'0050',ClosingPrice:'99',Change:'1',Date:'1151005'}];assert.throws(()=>run('applyQuoteImport(__old)'),/有效新價格/);assert.equal(run('state.holdings[0].price'),15.25);
run("state.holdings.push({id:'2330',name:'舊示意',qty:10,cost:10000,price:1043});");assert.equal(run('investmentToday().covered'),1);assert.equal(run('investmentToday().change'),1.25);
run("openQuoteEditor('0050')");context.__values=new Map([['price','15.67'],['date','2026-10-06']]);run('modalHandler(__values);dismissModal({saved:true})');assert.equal(run('state.holdings[0].price'),15.67);assert.equal(run('holdingPreviousClose(state.holdings[0])'),null);assert.ok(run('quoteStatus(state.holdings[0])').includes('手動價格'));
run("globalThis.priceCalc={expression:'15.67',fresh:false,dirty:true}");assert.equal(run("stepAmountCalculator(priceCalc,'完成',.01,2).completed"),true);
run("priceCalc.expression='15.671'");assert.equal(run("stepAmountCalculator(priceCalc,'完成',.01,2).completed"),false);
console.log('PASS: realized gains replay on sale/delete/undo; dated quote import and manual decimal editing; stale prices rejected and differing quote dates never combined.');

reset();run("state.chartScales={investment:'linear',waterfall:'linear'}");assert.equal(run('investmentBarWidth(.2,[.2,.1])'),50);assert.equal(run('investmentBarWidth(.1,[.2,.1])'),25);
const svg=run("accountWeeklyWaterfall(account('bank'),false)");assert.ok(svg.includes('等比例'));assert.ok(svg.includes('viewBox="0 0 320 120"'));assert.ok(!/NaN|Infinity/.test(svg));
const bars=[...svg.matchAll(/<rect class="waterfall-bar"[^>]*y="([\d.]+)"[^>]*height="([\d.]+)"/g)];assert.equal(bars.length,6);for(const [,y,h] of bars)assert.ok(Number(y)>=0&&Number(y)+Number(h)<100);
run("waterfallSelections.set('bank','2026-09-14');setChartScale('waterfall')");assert.match(run("accountWeeklyWaterfall(account('bank'),false)"),/class="waterfall-item [^"]*selected"[^>]*data-date="2026-09-14"/);
run('selectHeat(4)');const receiptTarget={closest:s=>s==='.daily-receipts'?{}:null};
for(const fn of docListeners.pointerdown||[])fn({target:receiptTarget,pointerId:21,clientX:200,clientY:100});
for(const fn of docListeners.pointerup||[])fn({target:receiptTarget,pointerId:21,clientX:100,clientY:105});
assert.equal(run('receiptPage'),1);assert.equal(run('dailyReceiptWindow().rows.length'),4);
for(const fn of docListeners.pointerdown||[])fn({target:receiptTarget,pointerId:22,clientX:100,clientY:100});
for(const fn of docListeners.pointerup||[])fn({target:receiptTarget,pointerId:22,clientX:180,clientY:300});
assert.equal(run('receiptPage'),1);
console.log('PASS: proportional bars and compact SVG bounds; selected week survives scale change; horizontal swipe pages while vertical scrolling does not.');
