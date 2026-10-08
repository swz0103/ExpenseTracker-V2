/* Navigation, draft continuity, focused feedback and compact app interactions. */
let navigationBook=null,routeMemory=new Map(),navigationTrail=[],navigationCursor=-1,activeRouteKey='',navigationSerial=0;
let modalSession=null,overlayHistory=false,ignoredHistoryEvents=0,feedbackAction=null,draftTimer=null;
const waterfallSelections=new Map();
function routeKey(name=page,id=selectedAccount){return name==='account-detail'?name+':'+id:name;}
function routeSnapshot(){return {page,month,selectedAccount,filter,search,categoryFilter,dateFilter,ledgerAccountFilter,ledgerAdvanced:ledgerAdvanced?JSON.parse(JSON.stringify(ledgerAdvanced)):null,heatDay,receiptPage,receiptDate,dailyStart,flowIndex,budgetFocus,assetMode,assetIndex,assetPinnedIndex,allocationParent:allocationParent?{...allocationParent}:null,growthVisible,scroll:Number($('.shell')?.scrollTop)||0};}
function restoreRouteSnapshot(s){
 page=s.page;month=s.month;selectedAccount=s.selectedAccount||selectedAccount;filter=s.filter||'all';search=s.search||'';categoryFilter=s.categoryFilter||'';dateFilter=s.dateFilter||'';ledgerAccountFilter=s.ledgerAccountFilter||'';ledgerAdvanced=s.ledgerAdvanced?JSON.parse(JSON.stringify(s.ledgerAdvanced)):null;
 heatDay=s.heatDay||1;receiptPage=s.receiptPage||0;receiptDate=s.receiptDate||'';dailyStart=s.dailyStart??0;flowIndex=s.flowIndex??-1;budgetFocus=s.budgetFocus??-1;assetMode=s.assetMode||'assets';assetIndex=s.assetIndex??-1;assetPinnedIndex=s.assetPinnedIndex??-1;allocationParent=s.allocationParent||null;growthVisible=s.growthVisible!==false;
}
function rememberCurrentRoute(writeHistory=true){
 if(!activeRouteKey)return;
 const snapshot=routeSnapshot();if(activeRouteKey.startsWith('account-detail:'))snapshot.selectedAccount=activeRouteKey.slice(15);
 routeMemory.set(activeRouteKey,snapshot);
 if(navigationTrail[navigationCursor])navigationTrail[navigationCursor].view=snapshot;
 if(writeHistory&&!overlayHistory&&navigationTrail[navigationCursor])history.replaceState({hibi:true,...navigationTrail[navigationCursor]},'','#'+page);
}
function navigatePage(name,options={}){
 if(navigationBook!==state){navigationBook=state;routeMemory=new Map();navigationTrail=[];navigationCursor=-1;activeRouteKey='';}
 if(name==='cards'){selectedAccount=state.accounts.find(a=>a.kind==='card')?.id||selectedAccount;name='account-detail';}
 if(!pages.some(p=>p[0]===name)&&name!=='more')name='overview';
 rememberCurrentRoute();const key=routeKey(name),saved=routeMemory.get(key),base=options.context?{...routeSnapshot(),...options.context,page:name,scroll:0}:saved||{...routeSnapshot(),page:name,month:state.viewMonths?.[key]||TODAY.slice(0,7),filter:'all',search:'',categoryFilter:'',dateFilter:'',ledgerAccountFilter:'',ledgerAdvanced:null,scroll:0};
 if(options.context||!saved){base.selectedAccount=selectedAccount;if(name==='overview'&&!saved){base.heatDay=Number(TODAY.slice(8));base.receiptPage=0;base.receiptDate='';base.flowIndex=-1;}}
 const same=activeRouteKey===key;restoreRouteSnapshot(base);activeRouteKey=key;
 render();$('.shell').scrollTop=base.scroll||0;$('#main')?.focus?.({preventScroll:true});
 const entry={id:++navigationSerial,key,view:routeSnapshot()};
 if(options.replace||same){if(navigationCursor<0){navigationCursor=0;navigationTrail=[entry];}else navigationTrail[navigationCursor]=entry;history.replaceState({hibi:true,...entry},'','#'+name);}
 else{navigationTrail=navigationTrail.slice(0,navigationCursor+1);navigationTrail.push(entry);navigationCursor++;if(overlayHistory){history.replaceState({hibi:true,...entry},'','#'+name);overlayHistory=false;closeModalSurface();}else if(history.pushState)history.pushState({hibi:true,...entry},'','#'+name);else history.replaceState({hibi:true,...entry},'','#'+name);}
 routeMemory.set(key,entry.view);
}
function navigateBack(fallback='more',useHistory=true){
 if(pickerStack.length){backPickerPage();return;}
 if(modalSession?.active){dismissModal();return;}
 if(navigationCursor>0){rememberCurrentRoute();navigationCursor--;const entry=navigationTrail[navigationCursor];restoreRouteSnapshot(entry.view);activeRouteKey=entry.key;render();$('.shell').scrollTop=entry.view.scroll||0;if(useHistory&&history.back){ignoredHistoryEvents++;history.back();}return;}
 navigatePage(fallback,{replace:true});
}
function openLedgerContext(context={}){navigatePage('ledger',{context:{filter:'all',search:'',categoryFilter:'',dateFilter:'',ledgerAccountFilter:'',ledgerAdvanced:null,...context}});}
function changePageMonth(step){
 const d=new Date(month+'-01T00:00:00Z');d.setUTCMonth(d.getUTCMonth()+step);const next=d.toISOString().slice(0,7);if(next<'2026-01'||next>'2030-12')return;
 month=next;dateFilter='';if(ledgerAdvanced?.scope==='month'){ledgerAdvanced.dateFrom='';ledgerAdvanced.dateTo='';}flowIndex=-1;receiptPage=0;receiptDate='';
 state.viewMonths??={};state.viewMonths[routeKey()]=month;save();render();rememberCurrentRoute();
}
function startOverlay(){if(overlayHistory||!activeRouteKey)return;rememberCurrentRoute();if(history.pushState){history.pushState({hibi:true,overlay:true,...navigationTrail[navigationCursor]},'','#'+page);overlayHistory=true;}}
function finishOverlay(fromHistory=false){if(!overlayHistory)return;overlayHistory=false;if(!fromHistory&&history.back){ignoredHistoryEvents++;history.back();}}
function beginModalSession(){startOverlay();modalSession={active:true,key:null,initial:null};}
function closeModalSurface(){resetPickerPages();$('#modal').close();if(modalSession)modalSession.active=false;}
function dismissModal({fromHistory=false,saved=false}={}){if(!saved)storeCurrentDraft();else clearCurrentDraft();closeModalSurface();finishOverlay(fromHistory);}
window.addEventListener('popstate',event=>{
 if(ignoredHistoryEvents){ignoredHistoryEvents--;return;}
 if(pickerStack.length){overlayHistory=false;backPickerPage(true);if(modalSession?.active||pickerStack.length)startOverlay();return;}
 if(modalSession?.active){dismissModal({fromHistory:true});return;}
 const entry=event.state;if(!entry?.hibi||entry.overlay)return;
 rememberCurrentRoute(false);navigationCursor=navigationTrail.findIndex(item=>item.id===entry.id);if(navigationCursor<0){navigationTrail=[entry];navigationCursor=0;}
 const view=navigationTrail[navigationCursor]?.view||entry.view;restoreRouteSnapshot(view);activeRouteKey=entry.key;render();$('.shell').scrollTop=view.scroll||0;
});

function readModalFields(){const fields={};for(const el of Array.from($('#modal-form')?.elements||[]))if(el.name&&!el.disabled&&['INPUT','TEXTAREA'].includes(el.tagName))fields[el.name]=el.value;return fields;}
function restoreModalFields(fields){
 for(const [name,value] of Object.entries(fields||{})){
   const el=$('#f-'+name);if(!el||el.isConnected===false)continue;
   const trigger=document.querySelector(`[data-action="field-options"][data-name="${name}"]`);
   if(trigger?.dataset?.options){const option=JSON.parse(trigger.dataset.options).find(o=>o.value===value);if(!option)continue;setFieldChoice(name,value,option.label);}else el.value=value;
   if(name==='date'&&utilityValidDate(value)){$('#edit-date-label').textContent=composerDateText(value);editCalendarSelected=value;editCalendarMonth=value.slice(0,7);}
   if(['amount','opening','qty','price'].includes(name)){const label=$('#picker-label-'+name);if(label)updateAmountText(label,name==='price'?quoteNumber(value):money(Number(value)));if(name==='amount'&&$('#edit-calc-amount'))updateAmountText($('#edit-calc-amount'),money(Number(value)));}
 }
}
function configureDraft(key,{restore=true,record=false}={}){
 if(!modalSession)return;modalSession.key=key;modalSession.record=record;modalSession.initial=JSON.stringify(readModalFields());
 const draft=restore?state.formDrafts?.[key]:null;
 if(draft){restoreModalFields(draft.fields);if(draft.calculator){editCalcExpression=draft.calculator.expression;editCalcFresh=draft.calculator.fresh;editCalcDirty=draft.calculator.dirty;}modalSession.restored=true;}
 $('#modal-draft').hidden=!key;$('#modal-draft').textContent=draft?'草稿':'重填';
 $('#modal .modal-actions .secondary').textContent='暫存';
}
function storeCurrentDraft(){
 if(!modalSession?.active||!modalSession.key)return false;
 const fields=readModalFields(),changed=JSON.stringify(fields)!==modalSession.initial||modalSession.restored;
 if(!changed)return false;
 state.formDrafts??={};state.formDrafts[modalSession.key]={fields,record:modalSession.record?captureRecordDraft():null,calculator:modalSession.record?{expression:editCalcExpression,fresh:editCalcFresh,dirty:editCalcDirty}:null};save();$('#modal-draft').textContent='草稿';return true;
}
function clearCurrentDraft(){if(modalSession?.key&&state.formDrafts?.[modalSession.key]){delete state.formDrafts[modalSession.key];save();}}
function resumeEntry(){const draft=state.formDrafts?.entry?.record;openRecordComposer(draft?.type||'expense',Boolean(draft?.cardOnly),Boolean(draft?.cardPay),draft||null);}
function discardCurrentDraft(){
 if(!modalSession?.key)return;
 showPickerPage({kind:'confirmation',title:'重新填寫？',render:()=>'<div class="compact-confirmation"><p>目前草稿將清除。</p><button type="button" data-action="draft-discard">清除草稿</button></div>'});
}
function resetCurrentDraft(){const original=modalSession?.initial,key=modalSession?.key;clearCurrentDraft();backPickerPage();$('#modal-form').reset();restoreModalFields(JSON.parse(original||'{}'));editCalcExpression=String($('#f-amount')?.value||0);editCalcDirty=false;editCalcFresh=true;if(modalSession){modalSession.restored=false;modalSession.initial=JSON.stringify(readModalFields());}$('#modal-draft').textContent='重填';if(key==='entry'){openRecordComposer(recordComposer?.type||'expense',false,false);}}
document.addEventListener('input',event=>{if(event.target.closest?.('#modal-form')&&modalSession?.key){clearTimeout(draftTimer);draftTimer=setTimeout(storeCurrentDraft,250);}});
window.addEventListener('pagehide',storeCurrentDraft);
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden')storeCurrentDraft();});

function appFieldError(field,message){const error=new Error(message);error.field=field;return error;}
function presentFormError(error){
 const message=error.message||'請確認輸入內容。',name=error.field||(/金額/.test(message)?'amount':/股數/.test(message)?'qty':/日期/.test(message)?'date':/轉入/.test(message)?'to':/帳戶/.test(message)?'account':/分類/.test(message)?'category':/名稱/.test(message)?'name':'');
 $('#modal-error').textContent=message;$('#modal-error').hidden=false;
 const field=name&&$('#f-'+name),control=field?.type==='hidden'?(field.closest?.('.edit-picker,.currency-control,.investment-quantity')?.querySelector?.('button')||document.querySelector(name==='date'?'[data-action="field-date"]':`[data-name="${name}"]`)):field;
 if(control){control.setAttribute?.('aria-invalid','true');control.setAttribute?.('aria-describedby','modal-error');control.classList?.add('app-field-invalid');control.focus?.({preventScroll:true});control.scrollIntoView?.({block:'nearest',behavior:'smooth'});}
}
function showFeedback(message,label='',action=null){
 const el=$('#toast');feedbackAction=action;el.innerHTML=`<span>${esc(message)}</span>${label?`<button type="button" data-action="feedback-action">${esc(label)}</button>`:''}`;el.classList.add('visible');clearTimeout(toast.timer);toast.timer=setTimeout(()=>{el.classList.remove('visible');feedbackAction=null;},label?10000:3300);
}
function recordSaved(tx,message='已記下這一筆。'){
 rememberCurrentRoute();render();showFeedback(message,'查看',()=>{openLedgerContext({month:tx.date.slice(0,7),dateFilter:tx.date});requestAnimationFrame(()=>{const row=document.querySelector(`[data-action="tx-detail"][data-id="${tx.id}"]`);row?.scrollIntoView?.({block:'center'});row?.classList?.add('record-saved');});txDetail(tx.id);});
}
function removeRecordWithUndo(id){
 const index=state.tx.findIndex(t=>t.id===id),tx=state.tx[index];if(!tx)return;
 commitLedgerTransactions(state.tx.filter(row=>row.id!==id));state.undoDelete={record:tx,index};if(state.formDrafts)delete state.formDrafts['edit:'+id];save();render();showFeedback('紀錄已刪除。','復原',undoDeletedRecord);
}
function undoDeletedRecord(){
 const undo=state.undoDelete;if(!undo)return;
 if(state.tx.some(t=>t.id===undo.record.id)){delete state.undoDelete;save();return;}
 const next=[...state.tx];next.splice(Math.min(undo.index,next.length),0,undo.record);
 try{commitLedgerTransactions(next);delete state.undoDelete;save();render();showFeedback('紀錄已復原。','查看',()=>txDetail(undo.record.id));}catch(error){showFeedback(error.message);}
}
function updateViewport(){const viewport=window.visualViewport;if(!viewport)return;document.documentElement?.style.setProperty('--visual-height',viewport.height+'px');document.documentElement?.style.setProperty('--visual-top',viewport.offsetTop+'px');}
window.visualViewport?.addEventListener('resize',updateViewport);window.visualViewport?.addEventListener('scroll',updateViewport);updateViewport();

let dailySwipe=null,suppressReceiptClick=false;
document.addEventListener('pointerdown',event=>{const el=event.target.closest?.('.daily-receipts');if(el&&event.isPrimary!==false)dailySwipe={x:event.clientX,y:event.clientY,id:event.pointerId};});
document.addEventListener('pointerup',event=>{const gesture=dailySwipe;dailySwipe=null;if(!gesture||gesture.id!==event.pointerId)return;const dx=event.clientX-gesture.x,dy=event.clientY-gesture.y;if(Math.abs(dx)>40&&Math.abs(dx)>Math.abs(dy)*1.5){suppressReceiptClick=true;setDailyReceiptPage(dailyReceiptWindow().page+(dx<0?1:-1));setTimeout(()=>suppressReceiptClick=false,350);}});
document.addEventListener('pointercancel',()=>dailySwipe=null);
document.addEventListener('click',event=>{if(suppressReceiptClick&&event.target.closest?.('.daily-receipts')){event.preventDefault();event.stopImmediatePropagation();suppressReceiptClick=false;}},true);
document.addEventListener('keydown',event=>{if(event.target.matches?.('.daily-receipts')&&['ArrowLeft','ArrowRight','Home','End'].includes(event.key)){event.preventDefault();const view=dailyReceiptWindow();setDailyReceiptPage(event.key==='Home'?0:event.key==='End'?view.pages-1:view.page+(event.key==='ArrowRight'?1:-1));$('.daily-receipts')?.focus?.({preventScroll:true});}});
function filterGroups(){const f=currentLedgerFilters();return [
 ['keyword',search?'搜尋 '+search:''],['type',f.types.map(t=>ledgerTypeNames[t]).join('／')],['account',f.accounts.length===1?account(f.accounts[0])?.name:f.accounts.length?f.accounts.length+' 個帳戶':''],['date',f.dateFrom||f.dateTo?f.dateFrom===f.dateTo?f.dateFrom:(f.dateFrom||'不限')+'～'+(f.dateTo||'不限'):''],['category',f.categories.join('、')],['amount',f.min!==''||f.max!==''?(f.min||'0')+'～'+(f.max||'不限'):''],['source',f.sources.length||f.references.length?'指定來源':''],['account-detail',f.direction!=='any'||f.accountKinds.length?'指定帳戶方向／類型':''],['more',f.status!=='active'||f.cardAction!=='all'||f.sort!=='newest'?'狀態／排序':''],['scope',f.scope==='all'?'跨月份':'']].filter(([,label])=>label);}
function ledgerAppliedFilters(){return `<div class="ledger-applied-filters" aria-label="已套用條件">${filterGroups().map(([key,label])=>`<span class="applied-filter"><button data-action="filter-edit" data-key="${key}">${esc(label)}</button><button data-action="filter-remove" data-key="${key}" aria-label="移除${esc(label)}">×</button></span>`).join('')}</div>`;}
function removeFilterGroup(key){const f=currentLedgerFilters(),defaults=defaultLedgerFilters(),keys={type:['types'],account:['accounts'],date:['dateFrom','dateTo'],category:['categories'],amount:['min','max'],source:['sources','references'],'account-detail':['direction','accountKinds'],more:['status','cardAction','sort'],scope:['scope']}[key]||[];for(const field of keys)f[field]=defaults[field];if(key==='keyword')search='';ledgerAdvanced=f;filter='all';categoryFilter='';dateFilter='';ledgerAccountFilter='';render();}
function editFilterGroup(key){if(key==='keyword'){ledgerSearch();return;}openLedgerFilters();if(['type','account','date','scope'].includes(key)){document.querySelector('#lf-primary-'+key)?.scrollIntoView?.({block:'center'});return;}if(ledgerFilterPages[key])ledgerFilterAction({dataset:{action:'lf-section',key}});}
function experienceAction(el){
 const {action,key,id}=el.dataset;
 if(action==='app-back')navigateBack(el.dataset.fallback||'more');
 else if(action==='draft-reset')discardCurrentDraft();
 else if(action==='draft-discard')resetCurrentDraft();
 else if(action==='feedback-action'){const fn=feedbackAction;feedbackAction=null;$('#toast').classList.remove('visible');fn?.();}
 else if(action==='filter-remove')removeFilterGroup(key);
 else if(action==='filter-edit')editFilterGroup(key);
 else if(action==='undo-delete')undoDeletedRecord();
 else if(action==='chart-scale')setChartScale(el.dataset.chart);
 else if(action==='quote-edit')openQuoteEditor(id);
 else if(action==='quotes-manage')openQuotesManager(el);
 else if(action==='quotes-import')$('#quotes-file')?.click();
 else return false;
 return true;
}

function chartScale(chart){return state.chartScales?.[chart]==='linear'?'linear':'readable';}
function chartScaleControl(chart){return `<button class="chart-scale-control" data-action="chart-scale" data-chart="${chart}" aria-label="圖表目前為${chartScale(chart)==='linear'?'等比例':'小額放大'}，切換顯示尺度">${chartScale(chart)==='linear'?'等比例':'小額放大'}</button>`;}
function setChartScale(chart){if(!['waterfall','investment'].includes(chart))return;state.chartScales??={};state.chartScales[chart]=chartScale(chart)==='linear'?'readable':'linear';const top=$('.shell').scrollTop;save();render();$('.shell').scrollTop=top;}
function quoteNumber(value){return Number(value).toLocaleString('zh-TW',{minimumFractionDigits:2,maximumFractionDigits:2});}
function holdingPreviousClose(h){if(h.quoteSource==='import')return Number.isFinite(h.previousClose)?h.previousClose:null;if(h.quoteSource==='manual'||h.quoteSource==='cost')return null;return DEMO_PREVIOUS_CLOSE[h.id];}
function investmentChangeItems(){const available=state.holdings.filter(h=>h.qty>0&&Number.isFinite(holdingPreviousClose(h))).map(h=>({...h,quoteDay:h.quoteDate||TODAY,change:h.qty*(h.price-holdingPreviousClose(h))})),date=available.map(h=>h.quoteDay).sort().at(-1)||'';return {date,items:available.filter(h=>h.quoteDay===date)};}
function quoteDateNow(){return new Date().toLocaleDateString('sv-SE',{timeZone:'Asia/Taipei'});}
function quoteStatus(h){return `${h.quoteSource==='import'?'匯入收盤':h.quoteSource==='manual'?'手動價格':h.quoteSource==='cost'?'成本估值':'示意行情'}${h.quoteDate?' · '+h.quoteDate:''}`;}
function portfolioQuoteStatus(){const sources=new Set(state.holdings.map(h=>h.quoteSource||'demo'));return sources.size>1?'混合價格':sources.has('import')?'匯入收盤':sources.has('manual')?'手動價格':sources.has('cost')?'成本估值':'示意行情';}
function openQuotesManager(trigger){showPickerPage({kind:'quotes',title:'參考價格',trigger,render:()=>`<div class="quotes-toolbar"><button type="button" data-action="quotes-import">匯入收盤價</button><a href="https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL" target="_blank" rel="noopener noreferrer">證交所資料</a><input id="quotes-file" type="file" accept=".json,application/json" hidden></div>${quoteRequestMessage?`<p class="quotes-status" role="status">${esc(quoteRequestMessage)}</p>`:''}<div class="quotes-list">${state.holdings.map(h=>`<button data-action="quote-edit" data-id="${esc(h.id)}"><span><strong>${esc(h.id+' '+h.name)}</strong><small>${esc(quoteStatus(h))}</small></span><b>${quoteNumber(h.price)}</b></button>`).join('')}</div>`});}
function openQuoteEditor(id){const h=state.holdings.find(row=>row.id===id);if(!h)return;
 utilityModal('更新 '+h.id+' 價格',`<div class="quote-edit-head"><strong>${esc(h.name)}</strong><span>${esc(quoteStatus(h))}</span></div><div class="utility-amount"><span>參考價格</span>${currencyControl('price',h.price,.01,false,'neutral',2)}</div>${editDatePicker(h.quoteDate||quoteDateNow(),'2026-01','2030-12')}`,'儲存價格',data=>{
 const price=Number(data.get('price')),date=String(data.get('date')||'');if(!Number.isFinite(price)||price<=0||price>100000000||Math.abs(price*100-Math.round(price*100))>1e-6)throw appFieldError('price','價格需大於零，最多保留兩位小數。');if(!utilityValidDate(date)||date>quoteDateNow()||date<'2026-01-01')throw appFieldError('date','請選擇有效且不晚於今天的價格日期。');
 Object.assign(h,{price,quoteDate:date,quoteSource:'manual'});delete h.previousClose;save();render();showFeedback('價格已更新。');
 });
}
let quoteRequestMessage='';
function normalizedQuoteDate(value){const text=String(value||'').replace(/\D/g,'');if(text.length===7)return (Number(text.slice(0,3))+1911)+'-'+text.slice(3,5)+'-'+text.slice(5,7);if(text.length===8)return text.slice(0,4)+'-'+text.slice(4,6)+'-'+text.slice(6,8);return '';}
function officialQuoteUpdates(rows,holdings=state.holdings){
 if(!Array.isArray(rows))throw Error('行情格式不正確。');const indexed=new Map(rows.map(row=>[String(row.Code),row])),updates=[];
 for(const holding of holdings){const row=indexed.get(holding.id);if(!row)continue;const price=Number(String(row.ClosingPrice).replaceAll(',','')),change=Number(String(row.Change).replaceAll(',','')),date=normalizedQuoteDate(row.Date);if(!Number.isFinite(price)||price<=0||price>100000000||!utilityValidDate(date)||date>quoteDateNow()||date<(holding.quoteDate||''))continue;updates.push({id:holding.id,price,quoteDate:date,quoteSource:'import',previousClose:Number.isFinite(change)&&price-change>0?price-change:null});}
 return updates;
}
function applyQuoteImport(rows){const updates=officialQuoteUpdates(rows);if(!updates.length)throw Error('沒有符合持股的有效新價格。');for(const update of updates)Object.assign(state.holdings.find(row=>row.id===update.id),update);save();render();return updates;}
document.addEventListener('change',async event=>{if(event.target.id!=='quotes-file')return;const file=event.target.files?.[0];if(!file)return;try{if(file.size>5000000)throw Error('檔案需小於 5 MB。');const updates=applyQuoteImport(JSON.parse(await file.text()));quoteRequestMessage=`已更新 ${updates.length} 檔 · ${updates.map(h=>h.quoteDate).sort().at(-1)}`;}catch(error){quoteRequestMessage=error instanceof SyntaxError?'請選擇證交所 JSON 行情檔案。':error.message||'匯入失敗，原價格已保留。';}if(pickerCurrent()?.kind==='quotes')renderPickerPage();else showFeedback(quoteRequestMessage);});
