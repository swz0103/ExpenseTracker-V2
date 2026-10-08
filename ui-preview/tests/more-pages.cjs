const assert=require('node:assert/strict');
const {run,context,node,docListeners}=require('./interaction-smoke.cjs');
function click(dataset){
  const el={dataset};
  for(const handler of docListeners.click||[])handler({target:{closest:selector=>selector==='[data-action]'?el:null}});
}
function submit(values){context.__form=new Map(Object.entries(values));run('modalHandler(__form)');}
function reset(){run("state=seed();month='2026-10';page='more';filter='all';search='';categoryFilter='';dateFilter='';ledgerAccountFilter='';ledgerAdvanced=null");}
reset();

// New monthly summaries use posted amounts, including refunds and reversals.
run("state.tx.push({id:'refund-test',type:'refund',amount:4000,account:'bank',category:'飲食日常',date:'2026-10-04'},{id:'excluded-test',type:'expense',amount:999,account:'bank',category:'其他支出',date:'2026-10-04',reversed:true})");
assert.equal(run('totals().expense'),13519);
assert.equal(run("categoryOverviewFacts('expense').find(r=>r.name==='飲食日常').amount"),-930);
assert.ok(run('reports()').includes('淨退款'));
assert.ok(run('reports()').includes('13,519'));
assert.ok(!run('categoryOverview()').includes('+930'));
assert.ok(run('reports()').includes('38,481'));

// A category tap must show its entire month, regardless of earlier account/day filters.
run("ledgerAccountFilter='cash';dateFilter='2026-10-03';search='old';ledgerAdvanced={scope:'all'}");
click({action:'category',category:'飲食日常',type:'expense'});
assert.equal(run('page'),'ledger');
assert.equal(run('dateFilter'),'');assert.equal(run('ledgerAccountFilter'),'');assert.equal(run('search'),'');
assert.equal(run('ledgerAdvanced'),null);
assert.ok(run("ledgerFilteredTransactions().some(t=>t.id==='refund-test')"));
assert.ok(run("ledgerFilteredTransactions().some(t=>t.account==='card')"));
run("ledgerAccountFilter='card';dateFilter='2026-10-03';search='old'");
click({action:'home-income'});
assert.equal(run('ledgerFilteredTransactions().length'),1);
assert.equal(run('ledgerFilteredTransactions()[0].amount'),52000);

// Budget status remains exact for refunds, overspending and imported zero limits.
reset();
run("state.budgets.find(b=>b.id==='food').limit=3000");
assert.equal(run("budgetFacts(state.budgets.find(b=>b.id==='food')).remaining"),-70);
assert.ok(run('budgets()').includes('超支 70'));
run('state.budgets.forEach(b=>b.limit=0)');
assert.ok(!/NaN|Infinity/.test(run('budgets()')));
assert.ok(run('budgets()').includes('未設定'));
run('state.tx=[]');assert.ok(!/NaN|Infinity/.test(run('budgets()')));

// Portfolio charts compare actual fixture value/cost, with no fabricated history.
reset();
const portfolio=run('portfolioFacts()');
assert.equal(portfolio.value,run('investmentTotal()'));
assert.equal(portfolio.profit,portfolio.value-portfolio.cost);
assert.equal((run('investments()').match(/data-action="holding"/g)||[]).length,12);
assert.ok(!run('investments()').includes('示意走勢'));
run("state.holdings=[{id:'ZERO',name:'零成本',qty:10,price:20,cost:0,dividend:0}]");
assert.equal(run('portfolioFacts().rate'),null);
assert.ok(!/NaN|Infinity/.test(run('investments()')));
run('state.holdings=[]');assert.ok(run('investments()').includes('目前沒有持股'));
run('dividend()');assert.ok(node('#toast').textContent.includes('沒有'));

// Pending, confirmed and paused entries are mutually exclusive and ordered by due date.
reset();
click({action:'toggle-recurring',id:'internet'});
const recurringMarkup=run('recurring()');
assert.ok(recurringMarkup.includes('routine-item upcoming" data-recurring-id="netflix"'));
assert.ok(recurringMarkup.includes('routine-item confirmed" data-recurring-id="rent"'));
assert.ok(recurringMarkup.includes('routine-item paused" data-recurring-id="internet"'));
assert.equal((recurringMarkup.match(/data-recurring-id=/g)||[]).length,4);
assert.ok(recurringMarkup.indexOf('data-recurring-id="netflix"')<recurringMarkup.indexOf('data-recurring-id="yoga"'));
run("month='2026-11'");assert.ok(run('recurring()').includes('routine-item upcoming" data-recurring-id="rent"'));

// New forms reject invalid bindings atomically, and the custom day grid writes its choice.
reset();run('newRecurring()');
assert.ok(!node('#modal-body').innerHTML.includes('type="number"'));
assert.ok(node('#modal-body').innerHTML.includes('data-name="day"'));
const dayMarkup=run("fieldOptionsMarkup(Array.from({length:31},(_,i)=>({value:String(i+1),label:'每月 '+(i+1)+' 日'})),'day','31')");
assert.equal((dayMarkup.match(/data-action="picker-choice"/g)||[]).length,31);
assert.equal((dayMarkup.match(/aria-pressed="true"/g)||[]).length,1);
const recurringCount=run('state.recurring.length');
assert.throws(()=>submit({name:'bad',amount:'100',day:'31',account:'missing',category:'訂閱服務'}),/帳戶/);
assert.equal(run('state.recurring.length'),recurringCount);
submit({name:'月底固定支出',amount:'100',day:'31',account:'bank',category:'訂閱服務'});
run("month='2026-02'");assert.equal(run('dueDate(state.recurring.at(-1))'),'2026-02-28');
run("confirmRecurring('netflix')");const txCount=run('state.tx.length');
assert.throws(()=>submit({amount:'100',account:'card',date:'2026-02-31',note:''}),/日期/);
assert.equal(run('state.tx.length'),txCount);
submit({amount:'100',account:'card',date:'2026-02-28',note:''});
assert.throws(()=>submit({amount:'100',account:'card',date:'2026-02-28',note:''}),/已經入帳/);
assert.equal(run('state.tx.length'),txCount+1);
run('dividend()');
assert.throws(()=>submit({holding:'0050',amount:'100',account:'card',date:'2026-02-28'}),/收款帳戶/);
assert.equal(run('state.tx.length'),txCount+1);

// Settings export respects its selected month. Reset must wait for form confirmation.
reset();run("route('settings');changePageMonth(-1);ledgerAccountFilter='card';dateFilter='2026-09-03';search='old'");
click({action:'export'});
assert.equal(context.artifact.name,'hibi-2026-09.csv');
assert.equal(context.artifact.text.split('\r\n').length,run("monthly('2026-09').length")+1);
run("state.tx.push({id:'user-kept',type:'income',amount:1,account:'bank',date:'2026-09-20',category:'其他收入'})");
click({action:'reset'});
assert.ok(run("state.tx.some(t=>t.id==='user-kept')"));
submit({});assert.ok(!run("state.tx.some(t=>t.id==='user-kept')"));
assert.equal(run('month'),'2026-10');

// Read-only/destructive dialog classes must never leak into another form.
const modal=node('#modal'),oldClassList=modal.classList,classes=new Set();
modal.classList={add(...names){names.forEach(n=>classes.add(n));},remove(...names){names.forEach(n=>classes.delete(n));},toggle(name,on){on?classes.add(name):classes.delete(name);}};
try{
  run("holding('0050')");assert.ok(classes.has('utility-holding'));
  run('newRecurring()');assert.ok(!classes.has('utility-holding'));assert.ok(classes.has('utility-modal'));
  run('resetPreview()');assert.ok(classes.has('utility-reset'));
  run("openEntry('expense')");assert.ok(!classes.has('utility-reset'));assert.ok(!classes.has('utility-modal'));
}finally{modal.classList=oldClassList;}
reset();
// The new graphics must stay within their viewBoxes at zero, normal and extreme values.
for(const limit of [0,1,32000,100000000]){
  context.__limit=limit;
  const graphic=run("budgetRuler(budgetFacts({category:'全部支出',limit:__limit}))");
  assert.ok(!/NaN|Infinity/.test(graphic));
  assert.ok(graphic.includes(run("budgetRate(budgetFacts({category:'全部支出',limit:__limit}))")));
  for(const rect of graphic.matchAll(/<rect\b[^>]+>/g)){
    const x=Number(rect[0].match(/\bx="([^"]+)"/)[1]),width=Number(rect[0].match(/\bwidth="([^"]+)"/)[1]);
    assert.ok(x>=0&&width>=0&&x+width<=320);
  }
}
const holdingWidths=[0,.0001,20,1000,1e8].map(value=>{context.__value=value;return run('holdingValueWidth(__value,1000)');});
assert.equal(holdingWidths[0],0);
assert.ok(holdingWidths.slice(1).every(width=>width>=8&&width<=100));
assert.ok(holdingWidths.every((width,i)=>i===0||width>=holdingWidths[i-1]));
for(const rows of [[],[{name:'其他支出',amount:-100}],[{name:'其他支出',amount:0}],[{name:'飲食日常',amount:1},{name:'居家生活',amount:1e8}]]){
  context.__rows=rows;
  const graphic=run('reportRing(__rows)');
  assert.ok(!/NaN|Infinity/.test(graphic));
  const arcs=[...graphic.matchAll(/stroke-dasharray="([\d.e+-]+) ([\d.e+-]+)"/g)];
  assert.equal(arcs.length,rows.filter(row=>row.amount>0).length);
  for(const arc of arcs){assert.ok(Number(arc[1])>0&&Number(arc[2])>=0);assert.ok(Math.abs(Number(arc[1])+Number(arc[2])-2*Math.PI*70)<1e-7);}
}
console.log('PASS: all More pages use exact values, refunds, complete monthly drilldowns, budget boundaries, portfolio empty/zero cases, recurring grouping, custom day selection, atomic forms, selected-month export and confirmed-only reset.');
