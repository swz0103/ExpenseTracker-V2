/* Original rounded, two-tone glyphs; shared across the app. */
const glyphs={
calendar:'<rect x="4" y="5" width="16" height="16" rx="3"/><path d="M8 3v4M16 3v4M4 10h16M8 14h2M14 14h2M8 17h2"/>',
note:'<path d="M14 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8M9 15l1-4 8-8 3 3-8 8-4 1Z"/>',
edit:'<path d="m14 5 5 5M4 20l5-1L20 8a2.1 2.1 0 0 0 0-3l-1-1a2.1 2.1 0 0 0-3 0L5 15l-1 5Z"/>',

filter:'<path d="M4 6h16M7 12h10M10 18h4"/><circle cx="8" cy="6" r="2" fill="var(--paper)"/><circle cx="15" cy="12" r="2" fill="var(--paper)"/>',
overview:'<path class="icon-tint" d="M4 9.5 12 3l8 6.5V20H4z"/><path d="m3.5 10 6.9-5.8a2.5 2.5 0 0 1 3.2 0l6.9 5.8M5 9v9a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V9M9 20v-6a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v6"/>',
ledger:'<rect class="icon-tint" x="5" y="4" width="14" height="17" rx="3"/><rect x="5" y="3" width="14" height="18" rx="3"/><path d="M9 8h6M9 12h6M9 16h3M3 7h3M3 12h3M3 17h3"/>',
accounts:'<rect class="icon-tint" x="3" y="6" width="18" height="14" rx="4"/><path d="M18 6V5a2 2 0 0 0-2-2L6 5a4 4 0 0 0-3 4v7a4 4 0 0 0 4 4h10a4 4 0 0 0 4-4V10a4 4 0 0 0-4-4H6"/><path d="M21 10h-5a2 2 0 0 0 0 4h5"/><circle cx="16" cy="12" r=".7" class="icon-solid"/>',
cards:'<rect class="icon-tint" x="3" y="5" width="18" height="14" rx="4"/><rect x="3" y="5" width="18" height="14" rx="4"/><path d="M3 10h18M7 15h3M14 15h3"/>',
investments:'<rect class="icon-tint" x="4" y="4" width="16" height="16" rx="5"/><path d="M4 15v3a2 2 0 0 0 2 2h12M5 12l5-5 4 4 6-7M16 4h4v4"/>',
budgets:'<path class="icon-tint" d="M11 3a9 9 0 1 0 9 10h-9z"/><path d="M10 3a9 9 0 1 0 11 11H10V3z"/><path d="M14 2v8h8a9 9 0 0 0-8-8z"/>',
reports:'<path class="icon-tint" d="M4 4h16v16H4z"/><path d="M5 20V4m0 16h15M9 16v-4m4 4V7m4 9v-6"/>',
categories:'<path class="icon-tint" d="M5 4h6v6H5zm8 0h6v6h-6zM5 12h6v6H5zm8 0h6v6h-6z"/><rect x="4" y="3" width="7" height="7" rx="2"/><rect x="13" y="3" width="7" height="7" rx="2"/><rect x="4" y="13" width="7" height="7" rx="2"/><rect x="13" y="13" width="7" height="7" rx="2"/>',
recurring:'<circle class="icon-tint" cx="12" cy="12" r="8"/><path d="M20 8a8.5 8.5 0 0 0-14-3L3 8m0-5v5h5M4 16a8.5 8.5 0 0 0 14 3l3-3m0 5v-5h-5M12 7v5l3 2"/>',
settings:'<circle class="icon-tint" cx="8" cy="7" r="3"/><circle class="icon-tint" cx="16" cy="17" r="3"/><path d="M3 7h2m6 0h10M3 17h10m6 0h2"/><circle cx="8" cy="7" r="3"/><circle cx="16" cy="17" r="3"/>',
plus:'<path d="M12 5v14M5 12h14"/>',arrow:'<path d="M5 12h14m-5-5 5 5-5 5"/>',
coffee:'<path class="icon-tint" d="M4 8h13v7a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5z"/><path d="M4 8h13v7a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5V8zm13 1h1a3 3 0 0 1 0 6h-1M7 3v2m4-2v2m4-2v2"/>',
food:'<path d="M4 11h16c0 5-3.5 8-8 8s-8-3-8-8Z"/><path d="M8 21h8M8 7c-2-2 2-3 0-5M13 7c-2-2 2-3 0-5M18 7c-2-2 2-3 0-5"/>',
home:'<path class="icon-tint" d="m4 10 8-6 8 6v10H4z"/><path d="m3 11 9-7 9 7M5 10v10h14V10M10 20v-6h4v6"/>',
travel:'<rect class="icon-tint" x="5" y="3" width="14" height="16" rx="5"/><rect x="5" y="3" width="14" height="16" rx="5"/><path d="M5 10h14M9 3v7M8 19l-1 2m9-2 1 2"/><circle cx="9" cy="15" r=".8" class="icon-solid"/><circle cx="15" cy="15" r=".8" class="icon-solid"/>',
bag:'<path class="icon-tint" d="M5 8h14l1 10a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3z"/><path d="M5 8h14l1 10a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3L5 8zm3 1V6a4 4 0 0 1 8 0v3"/>',
income:'<circle class="icon-tint" cx="12" cy="12" r="9"/><path d="M17 13v4H7V7h4m-4 10L18 6m-5 0h5v5"/>',
transfer:'<path class="icon-tint" d="M3 7h18v10H3z"/><path d="M4 7h16m-4-4 4 4-4 4M20 17H4m4-4-4 4 4 4"/>',
search:'<circle class="icon-tint" cx="10" cy="10" r="6"/><circle cx="10" cy="10" r="6"/><path d="m15 15 5 5"/>',
leaf:'<path class="icon-tint" d="M20 3C8 2 3 8 5 16c8 4 16-2 15-13z"/><path d="M20 3C8 2 3 8 5 16c8 4 16-2 15-13zM4 21l11-11"/>',
more:'<circle class="icon-solid" cx="5" cy="12" r="1.7"/><circle class="icon-solid" cx="12" cy="12" r="1.7"/><circle class="icon-solid" cx="19" cy="12" r="1.7"/>',
export:'<path class="icon-tint" d="M4 15h16v6H4z"/><path d="M12 3v12m-4-4 4 4 4-4M4 15v4a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-4"/>',
eye:'<path d="M2 12s4-6 10-6 10 6 10 6-4 6-10 6S2 12 2 12z"/><circle cx="12" cy="12" r="2.5"/>',
eyeoff:'<path d="m4 4 16 16M8 6.5A12 12 0 0 1 12 6c6 0 10 6 10 6a20 20 0 0 1-3 3M15 17.5A12 12 0 0 1 12 18C6 18 2 12 2 12a20 20 0 0 1 3-3"/>'
};
const icon=n=>`<svg class="icon icon-${n}" viewBox="0 0 24 24" aria-hidden="true">${glyphs[n]||glyphs.ledger}</svg>`;

// Clean journal glyphs share a centered 24px grid and rounded strokes.
const journalGlyphs={
food:'<path d="M4 11h16c0 5-3.5 8-8 8s-8-3-8-8Z"/><path d="M8 21h8M8 7c-2-2 2-3 0-5M13 7c-2-2 2-3 0-5M18 7c-2-2 2-3 0-5"/>',
home:'<path d="m3.5 10 8.5-7 8.5 7M5.5 9v10a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V9"/><path d="M10 21v-6a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v6"/>',
travel:'<rect x="5" y="3" width="14" height="16" rx="4"/><path d="M5 10h14M9 6h6M8 19l-1 2m9-2 1 2"/><circle cx="8.5" cy="15" r="1" class="icon-solid"/><circle cx="15.5" cy="15" r="1" class="icon-solid"/>',
bag:'<path d="M5 8h14l1 11a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2L5 8Z"/><path d="M8.5 9V6a3.5 3.5 0 0 1 7 0v3"/>',
recurring:'<rect x="4" y="5" width="16" height="15" rx="3"/><path d="M8 3v4M16 3v4M4 10h16M9 15h6"/>',
other:'<circle cx="12" cy="12" r="8.5"/><circle cx="8" cy="12" r="1" class="icon-solid"/><circle cx="12" cy="12" r="1" class="icon-solid"/><circle cx="16" cy="12" r="1" class="icon-solid"/>',
income:'<path d="M5 8h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V10a2 2 0 0 1 2-2Z"/><path d="M12 2v11m-3-3 3 3 3-3M3 16h18"/>',
refund:'<path d="M7 8H4V5M4 8a8 8 0 1 1-.5 7"/><path d="M12 8v8M9.5 10H13a2 2 0 0 1 0 4H9.5"/>',
transfer:'<path d="M4 7h16m-4-4 4 4-4 4M20 17H4m4-4-4 4 4 4"/>',
dividend:'<ellipse cx="8.5" cy="10" rx="5.5" ry="2.5"/><path d="M3 10v7c0 1.4 2.5 2.5 5.5 2.5s5.5-1.1 5.5-2.5v-7M3 13.5c0 1.4 2.5 2.5 5.5 2.5s5.5-1.1 5.5-2.5M18 3v7m-2.5-2.5L18 10l2.5-2.5"/>'
};
function journalIcon(t){if(t.type==='investment')return icon('investments');const key=t.dividend?'dividend':t.type==='transfer'?'transfer':t.type==='refund'?'refund':t.type==='income'?(categoryByName(t.category,'income')?.icon||'income'):cat(t.category).icon;return `<svg class="icon journal-icon" viewBox="0 0 24 24" aria-hidden="true">${journalGlyphs[key]||journalGlyphs.other}</svg>`;}

const summaryGlyphs={
income:journalGlyphs.income,
expense:'<path d="M5 8h3m8 0h3a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V10a2 2 0 0 1 2-2"/><path d="M12 13V2m-3 3 3-3 3 3M3 16h18"/>',
invest:journalGlyphs.dividend,
surplus:glyphs.accounts
};
function summaryIcon(kind){return `<svg class="icon summary-icon" viewBox="0 0 24 24" aria-hidden="true">${summaryGlyphs[kind]}</svg>`;}

const accountPickerGlyphs={
notes:'<rect x="3" y="6" width="18" height="12" rx="2"/><circle cx="12" cy="12" r="3"/><path d="M6 9v2M18 13v2M6 18v2h13"/>',
coins:'<ellipse cx="9" cy="7" rx="5" ry="2"/><path d="M4 7v4c0 1 2 2 5 2M4 11v4c0 1 2 2 5 2"/><ellipse cx="15" cy="13" rx="5" ry="2"/><path d="M10 13v5c0 1 2 2 5 2s5-1 5-2v-5"/>',
bank:'<path d="m3 8 9-5 9 5H3ZM5 11v7M10 11v7M14 11v7M19 11v7M3 21h18"/>',
phone:'<rect x="6" y="2.5" width="12" height="19" rx="3"/><path d="M10 6h4M9 11h6"/><circle cx="12" cy="18" r=".8" class="icon-solid"/>',
vault:'<rect x="4" y="4" width="16" height="16" rx="3"/><circle cx="12" cy="12" r="4"/><path d="M12 8v8M8 12h8M4 8H2M4 16H2"/>',
suitcase:'<rect x="5" y="5" width="14" height="15" rx="3"/><path d="M9 5V3h6v2M9 9v7M15 9v7M8 20v1M16 20v1"/>',
briefcase:'<rect x="3" y="7" width="18" height="13" rx="3"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 12c5 3 13 3 18 0M10 14h4"/>',
card:'<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M3 10h18M7 15h4"/>',
message:'<path d="M5 4h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H9l-5 3v-3a2 2 0 0 1-1-2V6a2 2 0 0 1 2-2Z"/><path d="M8 8v6h8"/>',
store:'<path d="M4 10v10h16V10M3 10l2-6h14l2 6M8 4l-1 6m9-6 1 6M3 10c1 3 4 3 5 0 1 3 4 3 5 0 1 3 4 3 5 0 1 3 3 3 3 0M9 20v-5h6v5"/>',
qr:'<path d="M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5"/><rect x="8" y="8" width="3" height="3" rx=".5"/><path d="M15 8v3M8 15h3M14 15l2 2 4-4"/>',
ticket:'<path d="M4 5h16v5a2 2 0 0 0 0 4v5H4v-5a2 2 0 0 0 0-4V5Z"/><path d="M14 8v2m0 4v2M8 10h2m-2 4h2"/>'
};
function accountPickerIcon(a){const known={cash:'notes','home-cash':'coins',bank:'bank',digital:'phone',savings:'vault','travel-bank':'suitcase','salary-bank':'briefcase',card:'card','line-pay':'message',jkopay:'store',pxpay:'qr','easy-wallet':'ticket'},key=known[a?.id]||(a?.kind==='cash'?'notes':a?.kind==='card'?'card':a?.kind==='ewallet'?'qr':'bank');return `<svg class="icon account-picker-icon" viewBox="0 0 24 24" aria-hidden="true">${accountPickerGlyphs[key]}</svg>`;}
const calcGlyphs={
calculator:'<rect x="5" y="2.5" width="14" height="19" rx="3"/><path d="M8 6h8M8 10h1M12 10h1M16 10h.1M8 14h1M12 14h1M8 18h1M12 18h1M16 14v4"/>',
backspace:'<path d="M9 5h11a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H9L3 12l6-7Z"/><path d="m11 9 6 6m0-6-6 6"/>',
'+':'<path d="M5 12h14M12 5v14"/>',
'−':'<path d="M5 12h14"/>',
'×':'<path d="m7 7 10 10m0-10L7 17"/>',
'÷':'<path d="M5 12h14"/><circle cx="12" cy="6" r="1.2" class="icon-solid"/><circle cx="12" cy="18" r="1.2" class="icon-solid"/>',
'=':'<path d="M5 8.5h14M5 15.5h14"/>'
};
function calcIcon(key){return `<svg class="calc-symbol" viewBox="0 0 24 24" aria-hidden="true">${calcGlyphs[key]||calcGlyphs.backspace}</svg>`;}
