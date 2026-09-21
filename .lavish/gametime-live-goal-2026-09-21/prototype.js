(() => {
  'use strict';
  const paths = {
    home: '<path d="M3 10.5 12 3l9 7.5V21h-6v-7H9v7H3z"/>',
    flag: '<path d="M5 22V3m0 0c5-4 9 4 15 0v11c-6 4-10-4-15 0"/>',
    user: '<circle cx="12" cy="7" r="4"/><path d="M4 22v-3a8 8 0 0 1 16 0v3"/>',
    arrow: '<path d="m9 5 7 7-7 7M3 12h13"/>',
    chevron: '<path d="m9 5 7 7-7 7"/>',
    back: '<path d="m15 5-7 7 7 7"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    close: '<path d="m6 6 12 12M6 18 18 6"/>',
    watch: '<rect x="6" y="5" width="12" height="14" rx="4"/><path d="M9 5V2h6v3M9 19v3h6v-3m-3-9V9m0 4 3 2"/>',
    shield: '<path d="M12 2 3 6v6c0 5 9 10 9 10s9-5 9-10V6z"/><path d="m8 12 3 3 5-6"/>',
    dollar: '<path d="M12 2v20m5-15c-2-3-10-3-10 1 0 5 10 2 10 7 0 4-8 4-11 1"/>',
    lock: '<rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V6a4 4 0 0 1 8 0v4m-4 5v2"/>',
    settings: '<path d="m9.5 3 .5-2h4l.5 2 2 .9 2-.6 2 3.5-1.5 1.5.2 2.2L21 12v4l-2.2.6-.9 1.7.7 2-3.5 2-1.6-1.6-2 .1-1.1 2.2H7l-.5-2.2-1.8-1-2 .5-2-3.4 1.6-1.5-.1-2.1L0 13V9l2.2-.6.9-1.8-.6-2 3.4-2 1.6 1.5z" transform="translate(2 0) scale(.86)"/><circle cx="12" cy="12" r="3.5"/>',
    run: '<circle cx="15" cy="4" r="2"/><path d="m4 21 6-6-2-4 5-4 3 4h5M4 10h4l2-3m3 7 4 3v5"/>',
    steps: '<ellipse cx="8" cy="7" rx="3" ry="5" transform="rotate(-20 8 7)"/><ellipse cx="16" cy="15" rx="3" ry="5" transform="rotate(20 16 15)"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10v.2"/>',
    plus: '<path d="M12 4v16M4 12h16"/>'
  };
  const icon = name => `<svg class="icon ${name}-icon" viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.info}</svg>`;
  const portrait = (person, size = '') => `<span class="avatar-wrap" ${size ? `style="width:${size}px;height:${size}px"` : ''}><span class="avatar ${person}" role="img" aria-label="${person === 'alex' ? 'Alex' : person[0].toUpperCase() + person.slice(1)}’s portrait"></span></span>`;
  const status = () => `<div class="status-bar" aria-hidden="true"><span>9:41</span><span class="island"></span><div class="status-icons"><svg viewBox="0 0 17 15"><path d="M1 11h2v3H1zm4-3h2v6H5zm4-3h2v9H9zm4-4h2v13h-2z" fill="currentColor"/></svg><svg viewBox="0 0 16 15"><path d="M1 5a11 11 0 0 1 14 0M4 8a6.5 6.5 0 0 1 8 0M7 11a2 2 0 0 1 2 0" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg><svg class="battery" viewBox="0 0 26 14"><rect x="1" y="2" width="21" height="10" rx="3" stroke="currentColor" fill="none" opacity=".5"/><rect x="3" y="4" width="17" height="6" rx="1" fill="currentColor"/><path d="M24 5v4" stroke="currentColor" stroke-width="2" opacity=".6"/></svg></div></div>`;
  const appNav = screen => `<nav class="tab-bar" aria-label="App tabs">${[['home','Home','home'],['challenges','Challenges','flag'],['you','You','user']].map(([key,label,symbol]) => `<button data-route="${key}" ${screen === key || key === 'home' && screen === 'goal' ? 'aria-current="page"' : ''}>${icon(symbol)}<span>${label}</span></button>`).join('')}</nav><div class="home-indicator" aria-hidden="true"></div>`;
  const phones = [...document.querySelectorAll('[data-phone]')];
  const states = new Map();
  let missing = false;
  let lastTrigger = null;
  const sampleFriends = [
    { id:'sam', name:'Sam', value:'7.8', target:'20', fraction:.39, status:'On track', dates:['saved','saved'] },
    { id:'jordan', name:'Jordan', value:'1.2', target:'15', fraction:.08, status:'Behind', dates:['saved','unknown'] },
    { id:'priya', name:'Priya', value:'10', target:'10', fraction:1, status:'Done', dates:['saved','unknown'] }
  ];
  function friendTile(friend) {
    return `<button class="friend" data-sheet="friend-${friend.id}" aria-label="${friend.name}: ${friend.status}. ${friend.value} of ${friend.target} kilometres saved."><span class="portrait-ring"><svg viewBox="0 0 64 64" aria-hidden="true"><circle cx="32" cy="32" r="30"/><circle cx="32" cy="32" r="30" stroke-dasharray="${188.5 * friend.fraction} 188.5"/></svg><span class="avatar ${friend.id}" aria-hidden="true"></span></span><b>${friend.name}</b><small ${friend.status === 'Done' ? 'class="is-done"' : ''}>${friend.status === 'Done' ? icon('check') : ''}${friend.status}</small></button>`;
  }
  function toolbar(label, back = false) {
    if(back) return `<header class="app-toolbar"><button class="icon-button" data-route="home" aria-label="Back to Home">${icon('back')}</button><span class="toolbar-label">${label}</span><span class="toolbar-end"></span></header>`;
    return `<header class="app-toolbar"><span class="app-logo">GameTime</span><button class="profile-shortcut" data-route="you" aria-label="Your record">${portrait('alex')}</button></header>`;
  }
  function home() {
    return toolbar() + `<div class="inset ${missing ? 'unknown' : ''}"><header class="home-head"><h2 class="app-title">September runs</h2><p class="meta meta-line"><span>Sep 21–27</span><span class="state-tag">${missing ? 'Waiting for activity' : 'On track'}</span></p></header><section class="hero-progress" aria-label="Your saved distance"><p class="metric-label">Your distance</p><div class="metric-line"><strong class="metric-value">${missing ? '—' : '6.4'}</strong><span class="metric-target">/ 20 km</span></div><div class="progress-rail" role="img" aria-label="${missing ? 'No saved distance is available' : '6.4 of 20 kilometres saved, 32 percent'}"><span></span></div><div class="rail-caption"><strong>${missing ? 'No update yet' : '32% complete'}</strong><span>Ends Sunday</span></div>${missing ? '<p class="unknown-message">Try Refresh after your Watch syncs. Missing activity isn’t a missed goal.</p>' : ''}</section><section class="friend-block"><div class="mini-heading"><h3>With you</h3><button data-sheet="week" aria-label="Your private group of 3 friends">3 friends ${'↗'}</button></div><div class="friends">${sampleFriends.map(friendTile).join('')}</div></section><div class="home-bottom"><p class="stake-line">$20 simulated · fee $0</p><button class="primary-button" data-route="goal">View goal ${icon('arrow')}</button><p class="sync-line">${icon('watch')}${missing ? 'Apple Health · no saved update' : 'Apple Health · updated 9:40 AM'}</p></div></div>`;
  }
  const fullRules = () => `<details class="disclosure"><summary>Full rules</summary><div class="rules-copy"><p><strong>Your goal.</strong> Save at least 20 km of eligible outdoor running during September 21–27, 2026. Sam’s goal is 20 km, Jordan’s is 15 km, and Priya’s is 10 km. Each person follows their own agreed goal.</p><p><strong>What counts.</strong> Outdoor runs recorded in Apple’s Workout app on Apple Watch and shared through Apple Health. Each whole run must start and finish within the challenge. Manual entries and unsupported sources don’t count.</p><p><strong>Dates.</strong> This example’s rules were agreed on September 19. The challenge starts September 21 at 12:00 AM and ends September 28 at 12:00 AM. Initial updates close September 29 at 12:00 AM; corrections close September 30 at 12:00 AM. All times are Pacific Time (Los Angeles).</p><p><strong>Your result.</strong> Reaching your goal can confirm success. Missing or incomplete activity alone never proves a miss. We return your simulated stake if the result can’t be confirmed. Fewer than two remaining participants with a confirmed result means the challenge won’t count and all simulated stakes return.</p><p><strong>Your stake.</strong> Your optional $20 simulated stake applies only to your result. Meeting your goal returns it; a confirmed miss uses it up in simulation. No friend receives it. There is no shared pot or prize. Fee $0. Nothing can be paid out or redeemed. No real money moves.</p><p><strong>Review.</strong> You have 48 full hours after we show your result notice to ask us to review it. We pause the simulated consequence during review. The reviewer has 72 hours from your request. Delayed notices never shorten your review time.</p><p><strong>Leaving.</strong> You may leave before the result is final, including if you need to rest or recover. Your simulated stake returns. Your agreement stays in your history. If fewer than two people remain, the challenge won’t count.</p><p><strong>Sharing.</strong> Only your agreed group sees the challenge progress you choose to share. Your wider record stays private. Sharing a result needs a separate choice. Changes to people, goals, or rules require everyone to agree again.</p></div></details>`;
  function goal() {
    return toolbar('Your goal',true) + `<div class="inset"><header class="goal-head"><h2 class="app-title">September runs</h2><p class="goal-subtitle"><b>20 km</b><span>over 7 days · Sep 21–27</span></p></header><section class="verdict-card" aria-label="Your rules at a glance"><div class="verdict-row">${icon('watch')}<div><h3>What counts</h3><strong>Apple Watch outdoor runs</strong><p>Use Apple’s Workout app.</p></div></div><div class="verdict-row">${icon('shield')}<div><h3>If you miss</h3><strong>Only a confirmed miss counts.</strong><p>Missing data alone never counts against you.</p></div></div><div class="verdict-row">${icon('dollar')}<div><h3>Your stake</h3><strong>$20 simulated · fee $0</strong><p>A confirmed miss uses your stake.<br>No shared pot. No real money moves.</p></div></div></section><section class="timeline-section"><h3>From start to result</h3><p>Rules lock when everyone agrees · Pacific Time</p><ol class="timeline"><li><b>Agreed</b><span>Sep 19</span></li><li><b>Start</b><span>Sep 21<br>12 AM</span></li><li><b>End</b><span>Sep 28<br>12 AM</span></li><li><b>Corrections</b><span>Sep 30<br>12 AM</span></li></ol></section>${fullRules()}<div class="goal-footer"><button class="text-button" data-sheet="leave">Leave challenge</button><button class="text-button" data-sheet="refresh">Refresh activity</button></div></div>`;
  }
  const moments = {
    steps: { title:'September steps', date:'SEP 7–13, 2026', outcome:'Both goals met', value:'52,480', unit:'steps', target:'Your goal: 50,000', friend:'sam' },
    runs: { title:'A week outside', date:'AUG 24–30, 2026', outcome:'Your goal met', value:'12.8', unit:'km', target:'Your goal: 12 km' }
  };
  function moment(key) {
    const m=moments[key];
    return `<button class="moment" data-sheet="result-${key}" aria-label="${m.title}, ${m.outcome}. Open finished challenge."><div class="moment-date"><span>${m.date}</span>${icon('check')}</div><h3>${m.title}</h3><p class="moment-outcome">${m.outcome}</p><div class="moment-metric"><div><b>${m.value}<span>${m.unit}</span></b><p>${m.target}</p></div>${m.friend ? `<div class="paired-portraits">${portrait('alex')}${portrait(m.friend)}</div>` : icon('run')}</div></button>`;
  }
  function you() {
    return `<header class="app-toolbar"><span class="you-title">You</span><button class="icon-button" data-sheet="settings" aria-label="Settings">${icon('settings')}</button></header><div class="inset"><div class="profile-header">${portrait('alex')}<div><h2>Alex Lee</h2><p class="meta">@alexlee</p></div></div><div class="record-heading"><h3>Your record</h3><span>2026</span></div><p class="record-summary">2 goals met · 3 finished challenges</p>${moment('steps')}${moment('runs')}<button class="moment simple" data-sheet="result-closed"><div class="moment-date"><span>AUG 10–16, 2026</span></div><h3>Midday steps</h3><p class="moment-outcome">Closed early · no missed goal</p></button><p class="record-privacy">Your record is private until you choose to share.</p></div>`;
  }
  function challenges() {
    return toolbar() + `<div class="inset"><header class="home-head"><h2 class="app-title">Challenges</h2><p class="meta" style="margin-top:9px">Your goals, from start to finish.</p></header><p class="list-group-title">ACTIVE</p><button class="challenge-row" data-route="goal"><div><h3>September runs</h3><p>With Sam, Jordan & Priya · Sep 21–27</p><p style="margin-top:8px">${missing ? 'No saved activity yet' : '6.4 / 20 km · On track'}</p>${missing ? '' : '<div class="challenge-small-progress"><span></span></div>'}</div>${icon('chevron')}</button><p class="list-group-title">FINISHED</p>${Object.entries(moments).map(([key,m])=>`<button class="challenge-row" data-sheet="result-${key}"><div><h3>${m.title}</h3><p>${m.outcome} · ${m.date.replace(', 2026','').toLowerCase()}</p></div>${icon('chevron')}</button>`).join('')}<button class="challenge-row" data-sheet="result-closed"><div><h3>Midday steps</h3><p>Closed early · Aug 10–16</p></div>${icon('chevron')}</button><button class="quiet-button" data-sheet="create">${icon('plus')} Create a challenge</button></div>`;
  }
  function renderPhone(phone, route, focus=false) {
    const functions={home,goal,you,challenges};
    if(!functions[route]) return;
    states.set(phone,route);
    phone.innerHTML=status()+`<div class="screen-body" tabindex="0" aria-label="${route === 'goal' ? 'Goal and rules' : route[0].toUpperCase()+route.slice(1)} screen">${functions[route]()}</div>`+appNav(route);
    phone.dataset.screen=route;
    if(focus) phone.querySelector('.screen-body').focus({preventScroll:true});
  }
  function statsRow(person,name,value,target) {
    return `<div class="sheet-stat">${portrait(person)}<div><strong>${name}</strong><span>${target}</span></div><b>${value}</b></div>`;
  }
  function weekGrid() {
    const rows=[{id:'alex',name:'You',dates:missing?['unknown','unknown']:['saved','saved']},...sampleFriends];
    return `<div class="week-grid" role="img" aria-label="Saved run days, September 21 through 27. ${missing ? "Your activity has no saved update. Sam has runs saved on Monday and Tuesday." : "You and Sam have runs saved on Monday and Tuesday."} Jordan and Priya have a Monday run saved. No update is not a missed day."><span></span>${['M','T','W','T','F','S','S'].map(d=>`<span>${d}</span>`).join('')}${rows.map(r=>`<span class="week-name">${r.name}</span>${[...r.dates,'future','future','future','future','future'].map(d=>`<span class="day-cell ${d === 'saved' ? 'saved' : ''}">${d === 'saved' ? icon('check') : d === 'unknown' ? '?' : '·'}</span>`).join('')}`).join('')}</div>`;
  }
  function sheetContent(kind) {
    if(kind.startsWith('friend-')) {
      const f=sampleFriends.find(f=>f.id === kind.slice(7));
      return {title:f.name,content:`<p class="sheet-kicker">September runs</p><div class="sheet-stats">${statsRow(f.id,f.name,`${f.value} km`,`Goal: ${f.target} km · ${f.status}`)}</div><p>Last saved update: September 22 at 9:40 AM.</p><div class="notice"><strong>${f.status === 'Done' ? 'Goal reached' : 'A guide to progress'}</strong>${f.status === 'Done' ? 'Priya has reached her distance goal. The shared challenge continues through Sunday.' : 'On track and Behind compare saved distance with the time passed. They are pace estimates, not final results. A missing update is shown separately.'}</div><p>Only the progress shared with this challenge is shown here.</p><button class="quiet-button" data-sheet="week">See the shared week</button>`};
    }
    if(kind === 'week') return {title:'The shared week',content:`<p class="sheet-kicker">September runs · Sep 21–27</p>${weekGrid()}<p>A check means at least one run was saved that day. A question mark means no saved update; it does not mean a missed day. Dots are days ahead.</p><div class="notice"><strong>A weekly goal, at your pace.</strong>You can reach your distance on the days that work for you. There is no daily streak to keep.</div><p>Each person chooses to share this view with the group. Activity routes and private notes stay private.</p>`};
    if(kind === 'settings') return {title:'Settings',content:`<div class="setting-row"><span>Apple Health</span><span>${missing ? 'No saved update' : 'Connected'}</span></div><button class="setting-row setting-link" data-sheet="sharing"><span>Sharing & privacy</span>${icon('chevron')}</button><button class="setting-row setting-link" data-sheet="reminders"><span>Reminders</span><span>Off ${'›'}</span></button><details class="disclosure" open><summary>Simulated stakes</summary><div class="rules-copy"><p>No real money moves. Stakes are optional and apply only to your own result. There are no shared pots, transfers, prizes, or cash withdrawals.</p><p>Your stake and fee appear before you agree to each challenge, and beside its result.</p></div></details><button class="setting-row setting-link" data-sheet="support"><span>Help & support</span>${icon('chevron')}</button><button class="setting-row setting-link" data-sheet="account"><span>Account</span>${icon('chevron')}</button>`};
    if(kind === 'sharing') return {title:'Sharing & privacy',content:'<p>Your record is private. September runs shares only its agreed goal, saved progress, status, and result with Sam, Jordan, and Priya.</p><p>Sharing a finished result is a separate choice. Your routes, private notes, and wider activity history stay private.</p><div class="notice"><strong>Design preview</strong>These example sharing choices do not change an account.</div>'};
    if(kind === 'reminders') return {title:'Reminders',content:'<p>Reminders are off in this example. Before enabling them, you would choose the updates you want and when to receive them.</p><p>Optional friend updates and near-deadline reminders need your explicit choice. They never tell you to exercise to protect a stake.</p>'};
    if(kind === 'support') return {title:'Help & support',content:'<p>From a result notice, choose Ask for review before the shown deadline. Your review window lasts 48 full hours after the actual notice.</p><p>During review, we pause any simulated consequence.</p><div class="notice"><strong>Design preview</strong>No support message or review request is sent from this study.</div>'};
    if(kind === 'account') return {title:'Your account',content:`<div class="profile-header">${portrait('alex')}<div><h2>Alex Lee</h2><p class="meta">@alexlee</p></div></div><p>This is a fictional profile used to review the layout. Account editing, sign-out, and deletion belong here in the native app.</p>`};
    if(kind === 'result-steps') return {title:'September steps',content:`<p class="sheet-kicker">September 7–13, 2026</p><h3 class="app-title">Both goals met.</h3><div class="sheet-stats">${statsRow('alex','You','52,480','50,000-step goal')}${statsRow('sam','Sam','61,200','60,000-step goal')}</div><p>Result confirmed September 19.<br>Review complete.</p><div class="notice"><strong>$20 simulated returned · fee $0</strong>Your own stake returned. No money moved. Nothing can be paid out or redeemed.</div><p>Shared within this challenge only. Your wider record stays private.</p>`};
    if(kind === 'result-runs') return {title:'A week outside',content:`<p class="sheet-kicker">August 24–30, 2026</p><h3 class="app-title">Your goal met.</h3><div class="sheet-stats">${statsRow('alex','You','12.8 km','12 km goal')}</div><p>Outdoor runs from Apple Watch.<br>Result confirmed September 5.</p><div class="notice"><strong>No stake</strong>You chose to take part without a simulated stake. Fee $0.</div><p>This goal stays in your record with the same treatment as any other completed goal.</p>`};
    if(kind === 'result-closed') return {title:'Midday steps',content:'<p class="sheet-kicker">August 10–16, 2026</p><h3 class="app-title">Closed early.</h3><p>You left this challenge on August 12. It does not count as a missed goal.</p><div class="notice"><strong>$20 simulated returned · fee $0</strong>No real money moved. Your agreement stays in your record.</div><p>You can choose a new goal whenever it works for you.</p>'};
    if(kind === 'leave') return {title:'Leave this challenge?',content:'<p>You can leave before the result is final. Your $20 simulated stake returns, with no fee. This challenge stays in your record and does not count as a missed goal.</p><p>The group continues only if at least two people remain. Otherwise the challenge closes and everyone’s simulated stake returns.</p><div class="notice"><strong>Design preview</strong>This sheet shows the exit explanation. It cannot end a real challenge.</div><button class="quiet-button" data-close>Keep viewing challenge</button>'};
    if(kind === 'refresh') return {title:missing ? 'No saved update yet' : 'Your activity is up to date',content:`<p>${missing ? 'Open Apple Health after your Watch syncs, then return and try Refresh. Missing activity alone never means you missed your goal.' : '6.4 km saved from eligible Apple Watch outdoor runs. Last updated September 22 at 9:40 AM.'}</p><div class="notice"><strong>Design preview</strong>The examples in this study do not fetch activity from Apple Health.</div>`};
    if(kind === 'create') return {title:'A new challenge',content:'<p>Set a goal and dates, choose friends, review the full agreement, then commit. Each friend deliberately agrees to their own goal and optional simulated stake.</p><div class="notice"><strong>Design scope</strong>This study covers active Home, goal rules, and your record. The creation flow is mapped below the three screens.</div>'};
    return {title:'GameTime',content:'<p>Open one of the three design screens to continue.</p>'};
  }
  function closeSheet(phone, restore = true) {
    const backdrop=phone.querySelector('.sheet-backdrop');
    if(!backdrop) return;
    phone.querySelectorAll(':scope > .screen-body,:scope > .tab-bar').forEach(node=>node.inert=false);
    backdrop.remove();
    if(restore && lastTrigger?.isConnected) lastTrigger.focus({preventScroll:true});
  }
  function openSheet(phone,kind,trigger) {
    const hadSheet=!!phone.querySelector('.sheet-backdrop');
    closeSheet(phone,false);
    if(!hadSheet) lastTrigger=trigger;
    const data=sheetContent(kind);
    const backdrop=document.createElement('div');
    backdrop.className='sheet-backdrop';
    const label=`sheet-${phone.dataset.phone}`;
    backdrop.innerHTML=`<section class="sheet-panel" role="dialog" aria-modal="true" aria-labelledby="${label}" tabindex="-1"><header class="sheet-header"><h2 id="${label}">${data.title}</h2><button class="sheet-close" data-close aria-label="Close ${data.title.replaceAll('"','')}">${icon('close')}</button></header><div class="sheet-content">${data.content}</div></section>`;
    phone.append(backdrop);
    phone.querySelectorAll(':scope > .screen-body,:scope > .tab-bar').forEach(node=>node.inert=true);
    if(document.documentElement.classList.contains('keyboard')) backdrop.style.setProperty('transition','none');
    if(document.documentElement.classList.contains('keyboard')) backdrop.querySelector('.sheet-panel').style.setProperty('transition','none');
    requestAnimationFrame(()=>{backdrop.classList.add('open');backdrop.querySelector('.sheet-close').focus({preventScroll:true});});
  }
  document.addEventListener('click',event=>{
    const phone=event.target.closest('[data-phone]');
    if(!phone) return;
    const close=event.target.closest('[data-close]');
    if(close || event.target.classList.contains('sheet-backdrop')) return closeSheet(phone);
    const sheet=event.target.closest('[data-sheet]');
    if(sheet) return openSheet(phone,sheet.dataset.sheet,sheet);
    const nav=event.target.closest('[data-route]');
    if(nav) renderPhone(phone,nav.dataset.route,true);
  });
  document.addEventListener('keydown',event=>{
    document.documentElement.classList.add('keyboard');
    const dialog=event.target.closest('.sheet-panel');
    if(!dialog) return;
    if(event.key === 'Escape'){event.preventDefault();closeSheet(dialog.closest('[data-phone]'));}
    if(event.key === 'Tab'){
      const focusable=[...dialog.querySelectorAll('button,a[href],summary,input,select,[tabindex="0"]')].filter(el=>el.getClientRects().length);
      const first=focusable[0],last=focusable.at(-1);
      if(event.shiftKey && document.activeElement === first){event.preventDefault();last.focus();}
      if(!event.shiftKey && document.activeElement === last){event.preventDefault();first.focus();}
    }
  });
  document.addEventListener('pointerdown',()=>document.documentElement.classList.remove('keyboard'));
  function reset(){phones.forEach(phone=>renderPhone(phone,phone.dataset.initial));}
  document.querySelector('#reset')?.addEventListener('click',()=>{
    missing=false;document.body.classList.remove('large-text');
    document.querySelector('#missing-data').checked=false;document.querySelector('#large-text').checked=false;reset();
  });
  document.querySelector('#large-text')?.addEventListener('change',event=>document.body.classList.toggle('large-text',event.target.checked));
  document.querySelector('#missing-data')?.addEventListener('change',event=>{
    missing=event.target.checked;phones.forEach(phone=>renderPhone(phone,states.get(phone)));
  });
  const params=new URLSearchParams(location.search);
  if(document.body.classList.contains('standalone')){
    phones[0].dataset.initial=['home','goal','you','challenges'].includes(params.get('screen')) ? params.get('screen') : 'home';
    if(params.get('large') === '1') document.body.classList.add('large-text');
    missing=params.get('missing') === '1';
  }
  reset();
})();
