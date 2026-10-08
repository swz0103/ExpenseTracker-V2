/* Category administration and investment records share the app's compact forms. */
const CATEGORY_ICONS=['home','food','travel','bag','recurring','other','income','dividend'];
const CATEGORY_COLORS=['#4c7055','#925a35','#406f83','#765389','#80652c','#975369'];
function categoryCatalog(){
  if(!Array.isArray(state.categorySettings))state.categorySettings=[...categories.map((c,i)=>({...c,icon:c.icon==='ledger'?'other':c.icon,color:ledgerIconColors[c.name]||CATEGORY_COLORS[0],id:'expense-'+i,type:'expense',active:true})),...['薪資收入','股息收入','其他收入'].map((name,i)=>({id:'income-'+i,type:'income',name,icon:i===1?'dividend':'income',color:'#4c7055',active:true,locked:i===1}))];
  return state.categorySettings;
}
function managedCategories(type,includeInactive=false){return categoryCatalog().filter(c=>c.type===type&&(includeInactive||c.active!==false));}
function categoryNameOptions(type){return managedCategories(type).filter(c=>!c.locked).map(c=>c.name);}
function categoryByName(name,type){return categoryCatalog().find(c=>c.name===name&&(!type||c.type===type));}
function categorySymbol(c){return `<svg class="icon journal-icon" viewBox="0 0 24 24" aria-hidden="true">${journalGlyphs[c.icon]||journalGlyphs.other}</svg>`;}
function openCategoryEditor(id='',type='expense'){
  const current=categoryCatalog().find(c=>c.id===id),kind=current?.type||(['expense','income'].includes(type)?type:'expense');
  const selectedIcon=current?.icon||'other',selectedColor=current?.color||CATEGORY_COLORS[0];
  utilityModal(current?'編輯分類':'新增'+(kind==='income'?'收入':'支出')+'分類',`${field('name','分類名稱',input('name','text',current?.name||'','required maxlength="12" autocomplete="off"'+(current?.locked?' readonly':'')))}<fieldset class="category-appearance"><legend>圖示</legend><div class="category-icon-options">${CATEGORY_ICONS.map(key=>`<button type="button" data-action="category-style" data-name="icon" data-value="${key}" aria-label="${({home:'居家',food:'餐飲',travel:'交通',bag:'購物',recurring:'定期',other:'其他',income:'收入',dividend:'股息'})[key]}" aria-pressed="${key===selectedIcon}" class="${key===selectedIcon?'selected':''}">${categorySymbol({icon:key})}</button>`).join('')}</div>${input('icon','hidden',selectedIcon)}</fieldset><fieldset class="category-appearance"><legend>顏色</legend><div class="category-color-options">${CATEGORY_COLORS.map((color,i)=>`<button type="button" data-action="category-style" data-name="color" data-value="${color}" aria-label="${['綠色','棕色','藍色','紫色','金色','莓紅色'][i]}" aria-pressed="${color===selectedColor}" class="${color===selectedColor?'selected':''}" style="--category:${color}"><span></span></button>`).join('')}</div>${input('color','hidden',selectedColor)}</fieldset>${current&&!current.locked?`<button type="button" class="category-status-button" data-action="category-status" data-id="${esc(id)}">${current.active===false?'重新啟用':'停用分類'}</button>`:''}`,'儲存分類',data=>{
    const name=String(data.get('name')||'').trim(),glyph=data.get('icon'),color=data.get('color');
    if(!name||name.length>12)throw Error('分類名稱請填寫 1 到 12 個字。');
    if(!CATEGORY_ICONS.includes(glyph)||!CATEGORY_COLORS.includes(color))throw Error('請選擇圖示與顏色。');
    if(current?.locked&&name!==current.name)throw Error('股息分類名稱由投資紀錄使用。');
    if(categoryCatalog().some(c=>c.id!==id&&c.type===kind&&c.name===name))throw Error('已有同名分類，請換個名稱。');
    if(current){
      const old=current.name;
      if(old!==name){for(const t of state.tx)if(t.category===old&&(kind==='income'?t.type==='income':['expense','refund'].includes(t.type))){t.category=name;if(t.note===old)t.note=name;}
        if(kind==='expense'){for(const r of state.recurring)if(r.category===old)r.category=name;for(const b of state.budgets)if(b.category===old)b.category=name;}
      }
      Object.assign(current,{name,icon:glyph,color});
    }else categoryCatalog().push({id:uid(),type:kind,name,icon:glyph,color,active:true});
    save();render();toast('分類已儲存。');
  });
}
function categoryStatus(id){
 const c=categoryCatalog().find(row=>row.id===id);if(!c||c.locked)return;
 if(c.active===false){c.active=true;save();render();$('#modal').close();return toast('分類已啟用。');}
 if(managedCategories(c.type).filter(row=>!row.locked).length<=1)return toast('至少保留一個可用分類。');
 utilityModal('停用'+c.name+'？','<p class="utility-reset-copy">既有紀錄、預算與定期交易會保留；新增記帳不再顯示此分類。</p>','確認停用',()=>{c.active=false;save();render();toast('分類已停用。');});
}
function categoryStyleChoice(el){
 const {name,value}=el.dataset;if(!['icon','color'].includes(name))return;
 if(!(name==='icon'?CATEGORY_ICONS:CATEGORY_COLORS).includes(value))return;
 $('#f-'+name).value=value;
 for(const item of document.querySelectorAll('[data-action="category-style"][data-name="'+name+'"]')){const selected=item.dataset.value===value;item.classList.toggle('selected',selected);item.setAttribute('aria-pressed',String(selected));}
}

function transactionIncoming(t){return ['income','refund'].includes(t.type)||t.type==='investment'&&t.investment?.side==='sell';}
function investmentPositions(transactions=state.tx,holdings=state.holdings,through='9999-12-31'){
 const positions=new Map(holdings.map(h=>[h.id,{...h,qty:h.openingQty??h.qty,cost:h.openingCost??h.cost,realized:0}]));
 const rows=transactions.map((t,index)=>({t,index})).filter(({t})=>t.type==='investment'&&!t.reversed&&t.date<=through).sort((a,b)=>a.t.date.localeCompare(b.t.date)||a.index-b.index);
 for(const {t} of rows){
   const trade=t.investment,h=positions.get(trade?.holding),qty=trade?.qty;
   if(!h||!Number.isSafeInteger(qty)||qty<1||!['buy','sell'].includes(trade.side)||!Number.isSafeInteger(t.amount)||t.amount<1)throw Error('投資紀錄的標的、股數或金額無效。');
   if(trade.side==='buy'){h.qty+=qty;h.cost+=t.amount;}else{
     if(qty>h.qty)throw Error(`${h.id} 在 ${t.date} 的可賣股數不足，請先調整後續賣出紀錄。`);
     const remainingCost=qty===h.qty?0:Math.round(h.cost*(h.qty-qty)/h.qty*100)/100;h.realized+=t.amount-(h.cost-remainingCost);h.cost=remainingCost;h.qty-=qty;
   }
   if(!Number.isSafeInteger(h.qty)||!Number.isFinite(h.cost))throw Error('投資數值超出可用範圍。');
 }
 return [...positions.values()];
}
function commitLedgerTransactions(next){
 const positions=investmentPositions(next);
 for(const h of state.holdings){const position=positions.find(row=>row.id===h.id);h.openingQty??=h.qty;h.openingCost??=h.cost;h.qty=position.qty;h.cost=position.cost;}
 state.tx=next;
}
function investmentSideTabs(side){return `<div class="investment-side-tabs" role="group" aria-label="投資動作">${[['buy','買入'],['sell','賣出'],['dividend','股息']].map(([key,label])=>`<button type="button" data-action="investment-side" data-side="${key}" aria-pressed="${side===key}" class="${side===key?'selected':''}">${label}</button>`).join('')}</div>`;}
function openInvestmentComposer(draft=null,editId=''){
 const original=editId?state.tx.find(t=>t.id===editId):null;
 const side=draft?.tradeSide||original?.investment?.side||(original?.dividend?'dividend':'buy'),incoming=side!=='buy',accounts=state.accounts.filter(a=>a.kind!=='card');
 if(!accounts.length)return toast('請先建立現金或銀行帳戶。');
 const selected=accounts.some(a=>a.id===draft?.account)?draft.account:accounts[0].id,date=draft?.date||composerDate(),amount=draft?.amount??0,note=draft?.note||'',holdingId=state.holdings.some(h=>h.id===draft?.holding)?draft.holding:state.holdings[0]?.id||'',qty=draft?.qty??0;
 recordComposer={type:'investment',tradeSide:side,account:selected,date,amount,note,holding:holdingId,qty,editId};
 editCalcExpression=draft?.expression??String(amount);editCalcFresh=draft?.fresh??true;editCalcDirty=draft?.dirty??false;
 const label={buy:'買入扣款',sell:'賣出入帳',dividend:'股息入帳'}[side];
 const quantity=side==='dividend'?'':`<div class="investment-quantity"><span>股數</span><input type="hidden" id="f-qty" name="qty" value="${esc(qty)}"><button type="button" data-action="field-calc" data-name="qty" data-unit="股" data-title="輸入股數" data-tone="neutral" data-min="1" aria-label="用計算機輸入股數"><strong id="picker-label-qty">${money(qty)}</strong><span>股</span>${calcIcon('calculator')}</button></div>`;
 const body=`<div class="record-compose-content investment-compose">${editId?'':recordTypeTabs('investment')}${editId?`<div class="investment-edit-kind">${label}</div>`:investmentSideTabs(side)}${input('tradeSide','hidden',side)}<section class="compose-stage" aria-label="${label}金額">${entryCalculator(amount,incoming,false)}${composerDatePicker(date)}</section><div class="investment-holding-field">${editPicker('holding','投資標的',state.holdings.map(h=>({value:h.id,label:h.id+' '+h.name})),holdingId)}${side==='buy'?'<button type="button" data-action="investment-new-holding" aria-label="新增投資標的">'+icon('plus')+'</button>':''}</div><div class="investment-settlement"><div class="compose-details">${editPicker('account',incoming?'收款帳戶':'扣款帳戶',accounts.map(a=>({value:a.id,label:a.name})),selected,'compose')}</div>${quantity}</div><div class="compose-note"><label class="edit-note-label" for="f-note">${icon('note')}<span>備註</span></label><textarea id="f-note" name="note" class="edit-note" rows="2" maxlength="500">${esc(note)}</textarea></div></div>`;
 openModal(editId?'編輯投資':'新增投資',body,editId?'儲存修改':'記下'+{buy:'買入',sell:'賣出',dividend:'股息'}[side],data=>{
   if(editCalcDirty)data.set('amount',String(calculateEntryExpression(editCalcExpression)));
   const amount=getAmount(data),a=account(data.get('account')),h=state.holdings.find(row=>row.id===data.get('holding')),date=String(data.get('date')||''),note=String(data.get('note')||'').trim();
   if(!a||a.kind==='card'||!h)throw Error('請選擇投資標的與有效的'+(incoming?'收款帳戶':'扣款帳戶')+'。');
   if(!utilityValidDate(date)||date<'2026-01-01'||date>'2030-12-31')throw Error('請選擇有效的入帳日期。');
   const tx={id:editId||uid(),date,amount,account:a.id,note:note||h.id+' '+h.name+'・'+{buy:'買入',sell:'賣出',dividend:'股息'}[side],type:side==='dividend'?'income':'investment',category:side==='dividend'?'股息收入':side==='buy'?'投資買入':'投資賣出'};
   if(side==='dividend')tx.dividend=h.id;else{const qty=Number(data.get('qty'));if(!Number.isSafeInteger(qty)||qty<1||qty>100000000)throw Error('股數需為 1 到 100,000,000 的整數。');tx.investment={holding:h.id,side,qty};}
   const next=editId?state.tx.map(row=>row.id===editId?tx:row):[...state.tx,tx];commitLedgerTransactions(next);
   if(side==='buy'&&h.price===0){h.price=amount/tx.investment.qty;h.quoteSource='cost';h.quoteDate=date;}
   save();recordSaved(tx,editId?'投資紀錄已更新。':'投資紀錄已儲存。');
 });
 $('#modal').classList.add('entry-edit','entry-compose');$('#modal').setAttribute('data-compose-type','investment');$('#modal').setAttribute('data-investment-side',side);configureDraft(editId?'edit:'+editId:'entry',{restore:editId?true:!draft,record:true});
}
function switchInvestmentSide(side){if(!recordComposer||recordComposer.type!=='investment'||recordComposer.editId||!['buy','sell','dividend'].includes(side))return;const draft=captureRecordDraft();draft.tradeSide=side;openInvestmentComposer(draft);}
function newInvestmentHolding(trigger){showPickerPage({kind:'new-holding',title:'新增投資標的',trigger,render:()=>`<div class="new-holding-form"><label for="holding-code">股票代號</label><input id="holding-code" maxlength="12" autocomplete="off" placeholder="例如：0050"><label for="holding-name">標的名稱</label><input id="holding-name" maxlength="30" autocomplete="off" placeholder="例如：元大台灣50"><p id="holding-error" role="alert"></p><button type="button" data-action="investment-save-holding">建立標的</button></div>`});}
function saveInvestmentHolding(){
 const id=String($('#holding-code').value||'').trim().toUpperCase(),name=String($('#holding-name').value||'').trim(),error=$('#holding-error');
 if(!/^[A-Z0-9][A-Z0-9.-]{0,11}$/.test(id)||!name||name.length>30){error.textContent='請填寫有效股票代號與名稱。';return;}
 if(state.holdings.some(h=>h.id===id)){error.textContent='這個標的已經存在。';return;}
 const draft=captureRecordDraft();state.holdings.push({id,name,qty:0,cost:0,price:0,dividend:0});save();backPickerPage();draft.holding=id;openInvestmentComposer(draft,recordComposer.editId);
}
