console.log(JSON.stringify(await page.eval(() => {
 const app=window.SignalDemo,issues=[], modes=[
  {size:'standard',text:'standard',theme:'light',platform:'ios26',material:'glass'},
  {size:'compact',text:'large',theme:'light',platform:'ios26',material:'glass'},
  {size:'compact',text:'large',theme:'dark',platform:'ios26',material:'solid'},
  {size:'standard',text:'standard',theme:'dark',platform:'ios18',material:'solid'}
 ];let checked=0;
 for(const mode of modes){
  for(const [k,v] of Object.entries(mode))app.setMode(k,v);
  for(const r of app.routes){
   app.reset();app.go(r,true);
   const c=document.querySelector('#phone-content');
   c.querySelectorAll('details').forEach(d=>d.open=true);
   const cr=c.getBoundingClientRect();
   if(c.scrollWidth>c.clientWidth+1)issues.push({route:r,mode,issue:'horizontal content overflow',client:c.clientWidth,scroll:c.scrollWidth});
   const bad=[...c.querySelectorAll('*')].filter(e=>{
     const rect=e.getBoundingClientRect(),st=getComputedStyle(e);
     return rect.width>0&&st.position!=='absolute'&&(rect.right>cr.right+1||rect.left<cr.left-1);
   }).slice(0,4).map(e=>({tag:e.tagName,cls:e.className,text:e.innerText?.slice(0,60)}));
   if(bad.length)issues.push({route:r,mode,issue:'child outside content',bad});
   checked++;
  }
 }
 app.reset();for(const [k,v] of Object.entries(modes[0]))app.setMode(k,v);
 return {checked,issues};
})));
