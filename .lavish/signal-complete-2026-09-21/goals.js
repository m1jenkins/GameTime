/* Source-backed presentation fixtures. No Health reads, uploads or real records. */
(() => {
'use strict';
const routes={
 challengeDetail:['Friend steps goal','Challenges','goal'],
 personalDetail:['Personal running distance','Challenges','goal'],
 timedDetail:['Personal timed run','Challenges','goal'],
 personalStepsDetail:['Personal steps goal','Challenges','goal'],
 personalMinutesDetail:['Personal Activity minutes','Challenges','goal'],
 friendMinutesDetail:['Friend Activity minutes','Challenges','goal'],
 friendDistanceDetail:['Friend running distance','Challenges','goal'],
 friendTimedDetail:['Friend timed run','Challenges','goal'],
 goalRules:['What you agreed to','Challenges','agreement'],
 goalReview:['Review this goal result','History & results','review'],
 goalReviewSaved:['Goal review request saved','History & results','receipt'],
 goalLeave:['Leave this goal','History & results','leave'],
 goalLeft:['Goal exit saved','History & results','receipt'],
 goalParticipant:['Friend in this goal','Challenges','lobby'],
 goalParticipantReport:['Report this participant','Friends & safety','support'],
 goalParticipantReported:['Participant report saved','Friends & safety','receipt'],
 goalParticipantBlock:['Block this participant','Friends & safety','leave'],
 useInvitation:['Use an invitation','Invitations','invitation'],
 invitationAccess:['Invitation access saved','Invitations','receipt'],
 communityReport:['Report a community concern','Community','support'],
 communityReportSaved:['Community report saved','Community','receipt']
};
const mapping={challengeDetail:['steps',false],personalDetail:['distance',true],timedDetail:['timed',true],personalStepsDetail:['steps',true],personalMinutesDetail:['minutes',true],friendMinutesDetail:['minutes',false],friendDistanceDetail:['distance',false],friendTimedDetail:['timed',false]};
const metrics={
 steps:{name:'Steps',unit:'steps',score:'18,420',target:'50,000',other:'21,200',otherTarget:'60,000',pct:36.84,source:'Eligible steps recorded by Apple Watch in Apple Health. Entries marked as manual and identifiable unsupported records do not count.'},
 minutes:{name:'Activity minutes',unit:'min',score:'95',target:'150',other:'108',otherTarget:'180',pct:63.33,source:'Apple Exercise credit recorded by Apple Watch. This is not every minute of movement. Apple Health does not identify the activity behind every credit, so indirectly derived credit may count. We exclude identifiable manual and unsupported records.'},
 distance:{name:'Running distance',unit:'km',score:'6.4',target:'20',other:'8.2',otherTarget:'25',pct:32,source:'Eligible outdoor runs recorded by Apple’s Workout app on Apple Watch. Each whole run must start and finish inside your challenge dates. We exclude manual and unsupported records.'},
 timed:{name:'Timed run',unit:'elapsed',score:'—',target:'30:00',other:'31:20',otherTarget:'32:00',pct:0,source:'A whole outdoor run of 5.00–5.10 km, including both distances, recorded by Apple’s Workout app on Apple Watch. Time from start to finish includes pauses and rounds up to whole seconds. The run must fit inside the challenge dates.'}
};
const link=(c,title,id,cls='secondary')=>'<button class="'+cls+'" data-go="'+id+'">'+c.esc(title)+'</button>';
function info(s,id){const current=mapping[id]?id:s.goalContext||'personalStepsDetail';const [key,personal]=mapping[current];return {id:current,key,personal,m:metrics[key]};}
function init(s){s.goalReviews ||= {};s.goalExits ||= {};s.goalSafetyReports ||= {};s.goalPendingActions ||= {};}
function timeline(x){return x.personal?{notice:'Sep 30, 2026 · noon Pacific',askBy:'Oct 2, 2026 · noon Pacific',filed:'Sep 30, 2026 · 1:00 PM Pacific',reviewBy:'Oct 3, 2026 · 1:00 PM Pacific',recorded:'Oct 3, 2026 · noon Pacific'}:{notice:'Sep 27, 2026 · noon Pacific',askBy:'Sep 29, 2026 · noon Pacific',filed:'Sep 27, 2026 · 1:00 PM Pacific',reviewBy:'Sep 30, 2026 · 1:00 PM Pacific',recorded:'Oct 1, 2026 · noon Pacific'};}
function fixtureClock(s){const id=s.route;if(!mapping[id]&&!id.startsWith('goal'))return null;const x=info(s,id);if(s.goalReviews?.[x.id])return x.personal?'Sep 30, 2026 · 1:00 PM Pacific':'Sep 27, 2026 · 1:00 PM Pacific';if(s.scenario==='final'||s.scenario==='void')return timeline(x).recorded;if(s.scenario==='review'||id==='goalReview')return timeline(x).notice;if(s.scenario==='syncing')return x.personal?'Sep 28, 2026 · noon Pacific':'Sep 25, 2026 · noon Pacific';if(s.scenario==='scheduled')return x.personal?'Sep 20, 2026 · 10:00 AM Pacific':'Sep 17, 2026 · 10:00 AM Pacific';return null;}
const failureStates=['offline','loading','pending','unavailable'];
function scenarios(id){if(mapping[id])return ['populated','scheduled','loading','offline','unavailable','pending','syncing','review','final','void'];if(id==='useInvitation')return ['populated','expired','revoked','full','unavailable','offline','loading','pending'];if(['goalReview','goalLeave','communityReport','goalParticipantReport','goalParticipantBlock'].includes(id))return ['populated',...failureStates,'review'];return routes[id]?['populated']:null;}
function reviewerControls(id,c){if(id!=='useInvitation')return '';return c.button('Fill fictional invitation link','goal-demo-link','secondary')+'<p>This local sample uses the accepted custom link format. No invitation is sent or opened outside the preview.</p>';}
function full(c,x){const {facts,disclosure}=c,m=x.m;const personal=x.personal;return disclosure('Full goal rules','<p>'+m.source+'</p><p>'+(x.key==='timed'?'Finish strictly under your agreed time. An equal time does not meet the goal.':'Reach at least your agreed total to meet the goal.')+'</p><p>An observed result can confirm success. Missing or incomplete activity never proves a missed goal. An unresolved result returns that person’s simulated entry.</p>'+facts([['Starts',personal?'Sep 21, 2026 · midnight':'Sep 18, 2026 · midnight'],['Ends',personal?'Sep 28, 2026 · midnight':'Sep 25, 2026 · midnight'],['Time zone','Pacific Time · Los Angeles'],['Initial updates through',personal?'Sep 29, 2026 · midnight':'Sep 26, 2026 · midnight'],['Corrections through',personal?'Sep 30, 2026 · midnight':'Sep 27, 2026 · midnight'],['Entry','$20 simulated'],['Fee','$0']])+'<p>'+(x.personal?'Meeting your goal returns your simulated entry. A confirmed miss leaves it unallocated.':'Each person has their own goal. People who meet their goals recover their entries and share confirmed misses evenly. Remainders and an all-miss pool stay unallocated. Fewer than two remaining confirmed results means the challenge does not count and entries return.')+'</p><p>You may leave before the result is final. Your entry returns. You have 48 full hours after the actual result notice to ask for review. Reviewers have 72 hours after filing. Delays do not shorten those windows.</p><p>'+(x.personal?'Your goal, activity and result stay private.':'Selected participants see only this challenge’s agreed goals, activity and results. Changing a roster or goal requires everyone to agree again.')+' Nothing can be paid out or redeemed. No real money moves.</p>');}
function render(id,c){
 if(!routes[id])return null;
 const {state:s,heading,section,band,facts,notice,row,actions,button,esc}=c;
 init(s);
 const b=(t,a,cls='secondary',attr='')=>button(t,'goal-'+a,cls,attr),x=info(s,id),m=x.m,t=timeline(x);
 const pending=s.goalPendingActions[x.id],stale=failureStates.includes(s.scenario)||!!pending;
 const failure=()=>s.scenario==='loading'?notice('We’re checking the latest details. Wait for the check before making a choice.'):s.scenario==='pending'||pending?notice('This action is waiting for confirmation. Retry checks the same action; it does not save another one.')+b('Retry saved action','retry'):stale?notice('We couldn’t confirm the latest details. Refresh before making a choice.')+b('Refresh','refresh'):'';
 if(mapping[id]){
  s.goalContext=id;
  const status=s.scenario,left=!!s.goalExits[id],safetyEnded=!x.personal&&s.socialBlocked,savedReview=s.goalReviews[id],scheduled=status==='scheduled'&&!savedReview,loading=status==='loading',done=status==='final'&&!savedReview&&!left,voided=status==='void'&&!savedReview&&!left,review=status==='review'||!!savedReview,unknown=!done&&!review&&(status==='unavailable'||m.score==='—');
  let h=heading(x.personal||s.socialBlocked?'Your '+m.name.toLowerCase()+' goal':m.name+' with Sam',x.personal?'JUST FOR YOU':'WITH FRIENDS');
  h+='<span class="badge">'+(left?'You left':savedReview?'Under review':done?'Goal met':voided?'Didn’t count':safetyEnded?'Ended safely':scheduled?'Upcoming':loading?'Checking activity':review?'Review open':status==='syncing'?'Waiting for updates':'Active')+'</span>';
  const val=scheduled||unknown||voided?'—':done||review?x.key==='timed'?'29:40':m.target:m.score;
  h+=band(val,m.unit,scheduled?(x.personal?'Starts Sep 21':'Starts Sep 18'):x.key==='timed'?'Your best saved run':'Your saved activity');
  if(!scheduled&&!unknown&&!voided)h+='<p class="muted">'+(done||review?'Result activity saved '+(x.personal?'Sep 29':'Sep 26')+' · 9:40 AM Pacific':'Last saved Sep 21 · 9:40 AM Pacific')+'</p>';
  if(!scheduled&&x.key!=='timed'&&!unknown&&!voided)h+='<div class="progress" role="img" aria-label="'+val+' of '+m.target+' '+m.unit+'"><span style="width:'+(done||review?100:m.pct)+'%"></span></div>';
  h+=facts([[x.key==='timed'?'Time to beat':'Your goal',m.target+' '+(x.key==='timed'?'for 5 km':m.unit)],['Dates',x.personal?'Sep 21–27, 2026':'Sep 18–24, 2026'],['Time zone','Pacific Time']]);
  if(x.key==='timed')h+='<p class="muted">One whole 5.00–5.10 km run. Pauses count.</p>';
  if(loading)h+=notice('Checking your activity. Your last saved update stays here.');
  if(unknown&&!scheduled&&!voided)h+=notice('No matching activity is saved yet. Try Refresh after your Watch syncs. Missing activity is not a missed goal.');
  if(status==='offline')h+=notice('We couldn’t refresh your activity. Your last saved score is still here. Try again when you’re connected.');
  if(status==='pending')h+=section('Waiting to save',facts([['On this phone',x.key==='steps'?'19,040 steps':x.key==='minutes'?'103 min':x.key==='distance'?'7.1 km':'29:40 elapsed'],['Saved by GameTime',m.score+' '+m.unit]])+'<p>We haven’t confirmed this update. Refresh to recover it.</p>');
  if(!x.personal&&!s.socialBlocked)h+=section('Agreed goals','<div class="row"><span class="row-copy"><strong class="row-title">You</strong><span class="row-sub">'+m.target+' '+m.unit+' goal</span></span><strong class="row-value">'+val+'</strong></div>'+row('Sam Parker',m.otherTarget+' '+m.unit+' goal',scheduled?'—':done||review?x.key==='timed'?m.other:m.otherTarget:m.other,'goalParticipant'));
  if(!x.personal&&s.socialBlocked)h+=notice('Shared details are hidden. Affected participation has ended safely. Your own saved record stays available.');
  if(x.personal)h+=section('Private to you','<p class="muted">Other participants can’t see your activity or result.</p>');
  if(review)h+=section('Your result',savedReview?notice('Your review request is saved. The final result and simulated return are paused.')+link(c,'View review request','goalReviewSaved','primary'):notice('A result update is ready. Ask for review by '+t.askBy+'.')+b('Ask for a review','review','primary'));
  if(done||voided)h+=section('Result', '<h2>'+(voided?'We couldn’t confirm this result.':'Your goal is met.')+'</h2><p>'+ (voided?'Your simulated entry returns.':'Review is complete.')+'</p>')+section('Simulated return',facts([['Recorded return','$20'],['Recorded',t.recorded]])+'<p class="muted">Nothing can be paid out or redeemed. No real money moved.</p>');
  if(left)h+=notice('Your exit is saved. The simulated return is still pending.')+link(c,'View exit record','goalLeft');
  h+=actions(b('Refresh','refresh')+link(c,'Apple Health','healthCheck'));
  h+=full(c,x)+facts([['Simulated entry','$20'],['Fee','$0']]);
  if(!done&&!voided&&!left&&!safetyEnded)h+=actions(b(scheduled?'Cancel this goal':'Leave this challenge','leave'));
  return h;
 }
 if(id==='goalRules')return heading('What you agreed to')+full(c,x);
 if(id==='goalReview')return s.goalReviews[x.id]?heading('Your request is already saved')+link(c,'View saved request','goalReviewSaved','primary'):heading('Ask for a review')+facts([['Activity',m.name],['Your goal',m.target+' '+m.unit],['Result notice',t.notice],['Ask by',t.askBy]])+notice('Saving a request pauses your final result and simulated return.')+failure()+'<label class="field"><span>What should we check?</span><select data-field="goalReason" '+(stale?'disabled':'')+'><option value="">Choose a reason</option>'+['Activity is missing','My total looks wrong','My result looks wrong'].map(v=>'<option'+(s.goalReason===v?' selected':'')+'>'+v+'</option>').join('')+'</select></label>'+actions(b('Send review request','review-save','primary',!s.goalReason||stale?'disabled':''));
 if(id==='goalReviewSaved'){
  const saved=s.goalReviews[x.id];
  return heading(saved?'Your review request is saved':'No review request saved')+(saved?facts([['Activity',m.name],['Reason',saved.reason],['Saved',saved.filed],['Reviewers’ deadline',saved.reviewBy],['Status','Under review']])+notice('The final result and simulated return are paused. No return has been recorded.'):notice('Open your result before asking for a review.'))+link(c,'Back to your goal',x.id,'primary');
 }
 if(id==='goalLeave')return s.goalExits[x.id]?heading('Your exit is already saved')+link(c,'View exit record','goalLeft','primary'):heading('Leave this challenge?')+facts([['Activity',m.name],['Your goal',m.target+' '+m.unit]])+notice('Your simulated entry returns. Your agreement stays in your history. '+(x.personal?'This ends your goal.':'The challenge continues only if at least two eligible people remain.'))+failure()+actions(b('Leave challenge','leave-save','primary',stale?'disabled':'')+link(c,'Keep my challenge',x.id));
 if(id==='goalLeft')return heading(s.goalExits[x.id]?'Your exit is saved':'No exit saved')+(s.goalExits[x.id]?facts([['Activity',m.name],['Simulated return','Update pending']])+'<p>No real money moved. Refresh your goal to check the final update.</p>':notice('Review your goal before choosing to leave.'))+link(c,'Back to your goal',x.id,'primary');
 if(id.startsWith('goalParticipant')&&x.personal)return heading('This goal is private')+notice('There are no other participants in this goal.')+link(c,'Back to your goal',x.id,'primary');
 if(id==='goalParticipant')return heading(s.socialBlocked?'Shared details are hidden':'Sam Parker')+(s.socialBlocked?notice('Your own agreement and final history remain available.')+link(c,'Back to your goal',x.id,'primary'):facts([['Username','@samparker'],['Challenge',m.name+' with friends'],['Agreed goal',m.otherTarget+' '+m.unit+(x.key==='timed'?' for 5 km':'')],['Dates','Sep 18–24, 2026']])+actions(link(c,'Report this account','goalParticipantReport')+link(c,'Block this account','goalParticipantBlock')+link(c,'Back to your goal',x.id)));
 if(id==='goalParticipantReport')return heading(s.socialBlocked?'Report an account':'Report Sam Parker')+'<label class="field"><span>What happened?</span><select data-field="goalSafetyReason"><option value="">Choose a reason</option>'+['Username','Unwanted contact','Unsafe behavior'].map(v=>'<option'+(s.goalSafetyReason===v?' selected':'')+'>'+v+'</option>').join('')+'</select></label>'+failure()+actions(b('Save report','person-report','primary',stale||!s.goalSafetyReason?'disabled':''));
 if(id==='goalParticipantReported')return heading(s.goalSafetyReports[x.id]?'Your report is saved':'No report saved')+(s.goalSafetyReports[x.id]?facts([['About',s.socialBlocked?'Former participant':'Sam Parker'],['Reason',s.goalSafetyReports[x.id].reason]])+'<p>Reporting does not block the account. You can choose to block it separately.</p>':notice('Choose a reason before saving a report.'))+link(c,'Back to participant','goalParticipant','primary');
 if(id==='goalParticipantBlock')return heading(s.socialBlocked?'Account is blocked':'Block Sam Parker?')+notice('Shared details will be hidden and affected participation will end safely. Your previous final records stay available.')+failure()+actions(b('Block account','person-block','primary',stale||s.socialBlocked?'disabled':'')+link(c,'Back to participant','goalParticipant'));
 if(id==='useInvitation')return heading('Use an invitation')+'<p>Opening a link doesn’t join a challenge. Sign in and confirm you’re 21 or older before you use it.</p><label class="field"><span>Invitation link</span><input data-field="invitationText" type="text" value="'+esc(s.invitationText||'')+'" placeholder="Paste invitation link"></label>'+(['expired','revoked','full','unavailable'].includes(s.scenario)?notice({expired:'This invitation has expired. Ask the creator for a new link.',revoked:'This link is turned off. Ask the creator for a new invitation.',full:'This link has reached its request limit. Ask the creator for a new invitation.',unavailable:'We couldn’t read this invitation. Check the link and try again.'}[s.scenario]):'')+actions(b('Use invitation','use-link','primary',!s.invitationText||s.scenario!=='populated'?'disabled':'')+link(c,'Age confirmation','ageConfirmation'));
 if(id==='invitationAccess')return heading(s.goalInvitationSaved?'Your request is saved':'No request saved')+(s.goalInvitationSaved?notice('You now have access to GameTime. Sam still chooses the roster, and you still need to agree to the rules.')+link(c,'View invitation','invitation','primary'):link(c,'Use an invitation','useInvitation','primary'));
 if(id==='communityReport')return heading('Report a concern')+'<p>Tell us about unsafe behavior in this community.</p><label class="field"><span>Reason</span><select data-field="communityReason">'+['Unsafe behavior','Unwanted contact'].map(v=>'<option'+(s.communityReason===v?' selected':'')+'>'+v+'</option>').join('')+'</select></label>'+failure()+actions(b('Send report','community-report','primary',stale?'disabled':''));
 return heading(s.goalCommunityReport?'Your report is saved':'No report saved')+(s.goalCommunityReport?facts([['Reason',s.goalCommunityReport.reason]])+'<p>We’ll review your report. It doesn’t change your challenge result.</p>':notice('Open the report form before saving a report.'))+link(c,'Back to community','community','primary');
}

function act(action,c){
 if(!action.startsWith('goal-'))return false;
 const s=c.state,a=action.slice(5),x=info(s,s.route),t=timeline(x);init(s);
 const blocked=()=>{
  if(s.scenario==='pending'||s.goalPendingActions[x.id]){s.goalPendingActions[x.id] ||= {action:a};c.error('We haven’t confirmed this action. Retry checks the same saved action; it does not start another one.');return true;}
  if(['offline','loading','unavailable'].includes(s.scenario)){c.error('We couldn’t confirm this change. Refresh the latest details before trying again.');return true;}
  return false;
 };
 if(a==='refresh'||a==='retry'){if(failureStates.includes(s.scenario)||s.goalPendingActions[x.id])c.error('We couldn’t confirm a newer update. Your saved information stays here. Try again later.');else c.render();return true;}
 if(a==='participant'){s.goalContext=x.id;c.go('goalParticipant');return true;}
 if(a==='review'){c.go('goalReview');return true;}
 if(a==='review-save'){
  if(blocked())return true;
  if(!['Activity is missing','My total looks wrong','My result looks wrong'].includes(s.goalReason)){c.error('Choose what you’d like us to check before sending your request.');return true;}
  if(s.goalExits[x.id]){c.error('This participation has ended. Open your saved exit to check the next update.');return true;}
  s.goalReviews[x.id] ||= Object.freeze({reason:s.goalReason,filed:t.filed,reviewBy:t.reviewBy});c.go('goalReviewSaved');return true;
 }
 if(a==='leave'){c.go('goalLeave');return true;}
 if(a==='leave-save'){if(blocked())return true;s.goalExits[x.id] ||= {saved:true};c.go('goalLeft');return true;}
 if(a==='person-report'){
  if(blocked())return true;
  if(!['Username','Unwanted contact','Unsafe behavior'].includes(s.goalSafetyReason)){c.error('Choose what happened before saving your report.');return true;}
  s.goalSafetyReports[x.id]={reason:s.goalSafetyReason};c.go('goalParticipantReported');return true;
 }
 if(a==='person-block'){if(blocked())return true;s.socialBlocked=true;c.go('goalParticipant');return true;}
 if(a==='demo-link'){s.invitationText='gametime-beta://challenge-invite/'+'a'.repeat(64);c.render();return true;}
 if(a==='use-link'){
  if(blocked())return true;
  if(s.scenario!=='populated'){c.error('This invitation can’t be used. Ask the creator for a new invitation.');return true;}
  if(s.invitationText!=='gametime-beta://challenge-invite/'+'a'.repeat(64)){c.error('We couldn’t read this invitation. Check the link and try again.');return true;}
  if(s.accountSignedIn===false){c.go('signin');return true;}
  if(!s.accountAgeSaved){c.go('ageConfirmation');return true;}
  s.invitation='requested';s.goalInvitationSaved=true;c.go('invitationAccess');return true;
 }
 if(a==='community-report'){if(blocked())return true;s.goalCommunityReport={reason:s.communityReason||'Unsafe behavior'};c.go('communityReportSaved');return true;}
 return true;
}
window.SignalGoals={routes,render,act,scenarios,fixtureClock,reviewerControls,scenarioLabels:{scheduled:'Scheduled',syncing:'Waiting for updates',review:'Result review',final:'Final · goal met',void:'Final · didn’t count',revoked:'Link turned off',full:'Request limit reached'},notes:['Four Personal and four friend goal policies preserve their own target, source, date and result rules. Exact accepted terms remain available.','An activity instrument leads every detail: saved value, unit, update, goal and date. Amount and full terms follow the activity. Different friend targets are not competing bars.','These are isolated fictional lifecycle variants. Scheduled data is absent, pending phone data is separate, and unknown data is never zero. Final-state variants use a later fixture clock. No daily series is invented.'],sourceMap:{goals:'ChallengeV1Views.swift: detail/activity/result/safeActions; ChallengeHealthViews.swift',goalParticipant:'ChallengeV1EntryViews.swift: ChallengePersonSafety; participant identity and challenge context stay together',useInvitation:'ChallengeV1EntryViews.swift: ChallengeEntryPanel; ChallengeInvitation.swift; only the explicit local sample link is accepted in this mockup'}};
})();
