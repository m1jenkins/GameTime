// Round 2: participants occupy their own progress lanes, never rank positions.
// All values are fictional. This file changes the review mock only.
const crewPeople = [
  {id:'you',name:'You',initials:'AL',value:6.4,target:20,color:'#f5c451',updated:'Updated from Apple Health 3 min ago'},
  {id:'sam',name:'Sam',initials:'SR',value:7.8,target:20,color:'#99cbbf',updated:'Updated from Apple Health 2 h ago'},
  {id:'jordan',name:'Jordan',initials:'JB',value:1.2,target:15,color:'#c2b5dc'},
  {id:'priya',name:'Priya',initials:'PN',value:10,target:10,color:'#e4ad9d'}
];
let crewSelected = null;
const crewRules = newChallenge().match(/<details>[\s\S]*?<\/details>/)[0];
const crewPriorRender = render;
const missingActivity = () => document.getElementById('missingUpdate').checked;

function personLane(person){
  const selected = person.id===crewSelected;
  if(person.id==='jordan' && missingActivity()) return `<button type="button" class="crew-lane crew-waiting" data-person="jordan" aria-pressed="${selected}" aria-label="Jordan, waiting for activity; no score available"><span class="waiting-token" aria-hidden="true">JB</span><span class="waiting-copy"><b>Jordan</b>Waiting for activity</span></button>`;
  const fraction=Math.min(person.value/person.target,1), x=18+fraction*276;
  const met=fraction>=1;
  const label=`${person.name}, ${person.value.toFixed(1)} of ${person.target} kilometres, ${Math.round(fraction*100)} percent of their own goal${met?', goal met':''}. Tap for details.`;
  return `<button type="button" class="crew-lane" data-person="${person.id}" aria-label="${label}" aria-pressed="${selected}"><span class="lane-label"><span>${person.name}</span>${met?'<span class="lane-achieved">✓ Goal met</span>':''}</span><svg class="lane-art" viewBox="0 0 322 51" aria-hidden="true"><title>${person.name} — progress toward their own goal</title><g id="track-${person.id}"><path d="M18 26H294" stroke="#39393e" stroke-width="7" stroke-linecap="round"/><path d="M18 26H${x}" stroke="${person.color}" stroke-width="7" stroke-linecap="round"/><path d="M53 23v6m35-6v6m35-6v6m35-6v6m35-6v6m35-6v6m35-6v6" stroke="#121214" stroke-opacity=".55" stroke-width="1.5"/><path d="M294 9v34" stroke="#e7e6df" stroke-opacity=".5" stroke-width="1.4"/>${met?'':`<path d="M295 9h12v10h-12Z" fill="#e7e6df"/><path d="M295 9h4v3h-4zm8 0h4v3h-4zm-4 3h4v4h-4zm-4 4h4v3h-4zm8 0h4v3h-4z" fill="#121214"/>`}</g><g class="token" id="token-${person.id}"><circle class="token-ring" cx="${x}" cy="26" r="21" fill="#121214"/><circle cx="${x}" cy="26" r="17" fill="${person.color}"/><text x="${x}" y="30" text-anchor="middle" fill="#222224" stroke="none">${person.initials}</text>${met?`<circle cx="${x+13}" cy="13" r="8" fill="#f3f3f1" stroke="#121214" stroke-width="2"/><path d="m${x+9} 13 3 3 5-6" stroke="#121214" stroke-width="1.5" fill="none"/>`:''}</g></svg></button>`;
}

function crewStage(isDetail){return `<div class="crew-stage"><div class="crew-nav">${isDetail?`<button class="back" data-action="home">${icon('back')}Home</button>`:'<span>Home</span>'}<span>With friends</span></div>${isDetail?'<div class="crew-heading"><h1>September runs</h1></div>':`<button class="crew-heading" data-action="challenge" aria-label="Open September runs"><h1>September runs</h1>${icon('chev')}</button>`}<div class="crew-dates"><span>Sep 21–27</span><span>Ends Sunday</span></div><div class="crew-lanes" role="group" aria-label="Progress toward each person’s own goal">${crewPeople.map(personLane).join('')}</div><div class="crew-track-key" aria-hidden="true"><span>Start</span><span>Each person’s own goal</span></div></div>`;}

function crewDetail(){
  if(!crewSelected) return `<div class="crew-story"><span class="crew-story-mark" aria-hidden="true">PN</span><span><strong>Priya reached her goal.</strong><small>Tap anyone to see their activity.</small></span></div>`;
  const person=crewPeople.find(p=>p.id===crewSelected);
  const waiting=person.id==='jordan'&&missingActivity();
  const met=person.value>=person.target;
  return `<div class="crew-selection" aria-live="polite"><span class="selection-name"><span class="selection-swatch" style="--person:${waiting?'#99999e':person.color}" aria-hidden="true"></span>${person.name}</span><button type="button" class="selection-clear" data-clear-person>Close details</button>${waiting?'<div class="selection-number" style="font-size:21px;letter-spacing:-.4px">Waiting for activity</div><div class="selection-extra">No activity has arrived yet. Missing data doesn’t count as a missed goal.</div>':`<div class="selection-number">${person.value.toFixed(1)} <small>of ${person.target} km</small></div><div class="selection-extra">${met?'Goal met':`${(person.target-person.value).toFixed(1)} km to go`}${person.updated?`<br>${person.updated}`:''}</div>`}</div>`;
}

newHome = function(){return `${status()}<div class="content">${crewStage(false)}<div class="crew-sheet">${crewDetail()}<div class="crew-invitation"><span class="avatar" aria-hidden="true">JB</span><span class="grow"><strong>Jordan invited you</strong><small>October runs · Sep 28–Oct 4</small></span><button class="textbutton" data-action="invite">See invite</button></div><div class="crew-next"><span>Park runs · Oct 5 with Sam</span>${icon('chev')}</div></div></div>${tabs()}`;};
newChallenge = function(){return `${status()}<div class="content">${crewStage(true)}<div class="crew-sheet">${crewDetail()}<div class="rules">${crewRules}<div class="rulesfooter">Simulated stakes — no real money moves.</div></div></div></div>${tabs()}`;};

render = function(screen){
  crewPriorRender(screen);
  document.getElementById('after').classList.toggle('crew',screen!=='invite');
  document.getElementById('interactionHint').textContent = screen==='invite'?'Invitation reading preview. Use Home to return; no account action is available.':'Tap a person for their numbers. The challenge title opens its details. Tabs and Park runs are shown for context.';
};

document.addEventListener('click',event=>{
  const personControl=event.target.closest('[data-person]');
  const clear=event.target.closest('[data-clear-person]');
  if(!personControl&&!clear)return;
  const scroll=document.querySelector('#after .content').scrollTop;
  crewSelected=clear?null:personControl.dataset.person;
  render(currentScreen);
  document.querySelector('#after .content').scrollTop=scroll;
  if(personControl)document.querySelector(`#after [data-person="${crewSelected}"]`).focus({preventScroll:true});
});
document.getElementById('missingUpdate').addEventListener('change',()=>render(currentScreen));
render('home');
