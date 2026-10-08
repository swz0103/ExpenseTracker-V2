const assert=require('node:assert/strict');
require('./interface-consistency.cjs');
const {run,context,node,docListeners}=require('./interaction-smoke.cjs');
function reset(){run("state=seed();month='2026-10';page='more';resetPickerPages();ledgerAdvanced=null;search='';categoryFilter='';filter='all';dateFilter='';ledgerAccountFilter=''");}
function click(dataset){const el={dataset};for(const handler of docListeners.click||[])handler({target:{closest:s=>s==='[data-action]'?el:null}});}
reset();

// Calendar weeks are continuous, including no-activity weeks, with exact end balances.
for(const id of ['cash','bank','digital','card']){
 context.__id=id;
 const series=run('accountWeeklySeries(account(__id),account(__id).kind==="card")');
 assert.equal(series.changes.length,4);
 assert.deepEqual(series.changes.map(w=>w.date).join(','),'2026-09-07,2026-09-14,2026-09-21,2026-09-28');
 assert.equal(series.periodOpening+series.changes.reduce((sum,w)=>sum+w.delta,0),series.running);
 assert.equal(series.running,run('account(__id).kind==="card"?Math.max(0,-balance(account(__id))):balance(account(__id))'));
 for(let i=1;i<4;i++)assert.equal(series.changes[i].before,series.changes[i-1].after);
}
run("state.tx=[]");
assert.ok(run("accountWeeklySeries(account('digital'),false).changes.every(w=>w.delta===0&&w.count===0)"));
run("account('digital').opening=0");assert.ok(run("accountWeeklyWaterfall(account('digital'),false)").includes('y="94.5"'));
run("state.tx=[{id:'cross',date:'2027-01-04',type:'income',amount:100,account:'cash'}]");
assert.equal(run("accountWeeklySeries(account('cash'),false).changes.map(w=>w.date).join(',')"),'2026-12-14,2026-12-21,2026-12-28,2027-01-04');
run("state.tx=[{id:'leap',date:'2028-03-01',type:'income',amount:100,account:'cash'}]");
assert.equal(run("accountWeeklySeries(account('cash'),false).changes.at(-1).date"),'2028-02-28');
assert.equal(run("accountWeeklySeries(account('cash'),false).changes.at(-1).count"),1);
run("state.tx=[{id:'old',date:'2026-01-01',type:'income',amount:100,account:'cash'},{id:'reversed',date:'2030-01-01',type:'expense',amount:999,account:'cash',reversed:true}]");
assert.equal(run("accountWeeklySeries(account('cash'),false).changes.at(-1).date"),'2026-09-28');
assert.equal(run("accountWeeklySeries(account('cash'),false).periodOpening"),36100);
run("state.tx=[{id:'payment',type:'transfer',date:'2026-10-02',account:'bank',to:'card',amount:10000}]");
assert.equal(run("accountWeeklySeries(account('card'),true).running"),0);
assert.equal(run("accountWeeklySeries(account('card'),true).changes.at(-1).delta"),-4680);

// Monthly comparisons use net expenses and never claim savings for an empty month.
reset();
run("state.tx=[{id:'old',date:'2026-09-01',type:'expense',amount:1000,account:'bank',category:'飲食日常'},{id:'new',date:'2026-10-01',type:'expense',amount:400,account:'bank',category:'飲食日常'},{id:'refund',date:'2026-10-02',type:'refund',amount:100,account:'bank',category:'飲食日常'},{id:'reversed',date:'2026-10-02',type:'expense',amount:999,account:'bank',category:'饮食日常',reversed:true}]");
const comparison=run('reportComparison()');assert.equal(comparison.delta,-700);assert.equal(comparison.rows[0].amount,300);assert.equal(comparison.rows[0].delta,-700);
assert.ok(run('reports()').includes('減少 700'));assert.ok(run('reports()').includes('至 4 日支出 · 較 9 月'));
run("month='2026-11'");assert.ok(run('reports()').includes('本月尚無支出'));assert.ok(!run('reports()').includes('減少 300'));
assert.ok(run('reports()').includes('data-action="entry"'));
assert.equal(run("previousMonth('2027-01')"),'2026-12');
run("month='2026-09'");assert.ok(run('reports()').includes('尚無比較基準'));assert.ok(!/NaN|Infinity/.test(run('reports()')));
run("state.tx=[{id:'refund',date:'2026-09-03',type:'refund',amount:900,account:'bank',category:'飲食日常'}]");
assert.ok(run('reports()').includes('淨退款'));assert.ok(run('utilityFlowRail(totals())').includes('class="refund" style="width:100%"'));

// Dividend cash is scoped to the selected month, independent of valuation fixtures.
reset();
run("state.tx.push({id:'monthly-dividend',date:'2026-10-02',type:'income',amount:1000,account:'bank',category:'股息收入',dividend:'0050'},{id:'old-dividend',date:'2026-09-02',type:'income',amount:2000,account:'bank',category:'股息收入',dividend:'0050'},{id:'reversed-dividend',date:'2026-10-02',type:'income',amount:9999,account:'bank',category:'股息收入',dividend:'0050',reversed:true})");
assert.equal(run('monthDividend()'),1000);
const investment=run('investments()');assert.ok(investment.includes('data-id="monthly-dividend"'));assert.ok(!investment.includes('data-id="old-dividend"'));assert.ok(!investment.includes('data-id="reversed-dividend"'));
assert.ok(investment.includes('未實現損益'));assert.ok(!investment.includes('holding-value-fill'));
assert.ok(run('overview()').includes('其中股息'));

// The queue displays what actually posted; template switches remain on a separate page.
reset();
run("Object.assign(state.tx.find(t=>t.recurring==='rent'),{amount:11900,account:'cash',date:'2026-10-03'})");
const row=run("recurringRow(state.recurring.find(r=>r.id==='rent'),'confirmed')");
assert.ok(row.includes('11,900'));assert.ok(!row.includes('12,500'));assert.ok(row.includes('隨身現金'));assert.ok(row.includes('<strong>3</strong>'));
assert.ok(!run('recurring()').includes('data-action="toggle-recurring"'));
click({action:'recurring-posted',id:'rent'});assert.ok(node('#modal-body').innerHTML.includes('11,900'));
click({action:'recurring-manage'});assert.equal(run('pickerCurrent().kind'),'recurring-settings');
click({action:'toggle-recurring',id:'internet'});assert.equal(run("state.recurring.find(r=>r.id==='internet').active"),false);assert.equal(run('pickerCurrent().kind'),'recurring-settings');assert.ok(node('#picker-content').innerHTML.includes('啟用家用網路'));
run('backPickerPage()');assert.equal(run('pickerStack.length'),0);

// Returning from a rebuilt nested page selects its original control without scrolling.
const oldQuery=context.document.querySelectorAll;let focused='';
const replacement={dataset:{action:'lf-amount-open',key:'min'},focus(options){assert.equal(options.preventScroll,true);focused='min';},classList:{add(){},remove(){}}};
const wrong={dataset:{action:'lf-amount-open',key:'max'},focus(){focused='wrong';}};
try{
 context.document.querySelectorAll=()=>[wrong,replacement];
 context.__oldTrigger={isConnected:false,dataset:{action:'lf-amount-open',key:'min'}};
 run("showPickerPage({kind:'filter-options',title:'金額',render:()=>''});showPickerPage({kind:'filter-calculator',title:'最低金額',trigger:__oldTrigger,render:()=>''});backPickerPage()");
 assert.equal(focused,'min');assert.equal(run('pickerStack.length'),1);
}finally{context.document.querySelectorAll=oldQuery;run('resetPickerPages()');}

// Large amounts stay exact; sparse details omit the empty note and unsafe text is escaped.
reset();
assert.equal(run('amountTextClass(100000000)'),'amount-long amount-wide');
assert.ok(run('entryCalculator(100000000,false,false)').includes('100,000,000'));
assert.ok(run('currencyControl("amount",100000000)').includes('amount-long amount-wide'));
assert.ok(run('currencyFigure(100000000)').includes('100,000,000'));
run("state.tx[0].note='';txDetail(state.tx[0].id)");assert.ok(!node('#modal-body').innerHTML.includes('entry-full-note'));
run("state.tx[0].note=state.tx[0].category;txDetail(state.tx[0].id)");assert.ok(!node('#modal-body').innerHTML.includes('entry-full-note'));
run("state.tx[0].note='<img src=x>\\n完整備註';txDetail(state.tx[0].id)");assert.ok(node('#modal-body').innerHTML.includes('&lt;img src=x&gt;'));assert.ok(!node('#modal-body').innerHTML.includes('<img'));
run("state.budgets.find(b=>b.id==='food').limit=1");const budgets=run('budgets()');assert.ok(budgets.indexOf('data-id="food"')<budgets.indexOf('data-id="home"'));
run('state.accounts=[]');assert.ok(run('accounts()').includes('data-action="account"'));
console.log('PASS: continuous four-week conservation, empty/cross-year/leap/overpaid-card cases; honest month comparisons and refunds; actual monthly dividends and confirmed records; independent recurring management, nested focus return, long exact amounts and concise notes.');
