/* Connected reference to the staged native creation flow.
 * Authority: ChallengeCreationDraft.swift, ChallengeCreationViews.swift,
 * ChallengeV1Policy.swift, ChallengeV1EntryViews.swift and docs/COPY.md.
 * This renderer has no network, Apple Health, payment or native-app access.
 */
(function () {
  'use strict';
  const metrics = {
    steps: { title: 'Steps', unit: 'steps total', example: '50000', suggestion: '50000', suggested: '50,000 steps' },
    minutes: { title: 'Activity minutes', unit: 'minutes : seconds total', example: '150:00', suggestion: '150:00', suggested: '150 min 0 sec' },
    distance: { title: 'Running distance', unit: 'kilometres total', example: '20', suggestion: '20', suggested: '20 km' },
    timed: { title: 'Timed run', unit: 'minutes : seconds · finish under this time', example: '30:00', suggestion: '30:00', suggested: '30 min 0 sec' }
  };
  const zones = {
    'America/Los_Angeles': 'Los Angeles · Pacific time',
    'America/New_York': 'New York · Eastern time',
    'Europe/London': 'London · United Kingdom',
    'UTC': 'Coordinated Universal Time'
  };
  function dateAt(raw, offset) {
    const date = new Date(raw + 'T12:00:00Z');
    if (!Number.isFinite(date.getTime())) return null;
    date.setUTCDate(date.getUTCDate() + offset);
    return date;
  }
  function day(date, year) {
    if (!date) return 'Choose a date';
    return new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', ...(year ? { year: 'numeric' } : {}), timeZone: 'UTC' }).format(date);
  }
  function displayTarget(d) {
    if (!String(d.target || '').trim()) return '—';
    if (d.metric === 'steps') return Number(d.target).toLocaleString('en-US');
    if (d.metric === 'minutes' || d.metric === 'timed') return String(d.target);
    return String(d.target);
  }
  function validTarget(d) {
    const value = String(d.target || '').trim();
    if (d.metric === 'steps') return /^\d+$/.test(value) && Number(value) >= 1 && Number(value) <= 1000000000;
    if (d.metric === 'distance') return /^\d+(?:\.\d{1,6})?$/.test(value) && Number(value) > 0 && Number(value) <= 1000;
    if (!/^\d+:\d{1,2}$/.test(value)) return false;
    const [minutes, seconds] = value.split(':').map(Number);
    return minutes <= 16666666 && seconds < 60 && minutes * 60 + seconds >= 1 && minutes * 60 + seconds <= 1000000000;
  }
  window.renderCreation = function renderCreation(route, ctx) {
    if (!['createType', 'createActivity', 'createDates', 'createAmount', 'createReview', 'createSaved'].includes(route)) return null;
    const { state, esc, button, facts, band, dates, notice, disclosure } = ctx;
    const d = route === 'createSaved' && state.created ? state.created : state.draft;
    const personal = d.kind === 'personal';
    const leaderboard = d.kind === 'leaderboard';
    const metric = metrics[d.metric] || metrics.steps;
    const duration = /^\d+$/.test(d.days) && Number(d.days) >= 1 && Number(d.days) <= 30 ? Number(d.days) : null;
    const first = dateAt(d.start, 0);
    const end = duration ? dateAt(d.start, duration) : null;
    const last = duration ? dateAt(d.start, duration - 1) : null;
    const sync = duration ? dateAt(d.start, duration + 1) : null;
    const corrections = duration ? dateAt(d.start, duration + 2) : null;
    const zone = zones[d.zone] || d.zone;
    const amount = /^\d+$/.test(d.amount) && Number(d.amount) >= 1 && Number(d.amount) <= 500 ? '$' + Number(d.amount).toLocaleString('en-US') : 'Choose an amount';
    const unavailable = state.scenario === 'unavailable';
    const loading = state.scenario === 'loading';
    const stale = state.scenario === 'offline';
    const source = {
      steps: 'We count eligible steps recorded by Apple Watch in Apple Health. Entries marked as manual and records from unsupported apps or devices don’t count.',
      minutes: 'Activity minutes use Apple Exercise credit recorded by Apple Watch. They don’t represent every minute you move. We exclude entries marked as manual and identifiable unsupported apps or devices. Apple Health doesn’t tell us which activity caused every credit, so indirectly derived credit may count.',
      distance: 'We count eligible outdoor runs recorded by Apple’s Workout app on Apple Watch. A whole run must fit inside your challenge dates; a run crossing either boundary doesn’t count.',
      timed: leaderboard ? 'We use whole outdoor runs recorded by Apple’s Workout app on Apple Watch. Time from start to finish includes pauses. Your fastest eligible saved run counts.' : 'We use whole outdoor runs recorded by Apple’s Workout app on Apple Watch. Time from start to finish includes pauses. You must finish strictly under your goal time.'
    }[d.metric] || '';
    const scoring = leaderboard
      ? d.metric === 'timed'
        ? 'Your fastest eligible whole run saved by GameTime by the deadline wins. A missing run cannot improve your saved time. Equal times share the win.'
        : 'The highest eligible total saved by GameTime by the deadline wins. A partial saved total ranks at that total. Equal totals share the win.'
      : d.metric === 'timed'
        ? 'Finish an eligible whole run strictly under your agreed time. A time equal to your goal does not meet it. Pauses count toward elapsed time.'
        : 'Reach at least your agreed total during the challenge to meet your goal.';
    const missing = leaderboard
      ? 'Missing or late activity doesn’t count. With no valid saved score, you’re unranked and your simulated entry returns. If fewer than two people have valid scores, the challenge doesn’t count and all entries return.'
      : personal
        ? 'A missing or unclear result never proves a missed goal. Your simulated entry returns if the result cannot be confirmed.'
        : 'A missing or unclear result never proves a missed goal. We return that person’s simulated entry and score the remaining results only if the agreed minimum remains.';
    const allocation = leaderboard
      ? 'Winners split the remaining simulated pool evenly. Any indivisible remainder stays unallocated.'
      : personal
        ? 'Meeting your goal returns your simulated entry. A confirmed miss leaves it unallocated. Nothing can be paid out or redeemed.'
        : 'People who meet their goals recover their entries and share confirmed misses evenly. Any remainder and an all-miss pool stay unallocated.';
    const range = () => dates(day(first, false), day(last, false), zone);
    const boundary = () => facts([
      ['Starts', day(first, true) + ' · midnight'],
      ['Ends', day(end, true) + ' · midnight'],
      ['Time zone', zone]
    ]);
    const p = text => '<p>' + esc(text) + '</p>';
    const rules = () => [
      p(scoring),
      p(source),
      leaderboard
        ? p('We rank what GameTime saves, without checking that your entire Apple Health history is available. Refresh to send activity and check your saved score. An update counts only after GameTime confirms it.') + p('If we can’t save an update, use Refresh to recover it. If your result is still wrong, ask us to review it before the review deadline.')
        : p('An observed result can confirm that you met your goal. Missing or incomplete activity cannot confirm a missed goal or a ranking.'),
      d.metric === 'timed' ? p('Whole outdoor run: ' + d.distance + ' km to ' + (Math.round(Number(d.distance) * 102000000) / 100000000) + ' km, including both distances. The whole run must fit inside these dates. Time from start to finish includes pauses.') : '',
      boundary(),
      leaderboard
        ? p('Save activity by ' + day(corrections, true) + ' at midnight · ' + zone + '. First updates and corrections count through this deadline, including the exact deadline.')
        : p('Initial updates through ' + day(sync, true) + ' at midnight · ' + zone + '. Corrections through ' + day(corrections, true) + ' at midnight · ' + zone + '.'),
      p(amount + ' simulated per person. Fee $0. Nothing can be paid out or redeemed. No real money moves.'),
      p(missing), p(allocation),
      p('You may leave before the result is final. Your simulated entry returns. The challenge continues only if at least ' + (personal ? '1 eligible person remains.' : '2 eligible people remain.')),
      p('You have 48 hours after the actual result notice to ask for a review. Reviewers have 72 hours after your request. A processing delay never shortens those windows.'),
      personal ? '' : p('Everyone agrees to the displayed roster and goals, when this format has goals. Reopening the lobby requires everyone to agree again. Incomplete agreement at the start cancels the challenge.'),
      p(personal ? 'Other participants cannot see your activity or results. Community challenges show anonymous participant counts.' : 'The selected friends can see your username, agreed goal when there is one, current challenge activity and results. Your activity history outside this challenge stays private.'),
      p('An assigned reviewer can inspect the normalized challenge facts needed for your review. Raw Apple Health records are not shared.'),
      p('Up to three unfinished challenges at once. Friend challenges for the same activity cannot overlap. One community challenge may overlap your friend steps challenge.')
    ].join('');
    const stepNames = ['createType', 'createActivity', 'createDates', 'createAmount', 'createReview'];
    const direct = Boolean(state.createDirect);
    const stepNumber = stepNames.indexOf(route) + (direct ? 0 : 1);
    const progress = route === 'createSaved' ? '' : '<p class="eyebrow">Step ' + stepNumber + ' of ' + (direct ? 4 : 5) + '</p>';
    const field = (label, key, value, unit, attributes) => '<label class="field"><span>' + esc(label) + '</span><input class="big-input" data-field="draft.' + key + '" value="' + esc(value) + '" ' + attributes + '><span class="muted">' + esc(unit) + '</span></label>';
    const choice = (title, sub, action, selected) => '<button type="button" class="choice ' + (selected ? 'selected' : '') + '" data-action="' + esc(action) + '" aria-pressed="' + selected + '"><span><strong>' + esc(title) + '</strong><small>' + esc(sub) + '</small></span><span aria-hidden="true">' + (selected ? '●' : '○') + '</span></button>';
    const next = label => '<div class="actions">' + button(label || 'Continue', 'create-next') + '</div>';
    const heading = title => progress + '<h1>' + esc(title) + '</h1>';

    if (route === 'createType') return heading('Who’s it for?') + '<div class="choices">' +
      choice('Personal goal', 'Just for you', 'create-kind:personal', personal) +
      choice('Goals with friends', 'Each person chooses a goal', 'create-kind:friends', d.kind === 'friends') +
      choice('Friend leaderboard', 'Compare saved results', 'create-kind:leaderboard', leaderboard) + '</div>' + next();

    if (route === 'createActivity') {
      const choices = Object.entries(metrics).map(([id, item]) => choice(item.title, id === 'timed' ? 'A whole outdoor run' : id === 'minutes' ? 'Apple Exercise credit' : id === 'distance' ? 'Outdoor running kilometres' : 'Steps during the challenge', 'create-metric:' + id, d.metric === id)).join('');
      let content = heading(personal ? 'Choose your goal.' : 'Choose your activity.') + '<div class="choices">' + choices + '</div>';
      if (unavailable) content += notice('Activity not available yet. Choose another activity or check again later.');
      if (d.metric === 'timed') content += '<section class="section fields">' + field('Whole run', 'distance', d.distance, 'kilometres', 'inputmode="decimal" placeholder="5" aria-label="Whole run in kilometres"') + '</section>';
      if (personal) {
        content += '<section class="section fields">' + field(d.metric === 'timed' ? 'Time to beat' : 'Your goal', 'target', d.target, metric.unit, 'inputmode="' + (d.metric === 'steps' ? 'numeric' : d.metric === 'distance' ? 'decimal' : 'text') + '" placeholder="' + metric.example + '" aria-label="' + esc(d.metric === 'timed' ? 'Time to beat in minutes and seconds' : metric.unit) + '"') + '</section>';
        content += disclosure('Use a suggestion', p('Suggestion: ' + metric.suggested + '. You choose whether to use this goal.') + button('Use this suggestion', 'create-suggest:' + metric.suggestion, 'secondary'));
      } else content += p(leaderboard ? scoring : 'Everyone chooses their goal in the lobby.');
      if (d.metric === 'minutes') content += p(source);
      return content + next();
    }

    if (route === 'createDates') return heading('Set the dates.') +
      '<div class="fields">' + field('Duration', 'days', d.days, 'full days · choose 1–30', 'inputmode="numeric" aria-label="Duration in full days"') +
      '<label class="field"><span>Starts</span><input type="date" data-field="draft.start" value="' + esc(d.start) + '" min="2026-09-23" max="2026-10-21"></label>' +
      '<label class="field"><span>Time zone</span><select data-field="draft.zone">' + Object.entries(zones).map(([id, title]) => '<option value="' + esc(id) + '"' + (d.zone === id ? ' selected' : '') + '>' + esc(title) + '</option>').join('') + '</select></label></div>' +
      (duration ? range() : '') + p('Start in 2–30 days; each day runs midnight to midnight.') +
      (duration ? disclosure('Exact start and end', boundary()) : '') + next();

    if (route === 'createAmount') return heading('Choose your amount.') + '<div class="fields">' +
      field('Simulated amount · $', 'amount', d.amount, 'USD · $1–$500', 'inputmode="numeric" aria-label="Simulated amount in whole US dollars"') + '</div>' +
      p('Simulated stakes — no real money moves.') + facts([['Fee', '$0'], ['Real money', '$0']]) + next('Review');

    if (route === 'createReview') {
      const targetOK = !personal || validTarget(d);
      const readinessBlocked = loading || unavailable || stale;
      let content = heading(personal ? 'Review your goal.' : 'Review your challenge.') +
        (personal ? band(displayTarget(d), metric.unit, 'Your goal') : '<h2>' + esc(metric.title) + '</h2>') +
        (d.metric === 'timed' ? p('Whole run: ' + d.distance + ' km') : '') + range() +
        facts([['Simulated amount', amount + (personal ? '' : ' per person')], ['Fee', '$0']]) +
        p('Simulated stakes — no real money moves. Nothing can be paid out or redeemed.');
      if (!targetOK) content += notice('Enter your goal before you agree.') + '<button class="secondary" data-go="createActivity">Choose your goal</button>';
      content += p(source);
      if (personal) content += p('Meet your goal and your simulated entry returns. A confirmed miss leaves it unallocated. Missing or unclear activity never proves a miss.');
      else content += p('Choose your friends next. Everyone reviews the roster and rules before agreeing.') + p(missing) + p(allocation);
      content += p('You can leave before the result is final. You have 48 hours after the result notice to ask for a review.') +
        facts([['Starts', day(first, true) + ' · midnight'], ['Ends', day(end, true) + ' · midnight'], [leaderboard ? 'Save activity by' : 'Corrections by', day(corrections, true) + ' · midnight'], ['Time zone', zone]]) +
        disclosure(personal ? 'Full goal rules' : 'Full challenge rules', rules());
      if (personal) {
        const ready = Boolean(state.createReady) && !readinessBlocked;
        const title = loading ? 'Checking your activity' : unavailable ? 'Activity not available yet' : stale ? 'Activity needs another check' : ready ? 'Activity found' : 'Check your activity';
        const explanation = loading ? 'We’re checking your activity. You can leave and return to this step.' : unavailable ? 'We can’t use this activity with these rules yet. Choose another activity or check again later.' : stale ? 'Some activity changed or couldn’t be read. Try Refresh. We won’t treat missing activity as zero.' : ready ? 'We found matching activity. This doesn’t mean your entire activity history is available.' : 'Check your activity before you agree. You can keep browsing without starting.';
        content += '<section class="section"><h2>' + esc(title) + '</h2>' + p(explanation) + button('Refresh activity check', 'create-check', 'secondary', loading || unavailable ? 'disabled' : '') + '</section>' +
          '<label class="consent"><input type="checkbox" data-check="createConsent"' + (state.createConsent ? ' checked' : '') + '><span>I have read the complete rules and agree</span></label>';
      }
      const cannotSave = !targetOK || loading || (personal && (!state.createConsent || !state.createReady || readinessBlocked));
      return content + '<div class="actions">' + button(personal ? 'Create personal goal' : 'Create lobby', 'create-save', 'primary', cannotSave ? 'disabled' : '') + '</div>';
    }

    if (route === 'createSaved') {
      if (!state.created) return '<h1>No challenge saved yet.</h1>' + p('Choose an activity and review the rules to create your challenge.') + '<button class="primary" data-go="createType">Create a challenge</button>';
      return '<p class="eyebrow">Saved</p><h1>' + (personal ? 'Your goal is saved.' : 'Your lobby is ready.') + '</h1>' +
        (personal ? band(displayTarget(d), metric.unit, 'Your goal') : '<h2>' + esc(metric.title) + '</h2>') +
        (d.metric === 'timed' ? p('Whole run: ' + d.distance + ' km') : '') + range() +
        facts([['Status', personal ? 'Scheduled' : 'Choose your roster'], ['Simulated amount', amount + (personal ? '' : ' per person')], ['Fee', '$0']]) +
        p('Simulated stakes — no real money moves. Nothing can be paid out or redeemed.') +
        p(personal ? 'Your goal, dates and rules are saved. Your challenge starts at midnight on ' + day(first, true) + ' · ' + zone + '.' : 'Choose your friends next. Everyone reviews the roster and rules before agreeing. Creating this lobby did not agree for anyone.') +
        disclosure('Saved rules', rules()) +
        '<div class="actions"><button class="primary" data-go="' + (personal ? 'createdDetail' : 'createdLobby') + '">' + (personal ? 'View goal' : 'View lobby') + '</button></div>';
    }
    return null;
  };
})();
