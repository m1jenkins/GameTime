const result=await page.eval(()=>{
 const findings=[],seen=new Set();let count=0;
 for(const size of ['standard','compact'])for(const text of ['standard','large'])for(const theme of ['light','dark'])for(const material of ['glass','solid']){
  SignalDemo.setMode('size',size);SignalDemo.setMode('text',text);SignalDemo.setMode('theme',theme);SignalDemo.setMode('material',material);
  for(const route of SignalDemo.routes){try{SignalDemo.go(route,true);}catch(e){if(!e.message.includes('replaceState'))throw e;}
   document.querySelectorAll('#phone-content details').forEach(x=>x.open=true);const phone=document.getElementById('phone-content');const setting=[route,size,text,theme,material].join('/');count++;
   const add=(kind,detail)=>{const key=kind+route+size+text+detail;if(!seen.has(key)){seen.add(key);findings.push({kind,setting,detail});}};
   if(phone.scrollWidth>phone.clientWidth+1)add('horizontal-overflow',phone.scrollWidth+' > '+phone.clientWidth);
   for(const el of phone.querySelectorAll('button,input,select,textarea,summary')){if(el.type==='checkbox'||el.type==='radio')continue;const r=el.getBoundingClientRect();if(r.width===0||r.height===0)continue;if(el.closest('details:not([open])')&&el.tagName!=='SUMMARY')continue;if(r.width<43.5||r.height<43.5)add('small-target',el.tagName+':'+(el.getAttribute('aria-label')||el.textContent||el.name).slice(0,60)+' '+Math.round(r.width)+'x'+Math.round(r.height));}
   if(!phone.querySelector('h1'))add('missing-heading','');
  }
 }
 return {rendered:count,findings};
});console.log(JSON.stringify(result,null,2));
