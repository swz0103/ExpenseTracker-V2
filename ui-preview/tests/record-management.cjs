const assert=require('node:assert/strict');
require('./app-format.cjs');
const {run,context,node,docListeners}=require('./interaction-smoke.cjs');
function reset(){run("state=seed();month='2026-10';page='overview';resetPickerPages();ledgerAdvanced=null;search='';categoryFilter='';filter='all';dateFilter='';ledgerAccountFilter=''");}
function submit(values){context.__form=new Map(Object.entries(values));run('modalHandler(__form)');}
function click(dataset){const el={dataset};for(const handler of docListeners.click||[])handler({target:{closest:s=>s==='[data-action]'?el:null}});}
function buy(values={}){run("openInvestmentComposer({tradeSide:'buy'})");submit({amount:'600',qty:'10',holding:'0050',account:'bank',date:'2026-10-04',note:'買入',...values});return run('state.tx.at(-1).id');}
function sell(values={}){run("openInvestmentComposer({tradeSide:'sell'})");submit({amount:'300',qty:'5',holding:'0050',account:'bank',date:'2026-10-05',note:'賣出',...values});return run('state.tx.at(-1).id');}
reset();
assert.equal(run('DAILY_RECEIPT_GROUP_SIZE'),6);
assert.equal((run('dailyDetails(4)').match(/class="daily-receipt-group"/g)||[]).length,1);
assert.ok(run('dailyDetails(4)').includes('1-6 / 10'));
assert.equal(run('dailyReceiptPosition({from:7,to:10,total:10})'),'7-10 / 10');
assert.equal(run('dailyReceiptPosition({from:501,to:503,total:503})'),'501-503 / 503');

// Category administration is independent of months and safely propagates renames.
const categoryMarkup=run('categoryOverview()');
assert.ok(run('categoryCatalog().every(c=>CATEGORY_ICONS.includes(c.icon)&&CATEGORY_COLORS.includes(c.color))'));
assert.ok(!categoryMarkup.includes('month-prev'));
assert.ok(!categoryMarkup.includes('category-family-total'));
assert.ok(!categoryMarkup.includes('data-action="category"'));
run("openCategoryEditor('','expense')");
submit({name:'學習進修',icon:'other',color:'#406f83'});
assert.ok(run("categoryNameOptions('expense').includes('學習進修')"));
assert.ok(JSON.parse(run('JSON.stringify(state)')).categorySettings.some(c=>c.name==='學習進修'));
run("openCategoryEditor('','expense')");
assert.throws(()=>submit({name:'學習進修',icon:'other',color:'#406f83'}),/同名/);
run("globalThis.foodId=categoryByName('飲食日常').id;openCategoryEditor(foodId)");
submit({name:'日常餐飲',icon:'food',color:'#925a35'});
assert.equal(run("state.tx.some(t=>t.category==='飲食日常')"),false);
assert.equal(run("state.budgets.find(b=>b.id==='food').category"),'日常餐飲');
const foodBefore=run("spent('日常餐飲')");
run('categoryStatus(foodId)');assert.ok(run("categoryNameOptions('expense').includes('日常餐飲')"));submit({});
assert.equal(run("categoryNameOptions('expense').includes('日常餐飲')"),false);
assert.equal(run("spent('日常餐飲')"),foodBefore);
assert.ok(run('categoryOverview()').includes('已停用'));
run('categoryStatus(foodId)');assert.ok(run("categoryNameOptions('expense').includes('日常餐飲')"));

// Every account selector omits both visual and accessible balances.
for(const expression of ["openEntry('expense')","openEntry('income')","transfer()","transfer(true)","newRecurring()","confirmRecurring('netflix')","dividend()","txEdit(state.tx.find(t=>t.type==='expense').id)"]){
 run(expression);assert.ok(!/picker-balance|餘額|未繳/.test(node('#modal-body').innerHTML),expression);
}

// Trades affect cash and positions once, while principal stays outside income/expense.
reset();
const originalCash=run("balance(account('bank'))"),originalQty=run("state.holdings[0].qty"),originalCost=run("state.holdings[0].cost"),originalIncome=run('totals().income'),originalExpense=run('totals().expense');
run("openEntry('investment')");assert.equal((node('#modal-body').innerHTML.match(/data-action="compose-type"/g)||[]).length,4);
assert.ok(node('#modal-body').innerHTML.includes('data-side="buy"'));
assert.ok(!node('#modal-body').innerHTML.includes('edit-calc-keys'));
const buyId=buy();
assert.equal(run("balance(account('bank'))"),originalCash-600);
assert.equal(run('state.holdings[0].qty'),originalQty+10);
assert.equal(run('state.holdings[0].cost'),originalCost+600);
assert.equal(run('totals().income'),originalIncome);assert.equal(run('totals().expense'),originalExpense);
assert.ok(run('dayActivityTags(4)').includes('activity-investment'));
assert.equal(run("ledgerFilteredTransactions({...defaultLedgerFilters(),types:['investment']}).length"),1);
assert.ok(run('dailyReceipt(state.tx.at(-1))').includes('−600'));
const sellId=sell();
assert.equal(run("balance(account('bank'))"),originalCash-300);
assert.equal(run('state.holdings[0].qty'),originalQty+5);
assert.equal(run('state.holdings[0].cost'),Math.round((originalCost+600)*(originalQty+5)/(originalQty+10)*100)/100);
assert.ok(run('txRow(state.tx.at(-1))').includes('+300'));
assert.ok(run("accountActivityRow(state.tx.at(-1),account('bank'))").includes('+300'));
run('txDetail(state.tx.at(-1).id)');assert.ok(node('#modal-body').innerHTML.includes('5 股'));assert.ok(node('#modal-body').innerHTML.includes('投資賣出'));
const beforeRejected=run('JSON.stringify(state)');
assert.throws(()=>sell({qty:'99999'}),/不足/);assert.equal(run('JSON.stringify(state)'),beforeRejected);
assert.throws(()=>buy({qty:'1.5'}),/股數/);assert.equal(run('JSON.stringify(state)'),beforeRejected);
assert.throws(()=>buy({account:'card'}),/帳戶/);assert.equal(run('JSON.stringify(state)'),beforeRejected);
assert.throws(()=>buy({date:'2026-02-31'}),/日期/);assert.equal(run('JSON.stringify(state)'),beforeRejected);
context.__sellId=sellId;run('txEdit(__sellId)');submit({amount:'360',qty:'6',holding:'0050',account:'cash',date:'2026-10-05',note:'調整賣出'});
assert.equal(run('state.holdings[0].qty'),originalQty+4);assert.equal(run("balance(account('bank'))"),originalCash-600);
run('txDeleteConfirm(__sellId)');submit({});assert.equal(run('state.holdings[0].qty'),originalQty+10);
context.__buyId=buyId;run('txDeleteConfirm(__buyId)');submit({});assert.equal(run('state.holdings[0].qty'),originalQty);assert.equal(run('state.holdings[0].cost'),originalCost);assert.equal(run("balance(account('bank'))"),originalCash);

// Deleting or backdating a dependent buy cannot create an invalid short position.
reset();run("state.holdings=[{id:'TEST',name:'測試',qty:0,cost:0,price:100,dividend:0}]");
const dependentBuy=buy({holding:'TEST',qty:'10',amount:'1000'});sell({holding:'TEST',qty:'10',amount:'1200'});
assert.equal(run('state.holdings[0].qty'),0);assert.equal(run('state.holdings[0].cost'),0);
const dependentState=run('JSON.stringify(state)');context.__buyId=dependentBuy;run('txDeleteConfirm(__buyId)');assert.throws(()=>submit({}),/不足/);assert.equal(run('JSON.stringify(state)'),dependentState);
run('txEdit(__buyId)');assert.throws(()=>submit({amount:'1000',qty:'10',holding:'TEST',account:'bank',date:'2026-10-06'}),/不足/);assert.equal(run('JSON.stringify(state)'),dependentState);

// Stock creation uses a detached child page; dividends retain their income linkage.
reset();run("openEntry('investment');newInvestmentHolding({dataset:{action:'investment-new-holding'}})");
assert.equal(run('pickerCurrent().kind'),'new-holding');
for(const [name,value] of Object.entries({date:'2026-10-04',account:'bank',holding:'0050',qty:'3',tradeSide:'buy',note:'保留草稿'}))node('#f-'+name).value=value;
node('#holding-code').value='TEST';node('#holding-name').value='測試標的';run('saveInvestmentHolding()');
assert.equal(run('recordComposer.holding'),'TEST');assert.equal(run('recordComposer.note'),'保留草稿');assert.equal(run('pickerStack.length'),0);
buy({holding:'TEST',qty:'3',amount:'600'});assert.equal(run("state.holdings.find(h=>h.id==='TEST').price"),200);
const beforeDividend=run('totals().income'),qtyBeforeDividend=run('state.holdings[0].qty');run('dividend()');submit({amount:'500',holding:'0050',account:'bank',date:'2026-10-04'});
assert.equal(run('totals().income'),beforeDividend+500);assert.equal(run('monthDividend()'),500);assert.equal(run('state.holdings[0].qty'),qtyBeforeDividend);
run("state.holdings=JSON.parse(JSON.stringify(state.holdings));state.tx=JSON.parse(JSON.stringify(state.tx));commitLedgerTransactions(state.tx)");assert.equal(run('state.holdings[0].qty'),qtyBeforeDividend);
run('exportCSV()');assert.ok(context.artifact.text.includes('投資標的'));assert.ok(context.artifact.text.includes('TEST'));
console.log('PASS: three-column receipt navigation; persistent category management and safe renames; balance-free forms; four composer modes; investment cash/quantity/cost consistency, edits/deletion, invalid and dependent-trade rejection, new symbols, dividends and export.');
