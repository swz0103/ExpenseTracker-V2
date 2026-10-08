/* Separate, fixed-size selection pages keep the parent form and its draft intact. */
let pickerStack=[],pickerCalc=null;
function pickerCurrent(){return pickerStack.at(-1);}
function renderPickerPage(){
  const current=pickerCurrent();if(!current)return;
  $('#picker-title').textContent=current.title;
  $('#picker-content').innerHTML=current.render();
  $('#picker-page').setAttribute('data-kind',current.kind||'options');
  $('#picker-page').setAttribute('data-tone',current.tone||'neutral');
  $('#picker-done').hidden=!current.done;
  $('#picker-done').textContent=current.doneLabel||'完成選擇';
}
function showPickerPage(page){
  page.triggerData=page.trigger?.dataset?{...page.trigger.dataset}:null;
  startOverlay();pickerStack.push(page);renderPickerPage();
  if(pickerStack.length===1)$('#picker-page').showModal();
  $('#picker-content').scrollTop=0;
}
function backPickerPage(fromHistory=false){
  const current=pickerStack.pop();if(!current)return;
  current.onBack?.();
  if(pickerStack.length)renderPickerPage();
  else{$('#picker-page').close();pickerCalc=null;}
  restorePickerFocus(current);if(!pickerStack.length&&!modalSession?.active)finishOverlay(fromHistory);
}
function restorePickerFocus(page){
  let trigger=page.trigger;
  if((!trigger||trigger.isConnected===false)&&page.triggerData){
    const keys=['action','name','key','id','value'].filter(key=>page.triggerData[key]!==undefined);
    trigger=[...document.querySelectorAll('[data-action]')].find(el=>keys.every(key=>el.dataset[key]===page.triggerData[key]));
  }
  trigger?.focus?.({preventScroll:true});
  if(page.changed&&trigger){trigger.classList?.add('field-updated');setTimeout(()=>trigger.classList?.remove('field-updated'),550);}
}
function resetPickerPages(){pickerStack=[];pickerCalc=null;$('#picker-page').close();}
function currencyControl(name,value='',minimum=1,editor=false,tone='neutral',precision=0){
  return `<div class="currency-control"><input type="hidden" id="f-${name}" name="${name}" value="${esc(value)}"><button type="button" class="currency-trigger" aria-label="用計算機輸入金額" data-action="field-calc" data-name="${name}" data-tone="${tone}" data-min="${minimum}" data-editor="${editor}" data-precision="${precision}"><small class="currency-unit">TWD</small><strong id="picker-label-${name}" class="${amountTextClass(value)}">${value===''?'0':precision?quoteNumber(value):money(Number(value))}</strong><span class="currency-calculator">${calcIcon('calculator')}</span></button></div>`;
}
function decodeOptionText(text){return String(text).replace(/&(?:amp|lt|gt|quot|#39);/g,s=>({'&amp;':'&','&lt;':'<','&gt;':'>','&quot;':'"','&#39;':"'"}[s]));}
function selectAsPicker(name,markup){
  const options=[...markup.matchAll(/<option\b([^>]*)>([\s\S]*?)<\/option>/g)].map(m=>({value:decodeOptionText(m[1].match(/\bvalue="([^"]*)"/)?.[1]??m[2]),label:decodeOptionText(m[2]),selected:/\bselected\b/.test(m[1])}));
  const selected=options.find(o=>o.selected)?.value??options[0]?.value??'';
  return editPicker(name,'',options,selected);
}
function choiceIcon(name,value){return ['account','from','to'].includes(name)?accountPickerIcon(account(value)):name==='category'?categorySymbol(categoryByName(value)||{icon:'other'}):name==='holding'?icon('investments'):name==='kind'?accountPickerIcon({kind:value}):icon('recurring');}
function fieldOptionsMarkup(options,name,selected){
  if(name==='day')return `<div class="picker-day-grid" role="group" aria-label="每月付款日期">${options.map(o=>`<button type="button" data-action="picker-choice" data-name="day" data-value="${esc(o.value)}" data-label="${esc(o.label)}" class="${o.value===selected?'selected':''}" aria-pressed="${o.value===selected}" aria-label="${esc(o.label)}">${esc(o.value)}</button>`).join('')}</div>`;
  return `<div class="edit-choices picker-choice-grid" data-kind="${name==='category'?'category':'account'}" role="group" aria-label="選項">${options.map(o=>`<button type="button" data-action="picker-choice" data-name="${name}" data-value="${esc(o.value)}" data-label="${esc(o.label)}" class="${o.value===selected?'selected':''}" aria-pressed="${o.value===selected}"><span class="edit-option-icon">${choiceIcon(name,o.value)}</span><span class="edit-option-copy"><strong>${esc(o.label)}</strong></span></button>`).join('')}</div>`;
}
function openFieldOptions(el){
  const name=el.dataset.name,options=JSON.parse(el.dataset.options||'[]');
  showPickerPage({kind:'options',title:el.dataset.title||({account:'選擇帳戶',from:'轉出帳戶',to:'轉入帳戶',category:'選擇分類',holding:'配息標的',kind:'帳戶類型'}[name]||'選擇項目'),trigger:el,options,name,render:()=>fieldOptionsMarkup(options,name,$('#f-'+name).value)});
}
function setFieldChoice(name,value,label){
  $('#f-'+name).value=value;$('#picker-label-'+name).textContent=label;
  const glyph=$('#picker-icon-'+name);if(glyph)glyph.innerHTML=choiceIcon(name,value);storeCurrentDraft();
}
function transferPickerPair(sourceName,sources,source,targets,target,pay=false,variant='tile'){
  return `<div class="transfer-picker-pair" aria-label="轉出帳戶至轉入帳戶">${editPicker(sourceName,'轉出帳戶',sources,source,variant)}<span class="transfer-direction" aria-hidden="true">${icon('arrow')}</span>${editPicker('to',pay?'繳入信用卡':'轉入帳戶',targets,target,variant)}</div>`;
}
function openFieldDate(el){
  const date=$('#f-date').value;
  editCalendarMonth=date.slice(0,7);editCalendarSelected=date;editCalendarMin=el.dataset.min||'2026-01';editCalendarMax=el.dataset.max||'2030-12';
  showPickerPage({kind:'calendar',title:'入帳日期',trigger:el,render:()=>`<div id="edit-calendar" class="edit-calendar">${editCalendar()}</div>`});
}
function calculatorPageMarkup(){
  let value;try{value=calculateEntryExpression(pickerCalc.calc.expression);}catch{}
  return `<div class="picker-calculator"><div class="picker-calculator-display"><div class="calculator-total"><small class="currency-unit">${esc(pickerCalc.unit||'TWD')}</small><strong id="picker-calc-value" class="${amountTextClass(value)}">${value===undefined?'…':Number.isInteger(value)?money(value):value}</strong></div><output id="picker-calc-expression" aria-label="計算式">${esc(pickerCalc.calc.expression)}</output><p id="picker-calc-error" class="edit-calc-message" role="status">${esc(pickerCalc.message||'')}</p></div>${calculatorKeypad('picker-calc-key')}</div>`;
}
function openFieldCalculator(el){
  const name=el.dataset.name||'amount',value=$('#f-'+name).value||'0';
  pickerCalc={name,precision:Number(el.dataset.precision||0),unit:el.dataset.unit||'TWD',minimum:Number(el.dataset.min??1),editor:el.dataset.editor==='true',calc:{expression:value,fresh:true,dirty:false},message:''};
  showPickerPage({kind:'calculator',tone:el.dataset.tone||'neutral',title:el.dataset.title||'輸入金額',trigger:el,render:calculatorPageMarkup});
}
function usePickerCalcKey(key){
  if(!pickerCalc)return;
  const result=stepAmountCalculator(pickerCalc.calc,key,pickerCalc.minimum,pickerCalc.precision);if(!result.changed)return;
  pickerCalc.message=result.message||'';
  if(result.completed){
    $('#f-'+pickerCalc.name).value=String(result.value);const label=$('#picker-label-'+pickerCalc.name);if(label)updateAmountText(label,pickerCalc.precision?quoteNumber(result.value):money(result.value));
    if(pickerCalc.editor){editCalcExpression=String(result.value);editCalcFresh=true;editCalcDirty=true;updateAmountText($('#edit-calc-amount'),money(result.value));}
    pickerCurrent().changed=true;backPickerPage();storeCurrentDraft();return;
  }
  // Keep the keypad DOM stable while updating its display.
  $('#picker-calc-expression').textContent=pickerCalc.calc.expression;
  updateAmountText($('#picker-calc-value'),result.value===undefined?'…':Number.isInteger(result.value)?money(result.value):String(result.value));
  $('#picker-calc-error').textContent=pickerCalc.message;
}
function pickerAction(el){
  const {action,name,value,label,key}=el.dataset;
  if(action==='picker-back'||action==='picker-done')backPickerPage();
  else if(action==='picker-choice'){
    const current=pickerCurrent();if(name!==current?.name||!current?.options?.some(o=>o.value===value))return;
    setFieldChoice(name,value,label);current.changed=true;backPickerPage();
  }else if(action==='picker-calc-key')usePickerCalcKey(key);
}
document.querySelector('#picker-page').addEventListener('cancel',e=>{e.preventDefault();backPickerPage();});
document.addEventListener('keydown',e=>{
  if(!['calculator','filter-calculator'].includes(pickerCurrent()?.kind))return;
  const key=({'Enter':'完成','Backspace':'⌫','Delete':'C','*':'×','/':'÷','-':'−'}[e.key]||e.key);
  if(['完成','⌫','C','×','÷','−','+','=','0','1','2','3','4','5','6','7','8','9','.'].includes(key)){e.preventDefault();if(pickerCurrent()?.kind==='filter-calculator')ledgerFilterAction({dataset:{action:'lf-amount-key',key}});else usePickerCalcKey(key);}
});
