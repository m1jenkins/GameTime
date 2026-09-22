const check = '<path d="m7 13 4 4 8-10" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>';
const arrow = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12h15m-6-6 6 6-6 6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const facts = '<div class="goal-name">September steps</div><div class="goal-dates">Sep 24–30</div><div class="sim-amount">$20 simulated · fee $0</div>';

const concepts = [
  {id:'A', name:'The starting line', cls:'starting', description:'An open track, a confident headline. The most athletic of the four.', motion:'The track arrives, then the check settles. One quick, clean movement.', tradeoff:'Strongest brand character; the illustration needs careful proportions.'},
  {id:'B', name:'The challenge pass', cls:'ticket-phone', description:'A crisp little pass. The challenge feels like something you just made.', motion:'The pass lifts into place, with a small offset stack behind it.', tradeoff:'Tangible and memorable; more card-heavy than the current page.'},
  {id:'C', name:'The signal', cls:'signal-phone', description:'A sculptural blue check. Centered, soft, and quietly satisfying.', motion:'A soft halo appears as the check rises into place. No ongoing pulse.', tradeoff:'The most polished acknowledgement; also the most familiar.'},
  {id:'D', name:'On the calendar', cls:'calendar-phone', description:'Your start date becomes the visual. A more personal kind of confirmation.', motion:'A date tile arrives and a small check confirms it’s saved.', tradeoff:'Grounded in this challenge; repeats the start date as an illustration.'}
];

function trackArt(prefix) {
  return `<div class="hero-art entrance-item" data-motion="track" aria-hidden="true"><svg viewBox="0 0 393 272" fill="none">
    <title>Open running-track lines with a saved check</title>
    <defs><linearGradient id="${prefix}-track" x1="80" y1="255" x2="270" y2="35" gradientUnits="userSpaceOnUse"><stop stop-color="#dbe5ff"/><stop offset=".54" stop-color="#245bff"/><stop offset="1" stop-color="#245bff"/></linearGradient></defs>
    <path d="m21 248 154-154c31-31 76-31 107 0l86 86" stroke="#e7edfb" stroke-width="16" stroke-linecap="round"/>
    <path d="m56 248 136-136c22-22 51-22 73 0l86 86" stroke="url(#${prefix}-track)" stroke-width="16" stroke-linecap="round"/>
    <path d="m91 248 118-118c11-11 25-11 37 0l86 86" stroke="#245bff" stroke-width="16" stroke-linecap="round"/>
    <path d="m126 248 100-100 89 86" stroke="#d6e1ff" stroke-width="16" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="m58 187 74 73" stroke="#fafbfc" stroke-width="10"/>
    <g data-motion="check"><circle cx="272" cy="76" r="36" fill="#fafbfc"/><circle cx="272" cy="76" r="28" fill="#245bff"/><path d="m259 76 9 9 17-21" stroke="white" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/></g>
  </svg></div>`;
}

function signalArt(prefix) {
  return `<div class="hero-art entrance-item" data-motion="signal" aria-hidden="true"><svg viewBox="0 0 393 276" fill="none">
    <title>A blue confirmation check with a soft halo</title>
    <defs>
      <radialGradient id="${prefix}-halo"><stop stop-color="#d6e2ff" stop-opacity=".6"/><stop offset="1" stop-color="#ebf0ff" stop-opacity="0"/></radialGradient>
      <linearGradient id="${prefix}-disc" x1="145" y1="68" x2="239" y2="194" gradientUnits="userSpaceOnUse"><stop stop-color="#5881ff"/><stop offset=".48" stop-color="#245bff"/><stop offset="1" stop-color="#1849df"/></linearGradient>
      <linearGradient id="${prefix}-rim" x1="196" y1="59" x2="196" y2="208" gradientUnits="userSpaceOnUse"><stop stop-color="#98b1ff"/><stop offset="1" stop-color="#1849df"/></linearGradient>
      <radialGradient id="${prefix}-shadow"><stop stop-color="#355bd3" stop-opacity=".2"/><stop offset="1" stop-color="#355bd3" stop-opacity="0"/></radialGradient>
    </defs>
    <circle data-motion="halo" cx="196" cy="128" r="126" fill="url(#${prefix}-halo)"/>
    <circle cx="196" cy="128" r="109" stroke="#e8edf6"/>
    <circle cx="196" cy="128" r="87" stroke="#e0e7f3"/>
    <ellipse cx="196" cy="231" rx="74" ry="13" fill="url(#${prefix}-shadow)"/>
    <g data-motion="check"><circle cx="196" cy="137" r="68" fill="#1645cb"/>
    <circle cx="196" cy="130" r="68" fill="url(#${prefix}-disc)" stroke="url(#${prefix}-rim)" stroke-width="1.5"/>
    <path d="m168 132 19 19 39-47" stroke="#0d39be" stroke-opacity=".2" stroke-width="12" stroke-linecap="round" stroke-linejoin="round" transform="translate(0 3)"/>
    <path d="m168 128 19 19 39-47" stroke="white" stroke-width="11" stroke-linecap="round" stroke-linejoin="round"/></g>
  </svg></div>`;
}

function calendarArt(prefix) {
  return `<div class="hero-art entrance-item" data-motion="calendar" aria-hidden="true"><svg viewBox="0 0 393 225" fill="none">
    <title>A calendar tile showing the challenge starts September 24</title>
    <defs><linearGradient id="${prefix}-paper" x1="117" y1="63" x2="260" y2="203" gradientUnits="userSpaceOnUse"><stop stop-color="white"/><stop offset="1" stop-color="#f0f2f5"/></linearGradient></defs>
    <rect x="92" y="20" width="212" height="185" rx="22" fill="#e3e9f3" transform="rotate(6 198 112)"/>
    <rect x="90" y="16" width="212" height="189" rx="22" fill="url(#${prefix}-paper)" stroke="#dce1e8"/>
    <path d="M112 16h168a22 22 0 0 1 22 22v23H90V38a22 22 0 0 1 22-22Z" fill="#245bff"/>
    <text x="111" y="45" fill="white" font-size="14" font-weight="700" letter-spacing="2">SEP</text>
    <text x="282" y="45" text-anchor="end" fill="white" font-size="9" font-weight="650" letter-spacing="1.1">STARTS</text>
    <path d="M137 9v20m118-20v20" stroke="#111318" stroke-width="6" stroke-linecap="round"/>
    <text x="189" y="175" text-anchor="middle" fill="#111318" font-size="114" font-weight="900" font-style="italic" letter-spacing="-9">24</text>
    <g data-motion="check"><circle cx="294" cy="185" r="29" fill="#fafbfc"/><circle cx="294" cy="185" r="23" fill="#245bff"/><path d="m283 185 8 8 14-18" stroke="white" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/></g>
  </svg></div>`;
}

function phoneContent(concept,prefix) {
  const heading='<h3>Challenge<br>locked in.</h3>';
  const info=`<div class="goal-info">${facts}</div>`;
  if(concept.id==='A') return `${trackArt(prefix)}<div class="confirmation entrance-item" data-motion="copy">${heading}${info}</div>`;
  if(concept.id==='B') return `<div class="ticket-stack entrance-item" data-motion="ticket"><div class="ticket"><div class="ticket-top"><div class="ticket-brand">GAMETIME<svg viewBox="0 0 26 26" fill="none"><circle cx="13" cy="13" r="12" fill="#245bff"/><g color="white">${check}</g></svg></div>${heading}</div><div class="ticket-dash"></div><div class="ticket-bottom">${facts}</div><div class="ticket-edge"></div></div></div>`;
  if(concept.id==='C') return `${signalArt(prefix)}<div class="confirmation entrance-item" data-motion="copy">${heading}${info}</div>`;
  return `<div class="confirmation entrance-item" data-motion="copy">${heading}</div>${calendarArt(prefix)}${info}`;
}

function phone(concept,prefix) {
  return `<div class="phone ${concept.cls}" data-concept="${concept.id}" aria-label="${concept.name} page preview">
    <div class="statusbar" aria-hidden="true"><span>9:41</span><span class="island"></span><svg class="status-symbols" viewBox="0 0 64 18"><path d="M1 14v-3h3v3zm5 0V8h3v6zm5 0V5h3v9zm5 0V2h3v12z" fill="currentColor"/><path d="M25 5q7-6 14 0m-11 4q4-4 8 0m-5 4 1-1 1 1" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><rect x="44" y="3" width="17" height="11" rx="3" stroke="currentColor" fill="none"/><rect x="46" y="5" width="13" height="7" rx="1" fill="currentColor"/><path d="M63 7v3" stroke="currentColor" stroke-width="2"/></svg></div>
    <div class="chrome"><button class="mock-close" data-preview="Close creation and return to the previous page." aria-label="Close creation preview">×</button></div>
    <div class="phone-content">${phoneContent(concept,prefix)}</div>
    <div class="phone-footer"><button class="home-button" data-preview="Go to Home, with your saved challenge available.">Go to Home ${arrow}</button><button class="goal-button" data-preview="Open the saved goal and its details.">View goal</button></div>
    <div class="home-indicator" aria-hidden="true"></div>
  </div>`;
}

document.querySelector('#concepts').innerHTML=concepts.map(concept=>`<article class="concept" id="concept-${concept.id}"><div class="concept-heading"><span class="letter">${concept.id}</span><h2>${concept.name}</h2></div><p class="concept-description">${concept.description}</p>${phone(concept,`grid-${concept.id}`)}<div class="concept-actions"><button class="outline-button" data-open="${concept.id}">Open concept <span aria-hidden="true">↗</span></button><button class="outline-button replay-button" data-replay="${concept.id}" aria-label="Replay ${concept.name} entrance">↻</button></div><p class="motion-caption"><b>The feel:</b> ${concept.motion}</p></article>`).join('');

const motionQuery=window.matchMedia('(prefers-reduced-motion: reduce)');
const gentle=document.querySelector('#gentle-motion');
gentle.checked=motionQuery.matches;
function reduced(){return gentle.checked||motionQuery.matches;}

function replay(target){
  target.getAnimations({subtree:true}).forEach(a=>a.cancel());
  const parts=target.querySelectorAll('.entrance-item');
  if(reduced()){
    parts.forEach(el=>el.animate([{opacity:.65},{opacity:1}],{duration:140,easing:'ease-out'}));
    return;
  }
  parts.forEach((el,i)=>{
    const type=el.dataset.motion;
    const from=type==='ticket'?{opacity:0,transform:'translateY(15px) rotate(-3deg)'}:{opacity:0,transform:`translateY(${type==='copy'?8:13}px)`};
    el.animate([from,{opacity:1,transform:'translateY(0) rotate(0deg)'}],{duration:type==='copy'?330:510,delay:i*95,easing:'cubic-bezier(.2,.75,.2,1)',fill:'backwards'});
  });
  target.querySelectorAll('[data-motion="check"]').forEach(el=>el.animate([{opacity:0,transform:'translateY(6px)'},{opacity:1,transform:'translateY(0)'}],{duration:310,delay:160,easing:'cubic-bezier(.2,.75,.2,1)',fill:'backwards'}));
}

gentle.addEventListener('change',()=>document.querySelectorAll('.phone').forEach(replay));
motionQuery.addEventListener('change',()=>{gentle.checked=motionQuery.matches;document.querySelectorAll('.phone').forEach(el=>el.getAnimations({subtree:true}).forEach(a=>a.cancel()));});
const dialog=document.querySelector('#focus-dialog');
let activeConcept=null;
document.addEventListener('click',event=>{
  const open=event.target.closest('[data-open]');
  const replayButton=event.target.closest('[data-replay]');
  const preview=event.target.closest('[data-preview]');
  if(open){
    activeConcept=concepts.find(c=>c.id===open.dataset.open);
    document.querySelector('#focus-phone').innerHTML=phone(activeConcept,`focus-${activeConcept.id}`);
    document.querySelector('#focus-code').textContent=`CONCEPT ${activeConcept.id}`;
    document.querySelector('#focus-title').textContent=activeConcept.name;
    document.querySelector('#focus-description').textContent=activeConcept.description+' '+activeConcept.tradeoff;
    document.querySelector('#focus-motion').textContent=activeConcept.motion;
    dialog.showModal();
    document.querySelector('#close-dialog').focus();
    replay(document.querySelector('#focus-phone .phone'));
  }
  if(replayButton) replay(document.querySelector(`#concept-${replayButton.dataset.replay} .phone`));
  if(preview) toast(`Preview: ${preview.dataset.preview}`);
});
document.querySelector('#close-dialog').addEventListener('click',()=>dialog.close());
document.querySelector('#focus-replay').addEventListener('click',()=>replay(document.querySelector('#focus-phone .phone')));
dialog.addEventListener('click',event=>{if(event.target===dialog){const rect=dialog.getBoundingClientRect();if(event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom)dialog.close();}});

let toastTimer;
function toast(message){const el=document.querySelector('#preview-toast');el.textContent=message;el.classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>el.classList.remove('visible'),3000);}

const form=document.querySelector('#feedback-form');
const queueStatus=document.querySelector('#queue-status');
const storageKey='gametime-locked-in-design-preferences-2026-09-22';
try{const saved=JSON.parse(localStorage.getItem(storageKey)||'null');if(saved){form.querySelectorAll('[name="concept"]').forEach(input=>input.checked=saved.ids.includes(input.value));form.note.value=saved.note||'';}}catch{}
form.addEventListener('input',()=>{
  queueStatus.textContent='Selections updated here. Queue when you’re ready.';
  try{localStorage.setItem(storageKey,JSON.stringify({ids:[...form.querySelectorAll('[name="concept"]:checked')].map(i=>i.value),note:form.note.value}));}catch{}
});
form.addEventListener('submit',event=>{
  event.preventDefault();
  const ids=[...form.querySelectorAll('[name="concept"]:checked')].map(i=>i.value);
  const note=form.note.value.trim();
  if(!ids.length&&!note){queueStatus.textContent='Choose a concept or add a note first.';return;}
  const names=ids.map(id=>`${id} — ${concepts.find(c=>c.id===id).name}`);
  const prompt=`Refine the GameTime “Challenge locked in” visual mockups using this feedback. ${names.length?'Explore: '+names.join('; ')+'. ':''}${note?'Notes: '+note+'. ':''}Continue the design exploration; this feedback does not request app implementation.`;
  if(window.lavish?.queuePrompt){window.lavish.queuePrompt(prompt,{tag:'design-direction',text:names.length?'Explore '+ids.join(' + '):'Confirmation design feedback',queueKey:'locked-in-directions',element:document.querySelector('.feedback'),data:{concepts:ids,note,scope:'mockup refinement'}});queueStatus.textContent='Queued. Press Send to Agent in the review bar to send it.';}
  else{queueStatus.textContent='Open the Lavish review link to send feedback, or copy your preferences into the chat.';}
});

const seen=new IntersectionObserver(entries=>{entries.forEach(entry=>{if(entry.isIntersecting){replay(entry.target);seen.unobserve(entry.target);}});},{threshold:.25});
document.querySelectorAll('.concept>.phone').forEach(el=>seen.observe(el));
