/* Local design study. The fixtures come from the complete Signal prototype.
   No account, activity, consent, payment, notification or network writes. */
(() => {
  'use strict';
  const state = { screen: 'home', theme: 'all', missing: false };
  const $ = s => document.querySelector(s);
  const icons = {
    arrow: '<path d="M4 12h15m-6-6 6 6-6 6"/>',
    back: '<path d="m14 5-7 7 7 7"/>',
    home: '<path d="m3 10 9-7 9 7v10h-6v-7H9v7H3z"/>',
    flag: '<path d="M5 21V3m0 1c5-4 9 4 14 0v10c-5 4-9-4-14 0"/>',
    user: '<circle cx="12" cy="7" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',
    run: '<circle cx="16" cy="4" r="2"/><path d="m5 7 6-2 5 7 5 1M11 6l-2 8 5 3 1 5M9 14l-5 6M14 10l-3 2"/>',
    check: '<path d="m5 12 4 4L20 5"/>',
    watch: '<rect x="6" y="5" width="12" height="14" rx="4"/><path d="M9 5V1h6v4M9 19v4h6v-4M12 9v4l3 1"/>',
    leaf: '<path d="M20 3C9 2 2 8 6 16c8 6 16-1 14-13ZM4 21 16 9M9 15v-5m0 5h5"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 1v3m0 16v3M1 12h3m16 0h3M4 4l2 2m12 12 2 2M4 20l2-2M18 6l2-2"/>',
    lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V6a4 4 0 0 1 8 0v4"/>',
    steps: '<path d="M7 3c3-1 4 4 2 6S4 6 5 4l2-1ZM16 10c3-1 4 4 2 6s-5-3-4-5l2-1Z"/><path d="m5 12 2 3m9 4 1 3"/>'
  };
  const icon = name => `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${icons[name] || icons.flag}</svg>`;
  const spark = cls => `<svg class="${cls}" viewBox="0 0 120 120" fill="none" aria-hidden="true"><path d="m60 3 13 34 32-21-12 37 26 8-30 16 13 31-34-13-13 24-9-31-34 10 17-31L3 52l36-8-3-34 24 23Z" fill="currentColor"/><path d="m39 61 13 13 29-30" stroke="#27162d" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  const track = () => '<svg class="track-art" viewBox="0 0 200 200" fill="none" aria-hidden="true"><rect x="9" y="9" width="182" height="182" rx="91" stroke="currentColor" stroke-width="2"/><rect x="25" y="25" width="150" height="150" rx="75" stroke="currentColor" stroke-width="2"/><rect x="41" y="41" width="118" height="118" rx="59" stroke="currentColor" stroke-width="2"/><path d="M100 10v70m0 39v72" stroke="currentColor" stroke-width="2"/></svg>';
  const emblem = theme => theme === 'fieldwork' ? '<img class="result-emblem generated-emblem" src="assets/fieldwork-emblem.webp" alt="">' : theme === 'rally' ? spark('result-emblem') : `<svg class="result-emblem" viewBox="0 0 100 100" fill="none" aria-hidden="true"><path d="m32 48 13 13 26-28" stroke="currentColor" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/><path d="M24 73C7 63 8 33 24 23M76 73c17-10 16-40 0-50M13 36l13 2M10 49l13-1M15 62l12-5M87 36l-13 2M90 49l-13-1M85 62l-12-5M34 82h32" stroke="currentColor" stroke-width="3" stroke-linecap="round"/></svg>`;
  const action = (label, screen, cls = 'btn') => `<button class="${cls}" data-screen="${screen}">${label}${cls === 'btn' ? icon('arrow') : ''}</button>`;
  const score = () => state.missing ? '—' : '6.4';
  const status = () => `<div class="status-bar" aria-hidden="true"><span>9:41</span><div class="status-icons"><svg viewBox="0 0 18 12" fill="currentColor"><path d="M0 8h3v4H0zM5 5h3v7H5zM10 2h3v10h-3zM15 0h3v12h-3z"/></svg><svg viewBox="0 0 20 12" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="1" y="2" width="15" height="8" rx="2"/><path d="M18 5v2"/><path d="M3 4h11v4H3z" fill="currentColor" stroke="none"/></svg></div></div><div class="simulation">Simulated stakes — no real money moves.</div>`;
  const nav = () => `<nav class="app-nav" aria-label="App navigation">${[['home','Home','home'],['challenges','Challenges','flag'],['you','You','user']].map(([screen,label,ic]) => `<button data-screen="${screen}" ${state.screen === screen || screen === 'challenges' && ['goal','result'].includes(state.screen) ? 'aria-current="page"' : ''}>${icon(ic)}${label}</button>`).join('')}</nav><span class="home-bar" aria-hidden="true"></span>`;
  const top = theme => `<div class="app-top"><div class="app-brand">${icon(theme === 'fieldwork' ? 'leaf' : 'run')}GameTime</div><button class="monogram" data-screen="you" aria-label="Your profile">AL</button></div>`;
  const toolbar = name => `<div class="app-toolbar"><button data-screen="home" aria-label="Back to Home">${icon('back')}</button><span>${name}</span><span class="right-label">Just for you</span></div>`;
  const freshness = () => `<p class="freshness">${icon('watch')}${state.missing ? 'No saved activity yet' : 'Saved today at 9:40 AM'}</p>`;
  const missing = () => state.missing ? '<p class="missing-notice">No matching activity is saved yet. Try Refresh after your Watch syncs. Missing activity is not a missed goal.</p>' : '';
  const progress = () => state.missing ? '' : '<div class="progress-line" role="img" aria-label="6.4 of 20 kilometers, 32 percent"><span></span></div>';
  const stake = () => '<div class="sim-stake"><span>Your simulated stake</span><strong>$20 <small>· fee $0</small></strong></div>';
  const friendRow = (kind = 'invite') => kind === 'invite' ? `<button class="friend-row" data-info="invitation"><span class="initials">SP</span><span>Sam invited you<small>Sep 30–Oct 6 · Steps</small></span>${icon('arrow')}</button>` : `<button class="friend-row" data-info="friend"><span class="initials">SP</span><span>Week in motion<small>18,420 / 50,000 steps · Sep 18–24</small></span>${icon('arrow')}</button>`;
  function home(theme) {
    let art = '';
    if(theme === 'pace') art = `<div class="pace-hero"><img src="assets/pace-runner.webp" alt="" fetchpriority="high"><h2>Bet on<br>yourself.</h2></div>`;
    if(theme === 'rally') art = `<div class="rally-headline"><h2>Big goal.<br>Your move.</h2><img class="rally-shoe" src="assets/rally-shoe.webp" alt=""></div><div class="rally-board"><div class="board-top"><h3>Your running goal</h3>${icon('run')}</div><div class="rally-score"><b>${score()}</b><span>of 20 km</span></div>${state.missing ? '<p style="padding:0 18px 14px;font-size:11px">No saved activity yet</p>' : '<div class="rally-meter" role="img" aria-label="32 percent of your goal saved">'+Array.from({length:20},(_,i)=>'<span'+(i<6?' class="lit"':'')+'></span>').join('')+'</div>'}<div class="board-bottom"><span>Sep 21–27</span><b>${state.missing ? '—' : '32% saved'}</b></div></div>`;
    if(theme === 'fieldwork') art = `<div class="field-headline"><h2>A little further.<br>A little more you.</h2><img class="field-emblem" src="assets/fieldwork-emblem.webp" alt=""></div><div class="field-illustration"><img src="assets/field-running.webp" alt="" fetchpriority="high"></div>`;
    const readout = theme === 'rally' ? '' : `<div class="goal-title"><h3>Your running goal</h3></div><div class="goal-meta"><span>Sep 21–27, 2026</span><span>Private to you</span></div><div class="score">${score()}<span>/ 20 km</span></div>${progress()}`;
    return top(theme)+art+`<div class="inset home-goal">${readout}${freshness()}${missing()}${stake()}${action('View your goal','goal')}<div class="section-heading"><h3>With friends</h3></div>${friendRow()}${friendRow('active')}<p class="source-line">Apple Watch outdoor runs · Apple Health</p><p class="inline-message" aria-live="polite"></p></div>`;
  }
  function fullRules() {
    return `<details><summary>Full goal rules</summary><div class="rules-content"><p>Eligible outdoor runs recorded by Apple’s Workout app on Apple Watch. Each whole run must start and finish inside your challenge dates. We exclude manual and unsupported records.</p><p>Reach at least your agreed total to meet the goal.</p><p>An observed result can confirm success. Missing or incomplete activity never proves a missed goal. An unresolved result returns that person’s simulated entry.</p><dl><dt>Starts</dt><dd>Sep 21, 2026 · midnight</dd><dt>Ends</dt><dd>Sep 28, 2026 · midnight</dd><dt>Time zone</dt><dd>Pacific Time · Los Angeles</dd><dt>Initial updates through</dt><dd>Sep 29, 2026 · midnight</dd><dt>Corrections through</dt><dd>Sep 30, 2026 · midnight</dd><dt>Entry</dt><dd>$20 simulated</dd><dt>Fee</dt><dd>$0</dd></dl><p>Meeting your goal returns your simulated entry. A confirmed miss leaves it unallocated.</p><p>You may leave before the result is final. Your entry returns. You have 48 full hours after the actual result notice to ask for review. Reviewers have 72 hours after filing. Delays do not shorten those windows.</p><p>Your goal, activity and result stay private. Nothing can be paid out or redeemed. No real money moves.</p></div></details>`;
  }
  function goal(theme) {
    const title = theme === 'pace' ? 'Make it<br>20 kilometers.' : theme === 'rally' ? 'You.<br>20 kilometers.' : 'Twenty kilometers.<br>All yours.';
    return toolbar('Your running goal')+`<div class="inset"><div class="goal-poster">${track()}<h2>${title}</h2><p>Sep 21–27, 2026 · Pacific Time</p></div><div class="goal-score-block"><p class="small-label">Your saved activity</p><div class="score">${score()}<span>/ 20 km</span></div>${progress()}${freshness()}${missing()}<p class="source-line">Apple Watch outdoor runs · Apple Health</p><button class="text-action" data-info="refresh">Refresh</button><p class="inline-message" aria-live="polite"></p></div>${stake()}<dl class="goal-facts"><div><dt>Your goal</dt><dd>20 km across 7 days</dd></div><div><dt>Who can see it</dt><dd>Private to you</dd></div><div><dt>First day</dt><dd>Sep 21, 2026</dd></div><div><dt>Last day</dt><dd>Sep 27, 2026</dd></div></dl><p class="sub">Meet your goal and your simulated stake returns. Missing activity alone never proves a missed goal.</p>${fullRules()}<details><summary>Leave this goal</summary><div class="rules-content"><p>You may leave before the result is final. Your simulated entry returns, and your agreement stays in your history.</p><p>This is a visual study. Use the complete Signal walkthrough to explore the exit and its saved receipt.</p><a href="http://127.0.0.1:4387/session/06bb462a4d13bd01" target="_blank" rel="noopener">Open full walkthrough</a></div></details></div>`;
  }
  function result(theme) {
    const title = theme === 'pace' ? 'You showed up.<br>You got there.' : theme === 'rally' ? 'Goal.<br>Crushed.' : 'Look how far<br>you’ve come.';
    return `<div class="app-toolbar"><button data-screen="challenges" aria-label="Back to Challenges">${icon('back')}</button><span>September steps</span><span class="right-label">Finished</span></div><div class="inset"><div class="result-title">${emblem(theme)}<h2>${title}</h2><p>Both goals met · Sep 7–13, 2026</p></div><div class="result-score"><span>You<small>50,000-step goal</small></span><b>52,480 <span>steps</span></b></div><div class="friend-row"><span class="initials">SP</span><span>Sam<small>60,000-step goal</small></span><strong>61,200</strong></div><div class="result-record"><h3>Result confirmed</h3><p>Both goals are met. Review is complete.</p><div class="sim-stake"><span>Simulated return recorded</span><strong>$20</strong></div><p class="sub">Recorded Sep 19, 2026 · 10 AM Pacific.<br>Fee $0.</p><p class="sub">Nothing can be paid out or redeemed. No real money moved.</p></div>${action('Back to your challenges','challenges')}</div>`;
  }
  function challenges(theme) {
    return top(theme)+`<div class="inset"><h2>Your challenges.</h2><div class="section-heading"><h3>Active</h3></div><button class="friend-row" data-screen="goal"><span class="initials">${icon('run')}</span><span>Your running goal<small>${score()} / 20 km · Sep 21–27</small></span>${icon('arrow')}</button>${friendRow('active')}<div class="section-heading"><h3>Invitations</h3></div>${friendRow()}<div class="section-heading"><h3>Finished</h3></div><button class="friend-row" data-screen="result"><span class="initials">${icon('check')}</span><span>September steps<small>Both goals met · Sep 7–13</small></span>${icon('arrow')}</button><p class="inline-message" aria-live="polite"></p></div>`;
  }
  function you(theme) {
    return top(theme)+`<div class="inset"><div class="you-monogram">AL</div><h2>Alex Lee</h2><p class="sub" style="margin-top:7px">@alexlee</p><div class="section-heading"><h3>Your record</h3></div><button class="friend-row" data-screen="result"><span class="initials">${icon('check')}</span><span>September steps<small>Both goals met · Finished challenge</small></span>${icon('arrow')}</button><button class="friend-row" data-screen="challenges"><span class="initials">${icon('flag')}</span><span>Your challenges<small>Goals, invitations and saved results</small></span>${icon('arrow')}</button><p class="source-line">Your progress belongs to each challenge. Open a goal to see its saved activity.</p></div>`;
  }
  function render(){
    const functions = { home, goal, result, challenges, you };
    ['pace','rally','fieldwork'].forEach(theme => { $('#'+theme+'-phone').innerHTML=status()+`<div class="app-content" tabindex="0" aria-label="${theme} ${state.screen} screen">${functions[state.screen](theme)}</div>`+nav(); });
    $('#screen').value=state.screen;
    $('#data-state').disabled=!['home','goal'].includes(state.screen);
    $('#data-state').title=['home','goal'].includes(state.screen) ? '' : 'Activity variants apply to Home and Your goal. Completed results remain confirmed.';
  }
  function setTheme(theme){
    state.theme=theme;
    $('#theme-grid').dataset.view=theme;
    document.querySelectorAll('[data-theme-pick]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.themePick===theme)));
    if(theme==='all' && matchMedia('(max-width:800px)').matches) document.querySelector('[data-theme-pick="pace"]').setAttribute('aria-pressed','true');
  }
  $('#screen').addEventListener('change',e=>{state.screen=e.target.value;render();});
  $('#data-state').addEventListener('change',e=>{state.missing=e.target.value==='missing';render();});
  document.addEventListener('click',e=>{
    const theme=e.target.closest('[data-theme-pick]');
    if(theme) return setTheme(theme.dataset.themePick);
    const screen=e.target.closest('[data-screen]');
    if(screen){state.screen=screen.dataset.screen;render();return;}
    const shortlist=e.target.closest('[data-shortlist]');
    if(shortlist){document.querySelector(`input[name="base"][value="${shortlist.dataset.shortlist}"]`).checked=true;$('#choice-status').textContent=shortlist.dataset.shortlist+' selected locally. Add any notes, then queue your direction.';$('#choose').scrollIntoView({behavior:matchMedia('(prefers-reduced-motion:reduce)').matches?'instant':'smooth'});return;}
    const info=e.target.closest('[data-info]');
    if(info){const phone=info.closest('.phone');const message=phone.querySelector('.inline-message');if(message){message.textContent=info.dataset.info==='refresh'?'Design preview: the saved example stays unchanged. No activity is fetched.':info.dataset.info==='friend'?'Week in motion: you have 18,420 of 50,000 steps saved; Sam has 21,200 of 60,000. Sep 18–24. $20 simulated each; fee $0.':'Sam’s invitation is part of the current Signal walkthrough. This study previews visual themes; it does not accept an invitation.';message.scrollIntoView({block:'nearest'});}}
  });
  $('#choice-form').addEventListener('submit',e=>{
    e.preventDefault();
    const data=new FormData(e.currentTarget),base=data.get('base'),keep=data.getAll('keep'),note=data.get('note').trim();
    const prompt=`Develop the next GameTime design exploration from ${base}. ${keep.length?'Keep or borrow: '+keep.join(', ')+'. ':''}${note?'My feedback: '+note+' ':''}Continue from the current Signal mockup and this theme study. Keep Robinhood inspiration excluded. This is a request for further design exploration, not approval to implement or migrate the native app.`;
    if(!window.lavish?.queuePrompt){$('#choice-status').textContent='Open this page in Lavish to queue feedback, or send your selection in the chat: '+base+(note?' — '+note:'');return;}
    window.lavish.queuePrompt(prompt,{tag:'design-direction',text:'Next direction: '+base,element:e.currentTarget,queueKey:'signal-theme-direction',data:{base,keep,note}});
    $('#choice-status').textContent='Queued: '+base+'. Use Send to Agent in Lavish to send it. Browsing the themes will not change this answer.';
  });
  setTheme('all');render();
})();
