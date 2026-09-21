/* Fictional, local-only presentation of retained Personal agreements.
   Historical consent: PersonalChallengeFlow.swift and docs/COPY.md.
   This module contains no transport, payment, Health, or authentication calls. */
(function () {
  'use strict';

  const consent = 'By starting, you agree that GameTime may create one $20.00 test charge only if this challenge is confirmed missed after the review window. Missing or unclear step data never counts as a miss.';
  const cancellation = 'This ends the challenge immediately. It will stay in your history, and your saved test payment method will not be charged.';
  const deadline = 'Sep 27, 2026 at 12:00 PM Pacific';

  window.renderLegacy = function (route, ctx) {
    if (!route.startsWith('legacy')) return null;
    const { state, esc, button, row, facts, band, dates, notice, disclosure } = ctx;
    const scenario = state.scenario;
    const pending = scenario === 'pending';
    const unknown = scenario === 'unavailable';
    const offline = scenario === 'offline';
    const loading = scenario === 'loading';
    const reviewDisabled = offline || loading || unknown;
    const savedReview = Boolean(state.legacyReviewSaved);
    // The August 31 setup/cancellation replay is a separate alternate fixture.
    // It must never replace the completed September challenge or its review.
    const replayLeft = Boolean(state.legacyLeft);
    const replayPayment = route === 'legacyPayment' && state.legacyPaymentContext === 'replay';
    const provisional = pending || savedReview;
    const total = unknown ? '—' : provisional ? '48,600' : '52,480';
    const heading = title => `<h1 tabindex="-1">${title}</h1>`;
    const section = (title, html) => `<section class="section"><h2>${title}</h2>${html}</section>`;
    const link = (label, target, className = 'secondary') => `<button type="button" class="${className}" data-go="${target}">${label}</button>`;
    const span = () => dates('Sep 1, 2026', 'Sep 7, 2026', 'Pacific Time · 7 full days');
    const protections = () => facts([
      ['Goal met', '$0 test charge'],
      ['Missing or unclear steps', '$0 test charge'],
      ['Confirmed miss after review', 'One $20.00 test charge'],
      ['Recurring charges', 'None']
    ]);
    const fullRules = () => disclosure('What you signed up for', `
      <p>Add your eligible steps across all seven days. The goal is 50,000 steps this week.</p>
      <p>The week starts Sep 1, 2026 at 12:00 AM and ends Sep 8, 2026 at 12:00 AM, Pacific Time (America/Los_Angeles).</p>
      <p>GameTime makes one final Apple Health check 24 hours after your last day.</p>
      <p>A seven-day review follows a missed goal. Settlement stays paused during review.</p>
      <p>Your test charge is $0 when you meet your goal or step data is missing or unclear.</p>
      <p>Only a confirmed miss after review can create one $20.00 test charge. This is not a subscription.</p>
      <p>${consent}</p>`);
    const mode = () => notice('Payment test mode — no real money moves.');
    const freshness = () => offline
      ? notice('Last confirmed Sep 20, 2026 at 12:00 PM Pacific. We couldn’t refresh it. Your saved update is still here.')
      : loading ? notice('Checking for an update. Your last saved information stays here.') : '';
    const paymentText = () => savedReview ? 'Under review — settlement paused.'
      : unknown ? 'Payment test status could not be confirmed.'
      : pending ? 'Goal missed — review open. Settlement is paused.'
      : 'Goal met — $0 test charge.';
    const resultText = () => unknown ? 'Final steps unavailable' : savedReview ? 'Goal missed · under review' : pending ? 'Goal missed · review open' : 'Goal met';
    const recovery = () => `<div class="actions">${button(loading ? 'Refreshing…' : 'Refresh', 'legacy-refresh', 'secondary', loading ? 'disabled' : '')}${link('Contact Support', 'support')}</div>`;

    if (route === 'legacy') {
      if (scenario === 'empty') return heading('Existing challenges') + mode() + section('No existing challenges', '<p>Your earlier challenges will appear here.</p>') + link('Back to Challenges', 'challenges');
      if (loading) return heading('Existing challenges') + mode() + notice('Loading your existing challenges…') + link('Back to Challenges', 'challenges');
      return heading('Existing challenges') + mode() + `<p class="muted">Your earlier steps challenges and what you agreed to.</p>` + freshness()
        + section(provisional ? 'Needs your attention' : 'September 2026', row('September steps', 'Sep 1–7 · Week total · 50,000 steps', unknown ? 'Steps unavailable' : provisional ? 'Review' : 'Goal met', 'legacyDetail'))
        + section('Your agreement', row('Original setup', 'Dates, goal and payment protection', 'View', 'legacySetup'));
    }

    if (route === 'legacyDetail') {
      return heading('September steps') + mode() + freshness() + band(total, 'steps saved', resultText())
        + `<div class="section">${unknown ? '' : `<div class="progress" role="progressbar" aria-label="Saved steps toward 50,000" aria-valuemin="0" aria-valuemax="50000" aria-valuenow="${provisional ? 48600 : 50000}" aria-valuetext="${total} of 50,000 steps"><span style="width:${provisional ? 97.2 : 100}%"></span></div>`}<p class="muted">${unknown ? 'No final step total is available. Missing or unclear step data never counts as a miss.' : '50,000 steps · Week total'}</p></div>`
        + span()
        + section('Activity result', facts([['Result', resultText()], ['Saved update', provisional ? 'Sep 20, 2026 · 12:00 PM' : 'Sep 9, 2026 · 12:00 AM'], ['Time zone', 'Pacific Time']]))
        + section('Review', savedReview
          ? row('Your review request is saved', 'Under review · settlement paused', 'Receipt', 'legacyReceipt')
          : pending ? notice(`Ask us to review this result by ${deadline}.`) + link('Request a review', 'legacyReview')
          : unknown ? '<p>Missing final step data does not count against you.</p>'
          : '<p>No review is needed for this result.</p>')
        + section('Payment test status', row(paymentText(), 'Shown separately from your activity result', 'Details', 'legacyPayment'))
        + fullRules() + link('Original setup', 'legacySetup');
    }

    if (route === 'legacySetup') {
      if (replayLeft) return heading('Cancellation confirmed') + mode() + notice('Challenge closed — $0 test charge.') + link('View cancellation', 'legacyExitReceipt', 'primary');
      if (state.legacyStarted) {
        return heading('Your challenge is saved') + mode() + band('50,000', 'steps this week', 'September steps') + span()
          + section('Your challenge', facts([['How it counts', 'Week total'], ['Amount', '$20.00'], ['Length', '7 full days']]))
          + section('Payment protection', protections())
          + disclosure('Your agreement', `<p>${consent}</p>`)
          + `<div class="actions">${link('Existing challenges', 'legacy', 'primary')}${link('Cancel this challenge', 'legacyExit')}</div>`;
      }
      return heading('Check and confirm') + mode() + band('50,000', 'steps this week', 'September steps') + span()
        + section('Your challenge', facts([['How it counts', 'Week total'], ['Amount', '$20.00'], ['Length', '7 full days']]))
        + section('When it starts', facts([['Starts', 'Sep 1, 2026 · 12:00 AM'], ['Time zone', 'Pacific Time'], ['Final check', '24 hours after your last day']]))
        + section('Payment protection', protections())
        + notice('Test method saved. No test charge exists.')
        + fullRules()
        + `<label class="consent"><input type="checkbox" data-check="legacyConsent" ${state.legacyConsent ? 'checked' : ''}><span>${consent}</span></label>`
        + `<div class="actions">${button('Start my challenge', 'legacy-start', 'primary', state.legacyConsent ? '' : 'disabled')}${link('Cancel this challenge', 'legacyExit')}</div>`;
    }

    if (route === 'legacyReview') {
      if (savedReview) return heading('Your review request is saved') + mode() + notice('Under review — settlement paused.') + link('View saved request', 'legacyReceipt', 'primary');
      return heading('Request a review') + mode() + notice(reviewDisabled
        ? 'We couldn’t confirm that review is open. Refresh before sending your request.'
        : `Ask us to review this result by ${deadline}.`)
        + section('Result to review', facts([['Challenge', 'September steps'], ['Saved steps', '48,600'], ['Goal', '50,000 steps'], ['Result update', 'Sep 20, 2026 · 12:00 PM Pacific']]))
        + `<div class="fields"><label for="legacy-reason">Why are you asking for a review?</label><select id="legacy-reason" data-field="legacyNote" ${reviewDisabled ? 'disabled' : ''}><option value="My step data is wrong or incomplete" ${state.legacyNote !== 'I disagree with the result' ? 'selected' : ''}>My step data is wrong or incomplete</option><option value="I disagree with the result" ${state.legacyNote === 'I disagree with the result' ? 'selected' : ''}>I disagree with the result</option></select></div>`
        + `<p>Settlement stays paused during review. Missing or unclear step data never counts as a miss.</p>`
        + `<div class="actions">${button('Request a review', 'legacy-review-save', 'primary', reviewDisabled ? 'disabled' : '')}</div>`
        + (reviewDisabled ? recovery() : '');
    }

    if (route === 'legacyReceipt') {
      if (!savedReview) return heading('Review request') + mode() + notice('No review request is saved. Open the result to check your next step.') + link('View result', 'legacyDetail', 'primary');
      return heading('Your review request is saved') + mode() + notice('Under review — settlement paused.')
        + section('Your request', facts([['Challenge', 'September steps'], ['Reason', state.legacyNote || 'My step data is wrong or incomplete'], ['Saved', 'Sep 21, 2026 · 9:41 AM Pacific'], ['Result update', 'Sep 20, 2026 · 12:00 PM Pacific']]))
        + `<p>We’ll update this challenge when the review is complete.</p>`
        + section('Payment test status', `<p>Under review — settlement paused.</p><p>Only a confirmed miss after review can create one $20.00 test charge.</p>`)
        + `<div class="actions">${link('View result', 'legacyDetail', 'primary')}${link('Payment test status', 'legacyPayment')}</div>`;
    }

    if (route === 'legacyPayment') {
      if (replayPayment) return heading('Payment test status') + mode()
        + section('September steps', `<h2>${replayLeft ? 'Challenge closed — $0 test charge.' : 'Test method saved. No test charge exists.'}</h2>`)
        + facts([['Amount', '$20.00'], ['Charge', '$0.00'], ['Payment method', 'Test Visa · 4242']])
        + `<p>${replayLeft ? 'Your saved test payment method will not be charged.' : 'Only a confirmed miss after review can create one $20.00 test charge. Missing or unclear step data never counts as a miss.'}</p>`
        + actionsForReplay();
      return heading('Payment test status') + mode() + freshness()
        + section('September steps', `<h2>${paymentText()}</h2>${pending && !savedReview ? `<p>Ask us to review this result by ${deadline}.</p>` : ''}`)
        + facts([['Amount', '$20.00'], ['Charge', pending || savedReview || unknown ? 'Not confirmed' : '$0.00'], ['Payment method', 'Test Visa · 4242']])
        + `<p>Only a confirmed miss after review can create one $20.00 test charge. Missing or unclear step data never counts as a miss.</p>`
        + (pending && !savedReview ? link('Request a review', 'legacyReview', 'primary') : '')
        + (savedReview ? link('View saved request', 'legacyReceipt') : '')
        + recovery() + fullRules();
    }

    if (route === 'legacyExit') {
      if (replayLeft) return heading('Cancellation confirmed') + mode() + link('View cancellation', 'legacyExitReceipt', 'primary');
      return heading('Cancel this challenge?') + mode() + band('50,000', 'steps this week', 'September steps') + span()
        + notice(cancellation)
        + section('What happens next', facts([['Challenge', 'Closed immediately'], ['Test charge', '$0.00'], ['Your record', 'Stays in your history']]))
        + `<div class="actions">${button('Yes, cancel it', 'legacy-exit-save', 'primary')}${link('Keep it', 'legacySetup')}</div>`;
    }

    if (route === 'legacyExitReceipt') {
      if (!replayLeft) return heading('Cancellation record') + mode() + notice('No cancellation is saved for this challenge.') + link('View challenge', 'legacyDetail', 'primary');
      return heading('Cancellation confirmed') + mode() + notice('Challenge closed — $0 test charge.')
        + section('Your record', facts([['Challenge', 'September steps'], ['Cancelled', 'Aug 31, 2026 · 6:00 PM Pacific'], ['Result', 'Closed before it started'], ['Test charge', '$0.00']]))
        + `<p>This challenge stays in your history. Your saved test payment method will not be charged.</p>`
        + `<div class="actions">${link('Existing challenges', 'legacy', 'primary')}${button('Payment test status', 'legacy-replay-payment', 'secondary')}</div>`;
    }
    return null;

    function actionsForReplay() {
      return `<div class="actions">${link('View cancellation', 'legacyExitReceipt', 'primary')}${link('Existing challenges', 'legacy')}</div>`;
    }
  };
}());
