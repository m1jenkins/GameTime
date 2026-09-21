await page.open('file:///Users/user/Documents/GitHub/GameTime/.lavish/signal-complete-2026-09-21/index.html');
console.log(JSON.stringify(await page.eval(() => {
 const app=window.SignalDemo,out=[];
 const check=(name,test)=>{try{test();out.push({name,pass:true});}catch(e){out.push({name,pass:false,error:e.message});}};
 const assert=(v,m)=>{if(!v)throw new Error(m);};
 const click=a=>{const b=document.querySelector('[data-action="'+a+'"]');assert(b,'Missing action '+a);assert(!b.disabled,'Disabled '+a);b.click();};
 const fill=(k,v)=>{const e=document.querySelector('[data-field="'+k+'"]');assert(e,'Missing field '+k);e.value=v;e.dispatchEvent(new Event('input',{bubbles:true}));};
 check('Direct Personal has two required stages and saves exact values',()=>{
  app.reset();app.act('create-personal');fill('draft.target','4703');
  click('create-next');assert(app.state.route==='createReview','Review must follow Goal & dates');
  click('create-check');const consent=document.querySelector('[data-check="createConsent"]');consent.click();
  click('create-save');assert(app.state.route==='createSaved','Saved receipt');assert(app.state.created.target==='4703','Exact target lost');
  app.go('createActivity');fill('draft.target','9000');assert(app.state.created.target==='4703','Saved receipt rewritten');
 });
 check('Offline creation cannot become ready by checking',()=>{
  app.reset();app.act('create-personal');fill('draft.target','50000');click('create-next');app.setScenario('offline');app.act('create-check');
  assert(!app.state.createReady,'Offline manufactured ready');assert(app.state.scenario==='offline','Offline was cleared');
 });
 check('Running activity opens matching detail',()=>{
  app.reset();app.act('metric:distance');app.go('activity');
  assert(document.querySelector('#phone-content').innerText.includes('6.4'),'Running score lost');assert(!document.querySelector('#phone-content').innerText.includes('18,420'),'Wrong steps record');
 });
 check('All linked app routes resolve',()=>{
  for(const r of app.routes){app.reset();app.go(r,true);for(const e of document.querySelectorAll('#phone-content [data-go]'))assert(app.routes.includes(e.dataset.go),r+' -> '+e.dataset.go);}
 });
 check('Sign out clears private state and Close stays signed out',()=>{
  app.reset();app.patch({created:{kind:'personal',target:'8888'},friendAgreement:{goal:'9999'}});
  app.go('accountSupport');app.act('account-sign-out');
  assert(!app.state.created&&!app.state.friendAgreement,'Old agreements retained');
  app.act('close');assert(['signin','signedOut'].includes(app.state.route),'Close exposed private tabs');
 });
 check('Fresh account can complete onboarding after sign out',()=>{
  app.reset();app.go('accountSupport');app.act('account-sign-out');app.act('account-signin');app.act('account-auth-complete');
  assert(app.state.route==='onboarding','Auth return');
  fill('accountName','Avery Test');fill('accountUsername','averytest');
  click('account-profile-save');assert(app.state.route!=='signin','Fresh profile was fenced out');
 });
 check('All sandbox states are distinct and contain no retry-payment action',()=>{
  const rs=app.routes.filter(r=>r.startsWith('legacyPay')&&!['legacyPayment','legacyPaymentSetup','legacyPaymentSheet'].includes(r));
  assert(rs.length===9,'Expected nine sandbox states');
  for(const r of rs){app.reset();app.go(r,true);assert(!/Retry payment|Charge again/.test(document.querySelector('#phone-content').innerText),'Payment retry exposed');}
 });
 check('All four metrics retain their own goal detail and pending exit guards',()=>{
  for(const r of ['personalStepsDetail','personalMinutesDetail','personalDetail','timedDetail','challengeDetail','friendMinutesDetail','friendDistanceDetail','friendTimedDetail']){
   app.reset();app.go(r,true);app.setScenario('offline');app.act('goal-leave');
   assert(app.state.scenario==='offline','Lost offline state at '+r);app.act('goal-leave-save');
   assert(!app.state.goalExits[r],'Offline exit invented for '+r);
  }
 });
 check('Timed final uses a confirmed time strictly below the agreed target',()=>{
  app.reset();app.go('timedDetail',true);app.setScenario('final');
  const content=document.querySelector('#phone-content').innerText;
  assert(content.includes('29:40'),'Confirmed time missing');assert(!content.includes('No matching activity'),'Final still unknown');
  assert(document.querySelector('#demo-clock').innerText.includes('Oct 3'),'Final clock precedes review end');
 });
 check('Saved review stays under review and receipts require records',()=>{
  app.reset();app.go('goalReviewSaved',true);assert(document.querySelector('#phone-content h1').innerText.includes('No'),'Unsaved receipt claims saved');
  app.go('personalStepsDetail',true);app.setScenario('review');app.act('goal-review');fill('goalReason','Activity is missing');app.act('goal-review-save');
  assert(app.state.goalReviews.personalStepsDetail,'Missing saved review');app.go('personalStepsDetail');
  assert(document.querySelector('#phone-content').innerText.includes('Under review'),'Saved review reverted to active');
 });
 check('Participant details preserve Activity minutes context',()=>{
  app.reset();app.go('friendMinutesDetail',true);app.act('goal-participant');
  const content=document.querySelector('#phone-content').innerText;
  assert(content.includes('Sam Parker'),'Wrong participant');assert(content.includes('180'),'Own challenge target lost');assert(!content.includes('60,000'),'Unrelated steps context leaked');
 });
 app.reset();return out;
})));
