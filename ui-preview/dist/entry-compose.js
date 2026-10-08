/* Shared calculator keypad and state transition for entries and range filters. */
function calculatorKeypad(action='edit-calc-key'){
  return `<div class="edit-calc-keys">${['C','⌫','÷','×','7','8','9','−','4','5','6','+','1','2','3','=','0','00','.','完成'].map(key=>`<button type="button" data-action="${action}" data-key="${key}" class="${['÷','×','−','+','='].includes(key)?'operator':key==='完成'?'done':['C','⌫'].includes(key)?'utility':''}" aria-label="${key==='⌫'?'刪除一位':key==='C'?'清除':({'+':'加','−':'減','×':'乘','÷':'除','=':'等於'}[key]||key)}">${key==='⌫'?calcIcon('backspace'):['÷','×','−','+','='].includes(key)?calcIcon(key):key}</button>`).join('')}</div>`;
}
function stepAmountCalculator(calc,key,minimum=1,precision=0){
  const allowed=['C','⌫','÷','×','−','+','=','完成','0','00','.','1','2','3','4','5','6','7','8','9'];
  if(!allowed.includes(key))return {changed:false};
  calc.dirty=true;let completed=false,message='';
  if(key==='C'){calc.expression='0';calc.fresh=true;}
  else if(key==='⌫'){calc.expression=calc.expression.slice(0,-1)||'0';calc.fresh=false;}
  else if(key==='='||key==='完成'){
    try{const value=calculateEntryExpression(calc.expression);if(key==='完成'&&(!Number.isSafeInteger(Math.round(value*10**precision))||Math.abs(value*10**precision-Math.round(value*10**precision))>1e-6||value<minimum||value>100000000))throw Error(precision?'價格需大於零，最多保留 '+precision+' 位小數。':'金額需為 '+minimum+' 到 100,000,000 之間的整數。');calc.expression=String(value);calc.fresh=true;completed=key==='完成';}
    catch(error){message=error.message;}
  }else if(['÷','×','−','+'].includes(key)){calc.fresh=false;calc.expression=calc.expression.replace(/[÷×−+]$/,'')+key;}
  else if(calc.fresh){calc.expression=key==='.'?'0.':key==='00'?'0':key;calc.fresh=false;}
  else{const number=calc.expression.split(/[÷×−+]/).at(-1);if(key==='.'&&number.includes('.'))return {changed:false};if(calc.expression==='0'&&key!=='.')calc.expression=key==='00'?'0':key;else calc.expression+=key;}
  calc.expression=calc.expression.slice(0,80);
  let value;try{value=calculateEntryExpression(calc.expression);}catch{}
  return {changed:true,value,message,completed};
}

let recordComposer=null;
function composerDate(){return month===TODAY.slice(0,7)?TODAY:month+'-01';}
function recordTypeTabs(type){return `<div class="record-type-tabs" role="group" aria-label="交易類型">${[['expense','支出'],['income','收入'],['transfer','轉帳'],['investment','投資']].map(([key,label])=>`<button type="button" data-action="compose-type" data-type="${key}" class="${type===key?'selected':''}" aria-pressed="${type===key}"><span class="record-type-glyph">${key==='investment'?icon('investments'):key==='expense'?icon('bag'):journalIcon({type:key})}</span><span>${label}</span></button>`).join('')}</div>`;}
function composerDateText(date){const value=new Date(date+'T00:00:00Z'),weekday='日一二三四五六'[value.getUTCDay()];return `${value.getUTCFullYear()} 年 ${value.getUTCMonth()+1} 月 ${value.getUTCDate()} 日 · 週${weekday}`;}
function composerDatePicker(date,min='2026-01',max='2030-12'){return `<div class="compose-date"><button type="button" class="compose-date-button" data-action="field-date" data-min="${min}" data-max="${max}"><span class="sr-only">入帳日期</span>${icon('calendar')}<strong id="edit-date-label">${composerDateText(date)}</strong></button>${input('date','hidden',date)}</div>`;}
function captureRecordDraft(){
  if(!recordComposer)return null;
  const draft={...recordComposer};
  for(const key of ['date','account','from','to','category','note','holding','qty','tradeSide']){const el=$('#f-'+key);if(el)draft[key]=el.value;}
  try{draft.amount=calculateEntryExpression(editCalcExpression);}catch{draft.amount=Number($('#f-amount')?.value)||0;}
  if(draft.type==='transfer')draft.account=draft.from;else draft.from=draft.account;
  draft.expression=editCalcExpression;draft.fresh=editCalcFresh;draft.dirty=editCalcDirty;
  return draft;
}
function switchRecordType(type){
  if(!['expense','income','transfer','investment'].includes(type)||!recordComposer||recordComposer.cardOnly||recordComposer.cardPay)return;
  const draft=captureRecordDraft();draft.from=draft.from||draft.account;draft.account=draft.account||draft.from;
  openRecordComposer(type,false,false,draft);
}
function openRecordComposer(type='expense',cardOnly=false,cardPay=false,draft=null){
  if(type==='investment')return openInvestmentComposer(draft);
  const isTransfer=type==='transfer',requestedCard=cardPay&&draft?.to?account(draft.to):null,card=requestedCard?.kind==='card'?requestedCard:state.accounts.find(a=>a.kind==='card');
  const sources=state.accounts.filter(a=>isTransfer||type==='income'?a.kind!=='card':cardOnly?a.kind==='card':true);
  if(!sources.length||isTransfer&&state.accounts.length<2||cardPay&&!card)return toast('請先建立可使用的帳戶。');
  const sourceId= sources.some(a=>a.id===(isTransfer?draft?.from||draft?.account:draft?.account))?(isTransfer?draft.from||draft.account:draft.account):sources[0].id;
  const destinations=state.accounts.filter(a=>cardPay?a.id===card.id:true);
  const target=destinations.some(a=>a.id===draft?.to&&a.id!==sourceId)?draft.to:destinations.find(a=>a.id!==sourceId)?.id;
  const categoryChoices=categoryNameOptions(type==='income'?'income':'expense');
  const category=categoryChoices.includes(draft?.category)?draft.category:categoryChoices[0]||'';
  const date=draft?.date||composerDate(),amount=draft?.amount??(cardPay?Math.max(0,-balance(card)):0),note=draft?.note??(cardPay?'信用卡繳款':'');
  recordComposer={...draft,type,cardOnly,cardPay,date,amount,note,category,account:sourceId,from:sourceId,to:target};
  editCalcExpression=draft?.expression??String(amount);editCalcFresh=draft?.fresh??true;editCalcDirty=draft?.dirty??false;
  editCalendarMonth=date.slice(0,7);editCalendarSelected=date;editCalendarMin='2026-01';editCalendarMax='2030-12';
  const accountOptions=sources.map(a=>({value:a.id,label:a.name}));
  const choices=isTransfer?transferPickerPair('from',accountOptions,sourceId,destinations.map(a=>({value:a.id,label:a.name})),target,cardPay,'compose'):`<div class="compose-choice-grid">${editPicker('account',type==='income'?'收款帳戶':cardOnly?'付款信用卡':'付款帳戶',accountOptions,sourceId,'compose')}${editPicker('category',type==='income'?'收入分類':'支出分類',categoryChoices.map(c=>({value:c,label:c})),category,'compose')}</div>`;
  const amountLabel=cardPay?'繳款金額':isTransfer?'轉帳金額':type==='income'?'收入金額':'支出金額';
  const modalTitle=cardPay?'信用卡繳款':cardOnly?'新增刷卡':isTransfer?'帳戶轉帳':type==='income'?'新增收入':'新增支出';
  const submitLabel=cardPay?'確認繳款':cardOnly?'記下刷卡':isTransfer?'確認轉帳':type==='income'?'記下收入':'記下支出';
  const body=`<div class="record-compose-content">${cardOnly||cardPay?'':recordTypeTabs(type)}<section class="compose-stage" aria-label="${amountLabel}">${entryCalculator(amount,type==='income',isTransfer)}${composerDatePicker(date)}</section><div class="compose-details">${choices}</div><div class="compose-note"><label class="edit-note-label" for="f-note">${icon('note')}<span>備註</span></label><textarea id="f-note" name="note" class="edit-note" rows="2" maxlength="500">${esc(note)}</textarea></div></div>`;
  openModal(modalTitle,body,submitLabel,data=>{
    if(editCalcDirty)data.set('amount',String(calculateEntryExpression(editCalcExpression)));
    const amount=getAmount(data),date=data.get('date'),source=data.get(isTransfer?'from':'account'),to=isTransfer?data.get('to'):null,category=isTransfer?'轉帳':data.get('category'),note=(data.get('note')||'').trim();
    if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isFinite(Date.parse(date))||new Date(date).toISOString().slice(0,10)!==date||date<'2026-01-01'||date>'2030-12-31')throw Error('請選擇有效的入帳日期。');
    if(!account(source)||!sources.some(a=>a.id===source))throw Error('請選擇有效的使用帳戶。');
    if(isTransfer&&(!account(to)||!destinations.some(a=>a.id===to)))throw Error('請選擇有效的轉入帳戶。');
    if(isTransfer&&source===to)throw Error('轉出與轉入帳戶需要不同。');
    if(!isTransfer&&!categoryChoices.includes(category))throw Error('請選擇有效分類。');
    const tx={id:uid(),type,amount,account:source,category,date,note:note||category};if(isTransfer)tx.to=to;
    state.tx.push(tx);save();recordSaved(tx,cardPay?'已記錄繳款。':isTransfer?'轉帳完成。':'已記下這一筆。');
  },'NEW RECORD');
  $('#modal').classList.add('entry-edit','entry-compose');
  $('#modal').setAttribute('data-compose-type',type);configureDraft(cardOnly?'entry-card':cardPay?'entry-card-pay':'entry',{restore:!draft,record:true});
}
