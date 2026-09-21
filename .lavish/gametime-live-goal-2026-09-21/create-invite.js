(() => {
  'use strict';
  const paths = {
    arrow:'<path d="m9 5 7 7-7 7M3 12h13"/>', chevron:'<path d="m9 5 7 7-7 7"/>', back:'<path d="m15 5-7 7 7 7"/>',
    check:'<path d="m5 12 4 4L19 6"/>', close:'<path d="m6 6 12 12M6 18 18 6"/>',
    watch:'<rect x="6" y="5" width="12" height="14" rx="4"/><path d="M9 5V2h6v3M9 19v3h6v-3m-3-9V9m0 4 3 2"/>',
    shield:'<path d="M12 2 3 6v6c0 5 9 10 9 10s9-5 9-10V6z"/><path d="m8 12 3 3 5-6"/>',
    dollar:'<path d="M12 2v20m5-15c-2-3-10-3-10 1 0 5 10 2 10 7 0 4-8 4-11 1"/>',
    lock:'<rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V6a4 4 0 0 1 8 0v4m-4 5v2"/>',
    run:'<circle cx="15" cy="4" r="2"/><path d="m4 21 6-6-2-4 5-4 3 4h5M4 10h4l2-3m3 7 4 3v5"/>',
    steps:'<ellipse cx="8" cy="7" rx="3" ry="5" transform="rotate(-20 8 7)"/><ellipse cx="16" cy="15" rx="3" ry="5" transform="rotate(20 16 15)"/>',
    plus:'<path d="M12 4v16M4 12h16"/>', calendar:'<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v4m10-4v4M3 10h18"/>',
    search:'<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
    people:'<circle cx="9" cy="8" r="3.5"/><path d="M2 21v-3a7 7 0 0 1 14 0v3m1-16a3.5 3.5 0 0 1 0 7m2 3a5 5 0 0 1 3 5v1"/>',
    link:'<path d="m10 14 4-4m-6 7-1 1a4.2 4.2 0 0 1-6-6l4-4a4.2 4.2 0 0 1 6 0m2-1 1-1a4.2 4.2 0 0 1 6 6l-4 4a4.2 4.2 0 0 1-6 0" transform="translate(1 0)"/>',
    edit:'<path d="m15 3 6 6M3 21l5-1L21 7a2 2 0 0 0-4-4L4 16z"/>'
  };
  const icon = n => `<svg class="icon ${n}-icon" viewBox="0 0 24 24" aria-hidden="true">${paths[n] || paths.check}</svg>`;
  const esc = v => String(v).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const people = [{id:'sam',name:'Sam',note:'From your contacts'},{id:'jordan',name:'Jordan',note:'From your contacts'},{id:'priya',name:'Priya',note:'From your contacts'}];
  const portrait = (id,size=42) => `<span class="avatar-wrap" style="width:${size}px;height:${size}px"><span class="avatar ${id}" role="img" aria-label="${people.find(p=>p.id===id)?.name || 'Alex'}’s portrait"></span></span>`;
  const status = `<div class="status-bar" aria-hidden="true"><span>9:41</span><div class="status-icons"><svg viewBox="0 0 17 15"><path d="M1 11h2v3H1zm4-3h2v6H5zm4-3h2v9H9zm4-4h2v13h-2z" fill="currentColor"/></svg><svg viewBox="0 0 16 15"><path d="M1 5a11 11 0 0 1 14 0M4 8a6.5 6.5 0 0 1 8 0M7 11a2 2 0 0 1 2 0" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg><svg class="battery" viewBox="0 0 26 14"><rect x="1" y="2" width="21" height="10" rx="3" stroke="currentColor" fill="none" opacity=".5"/><rect x="3" y="4" width="17" height="6" rx="1" fill="currentColor"/><path d="M24 5v4" stroke="currentColor" stroke-width="2" opacity=".6"/></svg></div></div>`;
  const states = new Map();
  const params = new URLSearchParams(location.search);
  const unit = s => s.activity==='steps'?'steps':'km';
  const fmt = (value,options={month:'short',day:'numeric'}) => new Intl.DateTimeFormat('en-US',{...options,timeZone:'UTC'}).format(new Date(value+'T12:00:00Z'));
  const dayCount = s => Math.round((Date.parse(s.end)-Date.parse(s.start))/86400000)+1;
  const addDays = (value,n) => {const d=new Date(value+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
  const dates = s => `${fmt(s.start)}–${fmt(s.end)}`;
  const stake = s => s.stake ? `$${s.stake} simulated · fee $0` : 'No stake · fee $0';
  const target = s => Number(s.target).toLocaleString('en-US');
  const title = s => s.name.trim() || (s.activity==='steps'?'October steps':'October runs');
  function track(step){return `<div class="steps-track" aria-label="Step ${step+1} of 3">${['Goal','Challenge','Friends'].map((name,i)=>`<span class="${i===step?'current':i<step?'complete':''}" ${i===step?'aria-current="step"':''}><i>${i<step?icon('check'):i+1}</i>${name}</span>`).join('')}</div>`;}
  function goal(s){
    const count=dayCount(s);
    let days='';
    if(count<=7){ for(let i=0;i<count;i++){const d=new Date(s.start+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+i);days+=`<span>${new Intl.DateTimeFormat('en-US',{weekday:'narrow',timeZone:'UTC'}).format(d)}<b>${d.getUTCDate()}</b></span>`;} }
    return `${track(0)}<h2 class="create-title" tabindex="-1">What’s your goal?</h2>
    <div class="activity-options" aria-label="Activity"><button data-activity="runs" aria-pressed="${s.activity==='runs'}">${icon('run')}Outdoor runs</button><button data-activity="steps" aria-pressed="${s.activity==='steps'}">${icon('steps')}Steps</button></div>
    <section class="target-card"><label class="target-label" for="target-${s.id}"><span>${s.activity==='steps'?'Your steps':'Your distance'}</span>${icon('edit')}</label><div class="target-line"><input class="target-number ${s.activity==='steps'?'steps-number':''}" id="target-${s.id}" type="text" inputmode="decimal" value="${esc(s.target)}" aria-label="Your target in ${unit(s)}" maxlength="6"><span>${unit(s)}</span></div><div class="target-footer"><span>Over ${count} days</span><span>${s.activity==='runs'?'Apple Watch':'Apple Health'}</span></div></section>
    <section class="date-section"><div class="section-label"><h3>Your dates</h3><span>${count} days</span></div><button class="date-range" data-action="dates" aria-label="Edit start and end dates"><span class="date-endpoints"><div><small>Starts ${fmt(s.start,{weekday:'short'})}</small><strong>${fmt(s.start)}</strong></div>${icon('arrow')}<div><small>Ends ${fmt(s.end,{weekday:'short'})}</small><strong>${fmt(s.end)}</strong></div></span>${days?`<span class="date-days" style="grid-template-columns:repeat(${count},minmax(0,1fr))">${days}</span>`:''}</button><p class="date-note">${icon('calendar')}2026 · Pacific Time</p></section><p class="flow-error" role="alert"></p>`;
  }
  function agreement(s){
    return `${track(1)}<h2 class="create-title" tabindex="-1">Make it a<br>challenge.</h2><p class="agreement-date">${target(s)} ${unit(s)} · ${dates(s)}</p>
    <label class="name-field"><span>Name <small>Optional</small></span><input data-name value="${esc(s.name)}" placeholder="${s.activity==='steps'?'October steps':'October runs'}" maxlength="36" aria-label="Challenge name"></label>
    <div class="private-line">${icon('lock')}<div><strong>Private challenge</strong><span>Only invited friends</span></div></div>
    <div class="agreement-intro"><h3>Your agreement</h3></div>
    <div class="agreement-modules"><section class="agreement-module"><span class="agreement-icon">${icon(s.activity==='runs'?'watch':'steps')}</span><div><h3>What counts</h3><strong>${s.activity==='runs'?'Apple Watch outdoor runs':'Steps from Apple Health'}</strong></div></section><section class="agreement-module"><span class="agreement-icon">${icon('shield')}</span><div><h3>If you miss</h3><strong>Only a confirmed miss counts</strong></div></section><button class="agreement-module stake-edit" data-action="stake" aria-label="Change your optional simulated stake"><span class="agreement-icon">${icon('dollar')}</span><div><h3>Your stake <span aria-hidden="true">· Optional</span></h3><strong>${stake(s)}</strong></div>${icon('chevron')}</button></div>
    <p class="simulation-note">No real money moves.</p><button class="full-rules-link" data-action="rules">Full rules${icon('chevron')}</button>`;
  }
  function selected(s){const rows=people.filter(p=>s.selected.has(p.id));return rows.length?rows.map(p=>`<button class="selected-friend" data-friend="${p.id}" aria-label="Remove ${p.name}"><span class="selection-ring"><span class="avatar ${p.id}" aria-hidden="true"></span></span><span class="remove-dot">${icon('close')}</span><b>${p.name}</b></button>`).join(''):`<div class="empty-selection"><span class="round-control">${icon('people')}</span><span>Pick a few friends<br>to do this with.</span></div>`;}
  function friendRows(s){return people.map(p=>`<button class="friend-select" data-friend="${p.id}" data-search="${p.name.toLowerCase()}" aria-pressed="${s.selected.has(p.id)}" aria-label="${s.selected.has(p.id)?'Remove':'Select'} ${p.name}">${portrait(p.id)}<span><strong>${p.name}</strong><small>${p.note}</small></span><span class="selection-check">${icon('check')}</span></button>`).join('');}
  function invite(s){return `${track(2)}<h2 class="create-title" tabindex="-1">Invite friends.</h2><p class="create-subtitle">Choose up to 5 friends.</p>
    <div class="selected-summary"><strong>Selected friends</strong><span data-count>${s.selected.size} of 5</span></div><div class="selected-faces">${selected(s)}</div>
    <label class="search-friends">${icon('search')}<input type="search" placeholder="Find a friend" aria-label="Find a friend" data-search-input></label><div class="friends-list">${friendRows(s)}<p class="contact-empty" hidden>No match yet.<br>Try another name or choose from Contacts.</p></div><button class="contact-add" data-action="contacts">${icon('people')}Choose from Contacts${icon('chevron')}</button>
    <div class="invite-share"><span>${icon('link')}Invitation link</span><div><button class="small-secondary" data-action="copy">Copy</button><button class="small-secondary" data-action="share">Share</button></div></div><p class="send-note">Each friend reviews their own goal<br>and agrees before joining.</p>`;}
  function confirm(s){return `<div class="confirm-content"><div class="confirm-mark">${icon('check')}</div><h2 class="create-title" tabindex="-1">Challenge ready.</h2><p class="create-subtitle">${s.selected.size} invitation${s.selected.size===1?'':'s'} sent.</p><section class="confirmation-hero"><h3>${esc(title(s))}</h3><p class="dates">${dates(s)} · ${dayCount(s)} days</p><div class="confirmed-target ${s.activity==='steps'?'steps-target':''}"><b style="${target(s).length>3?`font-size:${target(s).length>6?48:target(s).length>5?56:target(s).length>4?64:76}px`:``}">${target(s)}</b><span>${unit(s)}</span></div><p class="confirmed-goal-label">Your ${s.activity==='steps'?'step':'outdoor running'} goal</p><p class="confirmed-stake">${stake(s)}</p></section><section class="confirm-friends"><div class="section-label"><h3>Waiting for friends</h3><span>${icon('lock')}</span></div><div class="pending-friends">${people.filter(p=>s.selected.has(p.id)).map(p=>`<div class="pending-friend">${portrait(p.id,46)}<b>${p.name}</b><small>Invited</small></div>`).join('')}</div></section></div>`;}
  const screens={goal,challenge:agreement,invite,confirm};
  function render(phone,focus=false){
    const s=states.get(phone), step=['goal','challenge','invite'].indexOf(s.screen);
    phone.dataset.create=s.screen;
    phone.innerHTML=`${status}<nav class="create-nav" aria-label="Creation navigation">${step>0?`<button class="round-control nav-back" data-action="back" aria-label="Previous step">${icon('back')}</button>`:`<span>${s.screen==='confirm'?'Create challenge':'Create challenge'}</span>`}${step>0?'<span>Create challenge</span>':''}<button class="round-control" data-action="close" aria-label="Close creation">${icon('close')}</button></nav><div class="create-content">${screens[s.screen](s)}</div><footer class="flow-footer">${s.screen==='challenge'?'<p class="footer-note">Review with your friends before you lock it in.</p>':''}<button class="primary-button" data-action="next" ${s.screen==='invite'&&!s.selected.size?'disabled':''}>${s.screen==='goal'?'Continue':s.screen==='challenge'?'Continue to invite':s.screen==='invite'?`Send ${s.selected.size} invite${s.selected.size===1?'':'s'}`:'View challenge'}${icon('arrow')}</button>${s.screen==='confirm'?'<button class="secondary-wide" data-action="library">Back to Challenges</button>':''}</footer><div class="home-indicator" aria-hidden="true"></div><div class="sheet-backdrop" hidden><section class="sheet-panel" role="dialog" aria-modal="true" aria-label="Challenge options" tabindex="-1"></section></div>`;
    fitTarget(phone);
    if(focus)phone.querySelector('.create-title').focus({preventScroll:true});
  }
  function fitTarget(phone){const input=phone.querySelector('.target-number');if(!input)return;const n=input.value.length;input.style.fontSize=(n>5?50:n>4?60:n>3?70:n>2?88:108)+'px';input.style.width=(Math.max(2,n)+.2)+'ch';}
  function sheet(phone,titleText,body){
    const s=states.get(phone),overlay=phone.querySelector('.sheet-backdrop');
    if(overlay.hidden) s.trigger=document.activeElement;
    overlay.querySelector('.sheet-panel').innerHTML=`<header class="sheet-header"><h2>${titleText}</h2><button class="sheet-close" data-action="dismiss" aria-label="Close ${titleText}">${icon('close')}</button></header><div class="sheet-content">${body}</div>`;
    overlay.querySelector('.sheet-panel').setAttribute('aria-label',titleText);
    [...phone.children].filter(el=>el!==overlay).forEach(el=>el.inert=true);
    overlay.hidden=false;requestAnimationFrame(()=>{overlay.classList.add('open');overlay.querySelector('.sheet-close').focus({preventScroll:true});});
  }
  function dismiss(phone){const s=states.get(phone),overlay=phone.querySelector('.sheet-backdrop');overlay.classList.remove('open');overlay.hidden=true;[...phone.children].forEach(el=>el.inert=false);if(s.trigger?.isConnected)s.trigger.focus({preventScroll:true});}
  function toast(phone,msg){phone.querySelector('.toast')?.remove();const el=document.createElement('div');el.className='toast';el.setAttribute('role','status');el.textContent=msg;phone.append(el);setTimeout(()=>el.remove(),4500);}
  function rules(phone){const s=states.get(phone);sheet(phone,'Full rules',`<p>${esc(title(s))} · ${dates(s)}, 2026</p>${[
    ['Everyone’s goal',`${target(s)} ${unit(s)} across ${dayCount(s)} days. Each person follows their own agreed goal. Every friend reviews their target and the group before agreeing.`],
    ['What counts',s.activity==='runs'?'Record outdoor runs in Apple’s Workout app and share them through Apple Health. Each whole run must start and finish within these dates. Manual entries and unsupported sources don’t count.':'Steps saved to Apple Health during these dates. Missing or incomplete updates alone never prove a miss.'],
    ['Dates and times',`All dates use Pacific Time · Los Angeles. Starts ${fmt(s.start)}, 2026 at 12:00 AM. Ends ${fmt(addDays(s.end,1))}, 2026 at 12:00 AM; ${fmt(s.end)} is the last full day. First updates close ${fmt(addDays(s.end,2))} at 12:00 AM. Corrections close ${fmt(addDays(s.end,3))} at 12:00 AM. Results can settle from then, after your notice and any review.`],
    ['Your result','Reaching your goal can confirm success. Missing or incomplete activity alone never proves a miss. If we can’t confirm your result, your simulated stake returns. Fewer than two remaining people with confirmed results: the challenge won’t count and everyone’s simulated stake returns.'],
    ['Your stake',s.stake?`$${s.stake} simulated · fee $0. Optional; applies only to your own result. Goal met: your simulated stake returns. Confirmed miss after review: your simulated stake is used up. No friend receives it. No shared pot or prize. No payouts or redemption. No real money moves.`:'No stake · fee $0. No real money moves.'],
    ['Ask for review','Ask within 48 full hours after we show your result notice. We pause the simulated consequence during review. The reviewer has 72 hours from your request. A delayed notice never shortens your review time.'],
    ['Leave the challenge','You can leave to rest or recover any time before your result is final. Your simulated stake returns; this isn’t a missed goal. Your agreement stays in your history. Fewer than two people remain: the challenge won’t count.'],
    ['Sharing and changes','Share only the challenge progress you choose. Your wider record stays private. Sharing a result needs a separate choice. Changing people, goals or rules needs everyone’s agreement again.']
  ].map(([h,p],i)=>`<details class="rules-module" name="create-rules-${s.id}" ${i===0?'open':''}><summary>${h}</summary><p>${p}</p></details>`).join('')}`);}
  function contacts(phone){sheet(phone,'Find your friends',`<div class="contact-permission-symbol">${icon('people')}</div><h3 class="permission-title">Choose friends<br>from Contacts.</h3><p>You choose who to invite. Nothing is sent until you tap Send invites.</p><button class="primary-button" data-action="choose-contacts">Choose contacts${icon('arrow')}</button><button class="secondary-wide" data-action="dismiss">Not now</button>`);}
  function reference(phone,type){
    const wrap=document.createElement('div');wrap.className='reference-screen';wrap.innerHTML=`<img class="mock-reference" src="captures/${type==='library'?'challenges-library.png':'goal-modules.png'}" alt="Unchanged locked ${type==='library'?'Challenges library':'Goal'} reference. This existing example shows September runs, not a newly saved challenge."><button class="reference-return" data-action="return-reference">Return to create & invite</button>`;phone.append(wrap);wrap.querySelector('button').focus();
  }
  function refreshSelection(phone){const s=states.get(phone);phone.querySelector('.selected-faces').innerHTML=selected(s);phone.querySelector('[data-count]').textContent=`${s.selected.size} of 5`;phone.querySelectorAll('.friend-select').forEach(btn=>{const p=people.find(p=>p.id===btn.dataset.friend);btn.setAttribute('aria-pressed',s.selected.has(p.id));btn.setAttribute('aria-label',`${s.selected.has(p.id)?'Remove':'Select'} ${p.name}`);});const cta=phone.querySelector('[data-action=next]');cta.disabled=!s.selected.size;cta.innerHTML=`Send ${s.selected.size} invite${s.selected.size===1?'':'s'}${icon('arrow')}`;}
  function handle(phone,button){const s=states.get(phone),action=button.dataset.action;
    if(button.dataset.activity){s.activity=button.dataset.activity;s.target=s.activity==='runs'?20:50000;s.name=s.activity==='runs'?'October runs':'October steps';render(phone);phone.querySelector(`[data-activity=${s.activity}]`).focus({preventScroll:true});return;}
    if(button.dataset.friend){const id=button.dataset.friend;s.selected.has(id)?s.selected.delete(id):s.selected.add(id);const removedChip=button.classList.contains('selected-friend');refreshSelection(phone);if(removedChip)phone.querySelector(`.friend-select[data-friend=${id}]`).focus({preventScroll:true});return;}
    if(button.dataset.amount!==undefined){s.stake=Number(button.dataset.amount);dismiss(phone);render(phone);phone.querySelector('.stake-edit').focus({preventScroll:true});return;}
    if(action==='back'){s.screen=s.screen==='invite'?'challenge':'goal';render(phone,true);}
    if(action==='next'){
      if(s.screen==='goal'){
        const n=Number(s.target);if(!Number.isFinite(n)||n<=0||n>999999||(s.activity==='steps'&&!Number.isInteger(n))){phone.querySelector('.flow-error').textContent='Enter a target greater than zero to continue.';phone.querySelector('.target-number').focus();return;}
        s.screen='challenge';
      }else if(s.screen==='challenge')s.screen='invite';
      else if(s.screen==='invite'){if(!s.selected.size)return;s.screen='confirm';}
      else{sheet(phone,'View challenge',`<p>Your ${esc(title(s))} example is ready. The existing Goal design shows where this action leads.</p><p>This browser mock has not saved a challenge or sent invitations.</p><button class="primary-button" data-action="goal-reference">Open locked Goal reference${icon('arrow')}</button>`);return;}
      render(phone,true);
    }
    if(action==='stake')sheet(phone,'Your stake',`<p>Optional. A consequence for your goal only.</p>${[0,10,20].map(amount=>`<button class="sheet-option" data-amount="${amount}" aria-pressed="${s.stake===amount}"><span>${amount?`$${amount} <small>simulated · fee $0</small>`:'No stake'}</span>${icon('check')}</button>`).join('')}<p>No real money moves. Nothing goes to another friend.</p>`);
    if(action==='rules')rules(phone);
    if(action==='dates')sheet(phone,'Your dates',`<p>Whole days, in Pacific Time.</p><label class="sheet-date">Starts<input type="date" data-date="start" value="${s.start}" min="2026-09-23" max="2026-12-31"></label><label class="sheet-date">Ends<input type="date" data-date="end" value="${s.end}" min="2026-09-23" max="2026-12-31"></label><p class="flow-error" role="alert"></p><button class="primary-button" data-action="save-dates">Use these dates${icon('check')}</button>`);
    if(action==='save-dates'){const start=phone.querySelector('[data-date=start]').value,end=phone.querySelector('[data-date=end]').value;const count=dayCount({start,end});if(!start||!end||count<1||count>30||start<'2026-09-23'||end>'2026-12-31'){phone.querySelector('.sheet-content .flow-error').textContent='Choose 1–30 days between September 23 and December 31.';return;}s.start=start;s.end=end;dismiss(phone);render(phone);phone.querySelector('.date-range').focus({preventScroll:true});}
    if(action==='contacts')contacts(phone);
    if(action==='choose-contacts')sheet(phone,'Contacts preview',`<p>In the iPhone app, you would choose the contacts to share here. This mock doesn’t access your address book.</p><div class="notice"><strong>Sam, Jordan and Priya</strong>Fictional contacts for this preview.</div><button class="primary-button" data-action="dismiss">Back to friends${icon('arrow')}</button>`);
    if(action==='copy'||action==='share')sheet(phone,action==='copy'?'Copy invitation link':'Share invitation',`<p>Your friends review the goal and agree before joining. Sharing a link doesn’t accept an invitation.</p><p>This mock doesn’t create or send a real link.</p><button class="primary-button" data-action="demo-link">${action==='copy'?'Copy sample link':'Preview sharing'}${icon('link')}</button><p>Sample only: gametime.invalid/invite/october</p>`);
    if(action==='demo-link'){const isCopy=phone.querySelector('.sheet-header h2').textContent==='Copy invitation link';if(isCopy&&navigator.clipboard){navigator.clipboard.writeText('https://gametime.invalid/invite/october').then(()=>{dismiss(phone);toast(phone,'Sample link copied. This preview link cannot be used to join.');}).catch(()=>toast(phone,'Couldn’t copy. Select the sample link in this sheet to copy it.'));}else{dismiss(phone);toast(phone,'Sharing preview only. No message was sent.');}}
    if(action==='dismiss')dismiss(phone);
    if(action==='close')sheet(phone,s.screen==='confirm'?'Close preview':'Leave this draft?',`<p>${s.screen==='confirm'?'Your example is complete. No challenge was saved and no invitations were sent.':'Nothing has been sent. This example draft will be cleared when you reload.'}</p><button class="primary-button" data-action="dismiss">${s.screen==='confirm'?'Keep viewing':'Keep editing'}</button><button class="secondary-wide" style="color:var(--warning)" data-action="library">Back to Challenges</button>`);
    if(action==='library'){dismiss(phone);reference(phone,'library');}
    if(action==='goal-reference'){dismiss(phone);reference(phone,'goal');}
    if(action==='return-reference'){button.closest('.reference-screen').remove();phone.querySelector('[data-action=next]').focus();}
  }
  document.querySelectorAll('[data-create]').forEach((phone,i)=>{
    const initial=params.get('screen')||phone.dataset.create;const screen=screens[initial]?initial:'goal';
    states.set(phone,{id:i,screen,activity:'runs',target:20,start:'2026-09-28',end:'2026-10-04',name:'October runs',stake:screen==='goal'?0:20,selected:new Set(screen==='goal'?[]:['sam','jordan','priya']),trigger:null});
    render(phone);
    phone.addEventListener('click',e=>{const button=e.target.closest('button');if(button&&phone.contains(button))handle(phone,button);if(e.target.classList.contains('sheet-backdrop'))dismiss(phone);});
    phone.addEventListener('input',e=>{const s=states.get(phone);if(e.target.classList.contains('target-number')){s.target=e.target.value;fitTarget(phone);}if(e.target.hasAttribute('data-name'))s.name=e.target.value;if(e.target.hasAttribute('data-search-input')){let visible=0;const q=e.target.value.trim().toLowerCase();phone.querySelectorAll('.friend-select').forEach(row=>{row.hidden=!row.dataset.search.includes(q);if(!row.hidden)visible++;});phone.querySelector('.contact-empty').hidden=visible>0;}});
    phone.addEventListener('keydown',e=>{const overlay=phone.querySelector('.sheet-backdrop');if(overlay.hidden)return;if(e.key==='Escape'){e.preventDefault();dismiss(phone);}if(e.key==='Tab'){const focusable=[...overlay.querySelectorAll('button,input,summary,a[href]')].filter(el=>!el.disabled&&el.getClientRects().length);const first=focusable[0],last=focusable.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}}});
    if(params.get('sheet')==='contacts')contacts(phone);
  });
  document.querySelector('[data-show-permission]')?.addEventListener('click',()=>{const phone=[...states.keys()][2];const s=states.get(phone);s.screen='invite';render(phone);phone.scrollIntoView({block:'center'});contacts(phone);});
})();
