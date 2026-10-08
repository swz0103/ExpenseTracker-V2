const assert=require('node:assert/strict');
require('./more-pages.cjs');
const {run,node,docListeners}=require('./interaction-smoke.cjs');

// A single classification drives overview, More, and the payment work queue.
run(`state=seed();state.privacy=false;month='2026-10';state.tx=[];
state.recurring=[
 {id:'future',name:'月底',day:28,amount:222,active:true,account:'bank',category:'訂閱服務'},
 {id:'due',name:'到期',day:2,amount:111,active:true,account:'bank',category:'訂閱服務'},
 {id:'paused',name:'暫停',day:1,amount:333,active:false,account:'bank',category:'訂閱服務'}
]`);
for(const expression of ['recurringReminder()','more()','recurring()']){
  const markup=run(expression);
  assert.ok(markup.includes('1 筆待確認'),expression);
  assert.ok(markup.includes('即將到期'),expression);
  assert.ok(!markup.includes('2 筆待確認'),expression);
}
assert.ok(run('recurring()').includes('routine-item upcoming" data-recurring-id="future"'));
assert.ok(run('recurring()').includes('routine-item pending" data-recurring-id="due"'));
run(`state.tx.push({id:'posted',recurring:'due',type:'expense',amount:111,account:'bank',category:'訂閱服務',date:'2026-10-02'})`);
for(const expression of ['recurringReminder()','more()','recurring()'])assert.ok(run(expression).includes('尚無到期項目'));
assert.ok(run('recurring()').includes('routine-item confirmed" data-recurring-id="due"'));
run("month='2026-09'");assert.equal(run('recurringReminderFacts().due.length'),2);
run("month='2026-11'");assert.equal(run('recurringReminderFacts().due.length'),0);assert.equal(run('recurringReminderFacts().upcoming.length'),2);

// Hiding a summary cannot leak through a hover readout or mask an opened account.
run("state=seed();state.privacy=true;month='2026-10';route('overview')");
for(const amount of ['52,000','17,519','34,481'])assert.ok(!node('#main').innerHTML.includes(amount));
run('selectBudgetFocus(-1);selectFlow(5);selectAsset(0)');
for(const id of ['#spending-used','#budget-remaining','#flow-income','#flow-expense','#asset-amount'])assert.ok(node(id).textContent.includes('••••'),id);
for(const id of ['#budget-canvas','#flow-canvas','#allocation-canvas'])assert.ok(node(id).attributes['aria-valuetext'].includes('••••'),id);
for(const expression of ['reports()','investments()','budgets()','recurring()','more()','ledger()'])assert.ok(!run(expression).includes('••••'),expression);
for(const id of ['cash','bank','card']){
  run(`selectedAccount='${id}';route('account-detail')`);
  assert.ok(!node('#main').innerHTML.includes('••••'));
  assert.ok(node('#main').innerHTML.includes('data-amount-visibility="always"'));
}
run('txDetail(state.tx[0].id)');assert.ok(!node('#modal-body').innerHTML.includes('••••'));
run("openEntry('expense')");assert.equal(run('pickerStack.length'),0);

// Date text is stable before and after selection in every form variant.
run("month='2026-10';editCalendarMin='2026-01';editCalendarMax='2030-12';selectEditDate('2026-11-08')");
assert.equal(node('#edit-date-label').textContent,run("composerDateText('2026-11-08')"));
assert.ok(run("editDatePicker('2026-11-08')").includes(node('#edit-date-label').textContent));
assert.ok(run("composerDatePicker('2026-11-08')").includes(node('#edit-date-label').textContent));

// Every month selector shares both limits; changing it still updates the selected page.
run("month='2026-01'");assert.match(run('period()'),/aria-label="上一個月" disabled/);
run("month='2030-12'");assert.match(run('period()'),/aria-label="下一個月" disabled/);
run("month='2026-10';route('reports')");
const el={dataset:{action:'month-next'}};
for(const handler of docListeners.click||[])handler({target:{closest:s=>s==='[data-action]'?el:null}});
assert.equal(run('month'),'2026-11');assert.ok(node('#main').innerHTML.includes('2026 / 11'));

// The approved direction, delete order, and account amount behavior remain intact.
run('transfer()');assert.equal((node('#modal-body').innerHTML.match(/class="transfer-direction"/g)||[]).length,1);
run("state=seed();txDetail(state.tx[0].id)");
assert.equal(node('#modal-submit').attributes['data-action'],'tx-delete-confirm');
assert.equal(node('#modal .modal-actions .secondary').attributes['data-action'],'tx-edit');
assert.ok(!run('more()').includes('more-tool-arrow'));
console.log('PASS: cross-page reminder semantics, summary-only privacy including accessible/hover values, visible account details, shared month limits and date formatting, independent controls and preserved user decisions.');
