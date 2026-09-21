const result=await page.eval(()=>{const findings=[];let rendered=0;
for(const size of ['standard','compact'])for(const text of ['standard','large'])for(const theme of ['light','dark'])for(const material of ['glass','solid'])for(const tab of ['activity','challenges']){
for(const [k,v] of Object.entries({size,text,theme,material}))SignalDemo.setMode(k,v);SignalDemo.go('you',true);document.querySelector('[data-action="profile-tab:'+tab+'"]').click();const p=document.getElementById('phone-content');p.querySelectorAll('details').forEach(x=>x.open=true);rendered++;
if(p.scrollWidth>p.clientWidth+1)findings.push({size,text,theme,material,tab,problem:'overflow'});for(const el of p.querySelectorAll('button,summary')){const r=el.getBoundingClientRect();if(r.width<44||r.height<44)findings.push({size,text,tab,problem:'target',name:el.textContent});}
p.scrollTop=p.scrollHeight;const last=p.querySelector('.row:last-child').getBoundingClientRect(),nav=document.getElementById('tabbar').getBoundingClientRect();if(last.bottom>nav.top)findings.push({size,text,tab,problem:'bottom-clearance'});
}
return {rendered,findings};});console.log(JSON.stringify(result,null,2));
