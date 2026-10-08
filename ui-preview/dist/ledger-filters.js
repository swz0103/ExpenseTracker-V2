/* Transaction filters use the same posted records as the ledger. */
let ledgerAdvanced=null,ledgerFilterDraft=null,ledgerFilterDateSlot='',ledgerFilterCalendarMonth='';
let ledgerFilterAmountSlot='',ledgerFilterAmountCalc=null,ledgerFilterAmountMessage='';
const ledgerTypeNames={expense:'支出',income:'收入',transfer:'轉帳',refund:'退款',investment:'投資'};
const ledgerSourceNames={manual:'手動記帳',recurring:'定期交易',dividend:'股息入帳'};
const ledgerKindNames={bank:'銀行',cash:'現金',card:'信用卡',ewallet:'電子支付'};
function defaultLedgerFilters(){return {scope:'month',types:[],categories:[],accounts:[],direction:'any',accountKinds:[],dateFrom:'',dateTo:'',min:'',max:'',sources:[],references:[],status:'active',cardAction:'all',sort:'newest'};}
function currentLedgerFilters(){return ledgerAdvanced?JSON.parse(JSON.stringify(ledgerAdvanced)):{...defaultLedgerFilters(),types:filter==='all'?[]:filter==='expense'?['expense','refund']:[filter],categories:categoryFilter?[categoryFilter]:[],accounts:ledgerAccountFilter?[ledgerAccountFilter]:[],dateFrom:dateFilter,dateTo:dateFilter};}
function transactionSource(t){return t.dividend?'dividend':t.recurring?'recurring':'manual';}
function ledgerFilteredTransactions(f=currentLedgerFilters(),keyword=search){
  const term=String(keyword||'').trim().toLocaleLowerCase();
  const list=state.tx.filter(t=>{
    if(f.scope==='month'&&!t.date.startsWith(month))return false;
    if(f.status==='active'&&t.reversed||f.status==='reversed'&&!t.reversed)return false;
    if(f.types.length&&!f.types.includes(t.type)||f.categories.length&&!f.categories.includes(t.category))return false;
    if(f.direction==='destination'&&!t.to)return false;
    const ids=f.direction==='source'?[t.account]:f.direction==='destination'?[t.to].filter(Boolean):[t.account,t.to].filter(Boolean);
    if(f.accounts.length&&!ids.some(id=>f.accounts.includes(id)))return false;
    if(f.accountKinds.length&&!ids.some(id=>f.accountKinds.includes(account(id)?.kind)))return false;
    if(f.dateFrom&&t.date<f.dateFrom||f.dateTo&&t.date>f.dateTo)return false;
    if(f.min!==''&&t.amount<Number(f.min)||f.max!==''&&t.amount>Number(f.max))return false;
    const source=transactionSource(t),reference=t.dividend?'dividend:'+t.dividend:t.recurring?'recurring:'+t.recurring:'';
    if(f.sources.length&&!f.sources.includes(source)||f.references.length&&!f.references.includes(reference))return false;
    if(f.cardAction==='spend'&&!(t.type==='expense'&&account(t.account)?.kind==='card'))return false;
    if(f.cardAction==='payment'&&!(t.type==='transfer'&&account(t.to)?.kind==='card'))return false;
    return !term||[t.id,t.note,t.category,account(t.account)?.name,account(t.to)?.name,state.recurring.find(r=>r.id===t.recurring)?.name,state.holdings.find(h=>h.id===(t.dividend||t.investment?.holding))?.name,t.dividend,t.investment?.holding,t.investment?.side==='buy'?'買入':t.investment?.side==='sell'?'賣出':''].join(' ').toLocaleLowerCase().includes(term);
  });
  const chronological=(a,b)=>b.date.localeCompare(a.date)||state.tx.indexOf(b)-state.tx.indexOf(a);
  return list.sort((a,b)=>f.sort==='oldest'?-chronological(a,b):f.sort==='highest'?b.amount-a.amount||chronological(a,b):f.sort==='lowest'?a.amount-b.amount||chronological(a,b):chronological(a,b));
}
function ledgerFilterLabels(f=currentLedgerFilters()){
  const labels=[];
  if(f.scope==='all')labels.push('跨月份');
  if(f.types.length)labels.push(f.types.map(k=>ledgerTypeNames[k]).join('／'));
  if(f.categories.length)labels.push(f.categories.length===1?f.categories[0]:f.categories.length+' 個分類');
  if(f.accounts.length)labels.push((f.direction==='source'?'轉出／使用 ':f.direction==='destination'?'轉入 ':'')+(f.accounts.length===1?account(f.accounts[0])?.name:f.accounts.length+' 個帳戶'));
  if(f.accountKinds.length)labels.push(f.accountKinds.map(k=>ledgerKindNames[k]).join('／'));
  if(f.direction!=='any'&&!f.accounts.length)labels.push(f.direction==='source'?'轉出／使用帳戶':'轉入帳戶');
  if(f.dateFrom||f.dateTo)labels.push(f.dateFrom===f.dateTo?f.dateFrom:(f.dateFrom||'不限起日')+' ～ '+(f.dateTo||'不限迄日'));
  if(f.min!==''||f.max!=='')labels.push('TWD '+(f.min!==''?money(Number(f.min)):'0')+' ～ '+(f.max!==''?money(Number(f.max)):'不限'));
  if(f.sources.length)labels.push(f.sources.map(k=>ledgerSourceNames[k]).join('／'));
  if(f.references.length)labels.push(f.references.length+' 個指定項目');
  if(f.status!=='active')labels.push(f.status==='reversed'?'已撤銷':'含已撤銷');
  if(f.cardAction!=='all')labels.push(f.cardAction==='spend'?'刷卡消費':'信用卡繳款');
  if(f.sort!=='newest')labels.push({oldest:'日期由舊到新',highest:'金額由大到小',lowest:'金額由小到大'}[f.sort]);
  return labels;
}
function ledgerFilterChip(key,value,label,selected,art=''){
  return `<button type="button" class="lf-option ${selected?'selected':''}" data-action="lf-option" data-key="${key}" data-value="${esc(value)}" aria-pressed="${selected}">${art?`<span class="lf-option-icon">${art}</span>`:''}<span>${esc(label)}</span></button>`;
}
function ledgerFilterOptions(key,options,multi=false,grid=''){
  const selected=ledgerFilterDraft[key];
  return `<div class="lf-options ${grid}" role="group">${multi?ledgerFilterChip(key,'','全部',!selected.length):''}${options.map(([value,label,art])=>ledgerFilterChip(key,value,label,multi?selected.includes(value):selected===value,art)).join('')}</div>`;
}
const ledgerFilterPages={};
function ledgerFilterSection(key,label,summary,body){ledgerFilterPages[key]={title:label,body};return `<button type="button" class="lf-section-trigger" data-action="lf-section" data-key="${key}"><strong>${label}</strong><span>${esc(summary||'不限')}</span><i class="month-chevron next" aria-hidden="true"></i></button>`;}
function ledgerFilterCalendar(){
  const ym=ledgerFilterCalendarMonth,[year,m]=ym.split('-').map(Number),first=(new Date(Date.UTC(year,m-1,1)).getUTCDay()+6)%7,chosen=ledgerFilterDraft[ledgerFilterDateSlot];
  const days=Array.from({length:42},(_,i)=>{const d=new Date(Date.UTC(year,m-1,i-first+1)),date=d.toISOString().slice(0,10),outside=!date.startsWith(ym),inRange=ledgerFilterDraft.dateFrom&&ledgerFilterDraft.dateTo&&date>=ledgerFilterDraft.dateFrom&&date<=ledgerFilterDraft.dateTo;return `<button type="button" class="${outside?'outside':chosen===date?'selected':inRange?'in-range':''}" data-action="lf-date" data-value="${date}" ${outside?'disabled':''} aria-label="${date}" ${chosen===date?'aria-current="date"':''}>${d.getUTCDate()}</button>`;}).join('');
  return `<div class="lf-calendar"><div class="lf-calendar-head"><button type="button" data-action="lf-calendar" data-value="-1" aria-label="上一個月"><span class="month-chevron previous"></span></button><strong>${year} 年 ${m} 月</strong><button type="button" data-action="lf-calendar" data-value="1" aria-label="下一個月"><span class="month-chevron next"></span></button></div><div class="edit-calendar-week">${['一','二','三','四','五','六','日'].map(d=>`<span>${d}</span>`).join('')}</div><div class="edit-calendar-days">${days}</div></div>`;
}
function ledgerAmountCalculator(){
  if(!ledgerFilterAmountSlot)return '';
  const label=ledgerFilterAmountSlot==='min'?'最低金額':'最高金額';
  let value;try{value=calculateEntryExpression(ledgerFilterAmountCalc.expression);}catch{}
  return `<div class="lf-amount-calculator"><div class="calculator-total"><small class="currency-unit">TWD</small><strong class="lf-calc-value ${amountTextClass(value)}">${value===undefined?'…':Number.isInteger(value)?money(value):value}</strong></div><output class="lf-calc-expression" aria-label="計算式">${esc(ledgerFilterAmountCalc.expression)}</output><p class="edit-calc-message" aria-live="polite">${esc(ledgerFilterAmountMessage)}</p>${calculatorKeypad('lf-amount-key')}<button type="button" class="lf-amount-unlimited" data-action="lf-amount-clear">清除此金額限制</button></div>`;
}
function previewLedgerAmountFilters(){
  const f={...ledgerFilterDraft};
  if(ledgerFilterAmountSlot&&ledgerFilterAmountCalc?.dirty){try{const value=calculateEntryExpression(ledgerFilterAmountCalc.expression);if(Number.isSafeInteger(value)&&value>=0&&value<=100000000)f[ledgerFilterAmountSlot]=String(value);}catch{}}
  return f;
}
function commitLedgerAmount(){
  if(!ledgerFilterAmountSlot||!ledgerFilterAmountCalc?.dirty)return;
  const value=calculateEntryExpression(ledgerFilterAmountCalc.expression);
  if(!Number.isSafeInteger(value)||value<0||value>100000000)throw Error('金額需為 0 到 100,000,000 之間的整數。');
  ledgerFilterDraft[ledgerFilterAmountSlot]=String(value);
  ledgerFilterAmountCalc.dirty=false;
}
function ledgerFilterBody(){
  const f=ledgerFilterDraft,categoryNames=[...new Set([...categoryCatalog().map(c=>c.name),...state.tx.map(t=>t.category)])];
  const refs=[...new Map(state.tx.filter(t=>t.recurring||t.dividend).map(t=>{const key=t.dividend?'dividend:'+t.dividend:'recurring:'+t.recurring;return [key,[key,t.dividend?(t.dividend+' '+(state.holdings.find(h=>h.id===t.dividend)?.name||'')):(state.recurring.find(r=>r.id===t.recurring)?.name||t.note||t.recurring)]];})).values()];
  const scope=ledgerFilterOptions('scope',[['month',Number(month.slice(5))+' 月紀錄'],['all','跨月份']]);
  const dates=`<div class="lf-date-range">${[['dateFrom','開始日期'],['dateTo','結束日期']].map(([key,label])=>`<button type="button" class="lf-date-trigger ${ledgerFilterDateSlot===key?'selected':''}" data-action="lf-date-open" data-key="${key}"><small>${label}</small><strong>${f[key]||'不限日期'}</strong></button>`).join('')}</div><div class="lf-date-shortcuts"><button type="button" data-action="lf-date-shortcut" data-value="month">整個${Number(month.slice(5))}月</button><button type="button" data-action="lf-date-shortcut" data-value="today">演示今天</button><button type="button" data-action="lf-date-shortcut" data-value="clear">清除日期</button></div>`;
  const advanced=[
    ledgerFilterSection('category','分類',f.categories.length?f.categories.length+' 個分類':'所有分類',ledgerFilterOptions('categories',categoryNames.map(c=>[c,c,journalIcon({type:c.includes('收入')?'income':c==='轉帳'?'transfer':'expense',category:c})]),true,'lf-category-grid')),
    ledgerFilterSection('account-detail','帳戶方向與類型',f.direction==='any'&&!f.accountKinds.length?'不限':'已指定',ledgerFilterOptions('direction',[['any','任一端'],['source','轉出／使用'],['destination','轉入']])+ledgerFilterOptions('accountKinds',Object.entries(ledgerKindNames),true)),
    ledgerFilterSection('amount','金額區間',f.min!==''||f.max!==''?'已指定金額':'不限金額',`<div class="lf-amount-range">${[['min','最低金額'],['max','最高金額']].map(([key,label],i)=>`${i?'<span>～</span>':''}<button type="button" class="lf-amount-trigger" data-action="lf-amount-open" data-key="${key}"><small>${label} · TWD</small><span>${f[key]!==''?money(Number(f[key])):key==='min'?'0':'不限'}</span><i>${calcIcon('calculator')}</i></button>`).join('')}</div>`),
    ledgerFilterSection('source','入帳來源',f.sources.length||f.references.length?'已指定來源':'所有來源',ledgerFilterOptions('sources',Object.entries(ledgerSourceNames),true)+(refs.length?`<h4>指定項目</h4>${ledgerFilterOptions('references',refs,true)}`:'')),
    ledgerFilterSection('more','狀態與排序',f.status==='active'&&f.cardAction==='all'&&f.sort==='newest'?'有效紀錄 · 最新優先':'已調整',`<h4>紀錄狀態</h4>${ledgerFilterOptions('status',[['active','有效紀錄'],['reversed','已撤銷'],['all','全部狀態']])}<h4>信用卡動作</h4>${ledgerFilterOptions('cardAction',[['all','不限'],['spend','刷卡消費'],['payment','信用卡繳款']])}<h4>排列順序</h4>${ledgerFilterOptions('sort',[['newest','最新優先'],['oldest','最舊優先'],['highest','金額由大到小'],['lowest','金額由小到大']])}`)
  ].join('');
  ledgerFilterPages.advanced={title:'其他篩選條件',body:advanced};
  ledgerFilterPages.type={title:'交易類型',body:ledgerFilterOptions('types',Object.entries(ledgerTypeNames).map(([key,label])=>[key,label,journalIcon({type:key})]),true,'lf-type-grid')};
  ledgerFilterPages.account={title:'帳戶',body:ledgerFilterOptions('accounts',state.accounts.map(a=>[a.id,a.name,accountPickerIcon(a)]),true,'lf-account-grid')};
  ledgerFilterPages.date={title:'日期區間',body:dates};
  const extra=f.categories.length+f.accountKinds.length+f.sources.length+f.references.length+Number(f.min!=='')+Number(f.max!=='')+Number(f.status!=='active')+Number(f.cardAction!=='all')+Number(f.sort!=='newest')+Number(f.direction!=='any');
  return `<div class="lf-compact-top"><div class="lf-preview"><strong id="lf-count">${ledgerFilteredTransactions(f,f.keyword).length}<span>筆紀錄</span></strong></div><div class="lf-scope">${scope}</div></div><label class="lf-search" for="lf-keyword">${icon('search')}<input id="lf-keyword" type="search" value="${esc(f.keyword)}" maxlength="100" placeholder="搜尋紀錄" data-lf-input="keyword" autocomplete="off"></label><section class="lf-primary" id="lf-primary-type"><h3>交易類型</h3>${ledgerFilterPages.type.body}</section><section class="lf-primary" id="lf-primary-account"><h3>帳戶<button type="button" data-action="lf-section" data-key="account">展開</button></h3><div class="lf-account-rail">${ledgerFilterOptions('accounts',state.accounts.map(a=>[a.id,a.name,accountPickerIcon(a)]),true)}</div></section><section class="lf-primary" id="lf-primary-date"><h3>日期</h3>${dates}</section><button class="lf-advanced-trigger" data-action="lf-section" data-key="advanced" type="button"><strong>其他條件</strong><span>${extra?extra+' 項已選':'分類、金額、來源、排序'}</span></button>`;
}

function refreshLedgerFilterPanel(){const body=$('#modal-body'),scroll=body.scrollTop;body.innerHTML=ledgerFilterBody();body.scrollTop=scroll;updateLedgerFilterCount();if(pickerCurrent()?.filterPage)renderPickerPage();}
function updateLedgerFilterCount(){const count=ledgerFilteredTransactions(previewLedgerAmountFilters(),ledgerFilterDraft.keyword).length;$('#lf-count').innerHTML=count+'<span>筆紀錄</span>';$('#modal-submit').textContent='顯示 '+count+' 筆紀錄';}
function validateLedgerFilters(f){
  for(const key of ['min','max'])if(f[key]!==''&&(!/^\d+$/.test(f[key])||!Number.isSafeInteger(Number(f[key]))||Number(f[key])>100000000))throw Error('金額請輸入 0 到 100,000,000 之間的整數。');
  if(f.min!==''&&f.max!==''&&Number(f.min)>Number(f.max))throw Error('最低金額不能高於最高金額。');
  for(const key of ['dateFrom','dateTo'])if(f[key]&&(!/^\d{4}-\d{2}-\d{2}$/.test(f[key])||!Number.isFinite(Date.parse(f[key]))||new Date(f[key]).toISOString().slice(0,10)!==f[key]))throw Error('請選擇有效日期。');
  if(f.dateFrom&&f.dateTo&&f.dateFrom>f.dateTo)throw Error('開始日期不能晚於結束日期。');
}
function applyLedgerFilters(){
  commitLedgerAmount();
  validateLedgerFilters(ledgerFilterDraft);
  const {keyword,...f}=ledgerFilterDraft;ledgerAdvanced=JSON.parse(JSON.stringify(f));search=keyword.trim();
  filter=f.types.length===1?f.types[0]:f.types.length===2&&f.types.includes('expense')&&f.types.includes('refund')?'expense':'all';
  categoryFilter=f.categories.length===1?f.categories[0]:'';ledgerAccountFilter=f.accounts.length===1?f.accounts[0]:'';dateFilter=f.dateFrom&&f.dateFrom===f.dateTo?f.dateFrom:'';
  render();
}
function openLedgerFilters(){
  ledgerFilterDraft={...currentLedgerFilters(),keyword:search};ledgerFilterDateSlot='';ledgerFilterAmountSlot='';ledgerFilterAmountCalc=null;
  openModal('篩選紀錄',ledgerFilterBody(),'套用篩選',applyLedgerFilters,'FIND YOUR RECORDS');
  $('#modal').classList.add('ledger-filter-panel');
  const reset=$('#modal .modal-actions .secondary');reset.textContent='重設條件';reset.setAttribute('data-action','lf-reset');updateLedgerFilterCount();
}
function ledgerFilterAction(el){
  const {action,key,value}=el.dataset;
  const returningPage=['lf-amount-clear','lf-amount-close','lf-amount-key','lf-date'].includes(action)?pickerCurrent():null;
  if(action==='lf-section'){showPickerPage({trigger:el,kind:'filter-options',filterPage:true,title:ledgerFilterPages[key].title,done:true,render:()=>`<div class="lf-section-body">${ledgerFilterPages[key].body}</div>`});return;}
  if(action==='lf-reset'){
    ledgerFilterDraft={...defaultLedgerFilters(),keyword:''};ledgerFilterDateSlot='';ledgerFilterAmountSlot='';ledgerFilterAmountCalc=null;
  }else if(action==='lf-amount-open'){
    ledgerFilterAmountSlot=key;ledgerFilterAmountCalc={expression:ledgerFilterDraft[key]||'0',fresh:true,dirty:false};ledgerFilterAmountMessage='';ledgerFilterDateSlot='';showPickerPage({trigger:el,kind:'filter-calculator',filterPage:true,title:key==='min'?'最低金額':'最高金額',render:ledgerAmountCalculator,onBack:()=>{ledgerFilterAmountSlot='';ledgerFilterAmountCalc=null;refreshLedgerFilterPanel();}});
  }else if(action==='lf-amount-key'){
    if(!ledgerFilterAmountSlot)return;
    const result=stepAmountCalculator(ledgerFilterAmountCalc,key,0);ledgerFilterAmountMessage=result.message||'';
    if(result.completed){commitLedgerAmount();ledgerFilterAmountSlot='';backPickerPage();}
  }else if(action==='lf-amount-close'){
    ledgerFilterAmountSlot='';ledgerFilterAmountCalc=null;backPickerPage();
  }else if(action==='lf-amount-clear'){
    ledgerFilterDraft[ledgerFilterAmountSlot]='';ledgerFilterAmountSlot='';ledgerFilterAmountCalc=null;backPickerPage();
  }else if(action==='lf-option'){
    if(Array.isArray(ledgerFilterDraft[key]))ledgerFilterDraft[key]=value===''?[]:ledgerFilterDraft[key].includes(value)?ledgerFilterDraft[key].filter(v=>v!==value):[...ledgerFilterDraft[key],value];
    else ledgerFilterDraft[key]=value;
  }else if(action==='lf-date-open'){
    ledgerFilterAmountSlot='';ledgerFilterAmountCalc=null;
    ledgerFilterDateSlot=key;ledgerFilterCalendarMonth=(ledgerFilterDraft[key]||ledgerFilterDraft.dateFrom||month+'-01').slice(0,7);showPickerPage({trigger:el,kind:'filter-calendar',filterPage:true,title:key==='dateFrom'?'開始日期':'結束日期',render:ledgerFilterCalendar,onBack:()=>{ledgerFilterDateSlot='';refreshLedgerFilterPanel();}});
  }else if(action==='lf-date'){
    ledgerFilterDraft[ledgerFilterDateSlot]=value;
    if(ledgerFilterDraft.dateFrom&&ledgerFilterDraft.dateTo&&ledgerFilterDraft.dateFrom>ledgerFilterDraft.dateTo){if(ledgerFilterDateSlot==='dateFrom')ledgerFilterDraft.dateTo='';else ledgerFilterDraft.dateFrom='';}
    // Explicit date ranges can span months independently of the header period.
    ledgerFilterDraft.scope='all';ledgerFilterDateSlot='';backPickerPage();
  }else if(action==='lf-calendar'){
    const d=new Date(ledgerFilterCalendarMonth+'-01T00:00:00Z');d.setUTCMonth(d.getUTCMonth()+Number(value));if(d.getUTCFullYear()<1900||d.getUTCFullYear()>2100)return;ledgerFilterCalendarMonth=d.toISOString().slice(0,7);
  }else if(action==='lf-date-shortcut'){
    if(value==='clear'){ledgerFilterDraft.dateFrom='';ledgerFilterDraft.dateTo='';}
    else if(value==='today'){ledgerFilterDraft.dateFrom=TODAY;ledgerFilterDraft.dateTo=TODAY;ledgerFilterDraft.scope='all';}
    else{ledgerFilterDraft.dateFrom=month+'-01';ledgerFilterDraft.dateTo=new Date(Date.UTC(Number(month.slice(0,4)),Number(month.slice(5)),0)).toISOString().slice(0,10);ledgerFilterDraft.scope='month';}
    ledgerFilterDateSlot='';
  }
  $('#modal-error').hidden=true;refreshLedgerFilterPanel();
  if(returningPage&&!pickerStack.includes(returningPage))restorePickerFocus({...returningPage,changed:!['lf-amount-close'].includes(action)});

  if(['lf-option','lf-calendar','lf-date-shortcut'].includes(action))restorePickerFocus({trigger:el,triggerData:{...el.dataset}});
  if(action==='lf-amount-key'&&ledgerFilterAmountSlot){const button=[...document.querySelectorAll('[data-action="lf-amount-key"]')].find(b=>b.dataset.key===key);button?.focus?.({preventScroll:true});}
}
document.addEventListener('input',e=>{const key=e.target.dataset?.lfInput;if(!key||!ledgerFilterDraft)return;ledgerFilterDraft[key]=e.target.value.trim();updateLedgerFilterCount();});
