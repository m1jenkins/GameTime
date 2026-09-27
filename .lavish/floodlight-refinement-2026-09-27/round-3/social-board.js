// Round 3: daylight, a quieter trail, and detail updates that preserve context.
// All values are fictional. This file changes the review mock only.
const crewPeople = [
  {id:'you',name:'You',initials:'AL',value:6.4,target:20,color:'#f5c451',ink:'#937326',updated:'Updated from Apple Health 3 min ago'},
  {id:'sam',name:'Sam',initials:'SR',value:7.8,target:20,color:'#99cbbf',ink:'#447767',updated:'Updated from Apple Health 2 h ago'},
  {id:'jordan',name:'Jordan',initials:'JB',value:1.2,target:15,color:'#c2b5dc',ink:'#746190'},
  {id:'priya',name:'Priya',initials:'PN',value:10,target:10,color:'#e4ad9d',ink:'#a66650'}
];
let crewSelected = null;
let crewTone = 'daylight';
const crewRules = newChallenge().match(/<details>[\s\S]*?<\/details>/)[0];
const crewPriorRender = render;
const missingActivity = () => document.getElementById('missingUpdate').checked;

function personLane(person){
  const selected = person.id===crewSelected;
  const attrs = `type="button" data-person="${person.id}" aria-controls="crewDetail" aria-pressed="${selected}" style="--person-color:${person.color};--person-ink:${person.ink}"`;
  if(person.id==='jordan' && missingActivity()) return `<button ${attrs} class="crew-lane crew-waiting" aria-label="Jordan, waiting for activity; no score available"><span class="waiting-token" aria-hidden="true">JB</span><span class="waiting-copy"><b>Jordan</b>Waiting for activity</span></button>`;
  const fraction=Math.min(person.value/person.target,1), x=22+fraction*290;
  const met=fraction>=1;
  const label=`${person.name}, ${person.value.toFixed(1)} of ${person.target} kilometres, ${Math.round(fraction*100)} percent of ${person.id==='you'?'your':'their'} own goal${met?', goal met':''}. Select for details.`;
  return `<button ${attrs} class="crew-lane" aria-label="${label}"><span class="lane-label"><span>${person.name}</span>${met?'<span class="lane-achieved">Goal met</span>':''}</span><svg class="lane-art" viewBox="0 0 352 44" aria-hidden="true"><path class="lane-base" d="M22 22H312"/><path class="lane-complete" d="M22 22H${x}"/><path class="finish" d="M338 3v38m0-36h10l-3 5 3 5h-10"/><circle class="finish-dot" cx="22" cy="22" r="2.5"/><g class="token"><circle class="token-ring" cx="${x}" cy="22" r="21"/><circle class="token-shadow" cx="${x}" cy="24" r="17.5"/><circle class="token-body" cx="${x}" cy="22" r="17"/><text x="${x}" y="26" text-anchor="middle" fill="#252a23" stroke="none">${person.initials}</text>${met?`<circle class="token-check-disc" cx="${x+13}" cy="9" r="8"/><path class="token-check" d="m${x+9} 9 3 3 5-6"/>`:''}</g></svg></button>`;
}

function crewStage(isDetail){return `<div class="crew-stage"><div class="crew-nav">${isDetail?`<button class="back" data-action="home">${icon('back')}Home</button>`:'<span>Home</span>'}<span>With friends</span></div>${isDetail?'<div class="crew-heading"><h1>September runs</h1></div>':`<button class="crew-heading" data-action="challenge" aria-label="Open September runs"><h1>September runs</h1>${icon('chev')}</button>`}<div class="crew-dates"><span>Sep 21–27</span><span>Ends Sunday</span></div><div class="crew-lanes" role="group" aria-label="Progress toward each person’s own goal">${crewPeople.map(personLane).join('')}</div><div class="crew-track-key" aria-hidden="true"><span>Start</span><span>Each person’s own goal</span></div></div>`;}

function crewDetail(){
  if(!crewSelected) return `<div class="crew-story"><span class="crew-story-mark" aria-hidden="true">PN</span><span><strong>Priya reached her goal.</strong><small>Tap anyone to see their activity.</small></span></div>`;
  const person=crewPeople.find(p=>p.id===crewSelected);
  const waiting=person.id==='jordan'&&missingActivity();
  const met=person.value>=person.target;
  return `<div class="crew-selection"><span class="selection-name"><span class="selection-swatch" style="--person:${waiting?'#99999e':person.color};--person-ink:${person.ink}" aria-hidden="true"></span>${person.name}</span><button type="button" class="selection-clear" data-clear-person aria-label="Close activity details">Close</button>${waiting?'<div class="selection-number selection-waiting">Waiting for activity</div><div class="selection-extra">No activity has arrived yet. Missing data doesn’t count as a missed goal.</div>':`<div class="selection-number">${person.value.toFixed(1)} <small>of ${person.target} km</small></div><div class="selection-extra">${met?'Goal met':`${(person.target-person.value).toFixed(1)} km to go`}${person.updated?`<br>${person.updated}`:''}</div>`}</div>`;
}
const crewDetailHost=()=>`<div class="crew-detail-host" id="crewDetail">${crewDetail()}</div><div class="sr-only" id="crewAnnouncement" role="status" aria-live="polite" aria-atomic="true"></div>`;

newHome = function(){return `${status()}<div class="content">${crewStage(false)}<div class="crew-sheet">${crewDetailHost()}<div class="crew-invitation"><span class="avatar" aria-hidden="true">JB</span><span class="grow"><strong>Jordan invited you</strong><small>October runs · Sep 28–Oct 4</small></span><button class="textbutton" data-action="invite">See invite</button></div><div class="crew-next"><span>Park runs · Oct 5 with Sam</span>${icon('chev')}</div></div></div>${tabs()}`;};
newChallenge = function(){return `${status()}<div class="content">${crewStage(true)}<div class="crew-sheet">${crewDetailHost()}<div class="rules">${crewRules}<div class="rulesfooter">Simulated stakes — no real money moves.</div></div></div></div>${tabs()}`;};

render = function(screen){
  const previousScreen=currentScreen;
  const moveFocus=document.getElementById('after').contains(document.activeElement);
  crewPriorRender(screen);
  const phone=document.getElementById('after');
  phone.classList.add('crew');
  phone.dataset.tone=crewTone;
  if(moveFocus){
    const destination=screen==='home'?(previousScreen==='invite'?'[data-action=invite]':'[data-action=challenge]'):'.back';
    phone.querySelector(destination)?.focus({preventScroll:true});
  }
  document.getElementById('interactionHint').textContent = screen==='invite'?'Invitation reading preview. Use Home to return; no account action is available.':'Tap a person for their numbers; tap again to close. The title opens challenge details. Daylight and Night compare the mood.';
};

function updateCrewDetail(){
  const host=document.getElementById('crewDetail');
  if(!host)return;
  host.innerHTML=crewDetail();
  document.querySelectorAll('#after [data-person]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.person===crewSelected)));
  const person=crewPeople.find(p=>p.id===crewSelected);
  const waiting=person?.id==='jordan'&&missingActivity();
  document.getElementById('crewAnnouncement').textContent=!person?'Activity details closed.':waiting?'Jordan. Waiting for activity. Missing data doesn’t count as a missed goal.':`${person.name}. ${person.value.toFixed(1)} of ${person.target} kilometres. ${person.value>=person.target?'Goal met.':`${(person.target-person.value).toFixed(1)} kilometres to go.`} ${person.updated||''}`;
}
function clearCrewDetail(){
  const previous=crewSelected;
  crewSelected=null;
  updateCrewDetail();
  document.querySelector(`#after [data-person="${previous}"]`)?.focus({preventScroll:true});
}
document.addEventListener('click',event=>{
  const tone=event.target.closest('[data-tone-choice]');
  if(tone){
    crewTone=tone.dataset.toneChoice;
    document.getElementById('previewRound').textContent=`Round 3 · ${crewTone}`;
    document.getElementById('after').dataset.tone=crewTone;
    document.querySelectorAll('[data-tone-choice]').forEach(button=>button.setAttribute('aria-pressed',String(button===tone)));
    return;
  }
  const personControl=event.target.closest('[data-person]');
  if(personControl){
    crewSelected=personControl.dataset.person===crewSelected?null:personControl.dataset.person;
    updateCrewDetail();
  }else if(event.target.closest('[data-clear-person]'))clearCrewDetail();
});
document.getElementById('after').addEventListener('keydown',event=>{
  if(event.key==='Escape'&&crewSelected){event.preventDefault();clearCrewDetail();}
});
document.getElementById('missingUpdate').addEventListener('change',()=>{
  const lanes=document.querySelector('#after .crew-lanes');
  if(!lanes)return;
  lanes.innerHTML=crewPeople.map(personLane).join('');
  updateCrewDetail();
});
render('home');
