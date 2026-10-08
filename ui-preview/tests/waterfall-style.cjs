const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const sharp=require(require.resolve('sharp',{paths:[process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES]}));
const {run,context,node,docListeners}=require('./interaction-smoke.cjs');

const css=fs.readFileSync('dist/visual-refresh.css','utf8')+'\n'+fs.readFileSync('dist/interface-system.css','utf8');
const background=[247,242,231,255];
const color={good:[49,93,71,255],bad:[139,64,59,255],flat:[167,163,152,255]};
const resolveTheme=source=>source.replaceAll('var(--wallet)','#9a7650').replaceAll('var(--ui-positive)',run('palette.income')).replaceAll('var(--ui-negative)',run('palette.expense'));
const attrs=markup=>Object.fromEntries([...markup.matchAll(/([\w-]+)="([^"]*)"/g)].map(m=>[m[1],m[2]]));
function weeks(markup){return [...markup.matchAll(/<g class="waterfall-item ([^"]+)"([^>]*)>([\s\S]*?)<\/g>/g)].filter(m=>m[2].includes('data-action="waterfall-info"')).map(m=>({classes:m[1],attributes:attrs(m[2]),hit:attrs(m[3].match(/<rect class="waterfall-hit"[^>]*>/)[0]),bar:attrs(m[3].match(/<rect class="waterfall-bar"[^>]*>/)[0])}));}
function chartSVG(markup,stylesheet,width=320){
  const inner=markup.match(/<svg\b[^>]*>([\s\S]*?)<\/svg>/)[1];
  const viewBox=markup.match(/viewBox="([^"]*)"/)[1],height=Number(viewBox.split(' ')[3]);
  // Render the production SVG and selector cascade. The HTML ancestor is represented
  // by the same class on a group; resolve inherited theme colors for SVG export.
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${width*height/320}" viewBox="${viewBox}"><style>${resolveTheme(stylesheet)}</style><rect width="320" height="${height}" fill="#f7f2e7"/><g class="account-waterfall-scroll">${resolveTheme(inner)}</g></svg>`;
}
async function raster(markup,stylesheet,width=320){const svg=chartSVG(markup,stylesheet,width);return sharp(Buffer.from(svg)).ensureAlpha().raw().toBuffer({resolveWithObject:true});}
function pixel(image,x,y){const scale=image.info.width/320,offset=(Math.floor(y*scale)*image.info.width+Math.floor(x*scale))*4;return Array.from(image.data.subarray(offset,offset+4));}
function eventElement(week){const attributes={...week.attributes},classes=new Set(week.classes.split(' '));return {attributes,dataset:Object.fromEntries(Object.entries(attributes).filter(([key])=>key.startsWith('data-')).map(([key,value])=>[key.slice(5),value])),classList:{toggle(name,on){if(on)classes.add(name);else classes.delete(name);}},setAttribute(name,value){attributes[name]=value;},selected:()=>classes.has('selected')};}

async function main(){
  assert.ok(!/\.account-waterfall-scroll(?:\s+\.[\w-]+)?\s+rect\s*\{/.test(css),'No broad rect fill may color hit areas');
  assert.ok(css.includes('.waterfall-hit{fill:none;stroke:none;pointer-events:all}'),'Invisible hit areas must stay interactive');
  run("state=seed();state.privacy=false;month='2026-10'");
  const cashChart=run("accountWeeklyWaterfall(account('cash'),false)");
  const cashWeeks=weeks(cashChart);
  assert.equal(cashWeeks.length,4);
  assert.ok(cashChart.includes('viewBox="0 0 320 120"'),'The chart uses the smaller plotting area');
  assert.ok(!cashChart.includes('<div class="waterfall-detail"'),'No separate detail box below the chart');
  assert.ok(cashChart.includes('<g class="waterfall-annotation" id="waterfall-detail"'),'Selected amount is integrated into the SVG');
  assert.ok(cashChart.indexOf('id="waterfall-detail"')<cashChart.indexOf('</svg>'));
  assert.ok(!cashChart.includes('waterfall-inspector'),'No HTML popup can cover the account summary');
  assert.equal((cashChart.match(/class="waterfall-value /g)||[]).length,1,'One selected value, not labels on every bar');
  // Negative control: this is the original specificity bug, not a fabricated bar shape.
  const brokenCSS=css+'\n.account-waterfall-scroll .bad rect{fill:#aa6b64}';
  const broken=await raster(cashChart,brokenCSS),badWeek=cashWeeks.find(week=>week.classes.split(' ').includes('bad'));
  assert.ok(badWeek,'The negative control needs an actual negative cash week');
  assert.deepEqual(pixel(broken,Number(badWeek.hit.x)+Number(badWeek.hit.width)/2,5),[170,107,100,255],'Legacy selector reproduces the red full-height block');

  for(const accountId of ['cash','bank','card','digital']){
    context.__waterfallAccount=accountId;
    const markup=run('accountWeeklyWaterfall(account(__waterfallAccount),account(__waterfallAccount).kind==="card")');
    for(const width of [280,320,390]){
      const image=await raster(markup,css,width);
      for(const week of weeks(markup)){
        assert.ok(Number(week.bar.y)>=26.5,'Bars leave space above for their value label');
        assert.equal(Number(week.attributes['data-x']),Number(week.bar.x)+Number(week.bar.width)/2,'Value centers on the selected bar');
        assert.ok(Math.abs(Number(week.bar.y)-Number(week.attributes['data-y'])-8)<0.11,'Value sits eight units above the selected bar');
        const center=Number(week.hit.x)+Number(week.hit.width)/2;
        for(const y of [98,100])assert.deepEqual(pixel(image,center,y),background,accountId+' '+width+': hit area must remain unpainted');
        const kind=week.classes.split(' ')[0];
        if(Number(week.attributes['data-delta']))assert.ok(Number(week.bar.height)>=10,'Small nonzero changes remain visible');
        assert.deepEqual(pixel(image,Number(week.bar.x)+Number(week.bar.width)/2,Number(week.bar.y)+Number(week.bar.height)/2),color[kind],accountId+' '+width+': true floating bar stays colored');
      }
    }
  }
  // Verify the zero-change class cannot reintroduce full-height hit-area paint.
  run("state.tx=[{id:'zero-in',date:'2026-10-01',type:'income',amount:100,account:'cash',category:'其他收入'},{id:'zero-out',date:'2026-10-02',type:'expense',amount:100,account:'cash',category:'飲食日常'}]");
  const flat=run("accountWeeklyWaterfall(account('cash'),false)"),flatWeek=weeks(flat)[0],flatImage=await raster(flat,css);
  assert.ok(flatWeek.classes.includes('flat'));
  assert.deepEqual(pixel(flatImage,Number(flatWeek.hit.x)+Number(flatWeek.hit.width)/2,98),background);

  // Touch, hover, and focus move the single value label to the corresponding bar.
  const elements=cashWeeks.map(eventElement),originalQuery=context.document.querySelectorAll;
  context.document.querySelectorAll=selector=>selector==='[data-action="waterfall-info"]'?elements:[];
  try{
    const target=el=>({closest:selector=>selector==='[data-action="waterfall-info"]'||selector==='[data-action]'?el:null});
    for(const handler of docListeners.click||[])handler({target:target(elements[0])});
    assert.equal(elements[0].attributes['aria-pressed'],'true');
    const selectedLabel=()=>attrs(node('#waterfall-detail').innerHTML);
    const atBar=i=>{
      assert.equal(Number(selectedLabel().x),Number(elements[i].dataset.x));
      assert.equal(Number(selectedLabel().y),Number(elements[i].dataset.y));
      assert.equal(selectedLabel()['text-anchor'],'middle');
    };
    atBar(0);
    assert.ok(!node('#waterfall-detail').innerHTML.includes('waterfall-range'));
    assert.equal((node('#waterfall-detail').innerHTML.match(/<text /g)||[]).length,1,'Only the amount appears above the bar');
    assert.ok(node('#waterfall-detail').innerHTML.includes('<text class="waterfall-value'));
    assert.ok(!node('#waterfall-detail').innerHTML.includes('<div>'));
    for(const handler of docListeners.pointerover||[])handler({pointerType:'mouse',target:target(elements[1])});
    assert.equal(elements[1].attributes['aria-pressed'],'true');
    atBar(1);
    for(const handler of docListeners.focusin||[])handler({target:target(elements[2])});
    assert.equal(elements[2].attributes['aria-pressed'],'true');
    atBar(2);
    assert.equal(elements.filter(el=>el.selected()).length,1);
  }finally{context.document.querySelectorAll=originalQuery;}

  if(process.env.WATERFALL_RENDER_DIR){
    const dir=process.env.WATERFALL_RENDER_DIR;
    await sharp(Buffer.from(chartSVG(cashChart,brokenCSS,960))).png().toFile(path.join(dir,'waterfall-before.png'));
    await sharp(Buffer.from(chartSVG(cashChart,css,960))).png().toFile(path.join(dir,'waterfall-after.png'));
  }
  console.log('PASS: compact waterfall with inline selected value, no detail box, invisible hit areas at 280/320/390 px; cash, bank, card, empty and flat states; click, hover and focus labels.');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
