
/* Supporting forms reuse the existing detached calculators and pickers. */
function utilityModal(title,body,submit,handler){
  openModal(title,body,submit,handler,'');
  $('#modal').classList.add('utility-modal');if(/name="/.test(body))configureDraft('form:'+title);
}
function utilityAccountOptions(includeCards=true){return state.accounts.filter(a=>includeCards||a.kind!=='card').map(a=>({value:a.id,label:a.name}));}
function utilityCategoryOptions(){return managedCategories('expense').map(c=>({value:c.name,label:c.name}));}
function utilityAmount(label,value='',tone='neutral'){return `<div class="utility-amount" data-tone="${tone}"><span>${esc(label)}</span>${currencyControl('amount',value,1,false,tone)}</div>`;}
function utilityValidDate(value){return /^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value))&&new Date(value+'T12:00:00Z').toISOString().slice(0,10)===value;}
function confirmRecurring(id){
  const r=state.recurring.find(r=>r.id===id);if(!r||!r.active)return;
  if(recurringConfirmed(r))return toast('這一期已確認，不會重複入帳。');
  const expectedMonth=month;
  utilityModal('確認 '+r.name,`${utilityAmount('本期入帳金額',r.amount,'expense')}${editPicker('account','付款帳戶',utilityAccountOptions(),r.account,'compose')}${editDatePicker(dueDate(r),expectedMonth,expectedMonth)}${field('note','備註',input('note','text',r.name,'maxlength="80"'))}`,'確認入帳',data=>{
    const date=String(data.get('date')||''),accountId=data.get('account');
    if(!utilityValidDate(date)||!date.startsWith(expectedMonth))throw Error('請選擇這一期月份內的日期。');
    if(!account(accountId))throw Error('請選擇付款帳戶。');
    if(activeTx().some(t=>t.recurring===id&&t.date.startsWith(expectedMonth)))throw Error('這一期已經入帳。');
    state.tx.push({id:uid(),type:'expense',amount:getAmount(data),account:accountId,category:r.category,note:String(data.get('note')||'').trim()||r.name,date,recurring:id});
    save();render();toast('本期已入帳。');
  });
}
function editBudget(id){
  const b=state.budgets.find(b=>b.id===id);if(!b)return;
  utilityModal('調整'+b.category,`${utilityAmount('每月預算上限',b.limit)}<div class="budget-edit-context"><span>本月已用</span><strong>${nt(spent(b.category))}</strong></div>`,'儲存預算',data=>{b.limit=getAmount(data);save();render();toast('預算已更新。');});
}
function newRecurring(){
  const accounts=utilityAccountOptions(),selected=accounts.find(a=>a.value==='bank')?.value||accounts[0]?.value||'';
  utilityModal('新增定期交易',`${utilityAmount('每月預計金額','','expense')}${field('name','交易名稱',input('name','text','','required maxlength="40" placeholder="例如：健身房月費"'))}<div class="utility-picker-pair">${editPicker('account','付款帳戶',accounts,selected,'compose')}${editPicker('category','支出分類',utilityCategoryOptions(),managedCategories('expense')[0]?.name||'','compose')}</div>${editPicker('day','付款日期',Array.from({length:31},(_,i)=>({value:String(i+1),label:`每月 ${i+1} 日`})),'5')}`,'建立交易',data=>{
    const name=String(data.get('name')||'').trim(),day=Number(data.get('day')),accountId=data.get('account'),category=data.get('category');
    if(!name)throw Error('請填寫交易名稱。');
    if(!Number.isInteger(day)||day<1||day>31)throw Error('日期需為 1 到 31 日。');
    if(!account(accountId)||!managedCategories('expense').some(c=>c.name===category))throw Error('請選擇帳戶與分類。');
    state.recurring.push({id:uid(),name,amount:getAmount(data),day,account:accountId,category,active:true});
    save();render();toast('定期交易已建立。');
  });
}
function dividend(){if(!state.holdings.length)return toast('目前沒有可記錄股息的持股。');openInvestmentComposer({tradeSide:'dividend'});}
function holding(id){
  const h=state.holdings.find(h=>h.id===id);if(!h)return;
  const value=h.qty*h.price,dividends=h.dividend+activeTx().filter(t=>t.dividend===id&&t.type==='income').reduce((n,t)=>n+t.amount,0);
  utilityModal(h.id+' '+h.name,`<div class="holding-detail-summary"><span>持股市值</span>${currencyFigure(value)}<small class="${value<h.cost?'negative':'positive'}">未實現損益 ${utilitySigned(value-h.cost)}</small></div>${valuationBars(h.cost,value)}<div class="holding-quote-status">${esc(quoteStatus(h))}</div><dl class="holding-detail-facts"><div><dt>持有股數</dt><dd>${money(h.qty)} 股</dd></div><div><dt>參考股價</dt><dd><button class="quote-price-edit" data-action="quote-edit" data-id="${esc(h.id)}">${quoteNumber(h.price)} ${icon('edit')}</button></dd></div><div><dt>累計股息</dt><dd>${money(dividends)}</dd></div></dl>`,'完成',()=>{});
  $('#modal').classList.add('utility-holding');
}
function resetPreview(){
  utilityModal('重設演示資料？','<p class="utility-reset-copy">目前新增或修改的紀錄將被清除，帳本會恢復初始演示資料。</p>','確認重設',()=>{
    state=seed();ledgerAdvanced=null;ledgerAccountFilter='';month='2026-10';search='';filter='all';categoryFilter='';dateFilter='';
    save();render();toast('已恢復初始演示資料。');
  });
  $('#modal').classList.add('utility-reset');
}

function openRecurringManager(trigger){
 showPickerPage({kind:'recurring-settings',title:'管理固定項目',trigger,render:()=>`<div class="routine-settings">${state.recurring.map(r=>`<div class="routine-setting"><span><strong>${esc(r.name)}</strong><small>每月 ${r.day} 日 · ${nt(r.amount)}</small></span><button class="utility-toggle ${r.active?'on':''}" data-action="toggle-recurring" data-id="${esc(r.id)}" role="switch" aria-checked="${r.active}" aria-label="${r.active?'暫停':'啟用'}${esc(r.name)}"><i aria-hidden="true"></i></button></div>`).join('')||'<p class="utility-empty">尚未建立固定項目</p>'}</div>`});
}
