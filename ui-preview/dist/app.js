'use strict';
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const categories = [
  {name:'居家生活',icon:'home',color:'#78906d'}, {name:'飲食日常',icon:'food',color:'#c28b60'},
  {name:'交通通勤',icon:'travel',color:'#6e929b'}, {name:'購物休閒',icon:'bag',color:'#927eaa'},
  {name:'訂閱服務',icon:'recurring',color:'#b19a56'}, {name:'其他支出',icon:'ledger',color:'#b77380'}
];
const pages=[['overview','生活總覽'],['ledger','收支紀錄'],['accounts','我的帳戶'],['account-detail','帳戶明細'],['reports','財務報表'],['categories','分類管理'],['investments','投資與股息'],['budgets','預算管理'],['recurring','定期交易'],['settings','設定與資料']];
const KEY='hibi-expense-preview-v1';
const TODAY='2026-10-04';
const EXTRA_DEMO_HOLDINGS=[
  {id:'0056',name:'元大高股息',qty:1800,price:36.5,cost:60200,dividend:3800},
  {id:'006208',name:'富邦台50',qty:550,price:112,cost:53500,dividend:1650},
  {id:'00919',name:'群益台灣精選高息',qty:2400,price:23.6,cost:52800,dividend:3100},
  {id:'2884',name:'玉山金',qty:1300,price:30.8,cost:34600,dividend:1800},
  {id:'2308',name:'台達電',qty:70,price:425,cost:25600,dividend:700},
  {id:'2412',name:'中華電',qty:160,price:128,cost:18800,dividend:960},
  {id:'2891',name:'中信金',qty:350,price:40.2,cost:11900,dividend:500},
  {id:'00929',name:'復華台灣科技優息',qty:80,price:19.8,cost:1440,dividend:60},
  {id:'2603',name:'長榮',qty:3,price:188,cost:510,dividend:0}
];
function extendDemoHoldings(data){if(data.holdingsDemoVersion===2)return false;const ids=new Set(data.holdings.map(h=>h.id));for(const h of EXTRA_DEMO_HOLDINGS)if(!ids.has(h.id))data.holdings.push({...h});data.holdingsDemoVersion=2;return true;}
const EXTRA_DEMO_ACCOUNTS=[
  {id:'savings',name:'儲蓄帳戶',kind:'bank',opening:125000},
  {id:'travel-bank',name:'旅遊基金',kind:'bank',opening:42000},
  {id:'salary-bank',name:'薪轉帳戶',kind:'bank',opening:26500},
  {id:'line-pay',name:'LINE Pay',kind:'ewallet',opening:6800},
  {id:'jkopay',name:'街口支付',kind:'ewallet',opening:4200},
  {id:'pxpay',name:'全支付',kind:'ewallet',opening:2800},
  {id:'easy-wallet',name:'悠遊付',kind:'ewallet',opening:1200},
  {id:'home-cash',name:'家用現金',kind:'cash',opening:8500}
];
function extendDemoAccounts(data){if(data.accountsDemoVersion===1)return false;const ids=new Set(data.accounts.map(a=>a.id));for(const a of EXTRA_DEMO_ACCOUNTS)if(!ids.has(a.id))data.accounts.push({...a});data.accountsDemoVersion=1;return true;}
// Eight additional fixtures make the default selected day a ten-record example.
const DENSE_DAY_DEMO=[
  [65,'日式餐點'],[45,'飲品採買'],[90,'下午點心'],[120,'超市採買'],
  [180,'日常點心'],[160,'餐點・外食'],[140,'咖啡・休閒'],[200,'週末點心']
].map(([amount,note],i)=>({id:'dense-day-demo-'+i,date:'2026-10-04',type:'expense',amount,account:'cash',category:'飲食日常',note}));
function extendDemoDailyTransactions(data){if(data.dailyDensityDemoVersion===1)return false;const ids=new Set(data.tx.map(t=>t.id));for(const t of DENSE_DAY_DEMO)if(!ids.has(t.id))data.tx.push({...t});data.dailyDensityDemoVersion=1;return true;}
function seed(){
  let tx=[],id=0;
  const add=(date,type,amount,account,category,note,extra={})=>tx.push({id:'seed-'+(++id),date,type,amount,account,category,note,...extra});
  for(let m=4;m<=9;m++){
    const prefix=`2026-${String(m).padStart(2,'0')}`;
    add(prefix+'-01','income',52000,'bank','薪資收入','每月薪資');
    add(prefix+'-01','expense',12500,'bank','居家生活',m+'月房租');
    add(prefix+'-06','expense',3800+m*170,'bank','飲食日常','日常餐飲');
    add(prefix+'-10','expense',1800+m*95,'card','購物休閒','生活用品');
    add(prefix+'-14','expense',1100,'bank','交通通勤','交通儲值');
    add(prefix+'-18','expense',699,'bank','居家生活','網路費');
    add(prefix+'-21','expense',570,'bank','訂閱服務','影音與音樂訂閱');
    add(prefix+'-26','expense',2600+m*180,'cash','飲食日常','外食與咖啡');
    add(prefix+'-28','transfer',1800+m*95,'bank','轉帳','信用卡繳款',{to:'card'});
  }
  add('2026-10-01','income',52000,'bank','薪資收入','十月薪資');
  add('2026-10-01','expense',12500,'bank','居家生活','十月房租',{recurring:'rent'});
  add('2026-10-02','expense',1680,'card','飲食日常','全聯・週末採買');
  add('2026-10-02','expense',480,'bank','交通通勤','悠遊卡加值');
  add('2026-10-03','expense',179,'card','訂閱服務','Spotify Premium');
  add('2026-10-03','expense',1290,'card','購物休閒','無印良品・收納用品');
  add('2026-10-04','expense',240,'cash','飲食日常','日式定食・午餐');
  add('2026-10-04','expense',150,'cash','飲食日常','巷口咖啡');
  tx.push(...DENSE_DAY_DEMO.map(t=>({...t})));
  return {version:1,dailyDensityDemoVersion:1,accounts:[{id:'bank',name:'日常銀行',kind:'bank',opening:45000},{id:'cash',name:'隨身現金',kind:'cash',opening:36000},{id:'digital',name:'數位帳戶',kind:'bank',opening:80000},{id:'card',name:'日常信用卡',kind:'card',opening:-4680},...EXTRA_DEMO_ACCOUNTS.map(a=>({...a}))],accountsDemoVersion:1,tx,
    budgets:[{id:'total',category:'全部支出',limit:32000},{id:'food',category:'飲食日常',limit:8000},{id:'home',category:'居家生活',limit:14000},{id:'travel',category:'交通通勤',limit:2500},{id:'shopping',category:'購物休閒',limit:5000}],
    recurring:[{id:'rent',name:'每月房租',amount:12500,day:1,account:'bank',category:'居家生活',active:true},{id:'netflix',name:'Netflix',amount:390,day:5,account:'card',category:'訂閱服務',active:true},{id:'internet',name:'家用網路',amount:699,day:10,account:'bank',category:'居家生活',active:true},{id:'yoga',name:'瑜珈月費',amount:1600,day:15,account:'bank',category:'購物休閒',active:true}],
    holdings:[{id:'0050',name:'元大台灣50',qty:3000,price:58.2,cost:154000,dividend:8100},{id:'00878',name:'國泰永續高股息',qty:5000,price:22.3,cost:103000,dividend:9450},{id:'2330',name:'台積電',qty:100,price:1050,cost:89500,dividend:2000},...EXTRA_DEMO_HOLDINGS.map(h=>({...h}))],holdingsDemoVersion:2,cardPaid:[],privacy:false};
}
let state,storageAvailable=true;
try{state=JSON.parse(localStorage.getItem(KEY));if(!state||state.version!==1||!Array.isArray(state.tx)||!Array.isArray(state.accounts))state=seed();}catch{state=seed();storageAvailable=false;}
const holdingsExtended=extendDemoHoldings(state),accountsExtended=extendDemoAccounts(state),dailyExtended=extendDemoDailyTransactions(state);
if(holdingsExtended||accountsExtended||dailyExtended)save();
let page='overview',month='2026-10',filter='all',search='',categoryFilter='',dateFilter='',ledgerAccountFilter='',chartMode='net',selectedAccount='bank';
function save(){try{localStorage.setItem(KEY,JSON.stringify(state));}catch{if(storageAvailable)toast('此瀏覽器無法保存資料；這次操作仍可繼續體驗。');storageAvailable=false;}}
const rawMoney=n=>Math.round(n).toLocaleString('zh-TW');
const money=rawMoney;
const totalMoney=n=>state.privacy?'••••':money(n);
const nt=n=>`TWD ${money(n)}`;
// Privacy applies to the overview and account summary, never opened records/forms.
const overviewMoney=n=>state.privacy?'••••':money(n);
const overviewCurrency=n=>`TWD ${overviewMoney(n)}`;
function amountTextClass(value){const length=money(Math.abs(Number(value)||0)).length;return length>=11?'amount-long amount-wide':length>=9?'amount-long':'';}
function updateAmountText(element,value){if(!element)return;const text=String(value);element.textContent=text;element.classList.toggle('amount-long',text.length>=9);element.classList.toggle('amount-wide',text.length>=11);}
function currencyFigure(value,{signed=false,masked=false,tone=''}={}){
  const sign=masked?'':value<0?'−':signed&&value>0?'+':'';
  return `<span class="currency-figure ${tone}"><small class="currency-unit">TWD</small><span class="currency-number">${sign?`<span class="currency-sign">${sign}</span>`:''}<strong class="${masked?'':amountTextClass(value)}">${masked?'••••':money(Math.abs(value))}</strong></span></span>`;
}
const account=id=>state.accounts.find(a=>a.id===id);
const cat=name=>categoryByName(name)||{icon:'other',color:'#765389'};
const activeTx=()=>state.tx.filter(t=>!t.reversed);
const monthly=(m=month)=>activeTx().filter(t=>t.date.startsWith(m));
function totals(m=month){let income=0,expense=0;for(const t of monthly(m)){if(t.type==='income')income+=t.amount;if(t.type==='expense')expense+=t.amount;if(t.type==='refund')expense-=t.amount;}return{income,expense};}
function balance(a,through='9999-12-31'){let n=a.opening;for(const t of activeTx().filter(t=>t.date<=through)){if(t.account===a.id)n+=transactionIncoming(t)?t.amount:-t.amount;if(t.type==='transfer'&&t.to===a.id)n+=t.amount;}return n;}
const investmentTotal=(through='9999-12-31')=>(through==='9999-12-31'?state.holdings:investmentPositions(state.tx,state.holdings,through)).reduce((n,h)=>n+h.qty*h.price,0);
const netWorth=(through='9999-12-31')=>state.accounts.reduce((n,a)=>n+balance(a,through),0)+investmentTotal(through);
function spent(category,m=month){return monthly(m).filter(t=>category==='全部支出'||t.category===category).reduce((n,t)=>n+(t.type==='expense'?t.amount:t.type==='refund'?-t.amount:0),0);}
const recent=(list=monthly())=>[...list].sort((a,b)=>b.date.localeCompare(a.date)||state.tx.indexOf(b)-state.tx.indexOf(a));
function toast(msg){feedbackAction=null;$('#toast').textContent=msg;$('#toast').classList.add('visible');clearTimeout(toast.timer);toast.timer=setTimeout(()=>$('#toast').classList.remove('visible'),3300);}
const uid=()=>globalThis.crypto?.randomUUID?.()||'new-'+Date.now()+'-'+Math.random().toString(16).slice(2);
const labelMonth=()=>`${month.slice(0,4)} 年 ${Number(month.slice(5))} 月`;
function period(){return `<div class="period app-period" aria-label="目前月份"><button data-action="month-prev" aria-label="上一個月" ${month<='2026-01'?'disabled':''}><span class="month-chevron previous" aria-hidden="true"></span></button><strong>${month.replace('-',' / ')}</strong><button data-action="month-next" aria-label="下一個月" ${month>='2030-12'?'disabled':''}><span class="month-chevron next" aria-hidden="true"></span></button></div>`;}
function heading(title,kicker,description,action='entry',actionLabel='記一筆',withPeriod=true){if(action==='entry')action=null;return `<div class="page-heading"><div><h1>${title}</h1></div><div class="heading-actions">${withPeriod?period():''}${action?`<button class="button primary" data-action="${action}">${icon('plus')}${actionLabel}</button>`:''}</div></div>`;}
function sectionHead(title,english,route,label='查看全部'){return `<div class="section-head"><div><h2>${title}</h2></div>${route?`<button class="text-button" data-route="${route}">${label}</button>`:''}</div>`;}
const ledgerIconColors={'居家生活':'#4c7055','飲食日常':'#925a35','交通通勤':'#406f83','購物休閒':'#765389','訂閱服務':'#80652c','其他支出':'#975369'};
function txRow(t){const isPlus=transactionIncoming(t);return `<button class="tx-row${t.reversed?' reversed-record':''}" data-action="tx-detail" data-id="${esc(t.id)}"><span class="tx-icon ${isPlus?'green':''}" style="--tx-color:${t.type==='transfer'?'#406f83':t.dividend||t.type==='investment'?'#765389':isPlus?palette.income:categoryByName(t.category)?.color||ledgerIconColors[t.category]||'#975369'}">${journalIcon(t)}</span><span class="tx-info"><strong>${esc(t.note||t.category)}</strong><small>${t.reversed?'已撤銷 · ':''}${esc(t.category)} · ${esc(account(t.account)?.name||'帳戶')}${t.type==='transfer'?' → '+esc(account(t.to)?.name):''}${page==='ledger'?'':' · '+Number(t.date.slice(5,7))+' / '+Number(t.date.slice(8))}</small></span><span class="tx-amount ${amountTextClass(t.amount)} ${isPlus?'positive':['expense','investment'].includes(t.type)?'expense-amount':''}">${t.type==='transfer'?'':isPlus?'+':'−'}${money(t.amount)}</span></button>`;}
function chart(mode=chartMode,invest=false){
  const selected=new Date(month+'-01T00:00:00Z'),data=[];
  for(let i=5;i>=0;i--){const d=new Date(selected);d.setUTCMonth(d.getUTCMonth()-i);const m=d.toISOString().slice(0,7);const end=new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+1,0)).toISOString().slice(0,10);data.push({m,label:Number(m.slice(5))+'月',value:invest?investmentTotal()*(1-i*.017):(mode==='net'?netWorth(end):totals(m).income-totals(m).expense)});}
  const values=data.map(d=>d.value),min=Math.min(...values),max=Math.max(...values),range=Math.max(max-min,10000);
  const points=data.map((d,i)=>({x:12+i*68,y:110-(d.value-min)/range*82,...d}));
  const path=points.map((p,i)=>(i?'L':'M')+p.x+','+p.y).join(' ');
  return `<div class="hero-chart"><div class="chart-top"><span>${invest?'持股市值走勢':mode==='net'?'淨資產走勢':'每月收支結餘'}</span>${invest?'<span>示意走勢</span>':`<div class="pill-group"><button data-action="chart-net" class="${mode==='net'?'active':''}">淨資產</button><button data-action="chart-flow" class="${mode==='flow'?'active':''}">收支</button></div>`}</div><svg viewBox="0 0 364 130" role="group" aria-label="近六個月${invest?'示意市值':mode==='net'?'淨資產':'收支結餘'}，點選圓點查看金額"><defs><linearGradient id="area${invest?'i':''}" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#8f9d78" stop-opacity=".25"/><stop offset="100%" stop-color="#8f9d78" stop-opacity="0"/></linearGradient></defs><path d="M0 32H364M0 72H364M0 112H364" stroke="#cad4bc" stroke-width=".6" stroke-dasharray="3 5"/><path d="${path}L352 125L12 125Z" fill="url(#area${invest?'i':''})"/><path d="${path}" stroke="#6d805d" stroke-width="2.2" fill="none"/>${points.map(p=>`<circle class="chart-point" cx="${p.x}" cy="${p.y}" r="4" tabindex="0" role="button" aria-label="${p.label} ${invest?'示意市值':mode==='net'?'淨資產':'收支結餘'} ${nt(p.value)}" data-action="chart-point" data-value="${p.value}" data-label="${p.label}"></circle>`).join('')}</svg><div class="chart-axis">${data.map(d=>`<span>${d.label}</span>`).join('')}</div><div class="chart-detail" id="chart-detail"></div></div>`;
}
function recurringConfirmed(r){return activeTx().some(t=>t.recurring===r.id&&t.date.startsWith(month));}
function dueDate(r){return month+'-'+String(Math.min(r.day,new Date(Number(month.slice(0,4)),Number(month.slice(5)),0).getDate())).padStart(2,'0');}
// Previous close prices are explicit illustrative fixtures, never live quotes.
const DEMO_PREVIOUS_CLOSE={'0050':57.9,'00878':22.25,'2330':1042,'0056':36.4,'006208':111.4,'00919':23.55,'2884':30.9,'2308':421,'2412':128.5,'2891':40,'00929':19.9,'2603':186.5};
function investmentToday(){const {date,items}=investmentChangeItems();let previous=0,change=0;for(const h of items){previous+=h.qty*holdingPreviousClose(h);change+=h.change;}return{value:investmentTotal(),change,rate:previous>0?change/previous*100:0,covered:items.length,count:state.holdings.filter(h=>h.qty>0).length,date};}
function investmentTodaySummary(){const d=investmentToday(),sign=d.change>0?'+':d.change<0?'−':'',positive=d.change>=0;return `<div class="investment-today" aria-label="投資今日狀況，${d.covered===d.count?portfolioQuoteStatus():'部分'+portfolioQuoteStatus()}"><div class="investment-value"><span>投資市值</span><strong>${state.privacy?'••••':nt(d.value)}</strong></div><div class="investment-day"><span>當日損益 </span><div class="investment-day-numbers ${positive?'positive':'negative'}"><strong>${sign}${money(Math.abs(d.change))}</strong><small>${sign}${Math.abs(d.rate).toFixed(2)}%</small></div></div></div>`;}
function recurringReminderFacts(){
  const pending=state.recurring.filter(r=>r.active&&!recurringConfirmed(r)).sort((a,b)=>a.day-b.day),cutoff=month<TODAY.slice(0,7)?month+'-31':month===TODAY.slice(0,7)?TODAY:month+'-00';
  return {due:pending.filter(r=>dueDate(r)<=cutoff),upcoming:pending.filter(r=>dueDate(r)>cutoff)};
}
function recurringReminderCopy(masked=false){
  const {due,upcoming}=recurringReminderFacts();
  return {due,upcoming,title:due.length?`${due.length} 筆待確認`:'尚無到期項目',detail:[due.length?(masked?'TWD ••••':nt(due.reduce((n,r)=>n+r.amount,0))):'',upcoming.length?`即將到期 ${upcoming.length} 筆`:''].filter(Boolean).join(' · ')};
}
function recurringReminder(){const r=recurringReminderCopy(state.privacy);if(!r.due.length&&!r.upcoming.length)return '';return `<button class="pending-entry reminder-banner ${r.due.length?'is-due':''}" data-route="recurring"><span class="reminder-indicator"></span><span class="reminder-copy"><strong>${r.title}</strong><small>${r.detail}</small></span><span class="reminder-arrow">›</span></button>`;}
function investmentBarWidth(value,values){if(chartScale('investment')==='linear')return Math.abs(value)/(Math.max(0,...values.map(Math.abs))||1)*50;const magnitude=Math.abs(value),positive=values.map(Math.abs).filter(v=>v>0&&Number.isFinite(v));if(!magnitude||!positive.length)return 0;const min=Math.min(...positive),max=Math.max(...positive);return max===min?50:12+38*(magnitude-min)/(max-min);}
function investmentTodayChart(){
 const d=investmentToday(),{items}=investmentChangeItems(),sign=d.change<0?'−':d.change>0?'+':'',groups=Array.from({length:Math.ceil(items.length/4)},(_,i)=>items.slice(i*4,i*4+4)),source=!items.length?portfolioQuoteStatus():items.every(h=>!h.quoteSource)?'示意行情':'收盤變動',dateLabel=d.date?Number(d.date.slice(5,7))+'/'+Number(d.date.slice(8)):'',scale=chartScale('investment');
 return `<section class="today-investment" aria-label="投資行情，${source}，${d.date||'尚無行情'}，涵蓋 ${d.covered} 檔，共 ${d.count} 檔"><div class="today-investment-head"><div><h2>投資行情 ${chartScaleControl('investment')}</h2><span>投資市值 ${state.privacy?'••••':overviewCurrency(d.value)}</span></div><div class="${d.change>=0?'positive':'negative'}"><strong>${dateLabel} ${d.covered<d.count?'部分':'當日'}損益 ${d.covered?state.privacy?'••••':sign+money(Math.abs(d.change)):'—'}</strong><small>${source}${d.covered?' · '+(state.privacy?'••••':sign+Math.abs(d.rate).toFixed(2)+'%'):''}</small></div></div>${items.length?`<div class="investment-bars investment-panels" data-scale="${scale}" role="group" aria-label="各持股同日損益，${scale==='linear'?'等比例':'小額圖條放大'}，${source}；點選查看詳情">${groups.map(group=>`<div class="investment-panel">${group.map(h=>`<button class="holding-performance" data-action="holding" data-id="${esc(h.id)}" aria-label="${esc(h.id+' '+h.name+' '+h.quoteDay+' 損益 '+overviewCurrency(h.change)+'，'+quoteStatus(h))}"><span>${esc(h.id)}</span><span class="performance-track"><i class="${h.change>=0?'gain':'loss'}" style="--bar-width:${investmentBarWidth(h.change,items.map(item=>item.change))}%"></i></span><b class="${h.change>=0?'positive':'negative'}">${state.privacy?'••••':(h.change>0?'+':'')+money(h.change)}</b></button>`).join('')}</div>`).join('')}</div>`:'<div class="daily-empty">尚無可比較的持股行情</div>'}</section>`;
}

function compactMoney(value){const a=Math.abs(value),sign=value<0?'−':'';return a>=1e8?sign+(a/1e8).toLocaleString('zh-TW',{maximumFractionDigits:1})+'億':a>=1e6?sign+(a/1e4).toLocaleString('zh-TW',{maximumFractionDigits:1})+'萬':money(value);}
function overviewSummary(){
 const t=totals(),metrics=[['income','本月收入',t.income],['expense','本月支出',t.expense],['invest','其中股息',monthDividend()],['surplus','本月結餘',t.income-t.expense]];
 return `<section class="home-summary" aria-label="本月財務摘要，TWD"><div class="home-summary-strip">${metrics.map(([kind,label,value])=>{
   const amount=state.privacy?'••••':compactMoney(value),tone=kind==='surplus'&&value<0?' is-negative':kind==='expense'&&value<0?' is-positive':'';
   return `<div class="home-stat home-${kind}${tone}"><span class="home-stat-icon" aria-hidden="true">${summaryIcon(kind)}</span><span class="home-stat-label">${label}</span><strong${amount.length>7?' class="home-amount-long"':''} aria-label="${state.privacy?'金額已隱藏':nt(value)}">${amount}</strong></div>`;
 }).join('')}</div></section>`;
}
function overview(){
 return `<div class="home-heading"><h1>總覽</h1><div class="home-heading-actions"><button class="icon-button" data-action="privacy" aria-label="${state.privacy?'顯示':'隱藏'}金額"><span class="css-eye ${state.privacy?'hidden':''}"><i></i></span></button>${period()}</div></div>${overviewSummary()}${recurringReminder()}<div id="dashboard-host">${canvasDashboard()}</div>`;
}
function ledgerComparison(){const t=totals(),income=Math.abs(t.income),expense=Math.abs(t.expense),total=income+expense,left=total?income/total*100:0,right=total?expense/total*100:0;return `<section class="ledger-comparison" aria-label="本月收入與支出比較"><div class="comparison-heading"><h2>本月收支</h2><span>結餘 <strong class="${t.income-t.expense<0?'negative':'positive'}">${money(t.income-t.expense)}</strong></span></div><div class="comparison-side-labels"><div><span>收入</span><strong class="positive">${money(t.income)}</strong></div><div><span>${t.expense<0?'淨退款':'支出'}</span><strong class="${t.expense<0?'positive':'expense-amount'}">${money(expense)}</strong></div></div><div class="comparison-single" role="img" aria-label="${esc(labelMonth()+'，左側收入 '+nt(t.income)+'，右側'+(t.expense<0?'淨退款 ':'支出 ')+nt(expense)+'；長度按兩者金額比例分配')}"><i class="comparison-income" style="width:${left}%"></i><i class="comparison-expense${t.expense<0?' refund':''}" style="width:${right}%"></i></div>${total?'':'<p class="comparison-empty">本月尚無收支</p>'}</section>`;}

function ledger(){const active=ledgerFilterLabels().length>0;return `<div class="page-heading ledger-heading"><h1>收支紀錄</h1>${period()}</div>${ledgerComparison()}<div class="ledger-tools"><span>${ledgerAdvanced?.scope==='all'?'跨月份紀錄':'本月紀錄'} · ${ledgerFilteredTransactions().length} 筆</span><div><button class="ledger-tool" data-action="ledger-search" aria-label="搜尋紀錄">${icon('search')}搜尋${search?'<i class="filter-dot"></i>':''}</button><button class="ledger-tool" data-action="ledger-filter">${icon('filter')}篩選${active?'<i class="filter-dot"></i>':''}</button><button class="ledger-tool icon-only" data-action="export" aria-label="匯出 CSV">${icon('export')}</button></div></div>${ledgerAppliedFilters()}<div id="transaction-list" class="ledger-records">${ledgerList()}</div>`;}
function ledgerFilters(){openLedgerFilters();}
function ledgerSearch(){
 openModal('搜尋紀錄',`<label class="app-search-field" for="f-keyword">${icon('search')}<input id="f-keyword" name="keyword" type="search" value="${esc(search)}" maxlength="100" placeholder="搜尋紀錄" autocomplete="off" enterkeyhint="search" aria-label="搜尋備註、分類或帳戶"><button type="button" data-action="search-input-clear" aria-label="清除搜尋文字">清除</button></label>`,'搜尋',data=>{search=data.get('keyword').trim();render();},'');
 $('#modal').classList.add('app-search-modal');
}

function ledgerList(){const list=ledgerFilteredTransactions();let date='';return list.map(t=>{const head=t.date!==date?`<div class="date-divider">${ledgerAdvanced?.scope==='all'?t.date.slice(0,4)+' 年 ':''}${Number(t.date.slice(5,7))} 月 ${Number(t.date.slice(8))} 日 · ${['週日','週一','週二','週三','週四','週五','週六'][new Date(t.date+'T12:00:00Z').getUTCDay()]}</div>`:'';date=t.date;return head+txRow(t);}).join('')||emptyAction('沒有符合的紀錄',ledgerFilterLabels().length||search?'ledger-clear':'entry',ledgerFilterLabels().length||search?'清除篩選':'記下第一筆');}
function accounts(){const cash=state.accounts.filter(a=>a.kind!=='card').reduce((n,a)=>n+balance(a),0),liability=state.accounts.filter(a=>a.kind==='card').reduce((n,a)=>n-Math.min(0,balance(a)),0),invest=investmentTotal(),assets=cash+invest,total=Math.max(1,Math.max(0,cash)+Math.max(0,invest)),cashWidth=Math.max(0,cash)/total*100,investWidth=Math.max(0,invest)/total*100,groups=[['cash','現金'],['bank','銀行帳戶'],['ewallet','電子支付'],['card','信用卡']];return `<div class="accounts-heading"><div><h1>我的帳戶</h1></div><button class="account-add" data-action="account" aria-label="新增帳戶">${icon('plus')}<span>新增</span></button></div><section class="account-overview" aria-label="資產概況"><div class="account-overview-top"><div><span>資產總額</span><div class="account-overview-value">${currencyFigure(assets,{masked:state.privacy})}</div></div></div><div class="account-allocation" aria-label="現金存款與投資市值分布"><i class="cash" style="width:${cashWidth}%"></i><i class="invest" style="width:${investWidth}%"></i></div><div class="account-facts" aria-label="資產包含存款與投資，信用卡負債另列"><div><span>現金與存款</span><strong>${totalMoney(cash)}</strong></div><div><span>投資市值</span><strong>${totalMoney(invest)}</strong></div><div><span>待繳卡款</span><strong class="${liability?'negative':''}">${totalMoney(liability)}</strong></div></div><div class="account-actions"><button data-action="transfer">${icon('transfer')}<span>帳戶轉帳／繳卡款</span></button></div></section><section class="account-collection"><div class="account-section-heading"><div><h2>帳戶一覽</h2></div></div><div class="account-groups">${groups.map(([kind,label])=>{const items=state.accounts.filter(item=>item.kind===kind);if(!items.length)return '';return `<section class="account-group ${kind}"><div class="account-group-heading"><h3>${label}</h3></div><div class="account-grid">${items.map(item=>`<button class="account-wallet ${item.kind}" data-action="account-open" data-id="${esc(item.id)}" aria-label="開啟 ${esc(item.name)} 帳戶"><span class="account-wallet-icon">${accountPickerIcon(item)}</span><span class="account-wallet-copy"><strong>${esc(item.name)}</strong></span><span class="account-wallet-balance ${amountTextClass(balance(item))} ${balance(item)<0?'negative':''}">${money(balance(item))}</span></button>`).join('')}</div></section>`;}).join('')||emptyAction('建立帳戶，開始整理收支','account','新增帳戶')}</div></section>`;}

function accountActivityRow(t,a){const incoming=t.to===a.id||t.account===a.id&&transactionIncoming(t),outgoing=t.account===a.id&&!transactionIncoming(t),other=t.type==='transfer'?(incoming?account(t.account):account(t.to)):null,label=t.type==='transfer'?(incoming?'轉入':'轉出'):t.dividend?'股息收入':t.category,detail=t.type==='transfer'?esc(other?.name||'其他帳戶'):esc(t.note||t.category),sign=t.type==='transfer'?(incoming?'+':'−'):incoming?'+':outgoing?'−':'';return `<button class="tx-row account-activity-row" data-action="tx-detail" data-id="${esc(t.id)}"><span class="tx-icon ${incoming?'green':''}" style="--tx-color:${t.type==='transfer'?'#406f83':t.dividend||t.type==='investment'?'#765389':incoming?palette.income:categoryByName(t.category)?.color||ledgerIconColors[t.category]||'#975369'}">${journalIcon(t)}</span><span class="tx-info"><strong>${esc(label)}</strong><small>${detail}</small></span><span class="tx-amount ${amountTextClass(t.amount)} ${incoming?'positive':outgoing?'expense-amount':''}">${sign}${rawMoney(t.amount)}</span></button>`;}
function waterfallDateRange(date){const start=new Date(`${date}T12:00:00Z`),end=new Date(start);end.setUTCDate(end.getUTCDate()+6);return `${start.getUTCMonth()+1}/${start.getUTCDate()}-${end.getUTCMonth()+1}/${end.getUTCDate()}`;}
function waterfallDetail(w,card,position={x:160,y:20}){
  if(!w)return '';
  const amount=utilitySigned(w.delta),tone=w.delta===0?'flat':(card?w.delta<0:w.delta>0)?'good':'bad';
  const fit=amount.length>8?' textLength="68" lengthAdjust="spacingAndGlyphs"':'';
  return `<text class="waterfall-value ${tone}" x="${position.x}" y="${position.y.toFixed(1)}" text-anchor="middle" aria-label="變動 ${nt(w.delta)}"${fit}>${amount}</text>`;
}
function showWaterfallInfo(el){
  const detail=$('#waterfall-detail');if(!detail||!el)return;waterfallSelections.set(selectedAccount,el.dataset.date);
  const w={date:el.dataset.date,count:Number(el.dataset.count),delta:Number(el.dataset.delta),before:Number(el.dataset.before),after:Number(el.dataset.after)},card=el.dataset.card==='1';
  for(const item of document.querySelectorAll('[data-action="waterfall-info"]')){const selected=item===el;item.classList.toggle('selected',selected);item.setAttribute('aria-pressed',String(selected));}
  detail.innerHTML=waterfallDetail(w,card,{x:Number(el.dataset.x),y:Number(el.dataset.y)});
}

function accountWeeklySeries(a,card){
 const entries=activeTx().filter(t=>t.account===a.id||t.to===a.id),anchor=entries.reduce((latest,t)=>t.date>latest?t.date:latest,TODAY),last=new Date(anchor+'T12:00:00Z');
 last.setUTCDate(last.getUTCDate()-(last.getUTCDay()+6)%7);
 const first=new Date(last);first.setUTCDate(first.getUTCDate()-21);
 const valueAt=date=>card?Math.max(0,-balance(a,date)):balance(a,date),beforeFirst=new Date(first);beforeFirst.setUTCDate(beforeFirst.getUTCDate()-1);
 const periodOpening=valueAt(beforeFirst.toISOString().slice(0,10)),changes=[];let running=periodOpening;
 for(let i=0;i<4;i++){const begin=new Date(first);begin.setUTCDate(begin.getUTCDate()+i*7);const end=new Date(begin);end.setUTCDate(end.getUTCDate()+6);const date=begin.toISOString().slice(0,10),until=end.toISOString().slice(0,10),after=valueAt(until);changes.push({date,before:running,after,delta:after-running,count:entries.filter(t=>t.date>=date&&t.date<=until).length});running=after;}
 return {periodOpening,running,changes,hasEntries:entries.length>0};
}
function accountWeeklyWaterfall(a,card,series=accountWeeklySeries(a,card)){
 const {periodOpening,running,changes,hasEntries}=series,selectedWeek=changes.some(w=>w.date===waterfallSelections.get(a.id))?waterfallSelections.get(a.id):changes.at(-1)?.date;
  const sizes=minimumSizes(changes.map(w=>Math.abs(w.delta)),56,10),offsets=[0];
  changes.forEach((w,i)=>{const good=card?w.delta<0:w.delta>0,direction=w.delta===0?0:good?-1:1;offsets.push(offsets.at(-1)+direction*sizes[i]);});
  const minOffset=Math.min(...offsets),maxOffset=Math.max(...offsets),span=maxOffset-minOffset,startLevel=!periodOpening&&!running&&changes.every(w=>w.delta===0)?96:28+(56-span)/2-minOffset,readableLevels=offsets.map(v=>startLevel+v),actualLevels=[periodOpening,...changes.map(w=>w.after)],low=Math.min(0,...actualLevels),high=Math.max(1,...actualLevels),linearY=value=>94-(value-low)/(high-low)*62,levels=chartScale('waterfall')==='linear'?actualLevels.map(linearY):readableLevels,floor=chartScale('waterfall')==='linear'?linearY(0):96,count=changes.length+2,width=320,slot=(width-20)/count,barWidth=28,x=i=>10+i*slot+(slot-barWidth)/2;
  const label=date=>{const d=new Date(`${date}T12:00:00Z`);return `${d.getUTCMonth()+1}/${d.getUTCDate()}`;};
  const bars=[{kind:'total',label:'期初',before:floor,after:levels[0],amount:periodOpening},...changes.map((w,i)=>({kind:w.delta===0?'flat':card?(w.delta>0?'bad':'good'):(w.delta>0?'good':'bad'),label:label(w.date),before:levels[i],after:levels[i+1],amount:w.delta,week:w,selected:w.date===selectedWeek})),{kind:'current',label:'目前',before:floor,after:levels.at(-1),amount:running}];
  const connectors=bars.slice(0,-1).map((bar,i)=>`<line x1="${x(i)+barWidth}" y1="${bar.after.toFixed(1)}" x2="${x(i+1)}" y2="${bar.after.toFixed(1)}"/>`).join('');
  let annotation='';
  const rects=bars.map((bar,i)=>{
    const top=Math.min(bar.before,bar.after),distance=Math.abs(bar.before-bar.after),height=chartScale('waterfall')==='linear'?(distance||1):Math.max(3,distance),adjusted=chartScale('waterfall')==='linear'?(distance?top:top-.5):height===3?top-1.5:top,center=x(i)+barWidth/2,labelY=Math.max(18,adjusted-8);
    if(bar.selected)annotation=waterfallDetail(bar.week,card,{x:center,y:labelY});
    const title=bar.week?`${waterfallDateRange(bar.week.date)}，${bar.week.count} 筆，變動 ${bar.amount>0?'+':bar.amount<0?'−':''}${rawMoney(Math.abs(bar.amount))}，週初 ${rawMoney(bar.week.before)}，週末 ${rawMoney(bar.week.after)}`:`${bar.label} ${rawMoney(bar.amount)}`;
    const fill=bar.kind==='total'||bar.kind==='current'?'var(--wallet)':bar.kind==='good'?palette.income:bar.kind==='bad'?palette.expense:'#a7a398';
    const interactive=bar.week?` role="button" tabindex="0" data-action="waterfall-info" data-date="${bar.week.date}" data-count="${bar.week.count}" data-delta="${bar.week.delta}" data-before="${bar.week.before}" data-after="${bar.week.after}" data-card="${card?'1':'0'}" data-x="${center}" data-y="${labelY.toFixed(1)}" aria-pressed="${bar.selected}" aria-label="${title}"`:'';
    return `<g class="waterfall-item ${bar.kind}${bar.selected?' selected':''}"${interactive}${bar.week?'':` role="img" aria-label="${title}"`}>${bar.week?`<rect class="waterfall-hit" x="${x(i)-8}" y="0" width="44" height="117" rx="6"/>`:''}<rect class="waterfall-bar" x="${x(i)}" y="${adjusted.toFixed(1)}" width="${barWidth}" height="${height.toFixed(1)}" rx="4" style="fill:${fill}"/><text class="waterfall-axis" x="${center}" y="112" text-anchor="middle">${bar.label}</text>${bar.week?`<line class="waterfall-selection" x1="${center-7}" x2="${center+7}" y1="118" y2="118" aria-hidden="true"/>`:''}</g>`;
  }).join('');
  return `<div class="account-waterfall-chart"><div class="account-waterfall-heading"><strong>${card?'每週卡款變動':'每週餘額變動'}</strong>${hasEntries?chartScaleControl('waterfall'):'<span>尚無交易</span>'}</div><div class="account-waterfall-scroll"><svg viewBox="0 0 320 120" role="group" aria-label="連續四週帳戶瀑布圖，${chartScale('waterfall')==='linear'?'等比例':'小額變動優先顯示'}，期初 ${rawMoney(periodOpening)}，目前 ${rawMoney(running)}，點選長條查看變動"><g class="waterfall-connectors">${connectors}</g>${rects}<g class="waterfall-annotation" id="waterfall-detail" role="status" aria-live="polite" aria-atomic="true">${annotation}</g></svg></div></div>`;
}
function accountDetail(){const a=account(selectedAccount);if(!a){selectedAccount=state.accounts[0]?.id||'';return accounts();}const card=a.kind==='card',kind={cash:'現金',bank:'銀行帳戶',ewallet:'電子支付',card:'信用卡'}[a.kind]||'帳戶',rows=recent(activeTx().filter(t=>(t.account===a.id||t.to===a.id)&&t.date.startsWith(month))),value=card?Math.max(0,-balance(a)):balance(a),weekly=accountWeeklySeries(a,card),change=weekly.running-weekly.periodOpening,changeSign=change>0?'+':change<0?'−':'',changeDown=card?change>0:change<0;return `<div class="account-detail-page ${a.kind}" data-amount-visibility="always" style="--wallet:${a.kind==='card'?'#a35f58':a.kind==='cash'?'#9a7650':a.kind==='ewallet'?'#5d7f83':'#687f6a'}"><header class="account-detail-heading"><button data-action="app-back" data-fallback="accounts" aria-label="返回帳戶一覽"><span class="month-chevron previous" aria-hidden="true"></span></button><div><small>${kind}</small><h1>${esc(a.name)}</h1></div></header><section class="account-detail-hero"><span class="account-detail-icon">${accountPickerIcon(a)}</span><div class="account-detail-balance"><small>${card?'目前待繳':'目前餘額'}</small><div>${currencyFigure(value,{tone:card&&value||value<0?'negative':''})}</div></div><div class="account-detail-net"><span>近四週變動</span><strong class="${amountTextClass(change)} ${changeDown?'negative':change?'positive':''}">${changeSign}${rawMoney(Math.abs(change))}</strong></div>${accountWeeklyWaterfall(a,card,weekly)}</section><div class="account-detail-actions">${card?`<button data-action="account-record">${icon('plus')}<span>新增刷卡</span></button><button data-action="account-pay">${icon('transfer')}<span>繳卡款</span></button>`:`<button data-action="account-record">${icon('plus')}<span>新增紀錄</span></button><button data-action="account-transfer">${icon('transfer')}<span>帳戶轉帳</span></button>`}</div><section class="account-detail-activity"><div class="account-detail-section-head"><h2>帳戶紀錄</h2>${period()}</div>${rows.map(t=>accountActivityRow(t,a)).join('')||emptyAction('這個月還沒有帳戶紀錄','account-record','新增紀錄')}</section></div>`;}
function reportCategoryFacts(){const facts=new Map(managedCategories('expense',true).map(c=>[c.name,{...c,amount:0,count:0}]));for(const t of monthly()){if(t.type!=='expense'&&t.type!=='refund')continue;const row=facts.get(t.category)||{name:t.category,icon:'ledger',color:'#8c776d',amount:0,count:0};row.amount+=t.type==='expense'?t.amount:-t.amount;row.count++;facts.set(t.category,row);}return [...facts.values()].filter(row=>row.amount||row.count).sort((a,b)=>b.amount-a.amount);}
function reportBarWidth(value,values){const positives=values.filter(v=>v>0),amount=Math.max(0,value);if(!amount||!positives.length)return 0;const min=Math.min(...positives),max=Math.max(...positives);return max===min?100:14+86*(amount-min)/(max-min);}
function categoryOverviewFacts(type){const names=type==='expense'?managedCategories('expense').map(c=>c.name):['薪資收入','股息收入','其他收入'];return names.map(name=>{const tx=monthly().filter(t=>type==='expense'?(t.type==='expense'||t.type==='refund')&&t.category===name:t.type==='income'&&t.category===name),amount=tx.reduce((n,t)=>n+(t.type==='refund'?-t.amount:t.amount),0),meta=type==='expense'?cat(name):{name,icon:'income',color:'#5f8067'};return{...meta,name,amount,count:tx.length};});}

function render(){
  destroyDashboard();
  $('#mobile-navigation').innerHTML=[['overview','總覽'],['ledger','紀錄'],['entry','記一筆'],['accounts','帳戶'],['more','更多']].map(([k,v])=>k==='entry'?`<button class="entry-button" data-action="entry" aria-label="新增記帳"><span class="entry-circle">${icon('plus')}</span><span>記一筆</span></button>`:`<button data-route="${k}" class="${page===k||(k==='accounts'&&page==='account-detail')||(k==='more'&&['reports','categories','budgets','investments','recurring','settings'].includes(page))?'active':''}" ${page===k?'aria-current="page"':''}>${icon(k)}${v}</button>`).join('');
  $('#breadcrumb').textContent=pages.find(p=>p[0]===page)?.[1]||'更多日常';
  $('#main').innerHTML=({overview,ledger,accounts,'account-detail':accountDetail,reports,categories:categoryOverview,investments,budgets,recurring,settings,more}[page]||overview)();
  if(page==='overview')attachDashboard();
}
function route(r,options={}){navigatePage(r,options);}
const optionAccounts=(selected,includeCards=true)=>state.accounts.filter(a=>includeCards||a.kind!=='card').map(a=>`<option value="${esc(a.id)}" ${a.id===selected?'selected':''}>${esc(a.name)}</option>`).join('');
const field=(name,label,content)=>`<div class="field"><label for="f-${name}">${label}</label>${content}</div>`;
const input=(name,type='text',value='',extra='')=>type==='number'&&['amount','opening'].includes(name)?currencyControl(name,value,name==='opening'?0:1):`<input id="f-${name}" name="${name}" type="${type}" value="${esc(value)}" ${extra}>`;
const select=(name,options)=>selectAsPicker(name,options);
const amountField=(label='金額',value='')=>field('amount',label,input('amount','number',value,'required min="1" max="100000000" step="1" inputmode="numeric" class="amount-input" placeholder="0"'));
const categoryOptions=selected=>managedCategories('expense').map(c=>`<option ${selected===c.name?'selected':''}>${c.name}</option>`).join('');
let modalHandler=null;
function openModal(title,body,submit,handler,kicker='NEW ENTRY'){beginModalSession();resetPickerPages();$('#modal-draft').hidden=true;$('#modal').classList.remove('entry-details','entry-edit','entry-compose','account-compose','ledger-filter-panel','utility-modal','utility-holding','utility-reset','app-search-modal','confirmation-modal');$('#modal').removeAttribute?.('data-compose-type');const cancel=$('#modal .modal-actions .secondary'),submitButton=$('#modal-submit');cancel.textContent='取消';for(const el of [cancel,submitButton]){el.removeAttribute?.('data-action');el.removeAttribute?.('data-id');el.removeAttribute?.('title');el.removeAttribute?.('aria-label');el.disabled=false;}submitButton.setAttribute('type','submit');$('#modal-title').textContent=title;$('#modal-kicker').textContent=kicker;$('#modal-body').innerHTML=body;$('#modal-error').hidden=true;$('#modal-error').textContent='';$('#modal-submit').textContent=submit;modalHandler=handler;$('#modal-form').reset();$('#modal').showModal();}
function validateAppFields(form){
  for(const field of Array.from(form?.elements||[])){
    if(field.disabled||!['INPUT','TEXTAREA'].includes(field.tagName)||field.type==='hidden')continue;
    const value=String(field.value||''),label=field.labels?.[0]?.textContent?.trim()||field.getAttribute?.('aria-label')||'欄位';
    const error=field.required&&!value.trim()?`請填寫${label}。`:field.maxLength>=0&&value.length>field.maxLength?`${label}最多 ${field.maxLength} 字。`:'';
    if(error){field.setAttribute('aria-invalid','true');field.classList.add('app-field-invalid');field.focus?.({preventScroll:true});throw appFieldError(field.name,error);}
  }
}
function dateField(value=month===TODAY.slice(0,7)?TODAY:month+'-01'){return editDatePicker(value,'2026-01','2030-12');}
function openEntry(type='expense',cardOnly=false){openRecordComposer(type,cardOnly);}
function getAmount(data,name='amount'){const n=Number(data.get(name));if(!Number.isSafeInteger(n)||n<1||n>100000000)throw Error('請輸入 1 到 100,000,000 之間的整數金額。');return n;}
function transfer(cardPay=false){openRecordComposer('transfer',false,cardPay);}
function recordFact(label,value,glyph){
  return `<div class="record-fact" aria-label="${esc(label+'：'+value)}"><span class="record-fact-label">${esc(label)}</span><div class="record-fact-content"><span class="record-fact-icon">${glyph}</span><strong>${esc(value)}</strong></div></div>`;
}
function txDetail(id){
  const t=state.tx.find(t=>t.id===id);if(!t)return;
  const plus=transactionIncoming(t),transfer=t.type==='transfer',kind=t.type==='investment'?(t.investment.side==='buy'?'投資買入':'投資賣出'):t.dividend?'股息收入':{expense:'支出',income:'收入',transfer:'轉帳',refund:'退款'}[t.type]||'紀錄',accountName=account(t.account)?.name||'帳戶',toName=account(t.to)?.name||'帳戶';
  const choices=transfer?`<div class="record-fact-transfer" aria-label="轉出帳戶至轉入帳戶">${recordFact('轉出',accountName,accountPickerIcon(account(t.account)))}<span class="record-transfer-arrow" aria-hidden="true">${icon('arrow')}</span>${recordFact('轉入',toName,accountPickerIcon(account(t.to)))}</div>`:`<div class="record-fact-grid">${recordFact(plus?'收款帳戶':'付款帳戶',accountName,accountPickerIcon(account(t.account)))}${recordFact(t.investment?'投資標的':'分類',t.investment?(t.investment.holding+' '+(state.holdings.find(h=>h.id===t.investment.holding)?.name||'')):t.category,journalIcon(t))}</div>`;
  const body=`<div class="record-detail-content"><div class="record-detail-type">${esc(kind)}${t.reversed?'<span class="record-reversed">已撤銷</span>':''}</div><section class="compose-stage" aria-label="${esc(kind)}金額">${recordAmount(t.amount,plus,transfer)}<div class="compose-date"><div class="compose-date-display">${icon('calendar')}<strong>${composerDateText(t.date)}</strong></div></div></section><div class="record-detail-choices">${choices}</div>${t.investment?`<div class="record-investment-quantity"><span>交易股數</span><strong>${money(t.investment.qty)} 股</strong></div>`:''}${t.note&&t.note.trim()&&t.note!==t.category?`<div class="entry-full-note record-detail-note"><span>備註</span><p>${esc(t.note)}</p></div>`:''}</div>`;
  openModal('紀錄明細',body,'刪除',()=>{},'');$('#modal').classList.add('entry-details');$('#modal').setAttribute('data-compose-type',transfer?'transfer':plus?'income':'expense');
  const edit=$('#modal .modal-actions .secondary'),remove=$('#modal-submit');edit.textContent='編輯';edit.disabled=Boolean(t.reversed);edit.setAttribute('aria-label',t.reversed?'已撤銷紀錄無法編輯':'編輯紀錄');edit.setAttribute('data-action','tx-edit');edit.setAttribute('data-id',id);
  remove.textContent='刪除';remove.setAttribute('type','button');remove.setAttribute('data-action','tx-delete-confirm');remove.setAttribute('data-id',id);
}

let editCalendarMonth='',editCalendarMin='2026-01',editCalendarMax='2030-12',editCalendarSelected='';
function editCalendar(){const [year,m]=editCalendarMonth.split('-').map(Number),offset=(new Date(Date.UTC(year,m-1,1)).getUTCDay()+6)%7;return `<div class="edit-calendar-nav"><button type="button" data-action="edit-calendar-prev" aria-label="上一個月" ${editCalendarMonth<=editCalendarMin?'disabled':''}><span class="month-chevron previous" aria-hidden="true"></span></button><strong aria-live="polite">${year} 年 ${m} 月</strong><button type="button" data-action="edit-calendar-next" aria-label="下一個月" ${editCalendarMonth>=editCalendarMax?'disabled':''}><span class="month-chevron next" aria-hidden="true"></span></button></div><div class="edit-calendar-week">${['一','二','三','四','五','六','日'].map(d=>`<span>${d}</span>`).join('')}</div><div class="edit-calendar-days" role="group" aria-label="選擇入帳日期">${Array.from({length:42},(_,i)=>{const d=new Date(Date.UTC(year,m-1,i-offset+1)),date=d.toISOString().slice(0,10),inMonth=date.startsWith(editCalendarMonth);return `<button type="button" ${inMonth?`data-action="edit-date-select" data-date="${date}"`:'disabled'} class="${inMonth?(date===editCalendarSelected?'selected':''):'outside'}" aria-pressed="${date===editCalendarSelected}" aria-label="${d.getUTCFullYear()} 年 ${d.getUTCMonth()+1} 月 ${d.getUTCDate()} 日${inMonth?'':'，不在本月'}">${d.getUTCDate()}</button>`;}).join('')}</div>`;}

function editDatePicker(date,min=editCalendarMin,max=editCalendarMax){return `<div class="edit-picker edit-date-picker"><button type="button" class="field-select-button" data-action="field-date" data-min="${min}" data-max="${max}"><span>入帳日期</span><strong id="edit-date-label">${composerDateText(date)}</strong><i aria-hidden="true"></i></button>${input('date','hidden',date)}</div>`;}
function moveEditCalendar(step){const [year,m]=editCalendarMonth.split('-').map(Number),next=new Date(Date.UTC(year,m-1+step,1)).toISOString().slice(0,7);if(next<editCalendarMin||next>editCalendarMax)return;editCalendarMonth=next;$('#edit-calendar').innerHTML=editCalendar();}
function selectEditDate(date){if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||date.slice(0,7)<editCalendarMin||date.slice(0,7)>editCalendarMax||!Number.isFinite(Date.parse(date))||new Date(date).toISOString().slice(0,10)!==date)return;editCalendarSelected=date;$('#f-date').value=date;$('#edit-date-label').textContent=composerDateText(date);$('#edit-calendar').innerHTML=editCalendar();if(pickerCurrent()?.kind==='calendar'){pickerCurrent().changed=true;backPickerPage();}storeCurrentDraft();}
function editPicker(name,label,options,selected,variant='row'){
  const current=options.find(o=>o.value===selected),title=esc(current?.label||'請選擇');
  const nameMarkup=`<strong id="picker-label-${name}">${title}</strong>`;
  const composeLabel=['from','to'].includes(name)?label.replace(/帳戶$/,''):label;
  const content=variant==='compose'?`<span class="account-tile-heading"><span class="picker-field-label">${esc(composeLabel)}</span></span><span class="account-tile-content"><span class="picker-account-icon" id="picker-icon-${name}" aria-hidden="true">${choiceIcon(name,selected)}</span><span class="account-tile-copy">${nameMarkup}</span></span>`:variant==='tile'?`<span class="account-tile-heading"><span class="picker-account-icon" id="picker-icon-${name}" aria-hidden="true">${choiceIcon(name,selected)}</span><span class="picker-field-label">${esc(label.replace(/帳戶$/,''))}</span></span><span class="account-tile-copy">${nameMarkup}</span>`:`${label?`<span class="picker-field-label">${label}</span>`:''}${nameMarkup}<i aria-hidden="true"></i>`;
  return `<div class="edit-picker ${['tile','compose'].includes(variant)?'account-picker-tile':''} ${variant==='compose'?'compose-picker-tile':''}" data-kind="${name==='category'?'category':'account'}"><input type="hidden" id="f-${name}" name="${name}" value="${esc(selected)}"><button type="button" class="field-select-button" data-action="field-options" data-name="${name}" data-title="${esc(label)}" data-options="${esc(JSON.stringify(options))}">${content}</button></div>`;
}
function pickEditOption(el){setFieldChoice(el.dataset.name,el.dataset.value,el.dataset.label);}
let editCalcExpression='',editCalcFresh=true,editCalcDirty=false;
function calculateEntryExpression(expression){const source=String(expression).replaceAll('×','*').replaceAll('÷','/').replaceAll('−','-').replace(/\s/g,'');if(!source||source.length>80)throw Error('請完成計算式。');const tokens=source.match(/\d+(?:\.\d*)?|\.\d+|[+*/-]/g)||[];if(tokens.join('')!==source)throw Error('計算式格式不正確。');let i=0;function factor(){let sign=1;if(tokens[i]==='+'||tokens[i]==='-')sign=tokens[i++]==='-'?-1:1;const token=tokens[i++];if(!token||!/^\d|^\.\d/.test(token))throw Error('請完成計算式。');const n=Number(token)*sign;if(!Number.isFinite(n))throw Error('金額過大。');return n;}function term(){let value=factor();while(tokens[i]==='*'||tokens[i]==='/'){const op=tokens[i++],n=factor();if(op==='/'&&n===0)throw Error('不能除以零。');value=op==='*'?value*n:value/n;}return value;}let result=term();while(i<tokens.length){const op=tokens[i++];if(op!=='+'&&op!=='-')throw Error('計算式格式不正確。');const n=term();result=op==='+'?result+n:result-n;}if(!Number.isFinite(result)||Math.abs(result)>1e12)throw Error('金額過大。');return Number(result.toFixed(8));}
function recordAmount(amount,positive,transfer,editable=false){
  const tone=positive?'positive':transfer?'':'expense-amount',sign=transfer?'':positive?'+':'−';
  const content=`<span class="entry-amount-unit">TWD</span><span class="entry-amount-value"><span class="edit-calc-sign ${tone}">${sign}</span><strong ${editable?'id="edit-calc-amount"':''} class="${amountTextClass(amount)} ${tone}">${money(amount)}</strong></span><span class="edit-calc-hint" aria-hidden="true">${editable?calcIcon('calculator'):''}</span>`;
  return editable?`<button type="button" class="entry-amount-trigger" data-action="field-calc" data-name="amount" data-tone="${positive?'income':transfer?'transfer':'expense'}" data-editor="true" data-min="1" aria-label="用計算機編輯金額 ${nt(amount)}">${content}</button>`:`<div class="record-amount-display" aria-label="${nt(amount)}">${content}</div>`;
}
function entryCalculator(amount,positive,transfer){return `<div class="edit-picker edit-calculator">${recordAmount(amount,positive,transfer,true)}${input('amount','hidden',amount)}</div>`;}
function useEntryCalcKey(key){const calc={expression:editCalcExpression,fresh:editCalcFresh,dirty:editCalcDirty},result=stepAmountCalculator(calc,key);if(!result.changed)return;editCalcExpression=calc.expression;editCalcFresh=calc.fresh;editCalcDirty=calc.dirty;$('#edit-calc-message').textContent=result.message||'';$('#edit-calc-expression').textContent=calc.expression;if(result.value!==undefined){$('#edit-calc-amount').textContent=Number.isInteger(result.value)?money(result.value):String(result.value);$('#f-amount').value=String(result.value);}if(result.completed){const picker=$('#edit-calc-amount').closest?.('details');if(picker)picker.open=false;}}
function txEdit(id){
  const t=state.tx.find(t=>t.id===id);if(!t||t.reversed)return;
  if(t.type==='investment'||t.dividend)return openInvestmentComposer({amount:t.amount,date:t.date,account:t.account,note:t.note,holding:t.investment?.holding||t.dividend,qty:t.investment?.qty||0,tradeSide:t.investment?.side||'dividend'},id);
  editCalcExpression=String(t.amount);editCalcFresh=true;editCalcDirty=false;
  editCalendarMonth=t.date.slice(0,7);editCalendarSelected=t.date;
  editCalendarMin=t.recurring?editCalendarMonth:'2026-01';editCalendarMax=t.recurring?editCalendarMonth:'2030-12';
  const plus=transactionIncoming(t),editKind=t.to?'transfer':plus?'income':'expense';
  const kind=t.type==='investment'?(t.investment.side==='buy'?'投資買入':'投資賣出'):t.dividend?'股息收入':{expense:'支出',income:'收入',refund:'退款',transfer:'轉帳'}[t.type];
  const amountLabel=kind+'金額';
  const categoryChoices=[...new Set([t.category,...(t.type==='expense'||t.type==='refund'?managedCategories('expense').map(c=>c.name):categoryNameOptions('income'))])];
  const sourceOptions=state.accounts.filter(a=>t.to?a.kind!=='card'||a.id===t.account:t.type==='expense'||a.kind!=='card'||a.id===t.account).map(a=>({value:a.id,label:a.name}));
  const choices=t.to
    ?transferPickerPair('account',sourceOptions,t.account,state.accounts.map(a=>({value:a.id,label:a.name})),t.to,account(t.to)?.kind==='card','compose')
    :`<div class="compose-choice-grid${t.dividend?' single':''}">${editPicker('account',plus?'收款帳戶':'付款帳戶',sourceOptions,t.account,'compose')}${t.dividend?'':editPicker('category','分類',categoryChoices.map(c=>({value:c,label:c})),t.category,'compose')}</div>`;
  const body=`<div class="record-compose-content"><section class="compose-stage" aria-label="${amountLabel}">${entryCalculator(t.amount,plus,t.type==='transfer')}${composerDatePicker(t.date,editCalendarMin,editCalendarMax)}</section><div class="compose-details">${choices}</div><div class="compose-note"><label class="edit-note-label" for="f-note">${icon('note')}<span>備註</span></label><textarea id="f-note" name="note" class="edit-note" rows="2" maxlength="500">${esc(t.note||'')}</textarea></div></div>`;
  openModal('編輯'+kind,body,'儲存修改',data=>{
    if(editCalcDirty)data.set('amount',String(calculateEntryExpression(editCalcExpression)));
    const amount=getAmount(data),date=data.get('date'),accountId=data.get('account'),target=t.to?data.get('to'):null,note=(data.get('note')||'').trim();
    if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isFinite(Date.parse(date))||new Date(date).toISOString().slice(0,10)!==date||date<'2026-01-01'||date>'2030-12-31')throw Error('請選擇有效的入帳日期。');
    if(!account(accountId)||target&&!account(target))throw Error('請選擇有效帳戶。');
    if(target===accountId)throw Error('轉出與轉入帳戶需要不同。');
    if(t.type!=='expense'&&account(accountId).kind==='card'&&accountId!==t.account)throw Error('請選擇現金或存款帳戶。');
    if(t.recurring&&date.slice(0,7)!==t.date.slice(0,7))throw Error('定期交易需保留在原入帳月份。');
    const category=t.to||t.dividend?t.category:data.get('category');if(!categoryChoices.includes(category))throw Error('請選擇有效分類。');
    Object.assign(t,{amount,date,account:accountId,category,note:note||category});if(target)t.to=target;
    save();recordSaved(t,'紀錄已更新。');
  },'EDIT ENTRY');
  $('#modal').classList.add('entry-edit','entry-compose');
  $('#modal').setAttribute('data-compose-type',editKind);configureDraft('edit:'+id,{record:true});
}

function txDeleteConfirm(id){const t=state.tx.find(t=>t.id===id);if(!t)return;openModal('刪除這筆紀錄？',`<p class="delete-entry-name">${esc(t.note||t.category)}</p><p class="delete-entry-value">${nt(t.amount)} · ${esc(t.date)}</p>`,'確認刪除',()=>{removeRecordWithUndo(id);},'DELETE ENTRY');}

function openAccount(){const kinds=[{value:'bank',label:'銀行帳戶'},{value:'cash',label:'現金'},{value:'ewallet',label:'電子支付'},{value:'card',label:'信用卡'}];openModal('新增帳戶',`<div class="account-create-content"><label class="account-name-control" for="f-name"><span>帳戶名稱</span><input id="f-name" name="name" type="text" required maxlength="30" placeholder="例如：旅遊基金" autocomplete="off"></label><div class="account-create-grid">${editPicker('kind','帳戶類型',kinds,'bank','compose')}<div class="account-opening-control"><span>起始金額</span><div>${currencyControl('opening',0,0)}</div></div></div></div>`,'建立帳戶',data=>{const name=data.get('name').trim(),kind=data.get('kind');if(!name)throw Error('請填寫帳戶名稱。');if(!kinds.some(item=>item.value===kind))throw Error('請選擇有效的帳戶類型。');const n=Number(data.get('opening'));if(!Number.isSafeInteger(n)||n<0||n>100000000)throw Error('請輸入有效的起始金額。');const a={id:uid(),name,kind,opening:kind==='card'?-n:n};state.accounts.push(a);selectedAccount=a.id;save();route('accounts');toast(kind==='card'?'信用卡已加入帳戶。':'新帳戶已建立。');},'NEW ACCOUNT');$('#modal').classList.add('entry-edit','entry-compose','account-compose');$('#modal').setAttribute('data-compose-type','account');configureDraft('account-new');}
function download(text,type,name){const url=URL.createObjectURL(new Blob([text],{type}));const link=document.createElement('a');link.href=url;link.download=name;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
function exportCSV(){const cell=s=>'"'+String(s??'').replace(/"/g,'""').replace(/^[=+@-]/,"'$&")+'"';const rows=[['日期','類型','分類','帳戶','轉入帳戶','金額 TWD','備註','狀態','入帳來源','定期項目','配息標的','投資標的','買賣方向','股數'],...(page==='ledger'?ledgerFilteredTransactions():recent()).map(t=>[t.date,t.type,t.category,account(t.account)?.name,t.to?account(t.to)?.name:'',t.amount,t.note,t.reversed?'已撤銷':'有效',ledgerSourceNames[transactionSource(t)],t.recurring||'',t.dividend||'',t.investment?.holding||'',t.investment?.side||'',t.investment?.qty||''])];download('\ufeff'+rows.map(row=>row.map(cell).join(',')).join('\r\n'),'text/csv;charset=utf-8',`hibi-${page==='ledger'&&ledgerAdvanced?.scope==='all'?'filtered':month}.csv`);toast(page==='ledger'?'已匯出目前符合條件的 '+ledgerFilteredTransactions().length+' 筆紀錄。':'已匯出 '+labelMonth()+' 的收支紀錄。');}
document.addEventListener('click',e=>{
  const routeButton=e.target.closest('[data-route]');if(routeButton){route(routeButton.dataset.route);return;}
  const el=e.target.closest('[data-action]');if(!el)return;const a=el.dataset.action,id=el.dataset.id;
  if(experienceAction(el))return;
  if(a==='category-new'){openCategoryEditor('',el.dataset.type);return;}if(a==='category-edit'){openCategoryEditor(id);return;}if(a==='category-status'){categoryStatus(id);return;}if(a==='category-style'){categoryStyleChoice(el);return;}
  if(a==='investment-side'){switchInvestmentSide(el.dataset.side);return;}if(a==='investment-new-holding'){newInvestmentHolding(el);return;}if(a==='investment-save-holding'){saveInvestmentHolding();return;}
  if(a==='search-input-clear'){$('#f-keyword').value='';$('#f-keyword').focus?.();return;}
  if(a.startsWith('picker-')){pickerAction(el);return;}
  if(a==='field-options'){openFieldOptions(el);return;}if(a==='field-date'){openFieldDate(el);return;}if(a==='field-calc'){openFieldCalculator(el);return;}
  if(a.startsWith('lf-')){ledgerFilterAction(el);return;}
  if(a.startsWith('dash-')){ledgerAdvanced=null;dashboardAction(a,el);return;}
  if(a==='home-income'||a==='home-expense'){openLedgerContext({filter:a==='home-income'?'income':'expense'});return;}
  if(a==='month-prev'||a==='month-next')changePageMonth(a==='month-prev'?-1:1);
  else if(a==='compose-type')switchRecordType(el.dataset.type);else if(a==='entry')resumeEntry();else if(a==='entry-expense'||a==='entry-income'||a==='entry-transfer')switchRecordType(a==='entry-transfer'?'transfer':a==='entry-income'?'income':'expense');
  else if(a==='transfer')transfer();else if(a==='card-pay')transfer(true);else if(a==='card-charge')openEntry('expense',true);
  else if(a==='chart-net'||a==='chart-flow'){chartMode=a==='chart-net'?'net':'flow';render();}
  else if(a==='chart-point')$('#chart-detail').textContent=`${el.dataset.label} · ${nt(Number(el.dataset.value))}`;
  else if(a==='category'){openLedgerContext({categoryFilter:el.dataset.category,filter:el.dataset.type||'expense'});}
  else if(a==='waterfall-info')showWaterfallInfo(el);
  else if(a==='ledger-filter')ledgerFilters();else if(a==='ledger-search')ledgerSearch();else if(a==='ledger-clear'){ledgerAdvanced=null;filter='all';categoryFilter='';ledgerAccountFilter='';dateFilter='';search='';render();}else if(a==='clear-date'){dateFilter='';render();}else if(a==='clear-category'){categoryFilter='';render();}else if(a==='filter'){filter=el.dataset.filter;render();}
  else if(a==='tx-detail')txDetail(id);else if(a==='edit-picker-open'){const current=el.closest('.edit-picker');for(const picker of document.querySelectorAll('#modal .edit-picker[open]'))if(picker!==current)picker.open=false;}else if(a==='edit-calc-key')useEntryCalcKey(el.dataset.key);else if(a==='edit-calendar-prev')moveEditCalendar(-1);else if(a==='edit-calendar-next')moveEditCalendar(1);else if(a==='edit-date-select')selectEditDate(el.dataset.date);else if(a==='edit-pick')pickEditOption(el);else if(a==='tx-edit'){$('#modal').close();txEdit(id);}else if(a==='tx-delete-confirm'){$('#modal').close();txDeleteConfirm(id);}
  else if(a==='reverse-confirm'){$('#modal').close();const t=state.tx.find(t=>t.id===id);openModal('撤銷這一筆？',`<p>${esc(t.note)} · ${nt(t.amount)}</p>`,'確認撤銷',()=>{commitLedgerTransactions(state.tx.map(row=>row.id===id?{...row,reversed:true}:row));save();render();toast('這一筆已撤銷，金額已重新計算。');},'REVERSE AN ENTRY');}
  else if(a==='account')openAccount();else if(a==='card-account'){selectedAccount=state.accounts.find(item=>item.kind==='card')?.id||selectedAccount;route('account-detail');}else if(a==='account-open'){if(account(id)){selectedAccount=id;route('account-detail');}}else if(a==='account-record'){const current=account(selectedAccount);if(current)openRecordComposer('expense',current.kind==='card',false,{account:current.id});}else if(a==='account-transfer'){const current=account(selectedAccount);if(current)openRecordComposer('transfer',false,false,{from:current.id});}else if(a==='account-pay'){const current=account(selectedAccount);if(current?.kind==='card')openRecordComposer('transfer',false,true,{to:current.id});}
  else if(a==='edit-budget')editBudget(id);else if(a==='confirm-recurring')confirmRecurring(id);else if(a==='recurring-new')newRecurring();
  else if(a==='recurring-manage')openRecurringManager(el);else if(a==='recurring-posted'){const r=state.recurring.find(r=>r.id===id),t=r&&recurringPosting(r);if(t)txDetail(t.id);}
  else if(a==='toggle-recurring'){const r=state.recurring.find(r=>r.id===id);if(!r)return;r.active=!r.active;save();render();if(pickerCurrent()?.kind==='recurring-settings'){renderPickerPage();restorePickerFocus({trigger:el,triggerData:{action:'toggle-recurring',id}});}toast(r.active?'定期交易已啟用。':'定期交易已暫停。');}
  else if(a==='holding')holding(id);else if(a==='dividend')dividend();
  else if(a==='privacy'){state.privacy=!state.privacy;save();render();}
  else if(a==='export')exportCSV();else if(a==='download-demo'){download(JSON.stringify(state,null,2),'application/json','hibi-demo-data.json');toast('已下載目前的演示資料。');}
  else if(a==='reset')resetPreview();
});
document.addEventListener('keydown',e=>{if((e.key==='Enter'||e.key===' ')&&e.target.matches('svg [data-action]')){e.preventDefault();e.target.dispatchEvent(new MouseEvent('click',{bubbles:true}));}});
document.addEventListener('pointerover',e=>{const el=e.target.closest?.('[data-action="waterfall-info"]');if(el&&e.pointerType==='mouse')showWaterfallInfo(el);});
document.addEventListener('focusin',e=>{const el=e.target.closest?.('[data-action="waterfall-info"]');if(el)showWaterfallInfo(el);});
document.addEventListener('input',e=>{if(e.target.closest?.('#modal-form')){e.target.removeAttribute?.('aria-invalid');e.target.classList?.remove('app-field-invalid');$('#modal-error').hidden=true;}if(e.target.id==='search'){search=e.target.value;$('#transaction-list').innerHTML=ledgerList();}});
$('#modal-form').addEventListener('submit',e=>{e.preventDefault();$('#modal-error').hidden=true;try{validateAppFields($('#modal-form'));modalHandler?.(new FormData(e.target));dismissModal({saved:true});}catch(error){presentFormError(error);}});
document.querySelectorAll('.close-modal').forEach(b=>b.addEventListener('click',()=>{if(b.dataset.action!=='lf-reset'&&!b.dataset.action)dismissModal();}));
$('#modal').addEventListener('cancel',e=>{e.preventDefault();dismissModal();});
$('#modal').addEventListener('click',e=>{if(e.target===$('#modal')){const r=e.target.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)dismissModal();}});
$('#settings-shortcut').innerHTML=icon('settings');$('#settings-shortcut').addEventListener('click',()=>route('settings'));
window.addEventListener('hashchange',()=>{const target=location.hash.slice(1)||'overview';if(target!==page&&!modalSession?.active)route(target,{replace:true});});
route(location.hash.slice(1)||'overview',{replace:true});
