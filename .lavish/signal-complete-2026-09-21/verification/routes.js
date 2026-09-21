console.log(JSON.stringify(await page.eval(() => {
 const app=window.SignalDemo, results=[], broken=[];
 for(const route of app.routes){
  app.reset();app.go(route,true);
  for(const state of app.scenarios(route)){
   app.setScenario(state);
   const content=document.querySelector('#phone-content');
   if(!content.querySelector('h1'))broken.push({route,state,issue:'missing heading'});
   if(/\bundefined\b|\bNaN\b/.test(content.innerText))broken.push({route,state,issue:'undefined content'});
   for(const el of content.querySelectorAll('[data-go]'))if(!app.routes.includes(el.dataset.go))broken.push({route,state,issue:'missing route',target:el.dataset.go});
   results.push({route,state,heading:content.querySelector('h1')?.innerText});
  }
 }
 app.reset();
 return {screens:app.routes.length,states:results.length,broken,results};
})));
