const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const {createCanvas,GlobalFonts}=require(require.resolve('@napi-rs/canvas',{paths:[process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES]}));
for(const weight of [400,500,600,700])assert.ok(GlobalFonts.registerFromPath(`dist/fonts/noto-sans-tc-${weight}.woff`,'Noto Sans TC'));
const html = fs.readFileSync('dist/index.html','utf8');
const cssFiles=['style.css','app-layout.css','compact-home.css','canvas-dashboard.css','ledger-filters.css','entry-compose.css','picker-pages.css'];
assert.ok(cssFiles.every(f=>!fs.readFileSync('dist/'+f,'utf8').includes('var(--serif)')));
assert.ok(!fs.readFileSync('dist/style.css','utf8').includes('fonts.googleapis.com'));
const nodes = new Map(),docListeners={},windowListeners={};
function node(s){if(!nodes.has(s)){
 const native=createCanvas(336,160),el={innerHTML:'',textContent:'',style:{setProperty(k,v){this[k]=v;}},listeners:{},attributes:{},classList:{add(){},remove(){},toggle(){}},addEventListener(type,handler){this.listeners[type]=handler;},setAttribute(k,v){this.attributes[k]=v;},removeAttribute(k){delete this.attributes[k];},setPointerCapture(){},getBoundingClientRect(){return {left:0,top:0,width:336,height:parseFloat(this.style.height)||126};},getContext(){return native.getContext('2d');},reset(){},showModal(){},close(){},reportValidity(){return true;},native};
 Object.defineProperty(el,'width',{get:()=>native.width,set:v=>native.width=v});Object.defineProperty(el,'height',{get:()=>native.height,set:v=>native.height=v});
 nodes.set(s,el);
}return nodes.get(s);}

let persisted,now=0;
let timerId=0;const timers=new Map();function flushHover(){for(const [id,t] of [...timers])if(t.delay===85){timers.delete(id);t.fn();}}
const context = vm.createContext({document:{querySelector:node,querySelectorAll:()=>[],addEventListener(type,handler){(docListeners[type]??=[]).push(handler);}},localStorage:{getItem:()=>null,setItem:(k,v)=>persisted=v},history:{replaceState(){}},location:{hash:''},window:{scrollTo(){},addEventListener(type,handler){(windowListeners[type]??=[]).push(handler);},removeEventListener(){},devicePixelRatio:1,matchMedia:()=>({matches:true})},performance:{now:()=>now},requestAnimationFrame:()=>1,cancelAnimationFrame(){},console,setTimeout:(fn,delay)=>{const id=++timerId;timers.set(id,{fn,delay});return id;},clearTimeout:id=>timers.delete(id),crypto:{randomUUID:()=>Math.random().toString()},Blob,URL,MouseEvent:class{}});
vm.runInContext(fs.readFileSync('dist/icons.js','utf8'),context);
vm.runInContext(fs.readFileSync('dist/dashboard.js','utf8'),context);
vm.runInContext(fs.readFileSync('dist/ledger-filters.js','utf8'),context);
vm.runInContext(fs.readFileSync('dist/entry-compose.js','utf8'),context);
vm.runInContext(fs.readFileSync('dist/picker-pages.js','utf8'),context);
vm.runInContext(fs.readFileSync('dist/more-views.js','utf8'),context);
vm.runInContext(fs.readFileSync('dist/more-pages.js','utf8'),context);
vm.runInContext(fs.readFileSync('dist/record-management.js','utf8'),context);
vm.runInContext(fs.readFileSync('dist/app-experience.js','utf8'),context);
vm.runInContext(fs.readFileSync('dist/app.js','utf8'),context);
const run = s => vm.runInContext(s,context);
const data = fields => new Map(Object.entries(fields));
function submit(fields){context.__data=data(fields);run('modalHandler(__data)');}
assert.equal(run('totals().income'),52000);
assert.equal(run('totals().expense'),17519);
assert.equal(run('dayTransactions(4).length'),10);assert.equal(run('DENSE_DAY_DEMO.reduce((n,t)=>n+t.amount,0)'),1000);
run("globalThis.migrationSample=seed();delete migrationSample.dailyDensityDemoVersion;migrationSample.tx=migrationSample.tx.filter(t=>!t.id.startsWith('dense-day-demo-'));migrationSample.tx.push({id:'user-kept',date:'2026-10-04',type:'expense',amount:1,account:'cash',category:'飲食日常',note:'自訂'});extendDemoDailyTransactions(migrationSample);extendDemoDailyTransactions(migrationSample)");assert.equal(run('migrationSample.tx.filter(t=>t.id.startsWith("dense-day-demo-")).length'),8);assert.ok(run('migrationSample.tx.some(t=>t.id==="user-kept")'));run('migrationSample.tx=migrationSample.tx.filter(t=>t.id!=="dense-day-demo-0");extendDemoDailyTransactions(migrationSample)');assert.ok(!run('migrationSample.tx.some(t=>t.id==="dense-day-demo-0")'));
const initialNet=run('netWorth()'),initialCash=run("balance(account('cash'))");
run("openEntry('expense')");submit({amount:'500',account:'cash',category:'飲食日常',date:'2026-10-04',note:'測試午餐'});
assert.equal(run('totals().expense'),18019);
assert.equal(run("balance(account('cash'))"),initialCash-500);
assert.equal(run('netWorth()'),initialNet-500);
assert.equal(run("spent('飲食日常')"),3570);
run("state.tx.at(-1).reversed=true");
assert.equal(run('netWorth()'),initialNet);
assert.equal(run('totals().expense'),17519);
const bankBefore=run("balance(account('bank'))"),cardBefore=run("balance(account('card'))");
run('transfer(true)');submit({amount:'1000',from:'bank',to:'card',date:'2026-10-04',note:'測試繳款'});
assert.equal(run("balance(account('bank'))"),bankBefore-1000);
assert.equal(run("balance(account('card'))"),cardBefore+1000);
assert.equal(run('netWorth()'),initialNet);
assert.equal(run('totals().expense'),17519);
run('transfer()');assert.throws(()=>submit({amount:'100',from:'bank',to:'bank',date:'2026-10-04',note:''}),/不同/);
run("openEntry('income')");assert.throws(()=>submit({amount:'-10',account:'bank',category:'其他收入',date:'2026-10-04',note:''}),/整數金額/);
run("confirmRecurring('netflix')");
assert.throws(()=>submit({amount:'400',account:'card',date:'2026-11-05',note:'Netflix'}),/月份/);
submit({amount:'400',account:'card',date:'2026-10-05',note:'Netflix'});
assert.equal(run('totals().expense'),17919);
assert.equal(run('state.tx.filter(t=>t.recurring==="netflix").length'),1);
assert.throws(()=>submit({amount:'400',account:'card',date:'2026-10-05',note:'Netflix'}),/已經入帳/);
run("editBudget('food')");submit({amount:'10000'});assert.equal(run('state.budgets.find(b=>b.id==="food").limit'),10000);
run('newRecurring()');submit({name:'月底訂閱',amount:'200',day:'31',category:'訂閱服務',account:'bank'});
run("month='2026-02'");assert.equal(run('dueDate(state.recurring.at(-1))'),'2026-02-28');
run("month='2026-10'");
const beforeDividend=run('netWorth()');run('dividend()');submit({holding:'0050',amount:'2000',account:'bank',date:'2026-10-04'});
assert.equal(run('netWorth()'),beforeDividend+2000);assert.equal(run('totals().income'),54000);
run('openAccount()');assert.ok(node('#modal-body').innerHTML.includes('信用卡'));submit({name:'<img src=x onerror=alert(1)>',kind:'bank',opening:'1234'});
assert.equal(run('netWorth()'),beforeDividend+3234);
run("openAccount()");submit({name:'測試信用卡',kind:'card',opening:'2000'});assert.equal(run('state.accounts.at(-1).opening'),-2000);run("state.accounts.pop();selectedAccount='bank';save()");
run("route('accounts')");assert.ok(node('#main').innerHTML.includes('&lt;img'));assert.ok(!node('#main').innerHTML.includes('<img src=x'));assert.ok(node('#main').innerHTML.includes('data-action="account-open"'));assert.ok(!node('#main').innerHTML.includes('data-action="account-select"'));
run("selectedAccount='bank';route('account-detail')");assert.ok(node('#main').innerHTML.includes('日常銀行'));assert.ok(node('#main').innerHTML.includes('目前餘額'));assert.ok(node('#main').innerHTML.includes('data-action="account-transfer"'));assert.ok(node('#main').innerHTML.includes('帳戶紀錄'));assert.ok(node('#main').innerHTML.includes('account-waterfall-chart'));assert.ok(node('#main').innerHTML.includes('連續四週帳戶瀑布圖'));assert.ok(node('#main').innerHTML.includes('每週餘額變動'));assert.ok(node('#main').innerHTML.includes('data-action="waterfall-info"'));assert.ok(node('#main').innerHTML.includes('id="waterfall-detail"'));assert.ok(node('#main').innerHTML.includes('aria-pressed="true"'));assert.ok((node('#main').innerHTML.match(/data-action="waterfall-info"/g)||[]).length<=4);assert.ok(!node('#main').innerHTML.includes('style="width:'));
run("selectedAccount='card';route('account-detail')");assert.ok(node('#main').innerHTML.includes('日常信用卡'));assert.ok(node('#main').innerHTML.includes('目前待繳'));assert.ok(node('#main').innerHTML.includes('data-action="account-pay"'));assert.ok(node('#main').innerHTML.includes('data-action="account-record"'));
run("state.privacy=true;selectedAccount='bank';route('account-detail')");assert.ok(!node('#main').innerHTML.includes('••••'));assert.ok(node('#main').innerHTML.includes(run("money(balance(account('bank')))")));run('state.privacy=false');
for(const p of ['overview','ledger','accounts','reports','categories','investments','budgets','recurring','settings','more']){
  run(`route('${p}')`);const page=node('#main').innerHTML;
  assert.ok(page.includes('<h1>'),p+' has title');assert.ok(!page.includes('undefined'),p+' has resolved content');assert.ok(page.length>300,p+' renders');
}
run("route('reports')");assert.ok(node('#main').innerHTML.includes('財務報表'));assert.ok(node('#main').innerHTML.includes('分類變化'));assert.ok(node('#main').innerHTML.includes('data-action="category"'));
run("route('categories')");assert.ok(node('#main').innerHTML.includes('分類管理'));assert.ok(node('#main').innerHTML.includes('薪資收入'));assert.ok(node('#main').innerHTML.includes('飲食日常'));
run('download=(text,type,name)=>globalThis.artifact={text,type,name}; exportCSV()');
assert.ok(context.artifact.text.startsWith('\ufeff'));assert.equal(context.artifact.name,'hibi-2026-10.csv');
run("state.privacy=true; route('overview')");assert.ok(node('#main').innerHTML.includes('••••'));
assert.equal(JSON.parse(persisted).version,1);
assert.ok(html.includes('aria-labelledby="modal-title"'));
run("route('cards')");assert.equal(run('page'),'account-detail');assert.equal(run('selectedAccount'),'card');assert.ok(node('#main').innerHTML.includes('日常信用卡'));
console.log('PASS: all 10 views; linked balances, spend and budgets; reversal; card payment; transfer rejection; recurring single confirmation and month-end; dividend; unified account creation; escaping; CSV; privacy; persistence.');

run("state=seed();state.privacy=false;month='2026-10';flowIndex=-1;route('overview')");
assert.equal((node('#main').innerHTML.match(/<canvas/g)||[]).length,3);
assert.equal((node('#main').innerHTML.match(/class="icon summary-icon"/g)||[]).length,4);
assert.ok(!node('#main').innerHTML.includes('↗'));
assert.ok(!node('#main').innerHTML.includes('dash-range'));
assert.ok(!node('#main').innerHTML.includes('最近紀錄'));
for(const removed of ['flow-scale','asset-scale','allocation-details','flow-metrics','flow-secondary','heat-amount','heat-label','dash-information','home-shortcuts','home-metrics','heat-week','heat-legend','category-dots','allocation-legend','budget-used','budget-selector','dashboard-budget'])assert.ok(!node('#main').innerHTML.includes(removed));
assert.ok(node('#main').innerHTML.includes('id="flow-income"'));assert.ok(node('#main').innerHTML.includes('id="flow-expense"'));
assert.ok(!node('#main').innerHTML.includes('growth-basis'));assert.ok(!node('#main').innerHTML.includes('dash-flow-detail'));
assert.equal((node('#main').innerHTML.match(/id="asset-amount"/g)||[]).length,1);
assert.ok(node('#main').innerHTML.includes('pending-entry'));
assert.ok(!node('#main').innerHTML.includes('data-action="home-income"'));assert.ok(!node('#main').innerHTML.includes('data-action="home-expense"'));
assert.ok(!node('#main').innerHTML.includes('信用卡待繳'));assert.ok(/class="budget-values"><strong id="budget-remaining">[\s\S]*?<\/strong><small id="budget-limit"/.test(node('#main').innerHTML));
const summary=node('#main').innerHTML.match(/<section class="home-summary"[\s\S]*?<\/section>/)[0];assert.ok(!summary.includes('data-action="card-account"'));assert.ok(!summary.includes('data-route="cards"'));assert.ok(!summary.includes('淨資產'));assert.equal((summary.match(/home-stat-label/g)||[]).length,4);assert.ok(!summary.includes('預算'));
run("globalThis.pendingSnapshot=state.tx.length;for(const r of state.recurring)if(r.active&&!recurringConfirmed(r))state.tx.push({id:r.id+'-badge-test',date:month+'-04',recurring:r.id,type:'expense',amount:r.amount,account:r.account,category:r.category});route('overview')");
assert.ok(!node('#main').innerHTML.includes('pending-entry'));
run('state.tx.length=pendingSnapshot;route("overview")');
assert.ok(node('#main').innerHTML.includes('daily-details'));
assert.equal(run('state.holdings.length'),12);
// Existing simulated edits survive the one-time sample holding extension.
run("globalThis.oldDemo=seed();oldDemo.holdings=oldDemo.holdings.slice(0,3);delete oldDemo.holdingsDemoVersion;oldDemo.tx.push({id:'keep-user-edit'});extendDemoHoldings(oldDemo);extendDemoHoldings(oldDemo)");
assert.equal(run('oldDemo.holdings.length'),12);assert.equal(run('oldDemo.tx.at(-1).id'),'keep-user-edit');
run("oldDemo.accounts=oldDemo.accounts.slice(0,4);oldDemo.accounts[0].name='保留的帳戶';delete oldDemo.accountsDemoVersion;extendDemoAccounts(oldDemo);extendDemoAccounts(oldDemo)");
assert.equal(run('oldDemo.accounts.length'),12);assert.equal(run('oldDemo.accounts[0].name'),'保留的帳戶');assert.equal(run('oldDemo.tx.at(-1).id'),'keep-user-edit');
assert.equal(run('new Set(oldDemo.accounts.map(a=>a.id)).size'),12);
assert.ok(node('#main').innerHTML.indexOf('heatmap-section')<node('#main').innerHTML.indexOf('flow-section'));
assert.ok(node('#main').innerHTML.indexOf('allocation-section')<node('#main').innerHTML.indexOf('flow-section'));
assert.ok(!node('#mobile-navigation').innerHTML.includes('data-route="budgets"'));
assert.ok(node('#mobile-navigation').innerHTML.includes('data-route="accounts"'));
const surface=node('#flow-canvas');
surface.listeners.pointerdown({pointerId:1,clientX:12,clientY:40,pointerType:'touch'});
assert.equal(run('flowIndex'),0);assert.equal(node('#flow-period').textContent,'5月');
surface.listeners.pointermove({pointerId:1,clientX:324,clientY:40,pointerType:'touch'});
assert.equal(run('flowIndex'),5);assert.equal(node('#flow-expense').textContent,'TWD 17,519');
assert.equal(node('#flow-income').textContent,'TWD 52,000');assert.equal(node('#flow-balance').textContent,'TWD 34,481');
surface.listeners.keydown({key:'Home',preventDefault(){}});assert.equal(run('flowIndex'),0);
surface.listeners.keydown({key:'End',preventDefault(){}});assert.equal(run('flowIndex'),5);
run("dashboardAction('dash-flow-detail',{dataset:{}})");
assert.equal(run('page'),'ledger');assert.equal(run('filter'),'all');assert.equal(run('month'),'2026-10');
run("route('overview');selectBudgetFocus(-1)");
assert.ok(!node('#main').innerHTML.includes('category-canvas'));assert.ok(!node('#main').innerHTML.includes('heatmap-canvas'));
// Minimum allocation fixes the smallest items first and preserves ratios for unfixed items.
assert.deepEqual(Array.from(run('minimumSizes([1,10,100],140,20)')),[20,20,100]);assert.deepEqual(Array.from(run('minimumSizes([0,0],140,20)')),[0,0]);
run("globalThis.todaySnapshot=investmentToday();globalThis.holdingSnapshot=state.holdings;state.holdings=[{id:'0050',qty:100,price:58.2,cost:5000},{id:'unknown',qty:20,price:10,cost:100}]");assert.ok(Math.abs(run('investmentToday().change')-30)<1e-8);assert.equal(run('investmentToday().covered'),1);assert.equal(run('investmentToday().value'),6020);assert.ok(run('investmentTodaySummary()').includes('部分示意行情'));
run("state.holdings=[{id:'0050',qty:100,price:56,cost:5000}]");assert.ok(run('investmentToday().change')<0);assert.ok(run('investmentTodaySummary()').includes('negative'));
run("state.holdings=[]");assert.equal(run('investmentToday().rate'),0);assert.ok(!run('investmentTodaySummary()').includes('NaN'));run('state.holdings=holdingSnapshot');
assert.ok(node('#main').innerHTML.includes('當日損益'));assert.ok(node('#main').innerHTML.includes('投資市值'));assert.ok(node('#main').innerHTML.includes('示意'));
run("categoryFilter='';dateFilter='';heatDay=4;route('overview')");
const calendar=node('#daily-calendar');
assert.equal((calendar.innerHTML.match(/data-action="dash-day-select"/g)||[]).length,7);assert.equal((calendar.innerHTML.match(/disabled/g)||[]).length,3);assert.ok(calendar.innerHTML.includes('aria-pressed="true"'));assert.ok(calendar.innerHTML.includes('1,390'));
assert.equal(run('dailyStart'),-3);assert.equal(node('#daily-week-label').textContent,'9 / 28 至 10 / 4');assert.equal(node('#daily-prev').disabled,true);assert.equal(node('#daily-week-total').textContent,'本週 TWD 17,519');
assert.equal(run('dayTransactions(4).length'),10);assert.equal((node('#daily-details').innerHTML.match(/data-action="tx-detail"/g)||[]).length,6);assert.ok(!node('#daily-details').innerHTML.includes('daily-receipt-nav'));
run("dashboardAction('dash-day-select',{dataset:{day:'2'}})");assert.equal(run('heatDay'),2);assert.ok(node('#daily-details').innerHTML.includes('全聯'));assert.equal(run('page'),'overview');
calendar.listeners.keydown({key:'End',preventDefault(){}});assert.equal(run('heatDay'),4);calendar.listeners.keydown({key:'ArrowRight',preventDefault(){}});assert.equal(run('heatDay'),5);assert.equal(run('dailyStart'),4);
calendar.listeners.keydown({key:'Home',preventDefault(){}});assert.equal(run('heatDay'),5);
run("dashboardAction('dash-week-next',{dataset:{}})");assert.equal(run('dailyStart'),11);assert.equal(run('heatDay'),12);run("dashboardAction('dash-week-prev',{dataset:{}})");assert.equal(run('dailyStart'),4);
for(const m of ['2026-10','2027-02','2026-03']){context.__month=m;run('month=__month;heatDay=1;dailyStart=dailyWeekStart(1)');const slots=run('dailyWeekSlots()');assert.equal(slots.length,7);assert.equal(new Date(slots[0].date+'T00:00:00Z').getUTCDay(),1);assert.equal(new Date(slots[6].date+'T00:00:00Z').getUTCDay(),0);assert.equal((run('dailyCalendar()').match(/data-action="dash-day-select"/g)||[]).length,7);}
run("month='2026-10';selectHeat(31)");assert.equal(node('#daily-next').disabled,true);assert.equal(run('dailyWeekSlots()[6].inMonth'),false);run('selectHeat(4)');
assert.equal(run('calendarAmount(12500)'),'1.25萬');assert.equal(run('calendarAmount(100000)'),'10萬');assert.equal(run('calendarAmount(-500)'),'+500');assert.equal(run('calendarAmount(0)'),'0');
run('selectHeat(1)');assert.ok(node('#daily-details').innerHTML.includes('daily-receipts'));assert.ok(node('#daily-details').innerHTML.includes('daily-receipt'));assert.ok(!node('#daily-details').innerHTML.includes('class="daily-tx"'));assert.ok(node('#daily-details').innerHTML.includes('data-action="tx-detail"'));assert.ok(node('#daily-details').innerHTML.includes('+52,000'));assert.ok(node('#daily-details').innerHTML.includes('−12,500'));
run("globalThis.dayNoteSnapshot=state.tx[0].note;state.tx[0].note='<script>x</script>';selectHeat(Number(state.tx[0].date.slice(8)))");assert.ok(!node('#daily-details').innerHTML.includes('<script>'));run('state.tx[0].note=dayNoteSnapshot');
run("globalThis.refundId='week-refund-test';state.tx.push({id:refundId,date:'2026-10-07',type:'refund',amount:500,account:'cash',category:'飲食日常',note:'退款測試'});selectHeat(7)");assert.equal(run('dailyFacts()[6].expense'),-500);assert.ok(!node('#daily-calendar').innerHTML.includes('calendar-amount'));assert.ok(node('#daily-calendar').innerHTML.includes('支出 TWD -500'));assert.ok(node('#daily-details').innerHTML.includes('+500'));run('state.tx=state.tx.filter(t=>t.id!==refundId)');
run('selectHeat(4)');assert.ok(!node('#main').innerHTML.includes('id="budget-context"'));assert.ok(!fs.readFileSync('dist/dashboard.js','utf8').includes('小額放大 · 金額不變'));
// Busy dates stay bounded to six tickets on a single page, preserve every record and maintain full-day totals.
run("globalThis.busySnapshot=state.tx;state.tx=Array.from({length:503},(_,i)=>({id:'busy-'+i,date:'2026-10-08',type:'expense',amount:i+1,account:'cash',category:'飲食日常',note:'紀錄 '+i}));selectHeat(8)");
assert.equal(run('dailyReceiptWindow().total'),503);assert.equal(run('dailyReceiptWindow().pages'),84);assert.equal(run('dailyFacts()[7].expense'),503*504/2);assert.ok(node('#daily-details').innerHTML.includes('TWD 126,756'));assert.equal((node('#daily-details').innerHTML.match(/data-action="tx-detail"/g)||[]).length,6);assert.ok(node('#daily-details').innerHTML.includes('daily-receipts paged'));assert.ok(node('#daily-details').innerHTML.includes('第 1 頁，共 84 頁'));
const reached=new Set();for(let page=0;page<84;page++){context.__receiptPage=page;run('setDailyReceiptPage(__receiptPage)');const current=run('dailyReceiptWindow()');assert.ok(current.rows.length<=6);for(const row of current.rows){assert.ok(!reached.has(row.id));reached.add(row.id);}assert.ok(node('#daily-details').innerHTML.includes('TWD 126,756'));}assert.equal(reached.size,503);assert.equal(run('dailyReceiptWindow().rows.length'),5);assert.ok(node('#daily-details').innerHTML.includes('第 84 頁，共 84 頁'));
run("dashboardAction('dash-receipt-prev',{dataset:{}})");assert.equal(run('receiptPage'),82);run("dashboardAction('dash-receipt-next',{dataset:{}})");assert.equal(run('receiptPage'),83);
run("openDailyReceiptPages();dashboardAction('dash-receipt-page-select',{dataset:{index:'83'}})");assert.equal(run('receiptPage'),83);assert.equal(run('dailyReceiptWindow().rows[0].id'),'busy-4');run('setDailyReceiptPage(Infinity)');assert.equal(run('receiptPage'),83);
run('selectHeat(9)');assert.equal(run('receiptPage'),0);assert.ok(node('#daily-details').innerHTML.includes('當天沒有紀錄'));run('selectHeat(8)');assert.equal(run('receiptPage'),0);
run("setDailyReceiptPage(83);state.tx=state.tx.slice(0,11);selectHeat(8)");assert.equal(run('receiptPage'),1);assert.equal(run('dailyReceiptWindow().rows.length'),5);assert.ok(node('#daily-details').innerHTML.includes('daily-receipts paged'));assert.ok(node('#daily-details').innerHTML.includes('TWD 66'));
run("state.tx=[{id:'large-long',date:'2026-10-08',type:'expense',amount:100000000,account:'cash',category:'飲食日常',note:'很長的紀錄'.repeat(12)}];selectHeat(8)");assert.ok(node('#daily-details').innerHTML.includes('−100,000,000'));assert.ok(node('#daily-details').innerHTML.includes('receipt-amount-small'));assert.ok(!node('#daily-details').innerHTML.includes('daily-receipt-nav'));
run("txDetail('large-long')");assert.ok(node('#modal-body').innerHTML.includes('很長的紀錄'.repeat(12)));run('state.tx=busySnapshot;selectHeat(4)');
const themeCSS=fs.readFileSync('dist/style.css','utf8');assert.ok(themeCSS.includes('--accent:#4f765b'));assert.ok(themeCSS.includes('--accent-light:#e2ecdf'));assert.ok(themeCSS.includes('--expense:#b45454'));assert.ok(fs.readFileSync('dist/index.html','utf8').includes('name="theme-color" content="#f7f2e7"'));
const receiptCSS=fs.readFileSync('dist/canvas-dashboard.css','utf8');assert.ok(receiptCSS.includes('overflow-x:auto'));assert.ok(receiptCSS.includes('flex:0 0 auto'));assert.ok(receiptCSS.includes('scroll-snap-type:x proximity'));assert.ok(!receiptCSS.includes('receipt-columns'));assert.ok(receiptCSS.includes('text-overflow:ellipsis'));assert.ok(!node('#daily-details').innerHTML.includes('receipt-columns'));assert.ok(!node('#daily-details').innerHTML.includes('receipt-account'));assert.ok(!node('#daily-details').innerHTML.includes('receipt-category'));assert.ok(!node('#daily-details').innerHTML.includes('receipt-kind'));assert.ok(receiptCSS.includes('height:44px'));assert.ok(!node('#daily-details').innerHTML.includes('receipt-main'));
assert.equal(run('new Set(categories.map(c=>c.color)).size'),6);
run("dashboardAction('dash-day-detail',{dataset:{}})");
assert.equal(run('dateFilter'),'2026-10-04');assert.ok(node('#main').innerHTML.includes('巷口咖啡'));
assert.ok(!node('#transaction-list').innerHTML.includes('全聯'));
run("dateFilter='';categoryFilter='';route('overview');selectFlow(5)");
assert.equal(node('#growth-amount').textContent,run('nt(netWorth(flowThrough(month)))'));
run("dashboardAction('dash-growth',{dataset:{}})");assert.equal(run('growthVisible'),false);assert.equal(node('#growth-amount').hidden,true);
run("dashboardAction('dash-growth',{dataset:{}})");assert.equal(run('growthVisible'),true);assert.equal(node('#growth-amount').hidden,false);
// Monthly asset snapshots use the journal cutoff; card payment does not change net worth.
assert.equal(run('flowFacts()[4].assets'),run("netWorth('2026-09-30')"));
run("dashboardAction('dash-flow-detail',{dataset:{}})");assert.equal(run('dateFilter'),'');
run("dateFilter='';route('overview')");
assert.equal(run('dashboardCanvases.size'),3);assert.ok(!node('#main').innerHTML.includes('id="budget-toggle"'));assert.ok(!node('#main').innerHTML.includes('id="spending-categories"'));assert.ok(!run('dailyCalendar()').includes('calendar-amount'));assert.equal(node('#budget-percent').textContent,'55%');assert.equal(run('budgetUsage()'),17519/32000*100);
const budgetPlot=node('#budget-canvas');
assert.equal(run('budgetBuckets().length'),5);assert.equal(run('new Set(budgetBuckets().map(b=>b.color)).size'),5);assert.equal(run('budgetBuckets().reduce((n,b)=>n+b.used,0)'),17519);
assert.ok(run('budgetBuckets().some(b=>b.category==="訂閱服務"&&b.limit===null&&b.used===179)'));assert.ok(!run('budgetBuckets().some(b=>b.category==="其他與預留")'));
for(const width of [120,280,336,420]){context.__width=width;const regions=run('budgetRegions(__width,52)'),positive=regions.filter(r=>r.value>0);assert.ok(regions.every(r=>r.x>=0&&r.x+r.w<=width+.001&&r.y>=0&&r.y+r.h<=52));const usedSegments=positive.filter(r=>r.id!=='available'),usedWidth=usedSegments.reduce((n,r)=>n+r.w,0);assert.ok(usedSegments.every(r=>r.w>=Math.min(28,usedWidth/usedSegments.length)-.001));assert.ok(Math.abs(usedWidth/(width-4)-17519/32000)<1e-8);assert.ok(Math.abs(regions.reduce((n,r)=>n+r.w,0)-(width-4))<1e-8);for(const r of positive){context.__region=r;assert.equal(run('budgetHit(__region.x+__region.w/2,22,__width,52)'),r.index);}}
assert.equal(run('BUDGET_HEIGHT'),52);assert.equal(budgetPlot.height,52);assert.equal(node('#spending-used').textContent,'TWD 17,519');assert.equal(node('#budget-limit').textContent,'／ 32,000');assert.equal(node('#budget-remaining').textContent,'TWD 14,481');
const foodIndex=run('budgetBuckets().findIndex(b=>b.category==="飲食日常")'),food=run('budgetRegions(336,52).find(b=>b.category==="飲食日常")'),foodTap={pointerId:6,clientX:food.x+food.w/2,clientY:22,pointerType:'touch'};
budgetPlot.listeners.pointerdown(foodTap);budgetPlot.listeners.pointerup(foodTap);assert.equal(run('budgetFocus'),foodIndex);assert.equal(node('#spending-label').textContent,'飲食日常');assert.equal(node('#spending-used').textContent,'TWD 3,070');assert.equal(node('#budget-limit').textContent,'／ 8,000');assert.equal(node('#budget-remaining').textContent,'TWD 4,930');assert.equal(run('budgetSummary().status'),'占本月支出 17.5%');assert.equal(run('page'),'overview');
run('clearBudgetOutside({target:{closest:()=>null}})');assert.equal(run('budgetFocus'),-1);budgetPlot.listeners.pointerleave({});assert.equal(run('budgetFocus'),-1);
context.__foodIndex=foodIndex;run("dashboardAction('dash-budget-category',{dataset:{index:String(__foodIndex)}})");assert.equal(run('budgetFocus'),foodIndex);run("dashboardAction('dash-budget-category',{dataset:{index:String(__foodIndex)}})");assert.equal(run('budgetFocus'),-1);
run("selectBudgetFocus(budgetBuckets().findIndex(b=>b.category==='訂閱服務'))");assert.equal(node('#spending-used').textContent,'TWD 179');assert.equal(node('#budget-remaining').textContent,'未設定');assert.equal(node('#budget-limit').textContent,'');assert.equal(run('budgetSummary().status'),'未設定分類預算');budgetPlot.listeners.keyup({key:'Escape'});assert.equal(run('budgetFocus'),-1);
budgetPlot.listeners.keydown({key:'End',preventDefault(){}});assert.equal(run('budgetFocus'),4);budgetPlot.listeners.keydown({key:'Home',preventDefault(){}});assert.equal(run('budgetFocus'),-1);
budgetPlot.listeners.pointermove({...foodTap,pointerType:'mouse'});flushHover();assert.equal(run('budgetFocus'),foodIndex);budgetPlot.listeners.pointerleave({});assert.equal(run('budgetFocus'),-1);
budgetPlot.listeners.pointerdown({...foodTap,clientX:330});budgetPlot.listeners.pointerup({});assert.equal(run('budgetFocus'),-1);
run("state.budgets.push({id:'zero-used',category:'其他支出',limit:500});route('overview');selectBudgetFocus(budgetBuckets().findIndex(b=>b.id==='zero-used'))");assert.equal(node('#spending-used').textContent,'TWD 0');assert.equal(node('#budget-remaining').textContent,'TWD 500');assert.equal(node('#spending-label').textContent,'其他支出');assert.equal(run('budgetRegions(336,52).find(b=>b.id==="zero-used").w'),0);run('state.budgets.pop();selectBudgetFocus(-1);route("overview")');
assert.equal(run('palette.expense'),fs.readFileSync('dist/interface-system.css','utf8').match(/--ui-negative:(#[0-9a-f]{6})/)[1]);assert.equal(run('palette.income'),fs.readFileSync('dist/interface-system.css','utf8').match(/--ui-positive:(#[0-9a-f]{6})/)[1]);assert.ok(node('#main').innerHTML.includes('home-surplus'));assert.ok(!node('#main').innerHTML.includes('class="net-value"'));
run("dashboardAction('dash-budget-edit',{dataset:{}})");submit({amount:'30000'});assert.equal(run('state.budgets[0].limit'),30000);
run('state.budgets[0].limit=1000;refreshBudget()');assert.equal(node('#budget-caption').textContent,'超出預算');assert.equal(node('#budget-remaining').textContent,'TWD 16,519');assert.equal(run('budgetRegions(336,52).find(b=>b.id==="available").w'),0);
run("state.budgets[1].limit=1000;selectBudgetFocus(budgetBuckets().findIndex(b=>b.category==='飲食日常'))");assert.equal(node('#budget-remaining').textContent,'TWD 2,070');assert.equal(node('#budget-caption').textContent,'超出預算');assert.ok(budgetPlot.attributes['aria-valuetext'].includes('超出預算 TWD 2,070'));
run('state.budgets[0].limit=32000;state.budgets[1].limit=8000;selectBudgetFocus(-1);refreshBudget()');
run("globalThis.mergeSnapshot=state.tx;state.tx=[];route('overview')");assert.equal(run('budgetBuckets().length'),4);assert.equal(run('budgetRegions(336,52).find(b=>b.id==="available").w'),332);assert.equal(node('#budget-remaining').textContent,'TWD 32,000');run('state.budgets[0].limit=0;refreshBudget()');assert.ok(run('budgetRegions(336,52).every(b=>Number.isFinite(b.w))'));
run("state.budgets[0].limit=32000;state.tx=[{id:'only-refund',date:'2026-10-04',type:'refund',amount:500,account:'cash',category:'訂閱服務'}];route('overview')");assert.equal(node('#budget-remaining').textContent,'TWD 32,500');assert.equal(run('budgetSummary().status'),'含退款抵扣 TWD 500');assert.ok(run('budgetRegions(336,52).every(b=>b.w>=0)'));run('state.tx=mergeSnapshot;route("overview")');
assert.ok(!node('#main').innerHTML.includes('data-action="dash-assets"'));
run("assetMode='assets';assetIndex=-1;route('overview')");
const allocation=node('#allocation-canvas'),allocationChart=run("dashboardCanvases.get('allocation-canvas')");
const investmentTile=run("splitTiles(assetFacts(),0,0,336,160).find(t=>t.kind==='investment')");
const accountsBefore=run("allocationTiles(336,160).filter(t=>t.kind==='group')");
assert.equal(accountsBefore.length,3);
assert.equal(node('#asset-amount').textContent,run('overviewCurrency(allocationTotal())'));assert.equal(node('#asset-name').textContent,'全部資產');
assert.equal(run('allocationOpacity(false)'),1);
assert.equal(node('#asset-amount').hidden,false);
const tap={pointerId:4,clientX:investmentTile.x+investmentTile.w/2,clientY:investmentTile.y+investmentTile.h/2,pointerType:'touch'};
// Scrubbing selects investment without drilling into it.
allocation.listeners.pointerdown({...tap,clientX:tap.clientX-10});
allocation.listeners.pointermove(tap);allocation.listeners.pointerup(tap);allocation.listeners.click({});
assert.equal(run('assetMode'),'assets');
// A deliberate tap drills in without changing page or replacing the chart.
allocation.listeners.pointerdown(tap);allocation.listeners.pointerup(tap);allocation.listeners.click({});
assert.equal(run('assetMode'),'holdings');assert.equal(run('page'),'overview');
assert.equal(run("dashboardCanvases.get('allocation-canvas')"),allocationChart);
assert.equal(node('#allocation-status').textContent,'返回資產');
assert.equal(run('holdingFacts().reduce((n,a)=>n+a.value,0)'),investmentTile.value);
assert.equal(run("allocationTiles(336,160).filter(t=>t.kind==='account').length"),0);
const childTiles=run("allocationTiles(336,160).filter(t=>t.kind==='holding')");
assert.equal(childTiles.length,run('holdingFacts().length'));
for(const t of childTiles){assert.ok(t.x>=0&&t.y>=0&&t.x+t.w<=336.001&&t.y+t.h<=160.001);}
assert.ok(Math.abs(childTiles.reduce((n,t)=>n+t.w*t.h,0)-336*160)<.001);
assert.ok(!node('#main').innerHTML.includes('allocation-legend'));
assert.equal(node('#asset-amount').textContent,run('nt(investmentTotal())'));assert.equal(node('#asset-name').textContent,'全部持股');assert.equal(run('allocationOpacity(false)'),1);
assert.equal(node('#asset-amount').hidden,false);assert.ok(run('holdingFacts().every(h=>h.name===h.id)'));assert.equal(run('new Set(holdingFacts().map(h=>h.color)).size'),12);
for(const [width,height] of [[280,160],[336,160],[420,160]]){
 context.__dimensions={width,height};const sized=run('splitTiles(holdingFacts(),0,0,__dimensions.width,__dimensions.height)');
 assert.ok(sized.every(t=>Number.isFinite(t.w)&&Number.isFinite(t.h)&&t.w>0&&t.h>0));
 assert.ok(Math.abs(sized.reduce((n,t)=>n+t.w*t.h,0)-width*height)<.001);
 const total=sized.reduce((n,t)=>n+t.displayWeight,0);
 for(const t of sized){assert.ok(Math.abs(t.w*t.h/(width*height)-t.displayWeight/total)<1e-8);context.__tile=t;const label=run("tileLabel(document.querySelector('#allocation-canvas').getContext('2d'),__tile)");assert.equal(label.lines.join(''),t.id);assert.equal(label.lines.length,1);assert.ok(t.h>label.font+8);}
 assert.ok(Math.min(...sized.map(t=>t.w*t.h))/(width*height)>.035);
 assert.ok(sized.every((t,i)=>i===0||t.displayWeight<=sized[i-1].displayWeight));
}
const allocationCtx=allocation.getContext('2d');
const tinyLabel=run("tileLabel(document.querySelector('#allocation-canvas').getContext('2d'),{name:'長到放不進去的帳戶名稱',kind:'account',w:25,h:25},11)");
assert.equal(tinyLabel.mode,'name');assert.equal(tinyLabel.lines.join(''),tinyLabel.label);assert.equal(tinyLabel.label,'長到放不進去的帳戶名稱');
run("allocationTransition={direction:'open',origin:allocationOrigin()};drawAllocation(document.querySelector('#allocation-canvas').getContext('2d'),336,160,.5);drawAllocation(document.querySelector('#allocation-canvas').getContext('2d'),336,160,1)");
const smallHolding=childTiles.find(t=>t.id==='2603'),holdTap={...tap,clientX:smallHolding.x+smallHolding.w/2,clientY:smallHolding.y+smallHolding.h/2};
allocation.listeners.pointerdown(holdTap);now+=300;allocation.listeners.pointerup(holdTap);allocation.listeners.click({});allocation.listeners.pointerleave({});
assert.equal(run('assetMode'),'holdings');assert.equal(node('#asset-name').textContent,'2603');assert.equal(node('#asset-amount').textContent,'TWD 564');
run("dashboardAction('dash-asset-all',{dataset:{}})");assert.equal(run('assetIndex'),-1);assert.equal(node('#asset-amount').textContent,run('nt(investmentTotal())'));
assert.equal(Number(allocation.attributes['aria-valuemax']),run('assetFacts().length'));
allocation.listeners.keydown({key:'End',preventDefault(){}});assert.equal(run('assetIndex'),run('assetFacts().length-1'));
// Tapping a holding folds only the investment block back into its parent.
const child=childTiles[0],childTap={...tap,clientX:child.x+child.w/2,clientY:child.y+child.h/2};
allocation.listeners.pointerdown(childTap);allocation.listeners.pointerup(childTap);allocation.listeners.click({});assert.equal(run('assetMode'),'assets');
assert.equal(run('assetIndex'),-1);assert.equal(node('#asset-name').textContent,'全部資產');
assert.equal(run("dashboardCanvases.get('allocation-canvas')"),allocationChart);
assert.equal(node('#allocation-status').hidden,true);
run("allocationTransition={direction:'close',origin:allocationOrigin()};drawAllocation(document.querySelector('#allocation-canvas').getContext('2d'),336,160,.5);drawAllocation(document.querySelector('#allocation-canvas').getContext('2d'),336,160,1)");
assert.deepEqual(run("allocationTiles(336,160).filter(t=>t.kind==='group')"),accountsBefore);
run("selectAsset(assetFacts().findIndex(a=>a.kind==='investment'))");allocation.listeners.keydown({key:'Enter',preventDefault(){}});assert.equal(run('assetMode'),'holdings');
// Any account block also returns, without routing to the accounts page.
const other=accountsBefore[0],otherTap={...tap,clientX:other.x+other.w/2,clientY:other.y+other.h/2};
allocation.listeners.pointerdown(otherTap);allocation.listeners.pointerup(otherTap);allocation.listeners.click({});assert.equal(run('assetMode'),'assets');assert.equal(run('page'),'overview');
run("openInvestment();dashboardAction('dash-asset-detail',{dataset:{}})");assert.equal(run('assetMode'),'assets');
// Groups expand into their own accounts, using current balances rather than spending.
for(const [id,count] of [['banks',5],['wallets',4],['cash-group',2]]){
 context.__accountId=id;const parent=run('assetFacts().find(a=>a.id===__accountId)');
 run("selectAsset(assetFacts().findIndex(a=>a.id===__accountId));openAllocation()");
 assert.equal(run('assetMode'),'account');assert.equal(run('page'),'overview');assert.equal(run("dashboardCanvases.get('allocation-canvas')"),allocationChart);
 assert.equal(node('#allocation-context').textContent,parent.name+' · 帳戶');
 assert.equal(run('assetFacts().length'),count);
 assert.equal(run('assetFacts().reduce((n,a)=>n+a.value,0)'),parent.value);assert.equal(node('#asset-name').textContent,'全部帳戶');assert.equal(node('#asset-amount').textContent,run('overviewCurrency(allocationTotal())'));assert.equal(run('allocationOpacity(false)'),1);
 assert.ok(run('assetFacts().every(a=>a.kind==="account"&&a.value===Math.max(0,balance(account(a.id))))'));
 allocation.listeners.keydown({key:'End',preventDefault(){}});
 assert.equal(node('#asset-amount').textContent,run('nt(assetFacts()[assetIndex].value)'));
 assert.equal(node('#asset-amount').hidden,false);
 assert.ok(!node('#main').innerHTML.includes('allocation-legend'));
for(const width of [280,336,420]){context.__width=width;const accountTiles=run('allocationTiles(__width,160)');for(const tile of accountTiles){context.__tile=tile;const label=run("tileLabel(document.querySelector('#allocation-canvas').getContext('2d'),__tile)");assert.equal(label.lines.join(''),tile.name);assert.ok(label.lines.length*(label.font+3)<tile.h-6);}}
 const tiles=run('allocationTiles(336,160)');const t=tiles.at(-1),tapAccount={...tap,clientX:t.x+t.w/2,clientY:t.y+t.h/2};
 allocation.listeners.pointerdown(tapAccount);allocation.listeners.pointerup(tapAccount);allocation.listeners.click({});
 assert.equal(run('assetMode'),'assets');assert.equal(run('assetIndex'),-1);
 assert.equal(node('#asset-amount').textContent,run('overviewCurrency(allocationTotal())'));
}
// Wallet transfers change the respective account balance, not monthly income or expense.
run("globalThis.walletTotals=totals();globalThis.walletNet=netWorth();globalThis.walletBefore=balance(account('line-pay'));transfer()");
submit({amount:'500',from:'bank',to:'line-pay',date:'2026-10-04',note:'錢包加值'});
assert.deepEqual(run('totals()'),run('walletTotals'));assert.equal(run('netWorth()'),run('walletNet'));
assert.equal(run("balance(account('line-pay'))"),run('walletBefore')+500);
run("assetMode='assets';route('overview')");
run("state.tx.push({id:'negative-month',date:'2026-09-29',type:'expense',amount:100000,account:'bank',category:'其他支出'});selectFlow(4)");
assert.ok(run('flowFacts()[flowIndex].balance')<0);assert.ok(node('#flow-balance').textContent.includes('-'));
assert.equal(node('#flow-income').textContent,run('nt(flowFacts()[flowIndex].income)'));
assert.equal(node('#flow-expense').textContent,run('nt(flowFacts()[flowIndex].expense)'));
const tiles=run('splitTiles(assetFacts(),0,0,300,126)');
assert.ok(Math.abs(tiles.reduce((n,t)=>n+t.w*t.h,0)-300*126)<.001);
assert.ok(tiles.every(t=>t.w>0&&t.h>0));
run("month='2027-02';flowIndex=-1;route('overview')");
assert.equal(run('dailyFacts().length'),28);assert.ok(!node('#main').innerHTML.includes('NaN'));
run("month='2026-10';state.privacy=true;route('overview')");
assert.ok((node('#main').innerHTML.match(/••••/g)||[]).length>6);assert.ok(!node('#main').innerHTML.includes('17,519'));assert.ok(!node('#main').innerHTML.includes('52,000'));
assert.equal(run('money(17519)'),'17,519');assert.equal(run('totalMoney(netWorth())'),'••••');
run("route('ledger')");assert.ok(!node('#main').innerHTML.includes('••••'));
run("route('overview');selectBudgetFocus(-1)");node('#budget-canvas').listeners.pointermove({pointerType:'mouse',clientX:10,clientY:22});
run("route('ledger')");flushHover();assert.equal(run('budgetFocus'),-1);assert.equal(run('dashboardCanvases.size'),0);
run("assetMode='assets';route('overview');selectAsset(0)");assert.equal(run('allocationOpacity(false)'),.32);assert.equal(run('allocationOpacity(true)'),1);node('#allocation-canvas').listeners.pointerleave({});assert.equal(run('assetIndex'),-1);run('selectAsset(0)');run("dashboardAction('dash-asset-all',{dataset:{}})");assert.equal(run('assetIndex'),-1);assert.equal(run('allocationOpacity(false)'),1);assert.equal(node('#asset-amount').textContent,run('overviewCurrency(allocationTotal())'));
console.log('PASS: unified category spending and budget panel; exact remaining and category limits, unbudgeted and zero-spend categories, minimum-first segments, outside reset, keyboard and hover; native Monday-to-Sunday calendar with month-edge dates, weekly navigation, refunds, and 503-record horizontal details; investment and allocation interactions.');
// Standalone renderer atlas for QA; not a browser screenshot.
if(process.env.CANVAS_QA_PATH){
 run("budgetExpanded=true;state=seed();month='2026-10';flowIndex=5;budgetFocus=-1;assetMode='assets';assetIndex=-1;heatDay=4;route('overview')");
 const atlas=createCanvas(720,780),ctx=atlas.getContext('2d');ctx.fillStyle='#f7f2e7';ctx.fillRect(0,0,720,780);
 const charts=[['#flow-canvas',18,35,'Cash flow'],['#budget-canvas',18,195,'Spending and budget'],['#allocation-canvas',365,195,'Assets']];
 for(const [id,x,y,label] of charts){ctx.fillStyle='#3d4438';ctx.font='12px sans-serif';ctx.fillText(label,x,y-10);if(id==='#budget-canvas'){const compact=createCanvas(336,52);context.__compact=compact.getContext('2d');run('drawBudget(__compact,336,52,1)');ctx.drawImage(compact,x,y);}else ctx.drawImage(node(id).native,x,y);}
 run("selectAsset(assetFacts().findIndex(a=>a.kind==='investment'));openInvestment()");ctx.fillStyle='#3d4438';ctx.fillText('Investment block expanded',365,395);ctx.drawImage(node('#allocation-canvas').native,365,405);
 run("backToAssets();selectAsset(assetFacts().findIndex(a=>a.id==='banks'));openAllocation()");ctx.fillStyle='#3d4438';ctx.fillText('Bank accounts expanded',18,595);ctx.drawImage(node('#allocation-canvas').native,18,605);
 run("backToAssets();selectAsset(assetFacts().findIndex(a=>a.id==='wallets'));openAllocation()");ctx.fillStyle='#3d4438';ctx.fillText('Payment accounts expanded',365,595);ctx.drawImage(node('#allocation-canvas').native,365,605);
 fs.writeFileSync(process.env.CANVAS_QA_PATH,atlas.toBuffer('image/png'));
}

// Calendar tags derive from posted records, never daily market movements.
run("globalThis.tagSnapshot=state.tx;state.tx=[{id:'a',date:'2026-10-04',type:'expense',amount:1},{id:'b',date:'2026-10-04',type:'income',amount:2},{id:'c',date:'2026-10-04',type:'transfer',amount:3},{id:'d',date:'2026-10-04',type:'income',amount:4,dividend:'0050'}]");
for(const kind of ['expense','income','transfer','investment'])assert.ok(run('dayActivityTags(4)').includes('activity-'+kind));assert.equal((run('dayActivityTags(4)').match(/class="activity-tag/g)||[]).length,4);assert.equal(run('dayActivityTags(3)'),'');run('state.tx=tagSnapshot');
run("globalThis.reminderSnapshot=state.recurring;state.recurring=[{id:'due-test',active:true,day:2,amount:100,name:'到期'},{id:'future-test',active:true,day:28,amount:200,name:'月底'}];month='2026-10'");assert.equal(run('recurringReminderFacts().due.length'),1);assert.equal(run('recurringReminderFacts().upcoming.length'),1);run("month='2026-09'");assert.equal(run('recurringReminderFacts().due.length'),2);run("month='2026-11'");assert.equal(run('recurringReminderFacts().due.length'),0);run("state.recurring=reminderSnapshot;month='2026-10'");assert.ok(run('investmentTodayChart()').includes('investment-bars'));assert.ok(!run('investmentTodayChart()').includes('NaN'));
console.log('PASS: posted activity tags, due versus upcoming reminders, monthly summary and illustrative holding chart.');

for(const width of [120,280,336,420]){context.__width=width;run("state=seed();month='2026-10'");const boundary=run('budgetRegions(__width,52).find(r=>r.id===\"available\").x');assert.ok(Math.abs(boundary-(2+(width-4)*run('budgetUsage()')/100))<1e-8);}console.log('PASS: used-budget boundary matches true percentage at every tested width.');

run("state=seed();month='2026-10';route('overview')");const ordered=node('#main').innerHTML;assert.ok(ordered.indexOf('class="heatmap-section"')<ordered.indexOf('class="today-investment"'));assert.ok(ordered.indexOf('class="today-investment"')<ordered.indexOf('class="spending-budget-section"'));assert.equal((ordered.match(/class="holding-performance"/g)||[]).length,run('state.holdings.length'));console.log('PASS: weekly records precede investment; all holding charts remain visible in the document.');

assert.equal(run('investmentBarWidth(1,[1,10,100])'),12);assert.equal(run('investmentBarWidth(100,[1,10,100])'),50);assert.equal(run('investmentBarWidth(-1,[1,10,100])'),12);assert.equal(run('investmentBarWidth(0,[0,1,100])'),0);assert.equal(run('investmentBarWidth(10,[10,10])'),50);assert.equal(run('investmentBarWidth(0,[0,0])'),0);assert.ok(run('investmentBarWidth(10,[1,10,100])')>12);console.log('PASS: minimum-first holding bars preserve order, shared gain/loss scale, zero and equal-value cases.');
run("state=seed();month='2026-10';route('ledger')");assert.ok(!node('#main').innerHTML.includes('class="chips"'));assert.ok(!node('#main').innerHTML.includes('id="search"'));assert.ok(!run('txRow(state.tx[0])').includes('<small>10 /'));run('ledgerFilters()');run("Object.assign(ledgerFilterDraft,{types:['expense','refund'],categories:['飲食日常'],accounts:['cash'],dateFrom:'2026-10-04',dateTo:'2026-10-04'})");submit({});assert.equal(run('filter'),'expense');assert.equal(run('ledgerAccountFilter'),'cash');assert.ok(run('ledgerList()').includes('dense-day-demo'));run('ledgerSearch()');submit({keyword:'不存在的紀錄字串'});assert.ok(run('ledgerList()').includes('沒有符合'));run("document.querySelector('#main').innerHTML=ledger()");for(const handler of docListeners.click||[])handler({target:{closest:selector=>selector==='[data-action]'?{dataset:{action:'ledger-clear'}}:null}});assert.equal(run('ledgerAccountFilter'),'');assert.equal(run('filter'),'all');assert.equal(run('search'),'');console.log('PASS: compact ledger search, combined filters and reset.');

run("state=seed();month='2026-10';route('ledger')");assert.ok(!node('#main').innerHTML.includes('ledger-summary'));assert.ok(node('#main').innerHTML.includes('app-period'));assert.ok(node('#main').innerHTML.includes('month-chevron previous'));assert.ok(node('#main').innerHTML.includes('>2026 / 10<'));console.log('PASS: journal has no duplicate monthly summary and retains month navigation.');

run("state=seed();month='2026-10';route('ledger')");assert.ok(node('#main').innerHTML.includes('ledger-comparison'));assert.ok(run('ledgerComparison()').includes('comparison-single'));assert.ok(run('ledgerComparison()').includes('width:'+52000/(52000+17519)*100+'%'));assert.ok(run('ledgerComparison()').includes('52,000'));run("globalThis.compareSnapshot=state.tx;state.tx=[]");assert.ok(!run('ledgerComparison()').includes('NaN'));assert.ok(run('ledgerComparison()').includes('本月尚無收支'));assert.equal((run('ledgerComparison()').match(/width:0%/g)||[]).length,2);run("state.tx=[{id:'comparison-refund',date:'2026-10-04',type:'refund',amount:500,account:'cash',category:'飲食日常'}]");assert.ok(run('ledgerComparison()').includes('淨退款'));run('state.tx=compareSnapshot');console.log('PASS: month comparison uses a shared scale; empty and net-refund months remain readable.');

run("route('ledger')");for(const kind of ['income','refund','transfer']){context.__kind=kind;assert.ok(run('journalIcon({type:__kind,category:"其他支出"})').includes('journal-icon'));}assert.notEqual(run('journalIcon({type:"income",dividend:"0050"})'),run('journalIcon({type:"income"})'));assert.ok(run('txRow(state.tx[0])').includes('journal-icon'));console.log('PASS: journal glyphs distinguish income, refund, transfer, dividend and category expense.');

run("state=seed();txDetail(state.tx[0].id)");assert.equal(node('#modal-title').textContent,'紀錄明細');assert.ok(node('#modal-body').innerHTML.includes('record-fact-icon'));assert.ok(node('#modal-body').innerHTML.includes('record-detail-choices'));assert.equal(node('#modal-submit').textContent,'刪除');run("globalThis.detailTxSnapshot=state.tx;state.tx=[{id:'detail-transfer',type:'transfer',amount:123,date:'2026-10-04',account:'bank',to:'cash',category:'轉帳',note:'<script>測試</script>'}];txDetail('detail-transfer')");assert.ok(node('#modal-body').innerHTML.includes('record-fact-transfer'));assert.ok(!node('#modal-body').innerHTML.includes('<script>'));assert.ok(node('#modal-body').innerHTML.includes('轉出帳戶'));run('state.tx=detailTxSnapshot');console.log('PASS: entry detail supports transfer accounts, complete values, escaped notes and existing reversal confirmation.');

run("state=seed();month='2026-10';globalThis.editTarget=state.tx.find(t=>t.type==='expense'&&!t.recurring&&t.date.startsWith(month));globalThis.editId=editTarget.id;globalThis.oldAmount=editTarget.amount;globalThis.oldBalance=balance(account(editTarget.account));globalThis.oldExpense=totals().expense;txEdit(editId)");const editAccount=run('editTarget.account'),editDate=run('editTarget.date'),editCategory=run('editTarget.category');submit({amount:String(run('oldAmount')+100),date:editDate,account:editAccount,category:editCategory,note:'完整備註更新'});assert.equal(run('totals().expense'),run('oldExpense')+100);assert.equal(run('balance(account(editTarget.account))'),run('oldBalance')-100);assert.equal(run('state.tx.filter(t=>t.id===editId).length'),1);run('txDetail(editId)');assert.ok(node('#modal-body').innerHTML.includes('完整備註更新'));assert.equal(node('#modal .modal-actions .secondary').attributes['data-action'],'tx-edit');assert.ok(!node('#modal-body').innerHTML.includes('entry-detail-value'));run("state.tx=[{id:'edit-transfer',type:'transfer',amount:123,date:'2026-10-04',account:'bank',to:'cash',category:'轉帳',note:'轉帳'}];txEdit('edit-transfer')");assert.throws(()=>submit({amount:'200',date:'2026-10-04',account:'bank',to:'bank',note:''}),/不同/);assert.equal(run('state.tx[0].amount'),123);console.log('PASS: compact entry offers editing; edits update balances and totals once, reject same-account transfers atomically.');

run("state.tx=[{id:'edit-recurring',type:'expense',amount:100,date:'2026-10-04',account:'bank',category:'居家生活',note:'房租',recurring:'rent'}];txEdit('edit-recurring')");assert.throws(()=>submit({amount:'100',date:'2026-11-04',account:'bank',category:'居家生活',note:''}),/原入帳月份/);assert.equal(run('state.tx[0].date'),'2026-10-04');run("state.tx=[{id:'edit-dividend',type:'income',amount:100,date:'2026-10-04',account:'bank',category:'股息收入',note:'股息',dividend:'0050'}];txEdit('edit-dividend')");submit({amount:'200',date:'2026-10-04',account:'bank',holding:'0050',note:'配息更正'});assert.equal(run('state.tx[0].dividend'),'0050');assert.equal(run('state.tx[0].category'),'股息收入');console.log('PASS: recurring edit stays in its original period and dividend edit preserves linkage.');

run("state=seed();month='2026-10';globalThis.deleteTx=state.tx.find(t=>t.type==='expense'&&t.date.startsWith(month));globalThis.deleteId=deleteTx.id;globalThis.deleteAmount=deleteTx.amount;globalThis.deleteExpense=totals().expense;txDetail(deleteId)");assert.equal(node('#modal .modal-actions .secondary').textContent,'編輯');assert.equal(node('#modal-submit').textContent,'刪除');assert.equal(node('#modal-submit').attributes.type,'button');assert.equal(node('#modal-submit').attributes['data-action'],'tx-delete-confirm');assert.ok(!node('#modal-body').innerHTML.includes('entry-detail-management'));run('txDeleteConfirm(deleteId)');assert.equal(node('#modal-submit').attributes.type,'submit');assert.equal(node('#modal-submit').attributes['data-action'],undefined);assert.equal(run('state.tx.filter(t=>t.id===deleteId).length'),1);submit({});assert.equal(run('state.tx.filter(t=>t.id===deleteId).length'),0);assert.equal(run('totals().expense'),run('deleteExpense-deleteAmount'));run('ledgerSearch()');assert.equal(node('#modal .modal-actions .secondary').textContent,'取消');console.log('PASS: paired edit/delete footer; deletion waits for confirmation, updates totals and resets modal actions.');

run("state=seed();txEdit(state.tx.find(t=>t.type==='expense').id)");assert.ok(node('#modal-body').innerHTML.includes('edit-picker'));assert.ok(!node('#modal-body').innerHTML.includes('<select'));run("globalThis.pickSummary={textContent:''};globalThis.pickPanel={querySelector:()=>pickSummary,querySelectorAll:()=>[],open:true};globalThis.pickButton={dataset:{name:'account',value:'cash',label:'現金'},closest:()=>pickPanel};document.querySelector('#f-note').value='尚未儲存的備註';pickEditOption(pickButton)");assert.equal(node('#f-account').value,'cash');assert.equal(node('#f-note').value,'尚未儲存的備註');assert.equal(node('#picker-label-account').textContent,'現金');console.log('PASS: field selection updates values without resetting the draft.');

run("state=seed();txEdit(state.tx.find(t=>t.type==='expense').id)");assert.ok(!node('#modal-body').innerHTML.includes('type="date"'));assert.ok(node('#modal-body').innerHTML.includes('field-date'));assert.ok(!node('#modal-body').innerHTML.includes('edit-calendar-days'));run("editCalendarMonth='2028-02';editCalendarMin='2026-01';editCalendarMax='2030-12'");assert.equal((run('editCalendar()').match(/data-action="edit-date-select"/g)||[]).length,29);run("document.querySelector('#f-note').value='保留草稿';moveEditCalendar(1);selectEditDate('2028-03-15')");assert.equal(run('editCalendarMonth'),'2028-03');assert.equal(node('#f-date').value,'2028-03-15');assert.equal(node('#f-note').value,'保留草稿');run("editCalendarMonth='2030-12';moveEditCalendar(1)");assert.equal(run('editCalendarMonth'),'2030-12');run("editCalendarMin='2026-10';editCalendarMax='2026-10';editCalendarMonth='2026-10';moveEditCalendar(-1)");assert.equal(run('editCalendarMonth'),'2026-10');console.log('PASS: custom calendar leap days, month boundaries, recurring limits and draft preservation.');

for(const calendarMonth of ['2026-02','2026-03','2026-08','2028-02']){context.__calendarMonth=calendarMonth;run('editCalendarMonth=__calendarMonth');const calendarMarkup=run('editCalendar()');const grid=calendarMarkup.split('class="edit-calendar-days"')[1];assert.equal((grid.match(/<button/g)||[]).length,42);assert.ok(calendarMarkup.includes('outside'));}run("state=seed();txEdit(state.tx.find(t=>t.type==='expense').id)");assert.ok(node('#modal-body').innerHTML.includes('data-kind="account"'));assert.ok(node('#modal-body').innerHTML.includes('data-kind="category"'));console.log('PASS: every edit month uses 42 cells and both selection grids retain icons and values.');

assert.equal(run('calculateEntryExpression("100+20×3")'),160);assert.equal(run('calculateEntryExpression("100÷4−5")'),20);assert.equal(run('calculateEntryExpression("0.1+0.2")'),0.3);assert.throws(()=>run('calculateEntryExpression("1÷0")'),/零/);assert.throws(()=>run('calculateEntryExpression("1+")'),/完成/);assert.throws(()=>run('calculateEntryExpression("1abc")'),/格式/);run("state=seed();txEdit(state.tx.find(t=>t.type==='expense').id);useEntryCalcKey('2');useEntryCalcKey('0');useEntryCalcKey('+');useEntryCalcKey('3');useEntryCalcKey('×');useEntryCalcKey('4');useEntryCalcKey('=')");assert.equal(node('#f-amount').value,'32');assert.equal(node('#edit-calc-amount').textContent,'32');assert.ok(!node('#modal-body').innerHTML.includes('type="number"'));run("useEntryCalcKey('C');useEntryCalcKey('1');useEntryCalcKey('÷');useEntryCalcKey('0');useEntryCalcKey('完成')");assert.ok(node('#edit-calc-message').textContent.includes('零'));console.log('PASS: built-in calculator precedence, decimals, validation and amount binding.');
run("state=seed();globalThis.calculatedTx=state.tx.find(t=>t.type==='expense'&&t.date.startsWith('2026-10'));txEdit(calculatedTx.id);useEntryCalcKey('2');useEntryCalcKey('0');useEntryCalcKey('+');useEntryCalcKey('3');useEntryCalcKey('×');useEntryCalcKey('4');useEntryCalcKey('完成')");submit({amount:'999',date:run('calculatedTx.date'),account:run('calculatedTx.account'),category:run('calculatedTx.category'),note:'計算金額測試'});assert.equal(run('calculatedTx.amount'),32);console.log('PASS: saving an edited record uses the calculator result.');

run("state=seed();txEdit(state.tx.find(t=>t.type==='expense').id)");assert.ok(!node('#modal-body').innerHTML.includes('edit-option-check'));assert.ok(!node('#modal-body').innerHTML.includes('>計算機<'));assert.ok(node('#modal-body').innerHTML.includes('calc-symbol'));assert.notEqual(run("accountPickerIcon(account('cash'))"),run("accountPickerIcon(account('home-cash'))"));assert.notEqual(run("accountPickerIcon(account('bank'))"),run("accountPickerIcon(account('digital'))"));for(const op of ['+','−','×','÷','=']){context.__op=op;assert.ok(run('calcIcon(__op)').includes('viewBox="0 0 24 24"'));}console.log('PASS: distinct account glyphs, no selection dots, and a shared calculator symbol grid.');

// Exercise the full posted-record schema, including source and destination semantics.
run(`state=seed();ledgerAdvanced=null;filter='all';categoryFilter='';ledgerAccountFilter='';dateFilter='';search='';month='2026-10';
state.tx.push(
 {id:'filter-refund',date:'2026-10-04',type:'refund',amount:150,account:'cash',category:'飲食日常',note:'退款測試'},
 {id:'filter-transfer',date:'2026-10-05',type:'transfer',amount:300,account:'bank',to:'digital',category:'轉帳',note:'數位轉入'},
 {id:'filter-card-pay',date:'2026-10-05',type:'transfer',amount:900,account:'bank',to:'card',category:'轉帳',note:'繳卡費'},
 {id:'filter-dividend',date:'2026-09-30',type:'income',amount:300,account:'digital',category:'股息收入',note:'九月配息',dividend:'0050'},
 {id:'filter-reversed',date:'2026-10-04',type:'expense',amount:150,account:'cash',category:'飲食日常',note:'已撤銷餐飲',reversed:true}
);route('ledger')`);
const filtered=(f,keyword='')=>{context.__filter=f;context.__keyword=keyword;return Array.from(run('ledgerFilteredTransactions({...defaultLedgerFilters(),...__filter},__keyword).map(t=>t.id)'));};
assert.equal(filtered({}).length,19);
assert.equal(filtered({scope:'all'}).length,74);
assert.deepEqual(filtered({types:['refund']}),['filter-refund']);
assert.deepEqual(filtered({types:['income','refund'],accounts:['cash','bank']}),['filter-refund','seed-55']);
assert.deepEqual(filtered({types:['expense','refund'],categories:['飲食日常'],accounts:['cash'],dateFrom:'2026-10-04',dateTo:'2026-10-04',min:'150',max:'150'}),['filter-refund','seed-62']);
assert.deepEqual(filtered({accounts:['digital'],direction:'destination'}),['filter-transfer']);
assert.deepEqual(filtered({direction:'destination'}),['filter-card-pay','filter-transfer']);
assert.deepEqual(filtered({accounts:['digital'],direction:'source'}),[]);
assert.deepEqual(filtered({accountKinds:['card'],direction:'destination'}),['filter-card-pay']);
assert.equal(filtered({accountKinds:['cash']}).length,11);
assert.equal(filtered({cardAction:'spend'}).length,3);
assert.deepEqual(filtered({cardAction:'payment'}),['filter-card-pay']);
assert.deepEqual(filtered({sources:['recurring']}),['seed-56']);
assert.deepEqual(filtered({references:['recurring:rent']}),['seed-56']);
assert.deepEqual(filtered({scope:'all',sources:['dividend'],references:['dividend:0050']}),['filter-dividend']);
assert.deepEqual(filtered({scope:'all',references:['dividend:0050','recurring:rent']}),['seed-56','filter-dividend']);
assert.deepEqual(filtered({scope:'all',dateFrom:'2026-09-30',dateTo:'2026-10-01'}),['seed-56','seed-55','filter-dividend']);
assert.deepEqual(filtered({scope:'all'},'元大台灣50'),['filter-dividend']);
assert.deepEqual(filtered({},'數位帳戶'),['filter-transfer']);
assert.deepEqual(filtered({},'FILTER-TRANSFER'),['filter-transfer']);
assert.deepEqual(filtered({status:'reversed'}),['filter-reversed']);
assert.equal(filtered({status:'all'}).length,20);
assert.ok(!filtered({sources:['manual']}).includes('seed-56'));
assert.equal(filtered({sort:'highest'})[0],'seed-55');
assert.equal(filtered({sort:'lowest'})[0],'dense-day-demo-1');
assert.equal(filtered({sort:'oldest'})[0],'seed-55');
assert.throws(()=>run("validateLedgerFilters({...defaultLedgerFilters(),min:'3',max:'2'})"),/最低/);
assert.throws(()=>run("validateLedgerFilters({...defaultLedgerFilters(),min:'1.5'})"),/整數/);
assert.throws(()=>run("validateLedgerFilters({...defaultLedgerFilters(),dateFrom:'2026-02-30'})"),/有效日期/);
assert.throws(()=>run("validateLedgerFilters({...defaultLedgerFilters(),dateFrom:'2026-10-05',dateTo:'2026-10-04'})"),/開始日期/);
run('ledgerFilters()');
assert.ok(!node('#modal-body').innerHTML.includes('<select'));
assert.ok(!node('#modal-body').innerHTML.includes('type="date"'));
assert.ok(!node('#modal-body').innerHTML.includes('type="number"'));
assert.ok(node('#modal-body').innerHTML.includes('lf-primary-type'));assert.ok(node('#modal-body').innerHTML.includes('lf-advanced-trigger'));
assert.ok(!node('#modal-body').innerHTML.includes('lf-account-grid'));
run("ledgerFilterAction({dataset:{action:'lf-option',key:'types',value:'expense'}});ledgerFilterAction({dataset:{action:'lf-option',key:'types',value:'refund'}})");
assert.deepEqual(Array.from(run('ledgerFilterDraft.types')),['expense','refund']);
run("ledgerFilterAction({dataset:{action:'lf-option',key:'types',value:'expense'}})");assert.deepEqual(Array.from(run('ledgerFilterDraft.types')),['refund']);
run("ledgerFilterAction({dataset:{action:'lf-option',key:'types',value:''}})");assert.equal(run('ledgerFilterDraft.types.length'),0);
run("ledgerFilterAction({dataset:{action:'lf-date-open',key:'dateFrom'}});ledgerFilterCalendarMonth='2028-02'");
const filterCalendar=run('ledgerFilterCalendar()');assert.equal((filterCalendar.match(/data-action="lf-date"/g)||[]).length,42);assert.ok(filterCalendar.includes('2028-02-29'));assert.ok(filterCalendar.includes('disabled'));
run("ledgerFilterAction({dataset:{action:'lf-date',value:'2026-09-30'}})");assert.equal(run('ledgerFilterDraft.scope'),'all');assert.equal(run('ledgerFilterDraft.dateFrom'),'2026-09-30');
run("ledgerFilterAction({dataset:{action:'lf-date-shortcut',value:'month'}})");assert.equal(run('ledgerFilterDraft.dateFrom'),'2026-10-01');assert.equal(run('ledgerFilterDraft.dateTo'),'2026-10-31');
run("ledgerFilterAction({dataset:{action:'lf-reset'}})");assert.equal(run('ledgerFilterDraft.scope'),'month');assert.equal(run('ledgerFilterDraft.types.length'),0);assert.equal(run('ledgerAdvanced'),null);
run("Object.assign(ledgerFilterDraft,{scope:'all',sources:['dividend']});applyLedgerFilters();exportCSV()");assert.ok(node('#main').innerHTML.includes('跨月份紀錄 · 1 筆'));assert.equal(context.artifact.name,'hibi-filtered.csv');assert.equal(context.artifact.text.split('\r\n').length,2);assert.ok(context.artifact.text.includes('filter-dividend')===false);assert.ok(context.artifact.text.includes('九月配息'));assert.ok(context.artifact.text.includes('入帳來源'));
run("ledgerFilters();ledgerFilterDraft.min='900';ledgerFilterDraft.max='2'");assert.throws(()=>submit({}),/最低/);assert.equal(run('ledgerAdvanced.sources[0]'),'dividend');
run("ledgerFilters();ledgerFilterDraft.status='reversed';ledgerFilterDraft.sources=[];applyLedgerFilters()");assert.ok(node('#main').innerHTML.includes('已撤銷餐飲'));assert.ok(node('#main').innerHTML.includes('reversed-record'));run("txDetail('filter-reversed')");assert.equal(node('#modal .modal-actions .secondary').disabled,true);run('ledgerFilters()');assert.equal(node('#modal .modal-actions .secondary').disabled,false);
const oldTotal=run('totals().expense');assert.equal(oldTotal,17369);
for(const handler of docListeners.click||[])handler({target:{closest:s=>s==='[data-action]'?{dataset:{action:'ledger-clear'}}:null}});
assert.equal(run('ledgerAdvanced'),null);assert.equal(run('ledgerFilteredTransactions().length'),19);assert.equal(run('totals().expense'),oldTotal);
assert.ok(html.includes('ledger-filters.css'));assert.ok(html.indexOf('ledger-filters.js')<html.indexOf('app.js'));
console.log('PASS: all ledger fields, inclusive ranges, multi-select AND/OR, cross-month sources, keyword, account directions, card actions, reversal, stable sorting, fixed calendar, draft reset, validation and filtered CSV.');

// The range calculator shares the editor's arithmetic but allows zero and unset bounds.
run("state=seed();month='2026-10';ledgerAdvanced=null;search='';filter='all';categoryFilter='';dateFilter='';ledgerAccountFilter='';ledgerFilters()");
assert.ok(!node('#modal-body').innerHTML.includes('id="lf-min"'));
assert.ok(!node('#modal-body').innerHTML.includes('inputmode="numeric"'));
assert.ok(run("ledgerFilterPages.amount.body.includes('lf-amount-open')"));
run("ledgerFilterAction({dataset:{action:'lf-amount-open',key:'min'}})");
assert.ok(node('#picker-content').innerHTML.includes('lf-amount-key'));assert.ok(!node('#modal-body').innerHTML.includes('lf-amount-key'));
for(const key of ['1','0','0','+','5','0','完成']){context.__key=key;run("ledgerFilterAction({dataset:{action:'lf-amount-key',key:__key}})");}
assert.equal(run('ledgerFilterDraft.min'),'150');assert.equal(run('ledgerFilterAmountSlot'),'');
run("ledgerFilterAction({dataset:{action:'lf-amount-open',key:'max'}})");
for(const key of ['3','0','0','÷','2']){context.__key=key;run("ledgerFilterAction({dataset:{action:'lf-amount-key',key:__key}})");}
assert.equal(run('ledgerFilterDraft.max'),'');assert.equal(run('previewLedgerAmountFilters().max'),'150');
submit({});assert.equal(run('ledgerAdvanced.max'),'150');assert.equal(run('ledgerFilteredTransactions().length'),1);
run("ledgerFilters();ledgerFilterAction({dataset:{action:'lf-amount-open',key:'max'}});ledgerFilterAction({dataset:{action:'lf-amount-key',key:'C'}});ledgerFilterAction({dataset:{action:'lf-amount-key',key:'完成'}})");assert.equal(run('ledgerFilterDraft.max'),'0');assert.throws(()=>submit({}),/最低/);
run("ledgerFilterAction({dataset:{action:'lf-amount-open',key:'max'}});ledgerFilterAction({dataset:{action:'lf-amount-clear'}})");assert.equal(run('ledgerFilterDraft.max'),'');
run("ledgerFilterAction({dataset:{action:'lf-amount-open',key:'min'}})");
for(const key of ['1','÷','0','完成']){context.__key=key;run("ledgerFilterAction({dataset:{action:'lf-amount-key',key:__key}})");}
assert.ok(run('ledgerFilterAmountMessage').includes('零'));assert.equal(run('ledgerFilterDraft.min'),'150');assert.throws(()=>submit({}),/零/);
run("ledgerFilterAction({dataset:{action:'lf-amount-close'}})");assert.equal(run('ledgerFilterDraft.min'),'150');
run("ledgerFilterAction({dataset:{action:'lf-amount-open',key:'min'}})");
for(const key of ['1','.','5','完成']){context.__key=key;run("ledgerFilterAction({dataset:{action:'lf-amount-key',key:__key}})");}
assert.ok(run('ledgerFilterAmountMessage').includes('整數'));assert.equal(run('ledgerFilterDraft.min'),'150');
run("ledgerFilterAction({dataset:{action:'lf-reset'}})");assert.equal(run('ledgerFilterDraft.min'),'');assert.equal(run('ledgerFilterAmountSlot'),'');assert.equal(run('ledgerAdvanced.min'),'150');
run("ledgerAdvanced=null;filter='all';categoryFilter='';dateFilter='';ledgerAccountFilter='';openEntry('expense')");
assert.equal(run('editCalcExpression'),'0');assert.equal(run('editCalcDirty'),false);assert.ok(node('#modal-body').innerHTML.includes('record-type-tabs'));assert.ok(node('#modal-body').innerHTML.includes('field-calc'));assert.ok(!node('#modal-body').innerHTML.includes('edit-calc-keys'));assert.ok(!node('#modal-body').innerHTML.includes('<details'));
assert.ok(!node('#modal-body').innerHTML.includes('<select'));assert.ok(!node('#modal-body').innerHTML.includes('type="date"'));assert.ok(!node('#modal-body').innerHTML.includes('type="number"'));
for(const key of ['1','0','0','+','5','0']){context.__key=key;run('useEntryCalcKey(__key)');}
run("document.querySelector('#f-date').value='2026-10-03';document.querySelector('#f-account').value='cash';document.querySelector('#f-category').value='飲食日常';document.querySelector('#f-note').value='保留這段備註';switchRecordType('income')");
assert.equal(run('recordComposer.date'),'2026-10-03');assert.equal(run('recordComposer.account'),'cash');assert.equal(run('recordComposer.note'),'保留這段備註');assert.equal(run('recordComposer.amount'),150);assert.equal(run('editCalcExpression'),'100+50');assert.equal(run('recordComposer.category'),'薪資收入');
run("document.querySelector('#f-category').value='薪資收入';switchRecordType('transfer')");assert.equal(run('recordComposer.type'),'transfer');assert.equal(run('recordComposer.from'),'cash');assert.ok(node('#modal-body').innerHTML.includes('data-name="from"'));assert.ok(node('#modal-body').innerHTML.includes('data-name="to"'));assert.ok(!node('#modal-body').innerHTML.includes('name="category"'));
const beforeCount=run('state.tx.length'),cashPrior=run("balance(account('cash'))"),digitalPrior=run("balance(account('digital'))"),netPrior=run('netWorth()');
submit({amount:'999',from:'cash',to:'digital',date:'2026-10-03',note:'保留這段備註'});assert.equal(run('state.tx.length'),beforeCount+1);assert.equal(run('state.tx.at(-1).amount'),150);assert.equal(run("balance(account('cash'))"),cashPrior-150);assert.equal(run("balance(account('digital'))"),digitalPrior+150);assert.equal(run('netWorth()'),netPrior);
run("openEntry('expense')");assert.equal(run('editCalcDirty'),false);const beforeInvalid=run('state.tx.length');
assert.throws(()=>submit({amount:'100',account:'cash',category:'飲食日常',date:'2026-02-30',note:''}),/有效的入帳日期/);
assert.throws(()=>submit({amount:'100',account:'missing',category:'飲食日常',date:'2026-10-03',note:''}),/有效的使用帳戶/);
assert.throws(()=>submit({amount:'100',account:'cash',category:'不存在',date:'2026-10-03',note:''}),/有效分類/);assert.equal(run('state.tx.length'),beforeInvalid);
run("openEntry('income')");assert.throws(()=>submit({amount:'100',account:'card',category:'其他收入',date:'2026-10-03',note:''}),/有效的使用帳戶/);
run("openEntry('expense',true)");assert.ok(!node('#modal-body').innerHTML.includes('record-type-tabs'));assert.ok(!node('#modal-body').innerHTML.includes('data-value="cash"'));
submit({amount:'200',account:'card',category:'飲食日常',date:'2026-10-03',note:'刷卡測試'});assert.equal(run('state.tx.at(-1).account'),'card');
run("transfer(true)");assert.ok(!node('#modal-body').innerHTML.includes('<select'));assert.ok(node('#modal-body').innerHTML.includes('繳入信用卡'));assert.throws(()=>submit({amount:'100',from:'cash',to:'digital',date:'2026-10-03',note:''}),/有效的轉入帳戶/);
// Editing and filters cannot carry arithmetic into a newly opened record.
run("txEdit(state.tx.find(t=>t.type==='expense').id);useEntryCalcKey('9');openEntry('expense')");assert.equal(run('editCalcExpression'),'0');assert.equal(run('editCalcDirty'),false);
run("ledgerFilters();ledgerFilterAction({dataset:{action:'lf-amount-open',key:'min'}});ledgerFilterAction({dataset:{action:'lf-amount-key',key:'9'}});openEntry('income')");assert.equal(run('editCalcExpression'),'0');assert.equal(run('editCalcDirty'),false);
assert.ok(html.includes('entry-compose.css'));assert.ok(html.indexOf('entry-compose.js')<html.indexOf('app.js'));
console.log('PASS: shared range calculator, zero/unset limits, draft isolation, arithmetic on apply, native-free new entry controls, type-switch draft preservation, atomic account/date/category validation, transfer conservation and card restrictions.');

// Separate pages leave the parent form DOM and its unsaved draft untouched.
run("state=seed();month='2026-10';openEntry();document.querySelector('#f-amount').value='0';document.querySelector('#f-note').value='不要遺失的草稿'");
const fixedParent=node('#modal-body').innerHTML;
assert.ok(!fixedParent.includes('edit-calc-keys'));assert.ok(!fixedParent.includes('<details'));assert.ok(!fixedParent.includes('edit-calendar-days'));assert.ok(!fixedParent.includes('edit-choices'));
run("openFieldCalculator({dataset:{name:'amount',editor:'true',min:'1'}})");assert.equal(run('pickerCurrent().kind'),'calculator');assert.equal(run('pickerStack.length'),1);assert.ok(node('#picker-content').innerHTML.includes('picker-calc-key'));assert.equal(node('#modal-body').innerHTML,fixedParent);
run("usePickerCalcKey('8');backPickerPage()");assert.equal(node('#f-amount').value,'0');assert.equal(run('editCalcDirty'),false);assert.equal(node('#f-note').value,'不要遺失的草稿');assert.equal(run('pickerStack.length'),0);
run("openFieldCalculator({dataset:{name:'amount',editor:'true',min:'1'}})");
for(const key of ['2','0','0','+','5','0','完成']){context.__key=key;run('usePickerCalcKey(__key)');}
assert.equal(node('#f-amount').value,'250');assert.equal(run('editCalcExpression'),'250');assert.equal(run('editCalcDirty'),true);assert.equal(run('pickerStack.length'),0);assert.equal(node('#f-note').value,'不要遺失的草稿');assert.equal(node('#modal-body').innerHTML,fixedParent);
run("openFieldCalculator({dataset:{name:'amount',editor:'true',min:'1'}});usePickerCalcKey('C');usePickerCalcKey('完成')");assert.equal(run('pickerStack.length'),1);assert.ok(node('#picker-calc-error').textContent.includes('整數'));assert.equal(node('#f-amount').value,'250');run('backPickerPage()');
run("document.querySelector('#f-date').value='2026-10-04';openFieldDate({dataset:{min:'2026-01',max:'2030-12'}})");assert.equal(run('pickerCurrent().kind'),'calendar');assert.equal((node('#picker-content').innerHTML.match(/class="edit-calendar-days"/g)||[]).length,1);assert.equal((node('#picker-content').innerHTML.match(/<button/g)||[]).length,44);assert.equal(node('#modal-body').innerHTML,fixedParent);
run("moveEditCalendar(1);backPickerPage()");assert.equal(node('#f-date').value,'2026-10-04');run("openFieldDate({dataset:{min:'2026-01',max:'2030-12'}});selectEditDate('2026-10-03')");assert.equal(node('#f-date').value,'2026-10-03');assert.equal(run('pickerStack.length'),0);assert.equal(node('#f-note').value,'不要遺失的草稿');
run("document.querySelector('#f-account').value='bank';openFieldOptions({dataset:{name:'account',options:JSON.stringify(state.accounts.map(a=>({value:a.id,label:a.name})))}})");assert.ok(node('#picker-content').innerHTML.includes('picker-choice'));assert.ok(!node('#modal-body').innerHTML.includes('picker-choice'));
run("pickerAction({dataset:{action:'picker-choice',name:'account',value:'missing',label:'錯誤'}})");assert.equal(run('pickerStack.length'),1);assert.equal(node('#f-account').value,'bank');
run("pickerAction({dataset:{action:'picker-choice',name:'account',value:'cash',label:'隨身現金'}})");assert.equal(node('#f-account').value,'cash');assert.equal(node('#picker-label-account').textContent,'隨身現金');assert.equal(run('pickerStack.length'),0);assert.equal(node('#f-note').value,'不要遺失的草稿');
run("document.querySelector('#f-category').value='飲食日常';openFieldOptions({dataset:{name:'category',options:JSON.stringify(categories.map(c=>({value:c.name,label:c.name})))}})");assert.ok(node('#picker-content').innerHTML.includes('data-kind="category"'));run("pickerAction({dataset:{action:'picker-choice',name:'category',value:'交通通勤',label:'交通通勤'}})");assert.equal(node('#f-category').value,'交通通勤');
submit({amount:'999',account:'cash',category:'交通通勤',date:'2026-10-03',note:'不要遺失的草稿'});assert.equal(run('state.tx.at(-1).amount'),250);
// Filter groups are standalone pages too, including nested range calendars/calculators.
run("ledgerAdvanced=null;search='';filter='all';categoryFilter='';dateFilter='';ledgerAccountFilter='';ledgerFilters()");const filterParent=node('#modal-body').innerHTML;assert.ok(!filterParent.includes('<details'));assert.ok(!filterParent.includes('lf-category-grid'));assert.ok(!filterParent.includes('edit-calc-keys'));
run("ledgerFilterAction({dataset:{action:'lf-section',key:'account'}})");assert.equal(run('pickerStack.length'),1);assert.equal(node('#picker-title').textContent,'帳戶');assert.ok(node('#picker-content').innerHTML.includes('lf-account-grid'));
run("ledgerFilterAction({dataset:{action:'lf-option',key:'accounts',value:'cash'}})");assert.equal(run('ledgerFilterDraft.accounts[0]'),'cash');assert.equal(run('ledgerAdvanced'),null);assert.ok(!node('#modal-body').innerHTML.includes('lf-account-grid'));run('backPickerPage()');
run("ledgerFilterAction({dataset:{action:'lf-section',key:'date'}});ledgerFilterAction({dataset:{action:'lf-date-open',key:'dateFrom'}})");assert.equal(run('pickerStack.length'),2);assert.equal(run('pickerCurrent().kind'),'filter-calendar');assert.ok(node('#picker-content').innerHTML.includes('edit-calendar-days'));assert.ok(!node('#modal-body').innerHTML.includes('edit-calendar-days'));
run("ledgerFilterAction({dataset:{action:'lf-date',value:'2026-10-01'}})");assert.equal(run('pickerStack.length'),1);assert.equal(run('ledgerFilterDraft.dateFrom'),'2026-10-01');assert.equal(run('pickerCurrent().kind'),'filter-options');run('backPickerPage()');
run("ledgerFilterAction({dataset:{action:'lf-section',key:'amount'}});ledgerFilterAction({dataset:{action:'lf-amount-open',key:'min'}})");assert.equal(run('pickerStack.length'),2);assert.equal(run('pickerCurrent().kind'),'filter-calculator');
for(const key of ['1','0','0','完成']){context.__key=key;run("ledgerFilterAction({dataset:{action:'lf-amount-key',key:__key}})");}
assert.equal(run('pickerStack.length'),1);assert.equal(run('ledgerFilterDraft.min'),'100');assert.equal(run('pickerCurrent().kind'),'filter-options');run('backPickerPage()');assert.equal(run('pickerStack.length'),0);
assert.ok(!node('#modal-body').innerHTML.includes('edit-calc-keys'));assert.ok(!node('#modal-body').innerHTML.includes('lf-amount-calculator'));
// Every monetary/date/account/category form uses the same non-expanding controls.
for(const expression of ["openEntry('expense')","openEntry('income')","transfer()","transfer(true)","txEdit(state.tx.find(t=>t.type==='expense').id)","dividend()","newRecurring()","openAccount()","editBudget('food')"]){run(expression);const body=node('#modal-body').innerHTML;assert.ok(!body.includes('<select'),expression);assert.ok(!body.includes('<details'),expression);assert.ok(!body.includes('type="date"'),expression);assert.ok(!body.includes('edit-calc-keys'),expression);assert.ok(!body.includes('edit-calendar-days'),expression);assert.ok(!body.includes('edit-choices'),expression);}
run("state.tx=state.tx.filter(t=>!t.recurring);confirmRecurring('rent')");assert.ok(node('#modal-body').innerHTML.includes('data-min="2026-10"'));assert.ok(!node('#modal-body').innerHTML.includes('type="date"'));
run("document.querySelector('#f-opening').value='0';openFieldCalculator({dataset:{name:'opening',min:'0'}});usePickerCalcKey('完成')");assert.equal(node('#f-opening').value,'0');assert.equal(run('pickerStack.length'),0);
run("transfer()");assert.ok(node('#modal-body').innerHTML.includes('transfer-picker-pair'));assert.ok(!node('#modal-body').innerHTML.includes('picker-balance-from'));run("state.tx.push({id:'pair-test',date:'2026-10-04',type:'transfer',amount:100,account:'bank',to:'cash',category:'轉帳',note:'測試轉帳'});txEdit('pair-test')");assert.ok(node('#modal-body').innerHTML.includes('transfer-picker-pair'));
run("openFieldCalculator({dataset:{name:'amount',editor:'true',min:'1'}});openEntry('income')");assert.equal(run('pickerStack.length'),0);assert.equal(run('pickerCalc'),null);
const pickerCss=fs.readFileSync('dist/picker-pages.css','utf8');assert.ok(pickerCss.includes('height:auto'));assert.ok(pickerCss.includes('max-height:min(560px,calc(100dvh - 48px))'));assert.ok(!pickerCss.includes('height:100dvh'));assert.ok(pickerCss.includes('flex:0 0 auto'));assert.ok(pickerCss.includes('width:min(376px,calc(100vw - 24px))'));assert.ok(html.includes('picker-pages.css'));assert.ok(html.includes('id="picker-page"'));
console.log('PASS: compact independent picker pages, no initial calculator, parent DOM/draft preservation, cancel versus commit, nested filter navigation, zero opening balance, all form controls and transfer account-pair layout.');

// Record creation must not read controls that exist only in the retired inline calculator.
const originalQuerySelector=context.document.querySelector;
context.document.querySelector=selector=>['#edit-calc-expression','#edit-calc-message'].includes(selector)?null:originalQuerySelector(selector);
try{
  for(const type of ['expense','income','transfer'])assert.doesNotThrow(()=>run("openRecordComposer('"+type+"')"));
}finally{context.document.querySelector=originalQuerySelector;}
console.log('PASS: all three composers open when the retired inline calculator nodes are absent.');

// Reuse the app harness for stylesheet/raster regression checks without a second mock DOM.
module.exports={run,context,node,docListeners,windowListeners};
