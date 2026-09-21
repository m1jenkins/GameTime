/* Retained Personal: fictional local preview, never a payment or Health client.
   Authority: PersonalChallengeFlow.swift, PersonalPaymentStatusCard.swift, docs/COPY.md.
   Existing agreements, seven-day review and exact sandbox consent remain distinct
   from the new challenge domain. Only this product already exposes daily steps. */
(function () {
  'use strict';
  const route = title => [title, 'Existing challenges', 'existing'];
  const routes = {
    legacy: route('Existing challenges'), legacyToday: route('Personal daily activity'),
    legacyDetail: route('Personal challenge detail'), legacySetup: route('Original agreement'),
    legacyReview: route('Request a Personal review'), legacyReceipt: route('Personal review receipt'),
    legacyPayment: route('Payment test status'), legacyExit: route('Cancel Personal challenge'),
    legacyExitReceipt: route('Personal cancellation receipt'),
    legacyCadence: route('Personal setup · How it counts'), legacyTarget: route('Personal setup · Goal'),
    legacyAmount: route('Personal setup · Amount'), legacyConnect: route('Personal setup · Apple Health'),
    legacyPaymentSetup: route('Personal setup · Test payment'), legacyPaymentSheet: route('Native test payment sheet'),
    legacyReviewSetup: route('Personal setup · Review'), legacySaved: route('Personal saved receipt'),
    legacyDiscard: route('Discard Personal setup'), legacyDraft: route('Saved Personal draft'),
    legacyDeleteDraft: route('Delete saved Personal draft'), legacyCancelPending: route('Saved cancellation'),
    legacyPayMethod: route('Payment · Method saved'), legacyPayReview: route('Payment · Review open'),
    legacyPayUnderReview: route('Payment · Under review'), legacyPayWaived: route('Payment · Did not count'),
    legacyPayNoCharge: route('Payment · No charge'), legacyPayProcessing: route('Payment · Processing'),
    legacyPayComplete: route('Payment · Test charge complete'), legacyPayAction: route('Payment · Needs action'),
    legacyPayFailed: route('Payment · Collection failed')
  };
  const paymentRoutes = {
    legacyPayMethod: 'method_saved', legacyPayReview: 'review_open', legacyPayUnderReview: 'under_review',
    legacyPayWaived: 'waived', legacyPayNoCharge: 'no_charge', legacyPayProcessing: 'charge_pending',
    legacyPayComplete: 'charged', legacyPayAction: 'requires_action', legacyPayFailed: 'collection_failed'
  };
  const consent = amount => `By starting, you agree that GameTime may create one ${amount} test charge only if this challenge is confirmed missed after the review window. Missing or unclear step data never counts as a miss.`;
  const cancellation = 'This ends the challenge immediately. It will stay in your history, and your saved test payment method will not be charged.';
  const deadline = 'Sep 27, 2026 at 12:00 PM Pacific';
  const amountText = cents => (Number(cents) / 100).toLocaleString('en-US', { style: 'currency', currency: 'USD' });
  const setupRoutes = ['legacyCadence', 'legacyTarget', 'legacyAmount', 'legacyConnect', 'legacyPaymentSetup', 'legacyReviewSetup'];
  function init(s) {
    const defaults = { legacyResult: 'met', legacyResultPinned: false, legacyDay: 6,
      legacyCadence: 'daily', legacyTarget: '10000', legacyAmount: '1000', legacyConnected: false,
      legacyPaymentConsent: false, legacyMethod: false, legacyStartNow: false, legacyCreated: null,
      legacyDraftSaved: false, legacyDraftSnapshot: null, legacyDraftDeleted: false, legacyCancellationPending: false,
      legacySetupDiscarded: false, legacyNote: 'My step data is wrong or incomplete', legacyReviewSaved: false,
      legacyLeft: false, legacyStarted: false, legacyPaymentContext: 'completed' };
    for (const [k,v] of Object.entries(defaults)) if (s[k] === undefined) s[k] = v;
    // Selecting the review fixture establishes a historical result. Refresh
    // only changes freshness, never this result or a saved review request.
    if (s.scenario === 'pending' && !s.legacyResultPinned && ['legacy','legacyDetail','legacyPayment','legacyToday'].includes(s.route)) {
      s.legacyResult = 'review'; s.legacyResultPinned = true;
    }
  }
  function draft(s) { return { cadence:s.legacyCadence, target:s.legacyTarget, amount:s.legacyAmount, startNow:s.legacyStartNow }; }
  function goal(d) { return Number(d.target).toLocaleString('en-US') + (d.cadence === 'daily' ? ' steps a day' : ' steps this week'); }
  function validTarget(s) { return /^\d+$/.test(s.legacyTarget) && Number(s.legacyTarget) >= 1 && Number(s.legacyTarget) <= 1000000; }
  function renderLegacy(id, c) {
    if (!routes[id]) return null;
    const { state:s, esc, button, row, facts, band, dates, notice, disclosure } = c;
    init(s);
    const heading = c.heading || (t => `<h1 tabindex="-1">${t}</h1>`);
    const section = c.section || ((t,h) => `<section class="section"><h2>${t}</h2>${h}</section>`);
    const actions = c.actions || (h => `<div class="actions">${h}</div>`);
    const link = (label, target, cls='secondary') => `<button type="button" class="${cls}" data-go="${target}">${esc(label)}</button>`;
    const mode = () => notice('Payment test mode — no real money moves.');
    const shell = (title, html) => heading(title) + mode() + html;
    const busy = s.scenario === 'loading';
    const stale = s.scenario === 'offline';
    const unknown = s.scenario === 'unavailable';
    const expired = s.scenario === 'expired';
    const reviewBlocked = busy || stale || unknown || expired;
    const reviewing = s.legacyResult === 'review' || s.legacyReviewSaved;
    const result = s.legacyReviewSaved ? 'Goal missed · under review' : reviewing ? 'Goal missed · review open' : 'Goal met';
    const total = reviewing ? '48,600' : '52,480';
    const freshness = () => unknown ? notice('We couldn’t confirm the latest update. Your last saved result stays here. Refresh to try again.') : stale ? notice('Last confirmed Sep 20, 2026 at 12:00 PM Pacific. We couldn’t refresh it. Your saved update is still here.') : busy ? notice('Checking for an update. Your last saved information stays here.') : '';
    const refresh = () => button(busy ? 'Refreshing…' : 'Refresh', 'legacyx-refresh', 'secondary', busy ? 'disabled' : '');
    const recover = () => actions(refresh() + link('Contact Support', 'support'));
    const span = () => dates('Sep 1, 2026', 'Sep 7, 2026', 'Pacific Time · 7 full days');
    const protection = amount => facts([['Goal met','$0 test charge'],['Missing or unclear steps','$0 test charge'],['Confirmed miss after review','One '+amount+' test charge'],['Recurring charges','None']]);
    const fullRules = () => disclosure('What you signed up for', '<p>Add your eligible steps across all seven days. The goal is 50,000 steps this week.</p><p>The week starts Sep 1, 2026 at 12:00 AM and ends Sep 8, 2026 at 12:00 AM, Pacific Time (America/Los_Angeles).</p><p>GameTime makes one final Apple Health check 24 hours after your last day.</p><p>A seven-day review follows a missed goal. Settlement stays paused during review.</p><p>Your test charge is $0 when you meet your goal or step data is missing or unclear.</p><p>Only a confirmed miss after review can create one $20.00 test charge. This is not a subscription.</p><p>'+consent('$20.00')+'</p>');
    const frozen = s.legacyCreated || draft(s);
    if (s.legacyCreated && setupRoutes.includes(id)) return shell('Your challenge is already saved',notice(s.legacyLeft?'Your cancelled challenge stays in history. Use Reset demo to try a separate new setup.':'You already have an open Personal challenge. Its saved goal and dates stay unchanged.')+link('View saved challenge','legacySaved','primary'));
    const setupLocked = Boolean(s.legacyDraftSaved && s.legacyDraftSnapshot);
    if (setupLocked && ['legacyCadence','legacyTarget','legacyAmount'].includes(id)) return shell('Your setup is saved',notice('The saved request keeps the goal, dates and amount you already chose. Continue it or delete the saved draft before starting another setup.')+actions(link('Continue saved setup','legacyDraft','primary')+link('Delete draft','legacyDeleteDraft')));
    const setupFacts = d => section('Your challenge',facts([['Goal',goal(d)],['How it counts',d.cadence==='daily'?'Every day':'Week total'],['Amount',amountText(d.amount)]])) + section('When it starts',facts([['Starts',d.startNow?'Sep 21, 2026 · now, counting today':'Sep 22, 2026 · midnight'],['Last day',d.startNow?'Sep 27, 2026':'Sep 28, 2026'],['Time zone','Pacific Time']])) + section('Payment protection',protection(amountText(d.amount)));
    const setupMore = d => disclosure('More details','<p>'+ (d.cadence==='daily'?'Meet your step goal on each of the seven days.':'Add your steps across all seven days.') + '</p><p>GameTime makes one final Apple Health check 24 hours after your last day. A seven-day review follows a missed goal. Settlement stays paused during review.</p><p>'+consent(amountText(d.amount))+'</p><p>'+cancellation+'</p><p>We save exactly what you picked on this phone so you can confirm the same request after a connection problem.</p>');
    const stepFooter = (next, previous, label='Continue', disabled=false) => actions(button(label,'legacyx-next:'+next,'primary',disabled||busy?'disabled':'') + (previous?link('Back',previous):'') + link('Close','legacyDiscard'));
    const setupIntro = title => `<p class="eyebrow">${esc(title)} · ${setupRoutes.indexOf(id)+1} OF 6</p>`;
    if (id === 'legacy') {
      if (busy) return shell('Existing challenges',notice('Loading your existing challenges…')+link('Back to Challenges','challenges'));
      if (s.scenario==='empty') return shell('Existing challenges',section('No challenges yet','<p>Your current week and the weeks you finish will appear here.</p>')+link('Start a challenge','legacyCadence','primary'));
      return shell('Existing challenges',freshness()+section(reviewing?'Needs your attention':'Finished',row('September steps','Sep 1–7 · Week total · 50,000 steps',result,'legacyDetail'))+row('Your step history','Daily values for this saved week','Open','legacyToday')+(s.legacyCreated?row('Your saved challenge',goal(s.legacyCreated),'Saved','legacySaved'):'')+(s.legacyDraftSaved?row('Unfinished setup','Your choices are saved on this phone','Continue','legacyDraft'):'')+(s.legacyCancellationPending?row('Cancellation waiting to finish','Confirm the saved request','Open','legacyCancelPending'):'')+section('Earlier agreements',row('Original agreement','Goal, dates and payment protection','View','legacySetup'))+actions(link('Start a challenge','legacyCadence','primary')));
    }
    if (id === 'legacyToday') {
      const values = unknown ? [8230,7450,null,6800,8430,7550,5000] : reviewing ? [8230,7450,9020,6800,8430,7550,1120] : [8230,7450,9020,6800,8430,7550,5000];
      const value = values[s.legacyDay];
      const sum = values.reduce((a,v)=>a+(v??0),0);
      const chart = `<div class="chart"><div class="chart-readout"><strong>${value===null?'Not available':value.toLocaleString('en-US')+' steps'}</strong><span>Sep ${s.legacyDay+1}, 2026</span></div><div class="chart-plot"><div class="bars" aria-hidden="true">${values.map((v,i)=>`<div class="bar-button ${v===null?'unknown':''} ${s.legacyDay===i?'selected':''}" style="--bar-height:${v===null?20:Math.max(3,v/10000*101)}px"><span class="bar-shape"></span><span class="bar-day">${['T','W','T','F','S','S','M'][i]}</span></div>`).join('')}</div><input class="chart-input" type="range" id="legacy-day-selector" min="0" max="6" value="${s.legacyDay}" aria-label="Select day" aria-valuetext="September ${Number(s.legacyDay)+1}, ${value===null?'steps unavailable':value+' steps'}"></div></div>`;
      return shell('Your steps',freshness()+band(busy?'—':sum.toLocaleString('en-US'),'steps',unknown?'Available days · one day unavailable':'September 1–7, 2026')+(busy?notice('Loading your saved daily steps…'):chart)+notice(unknown?'We can’t confirm Wednesday’s steps. We don’t turn missing activity into zero.':'Updated from Apple Health Sep 9, 2026 at 12:00 AM Pacific.')+actions(refresh())+section('Your challenge',row('September steps','50,000 steps · Week total',unknown?'Daily data unavailable':result,'legacyDetail'))+link('Apple Health access','legacyHealth'));
    }
    if (id === 'legacyDetail') return shell('September steps',freshness()+band(total,'steps',result)+span()+section('Activity result',facts([['Goal','50,000 steps this week'],['Saved update',reviewing?'Sep 20, 2026 · 12:00 PM':'Sep 9, 2026 · 12:00 AM'],['Time zone','Pacific Time']]))+row('Daily steps','See each day in this challenge','Open','legacyToday')+section('Review',s.legacyReviewSaved?row('Your review request is saved','Under review · settlement paused','Receipt','legacyReceipt'):reviewing?notice('Ask us to review this result by '+deadline+'.')+link('Request a review','legacyReview'):unknown?'<p>Missing final step data does not count against you.</p>':'<p>No review is needed for this result.</p>')+section('Payment test status',row(s.legacyReviewSaved?'Under review — settlement paused.':unknown?'Payment test status could not be confirmed.':reviewing?'Goal missed — review open.':'Goal met — $0 test charge.','Payment status is separate from your activity result','Details','legacyPayment'))+fullRules()+actions(refresh()+link('Original agreement','legacySetup')));
    if (id === 'legacySetup') return shell('Your original agreement',band('50,000','steps this week','September steps')+span()+facts([['How it counts','Week total'],['Amount','$20.00'],['Length','7 full days']])+section('Payment protection',protection('$20.00'))+fullRules()+actions(link('View result','legacyDetail','primary')+link('Start a new setup','legacyCadence')));
    if (id === 'legacyCadence') return shell('How it counts',setupIntro('Your steps')+actions(button('Every day','legacyx-cadence:daily',s.legacyCadence==='daily'?'primary':'secondary',`aria-pressed="${s.legacyCadence==='daily'}"`)+button('Week total','legacyx-cadence:cumulative',s.legacyCadence==='cumulative'?'primary':'secondary',`aria-pressed="${s.legacyCadence==='cumulative'}"`))+'<p class="muted">'+(s.legacyCadence==='daily'?'Meet your goal on each of seven days.':'Reach one total by the end of the week.')+'</p>'+stepFooter('legacyTarget',null));
    if (id === 'legacyTarget') return shell('Your goal',setupIntro('Whole steps')+`<label class="fields">${s.legacyCadence==='daily'?'Steps each day':'Steps over the week'}<input class="big-input" data-field="legacyTarget" inputmode="numeric" value="${esc(s.legacyTarget)}" aria-label="Step goal"></label>`+actions((s.legacyCadence==='daily'?[7000,10000,12500,15000]:[50000,70000,100000]).map(v=>button(v.toLocaleString('en-US'),'legacyx-target:'+v,'secondary',`aria-pressed="${Number(s.legacyTarget)===v}"`)).join(''))+'<p class="muted">Pick any whole number from 1 to 1,000,000.</p>'+stepFooter('legacyAmount','legacyCadence'));
    if (id === 'legacyAmount') return shell('Your amount',setupIntro('Test commitment')+band(amountText(s.legacyAmount),'','Your selected amount')+actions([1000,2000,3000,4000,5000].map(v=>button(amountText(v),'legacyx-amount:'+v,'secondary',`aria-pressed="${Number(s.legacyAmount)===v}"`)).join(''))+protection(amountText(s.legacyAmount))+stepFooter('legacyConnect','legacyTarget'));
    if (id === 'legacyConnect') return shell(s.legacyConnected?'Health connected':'Connect Apple Health',setupIntro('Step access')+'<p>Connect Apple Health so GameTime can update this challenge automatically from your step history.</p>'+notice(unknown?'We couldn’t update your steps. Check Apple Health access and try again.':busy?'Connecting…':s.legacyConnected?'GameTime can update your challenge from your step history.':'You choose whether to share your steps with GameTime.')+(!s.legacyConnected?actions(button('Connect Apple Health','legacyx-connect','primary',busy?'disabled':'')):'')+link('Apple Health help','legacyHealth')+stepFooter('legacyPaymentSetup','legacyAmount','Continue',!s.legacyConnected));
    if (id === 'legacyPaymentSetup') return shell('Test payment',setupIntro('Payment method')+notice(s.legacyMethod?'Test method saved. No test charge exists.':'Add your test payment method before you start.')+protection(amountText(s.legacyAmount))+`<label class="consent"><input type="checkbox" data-check="legacyPaymentConsent" ${s.legacyPaymentConsent?'checked':''} ${s.legacyMethod?'disabled':''}><span>${consent(amountText(s.legacyAmount))}</span></label>`+`<label class="consent"><input type="checkbox" data-check="legacyStartNow" ${s.legacyStartNow?'checked':''} ${s.legacyDraftSaved?'disabled':''}><span>Start now and count today</span></label>`+actions(s.legacyMethod?link('Continue','legacyReviewSetup','primary'):button('Set up test payment','legacyx-payment-open','primary',s.legacyPaymentConsent&&!busy?'':'disabled'))+actions(link('Back','legacyConnect')+link('Close','legacyDiscard')));
    if (id === 'legacyPaymentSheet') return shell('Add test payment method',notice('The app opens the native payment sheet here. It handles payment details and returns you to your setup.')+facts([['Payment mode','Test only'],['Amount charged now','$0.00']])+(unknown?notice('We couldn’t save the test payment method. Go back and try again.'):busy?notice('Confirming your saved test method…'):'')+actions(button('Preview method saved','legacyx-method-saved','primary',busy?'disabled':'')+button('Cancel','legacyx-payment-cancel','secondary')));
    if (id === 'legacyReviewSetup') return shell('Check and confirm',setupIntro('Your agreement')+setupFacts(draft(s))+`<label class="consent"><input type="checkbox" data-check="legacyStartNow" ${s.legacyStartNow?'checked':''} ${s.legacyDraftSaved?'disabled':''}><span>Start now and count today</span></label>`+setupMore(draft(s))+(s.legacyMethod?notice('Test method saved. No test charge exists.'):notice('Add your test payment method before you start.'))+actions(button('Start my challenge','legacyx-start','primary',s.legacyConnected&&s.legacyMethod&&!busy?'':'disabled')+link('Back','legacyPaymentSetup')+link('Close','legacyDiscard')));
    if (id === 'legacySaved') return shell('Your challenge is saved',s.legacyCreated?band(Number(frozen.target).toLocaleString('en-US'),frozen.cadence==='daily'?'steps each day':'steps this week','Scheduled')+setupFacts(frozen)+setupMore(frozen)+actions(link('Existing challenges','legacy','primary')+link('Cancel this challenge','legacyExit')):notice('No new challenge is saved yet. Finish the setup to see its receipt.')+link('Continue setup','legacyCadence','primary'));
    if (id === 'legacyDiscard') return shell('Discard this setup?',notice('Your unsaved choices will be removed. A request already saved on this phone stays available for recovery.')+actions(button('Discard changes','legacyx-discard','primary')+link('Keep editing',s.legacyDraftSaved?'legacyDraft':'legacyCadence')));
    if (id === 'legacyDraft') {
      if (s.legacyDraftDeleted) return shell('Draft deleted',notice('The copy saved on your phone was deleted. If your challenge already started, it keeps running.')+link('Existing challenges','legacy','primary'));
      if (unknown) return shell('Saved setup needs attention',notice('GameTime couldn’t safely open the setup saved on this phone. Try again after unlocking your phone.')+actions(button('Try saving again','legacyx-draft-recover','primary')+link('Contact Support','support')));
      const saved = s.legacyDraftSnapshot || {cadence:'cumulative',target:'50000',amount:'2000',startNow:false};
      return shell('Unfinished setup',band(Number(saved.target).toLocaleString('en-US'),saved.cadence==='daily'?'steps a day':'steps this week','Saved on your phone')+facts([['Amount',amountText(saved.amount)],['How it counts',saved.cadence==='daily'?'Every day':'Week total']])+notice('We saved exactly what you picked, so you can pick up where you left off.')+freshness()+actions(button('Continue setup','legacyx-draft-resume','primary',busy?'disabled':'')+link('Delete draft','legacyDeleteDraft')));
    }
    if (id === 'legacyDeleteDraft') return shell('Delete this draft?',notice('This deletes the copy saved on your phone. If your challenge already started, it keeps running.')+actions(button('Delete draft','legacyx-draft-delete','primary')+link('Keep it','legacyDraft')));
    if (id === 'legacyReview') {
      if(s.legacyReviewSaved) return shell('Your review request is saved',notice('Under review — settlement paused.')+link('View saved request','legacyReceipt','primary'));
      return shell('Request a review',notice(expired?'Review window ended — settlement update pending.':reviewBlocked?'We couldn’t confirm that review is open. Refresh before sending your request.':'Ask us to review this result by '+deadline+'.')+facts([['Challenge','September steps'],['Saved steps','48,600'],['Goal','50,000 steps'],['Result update','Sep 20, 2026 · 12:00 PM Pacific']])+`<label class="fields">Why are you asking for a review?<select data-field="legacyNote" ${reviewBlocked?'disabled':''}>${['My step data is wrong or incomplete','I disagree with the result'].map(v=>`<option ${s.legacyNote===v?'selected':''}>${v}</option>`).join('')}</select></label>`+'<p>Settlement stays paused during review. Missing or unclear step data never counts as a miss.</p>'+actions(button('Request a review','legacyx-review-save','primary',reviewBlocked?'disabled':''))+(reviewBlocked?recover():''));
    }
    if (id === 'legacyReceipt') return shell('Your review request',s.legacyReviewSaved?notice('Your review request is saved. Under review — settlement paused.')+facts([['Challenge','September steps'],['Reason',s.legacyNote],['Saved','Sep 21, 2026 · 9:41 AM Pacific'],['Result update','Sep 20, 2026 · 12:00 PM Pacific']])+'<p>We’ll update this challenge when the review is complete.</p>'+actions(link('View result','legacyDetail','primary')+link('Payment test status','legacyPayment')):notice('No review request is saved. Open the result to check your next step.')+link('View result','legacyDetail','primary'));
    if (id === 'legacyPayment' || paymentRoutes[id]) {
      const replay = s.legacyPaymentContext==='replay';
      const payAmount = replay && s.legacyCreated ? amountText(s.legacyCreated.amount) : '$20.00';
      const payTitle = replay && s.legacyCreated ? goal(s.legacyCreated) : 'September steps';
      const payAgreement = replay && s.legacyCreated ? setupFacts(s.legacyCreated)+setupMore(s.legacyCreated) : fullRules();
      const pay = paymentRoutes[id] || (s.legacyPaymentContext==='replay' ? s.legacyLeft?'no_charge':'method_saved' : s.legacyReviewSaved?'under_review':reviewing?'review_open':'no_charge');
      const titles = {method_saved:'Test method saved. No test charge exists.',review_open:expired?'Review window ended — settlement update pending.':'Goal missed — review open. Settlement is paused.',under_review:'Under review — settlement paused.',waived:'This one didn’t count — $0 test charge.',no_charge:s.legacyPaymentContext==='replay'&&s.legacyLeft?'Challenge closed — $0 test charge.':'Goal met — $0 test charge.',charge_pending:'Processing one $20.00 test charge.',charged:'Test charge complete — sandbox transaction recorded.',requires_action:'Test payment needs your attention. We won’t try again automatically.',collection_failed:'Test payment needs your attention. We won’t try again automatically.'};
      return shell('Payment test status',freshness()+section(payTitle,notice(unknown?'Payment test status could not be confirmed.':titles[pay]))+facts([['Agreed amount',payAmount],['Payment method','Test Visa · 4242'],['Test charge',['no_charge','waived','method_saved'].includes(pay)?'$0.00':pay==='charged'?'$20.00':'Not confirmed']])+(!unknown&&pay==='review_open'?'<p>Ask us to review this result by '+deadline+'.</p>'+actions(button('Request a review','legacyx-open-review','primary',reviewBlocked?'disabled':'')):'')+(!unknown&&pay==='under_review'&&s.legacyReviewSaved?link('View saved request','legacyReceipt'):'')+'<p>Only a confirmed miss after review can create one '+payAmount+' test charge. Missing or unclear step data never counts as a miss.</p>'+recover()+payAgreement);
    }
    if (id === 'legacyExit') return shell('Cancel this challenge?',s.legacyLeft?notice('Cancellation is confirmed.')+link('View cancellation','legacyExitReceipt','primary'):notice(cancellation)+(s.legacyCreated?setupFacts(s.legacyCreated):band('50,000','steps this week','September steps')+span()+facts([['Amount','$20.00'],['Status','Scheduled'],['Test charge','$0.00']]))+actions(button('Yes, cancel it','legacyx-cancel','primary')+link('Keep it',s.legacyCreated?'legacySaved':'legacySetup')));
    if (id === 'legacyCancelPending') return shell('Cancellation is waiting to finish',notice(unknown?'We couldn’t open the saved cancellation. Unlock your phone and try again.':'Your cancellation is saved on this phone, but we haven’t confirmed it yet. Retry the same request before making another change.')+freshness()+actions(button('Retry cancellation','legacyx-cancel-retry','primary',busy?'disabled':'')+link('Contact Support','support')));
    if (id === 'legacyExitReceipt') return shell('Cancellation record',s.legacyLeft?notice('Challenge closed — $0 test charge.')+facts([['Challenge',s.legacyCreated?goal(s.legacyCreated):'September steps'],['Cancelled',s.legacyCreated?'Sep 21, 2026 · 10:00 AM Pacific':'Aug 31, 2026 · 6:00 PM Pacific'],['Result','Cancellation confirmed'],['Test charge','$0.00']])+'<p>This challenge stays in your history. Your saved test payment method will not be charged.</p>'+actions(link('Existing challenges','legacy','primary')+button('Payment test status','legacyx-replay-payment','secondary')):notice('No cancellation is confirmed. Open the challenge or recover your saved request.')+actions(link('View challenge','legacySetup','primary')+link('Saved cancellation','legacyCancelPending')));
    return null;
  }
  function act(action,c) {
    if (!action.startsWith('legacyx-')) return false;
    const s=c.state; init(s); const [name,value]=action.split(':');
    const go=r=>{c.go(r);return true;}, render=()=>{c.render();return true;}, fail=t=>{c.error(t);return true;};
    if(name==='legacyx-refresh'){if(s.scenario!=='expired')s.scenario='populated';return render();}
    if(name==='legacyx-day'){s.legacyDay=Number(value);return render();}
    if(name==='legacyx-cadence') {if(s.legacyDraftSaved)return fail('Continue or delete your saved draft before changing its goal.');const old=s.legacyCadence==='daily'?'10000':'70000';s.legacyCadence=value;if(s.legacyTarget===old)s.legacyTarget=value==='daily'?'10000':'70000';s.legacyMethod=false;s.legacyPaymentConsent=false;return render();}
    if(name==='legacyx-target'){s.legacyTarget=value;return render();}
    if(name==='legacyx-amount'){if(s.legacyDraftSaved)return fail('Continue or delete your saved draft before changing its amount.');s.legacyAmount=value;s.legacyMethod=false;s.legacyPaymentConsent=false;return render();}
    if(name==='legacyx-next'){if(s.route==='legacyTarget'&&!validTarget(s))return fail('Enter a whole number from 1 to 1,000,000.');return go(value);}
    if(name==='legacyx-connect'){s.legacyConnected=true;s.scenario='populated';return render();}
    if(name==='legacyx-payment-open'){if(!s.legacyPaymentConsent)return fail('Read and agree to the test-payment terms before continuing.');return go('legacyPaymentSheet');}
    if(name==='legacyx-payment-cancel')return go('legacyPaymentSetup');
    if(name==='legacyx-method-saved'){s.legacyMethod=true;s.scenario='populated';return go('legacyPaymentSetup');}
    if(name==='legacyx-start'){
      if(s.scenario==='unavailable')return fail('We couldn’t confirm your setup. Refresh before starting.');
      if(!validTarget(s)||!s.legacyConnected||!s.legacyMethod||!s.legacyPaymentConsent)return fail('Finish your goal, Apple Health connection and test-payment setup before starting.');
      if(s.scenario==='offline'||s.scenario==='pending'){s.legacyDraftSaved=true;s.legacyDraftDeleted=false;s.legacyDraftSnapshot={...draft(s)};return go('legacyDraft');}
      if(!s.legacyCreated)s.legacyCreated={...draft(s)};s.legacyStarted=true;s.legacyDraftSaved=false;return go('legacySaved');
    }
    if(name==='legacyx-discard'){s.legacyCadence='daily';s.legacyTarget='10000';s.legacyAmount='1000';s.legacyPaymentConsent=false;s.legacyMethod=false;s.legacyStartNow=false;s.legacySetupDiscarded=true;return go('legacy');}
    if(name==='legacyx-draft-recover'){s.scenario='populated';return render();}
    if(name==='legacyx-draft-resume'){const d=s.legacyDraftSnapshot||{cadence:'cumulative',target:'50000',amount:'2000',startNow:false};s.legacyDraftSnapshot={...d};s.legacyDraftSaved=true;s.legacyCadence=d.cadence;s.legacyTarget=d.target;s.legacyAmount=d.amount;s.legacyStartNow=d.startNow;s.legacyConnected=true;s.legacyMethod=true;s.legacyPaymentConsent=true;s.scenario='populated';return go('legacyReviewSetup');}
    if(name==='legacyx-draft-delete'){s.legacyDraftSaved=false;s.legacyDraftDeleted=true;s.legacyDraftSnapshot=null;return go('legacyDraft');}
    if(name==='legacyx-open-review'){if(['loading','offline','unavailable','expired'].includes(s.scenario))return fail('Refresh to confirm that review is still open.');s.legacyResult='review';s.legacyResultPinned=true;return go('legacyReview');}
    if(name==='legacyx-review-save'){if(['loading','offline','unavailable','expired'].includes(s.scenario))return fail('Refresh to confirm that review is still open.');s.legacyReviewSaved=true;s.legacyResult='review';s.legacyResultPinned=true;return go('legacyReceipt');}
    if(name==='legacyx-cancel'){if(['offline','pending','unavailable'].includes(s.scenario)){s.legacyCancellationPending=true;return go('legacyCancelPending');}s.legacyLeft=true;s.legacyPaymentContext='replay';return go('legacyExitReceipt');}
    if(name==='legacyx-cancel-retry'){s.legacyCancellationPending=false;s.legacyLeft=true;s.legacyPaymentContext='replay';s.scenario='populated';return go('legacyExitReceipt');}
    if(name==='legacyx-replay-payment'){s.legacyPaymentContext='replay';return go('legacyPayment');}
    return false;
  }
  window.renderLegacy=renderLegacy;
  window.SignalLegacy={routes,notes:[
    'Retained Personal stays separate: seven-day steps, original consent, sandbox payment status and saved-request recovery. Missing final step data never counts as a miss.',
    'Daily steps use the existing Personal daily model. Neutral instruments, aligned facts and separate glass controls replace the earlier cards; review and payment remain distinct.',
    'Cancellation without a newly saved goal is a separate August 31 historical replay. The native Health, Apple and payment sheets keep their platform behavior. This preview uses fictional records and local outcomes. A refresh never changes the selected activity result or resolves a pending review.'
  ],scenarios(id){if(!routes[id])return null;if(['legacyReview','legacyPayReview'].includes(id))return ['populated','offline','loading','unavailable','expired'];if(id==='legacy')return ['populated','empty','loading','offline','pending'];if(['legacyToday','legacyDetail','legacyPayment','legacyDraft','legacyCancelPending',...Object.keys(paymentRoutes)].includes(id))return ['populated','loading','offline','unavailable','pending'];if(['legacyConnect','legacyPaymentSheet','legacyReviewSetup','legacyExit'].includes(id))return ['populated','loading','offline','unavailable','pending'];return ['populated'];},act};
}());
