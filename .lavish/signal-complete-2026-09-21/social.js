/* Signal review mockup only. Fictional people and local state; no network,
 * clipboard, share service, Health read or account mutation is performed.
 * Source: ChallengeV1Views.swift (people/lobby/activity/safeActions),
 * ChallengeV1EntryViews.swift (ChallengeLinkIssuer/ChallengePersonSafety),
 * ChallengeV1Policy.swift, RECEIVED_LEADERBOARD_V2.md and docs/COPY.md.
 */
(() => {
  'use strict';
  const group = 'Friends & safety';
  const routes = {
    socialFriends: ['People in this challenge', group, 'lobby'],
    socialInvite: ['Invite by username', group, 'lobby'],
    socialInviteReceipt: ['Invitation saved', group, 'receipt'],
    socialLink: ['Invitation link', group, 'lobby'],
    socialShare: ['Share invitation', group, 'lobby'],
    socialRevoke: ['Turn off invitation link', group, 'leave'],
    socialLinkReceipt: ['Invitation link is off', group, 'receipt'],
    socialRoster: ['Choose the roster', group, 'lobby'],
    socialProposal: ['Your proposed goal', group, 'create'],
    socialRosterAgreement: ['Roster and goals', group, 'agreement'],
    socialPerson: ['Participant', group, 'lobby'],
    socialReport: ['Report an account', group, 'support'],
    socialReportReceipt: ['Report saved', group, 'receipt'],
    socialBlock: ['Block this account', group, 'leave'],
    socialBlocked: ['Shared details hidden', group, 'existing'],
    socialLeaderboard: ['Saved-score leaderboard', group, 'leaderboard'],
    socialLeaderboardRules: ['Leaderboard rules', group, 'agreement'],
    socialLeaderboardResult: ['Earlier leaderboard result', group, 'result'],
    socialLeaderboardReview: ['Review a leaderboard result', group, 'review'],
    socialLeaderboardReviewReceipt: ['Leaderboard review saved', group, 'reviewReceipt'],
    socialLeaderboardExit: ['Leave leaderboard', group, 'leave'],
    socialLeaderboardExitReceipt: ['Leaderboard exit saved', group, 'exit'],
    socialPending: ['A saved action', group, 'receipt']
  };
  const metrics = {
    steps: { label: 'Steps', unit: 'steps', values: [38420, 41280, 35450, null, 26910, null], source: 'Eligible steps recorded by Apple Watch in Apple Health. Manual entries and identifiable unsupported records do not count.' },
    minutes: { label: 'Activity minutes', unit: 'min', values: [138, 152, 120, null, 96, null], source: 'Apple Exercise credit recorded by Apple Watch. This is not every minute of movement. Apple Health does not identify the activity behind every credit, so indirectly derived credit may count. We exclude identifiable manual and unsupported records.' },
    distance: { label: 'Running distance', unit: 'km', values: [16.4, 18.6, 12.8, null, 9.7, null], source: 'Eligible whole outdoor runs recorded by Apple’s Workout app on Apple Watch. Each run must start and finish inside the challenge dates.' },
    timed: { label: 'Timed run', unit: 'elapsed', values: [1814, 1786, 1852, null, 1927, null], source: 'Whole outdoor runs recorded by Apple’s Workout app on Apple Watch, from 5.00 to 5.10 km inclusive. Each run must fit inside the dates. Time from start to finish includes pauses and rounds up to whole seconds.' }
  };
  function init(s) {
    if (s.socialInitialized) return;
    Object.assign(s, {
      socialInitialized: true, socialUsername: '', socialFound: false,
      socialInviteSaved: false, socialLinkIssued: false, socialLinkRevoked: false,
      socialShared: false, socialTarget: '50000', socialMetric: 'steps',
      socialSelected: [0, 1, 2, 3, 4, 5], socialDeclined: [],
      socialFrozen: null, socialOwnConsent: false, socialOwnReady: false,
      socialChosenPerson: 1, socialReportReason: '', socialReportSaved: null,
      socialBlocked: false, socialPendingAction: null, socialRetryText: '',
      socialStopConfirmed: false, socialReadMessage: '', socialResultMode: 'recorded',
      socialBoardReviewReason: '', socialBoardReviewSaved: null, socialBoardExit: null
    });
  }
  const people = [
    { name: 'You', username: 'alexlee', goal: 50000 },
    { name: 'Sam Parker', username: 'samparker', goal: 60000 },
    { name: 'Maya Chen', username: 'mayachen', goal: 42000 },
    { name: 'Jordan Ross', username: 'jordanross', goal: 48000 },
    { name: 'Riley Ellis', username: 'rileyellis', goal: 55000 },
    { name: 'Casey Reed', username: 'caseyreed', goal: 36000 }
  ];
  const sampleConfig = { kind: 'friends', metric: 'steps', start: '2026-09-30', days: '7', zone: 'America/Los_Angeles', amount: '20', distance: '5', name: 'A week of steps' };
  const lobbyRoutes = ['socialFriends', 'socialInvite', 'socialInviteReceipt', 'socialLink', 'socialShare', 'socialRevoke', 'socialLinkReceipt', 'socialRoster', 'socialProposal', 'socialRosterAgreement'];
  const lobbyFields = ['socialConfig', 'socialTarget', 'socialProposals', 'socialAvailable', 'socialSelected', 'socialDeclined', 'socialFrozen', 'socialOwnConsent', 'socialConsent', 'socialOwnReady', 'socialAllAgreed', 'socialUsername', 'socialInviteSaved', 'socialLinkIssued', 'socialLinkRevoked', 'socialShared'];
  const clone = value => JSON.parse(JSON.stringify(value));
  function parseTarget(metric, input) {
    const raw = String(input ?? '').trim();
    let result;
    if (metric === 'steps') result = /^\d+$/.test(raw) ? Number(raw) : NaN;
    else if (metric === 'distance') {
      if (!/^\d+(?:\.\d{1,6})?$/.test(raw) || Number(raw) > 1000) return null;
      const [whole, decimal = ''] = raw.split('.');
      result = Number(whole) * 1000000 + Number(decimal.padEnd(6, '0'));
    } else {
      if (!/^\d+:\d+$/.test(raw)) return null;
      const [minutes, seconds] = raw.split(':').map(Number);
      result = minutes <= 16666666 && seconds < 60 ? minutes * 60 + seconds : NaN;
    }
    return Number.isInteger(result) && result >= 1 && result <= 1000000000 ? result : null;
  }
  function targetText(metric, value) {
    if (value === null || value === undefined) return 'No proposal yet';
    if (metric === 'steps') return value.toLocaleString('en-US') + ' steps';
    if (metric === 'distance') return value / 1000000 + ' km';
    return Math.floor(value / 60).toLocaleString('en-US') + ' min ' + value % 60 + ' sec';
  }
  const targetHelp = {
    steps: 'Enter a whole number of steps from 1 to 1,000,000,000.',
    minutes: 'Enter minutes and seconds, such as 150:00. Seconds must be 00–59, and the time must be greater than zero.',
    distance: 'Enter kilometres greater than zero and up to 1,000. Use a decimal point and no more than six decimal places.',
    timed: 'Enter minutes and seconds, such as 30:00. Seconds must be 00–59, and the time must be greater than zero.'
  };
  function dateLabel(config, offset = 0) {
    const date = new Date(config.start + 'T12:00:00Z');
    date.setUTCDate(date.getUTCDate() + offset);
    return new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' }).format(date);
  }
  function switchLobby(s, key, config) {
    s.socialSessions ||= {};
    if (s.socialModeKey) s.socialSessions[s.socialModeKey] = Object.fromEntries(lobbyFields.map(field => [field, clone(s[field] ?? null)]));
    s.socialModeKey = key;
    if (s.socialSessions[key]) Object.assign(s, clone(s.socialSessions[key]));
    else Object.assign(s, {
      socialConfig: clone(config), socialTarget: key === 'sample' ? '50000' : '',
      socialProposals: key === 'sample' ? people.map(x => x.goal) : [null, null, null, null, null, null],
      socialAvailable: key === 'sample' ? [0, 1, 2, 3, 4, 5] : [0],
      socialSelected: key === 'sample' ? [0, 1, 2, 3, 4, 5] : [0], socialDeclined: [],
      socialFrozen: null, socialOwnConsent: false, socialConsent: false, socialOwnReady: false, socialAllAgreed: false,
      socialUsername: '', socialInviteSaved: false, socialLinkIssued: false, socialLinkRevoked: false, socialShared: false
    });
    s.socialReadMessage = '';
  }
  function lobbyContext(s, route) {
    if (!s.socialModeKey) switchLobby(s, 'sample', sampleConfig);
    const previous = s.history?.at(-1)?.route;
    const entry = s.history?.length + ':' + previous;
    if (lobbyRoutes.includes(route) && previous === 'createdLobby' && s.created && s.created.kind !== 'personal' && s.socialEntrySeen !== entry) {
      s.socialEntrySeen = entry;
      const key = 'created:' + JSON.stringify(s.created);
      if (s.socialModeKey !== key) switchLobby(s, key, s.created);
    }
    return s.socialConfig;
  }
  function reviewerControls(route, c) {
    if (!lobbyRoutes.includes(route)) return '';
    const s = c.state; init(s); lobbyContext(s, route);
    const b = (text, action) => c.button(text, 'social-' + action, 'secondary');
    let html = '<p>' + (s.socialModeKey === 'sample' ? 'Standalone six-person steps fixture.' : 'This is your saved creation. Requests and agreements from other people are separate sample responses.') + '</p>';
    if (s.socialAvailable.length === 1) html += b('Add five fictional requests', 'demo-requests') + '<p>This reviewer control supplies sample requests and independently proposed goals. It does not send invitations or select people for you.</p>';
    if (s.socialOwnConsent && !s.socialAllAgreed) html += b('Simulate the others agreeing', 'demo-consents') + '<p>Your consent remains separate. This advances the fictional participants only.</p>';
    if (s.socialModeKey !== 'sample') html += b('Open standalone six-person fixture', 'demo-sample');
    else if (s.created && s.created.kind !== 'personal') html += b('Return to my created lobby', 'demo-created');
    return html;
  }
  const sourceMap = {
    socialFriends: 'ChallengeV1Views.swift:842 people(_:) and :887 lobby(_:); per-challenge people only',
    socialInvite: 'ChallengeV1Views.swift:917 exact friend username and invite operation',
    socialLink: 'ChallengeV1EntryViews.swift:242 ChallengeLinkIssuer; BETA_IMPLEMENTATION_PLAN.md:139 reusable links',
    socialRoster: 'ChallengeV1Views.swift:862 select/reject and :927 freeze; D134 2–6 people',
    socialProposal: 'ChallengeV1Views.swift:888 own target proposal; ChallengeV1Policy.swift:30 Metric.parse normalization and bounds; no creator editing another target',
    socialRosterAgreement: 'ChallengeCreationDraft.swift saved config; ChallengeV1Views.swift lobby/freeze/consent and ChallengeV1Policy.swift scoring/missing/allocation; per-lobby config and proposals stay fixed at freeze',
    socialPerson: 'ChallengeV1EntryViews.swift:269 ChallengePersonSafety',
    socialLeaderboard: 'ChallengeV1Views.swift:755 activity(_:) and ChallengeV1Policy.swift; RECEIVED_LEADERBOARD_V2.md',
    socialLeaderboardResult: 'ChallengeV1Views.swift:933 resultText and :943 allocation; RECEIVED_LEADERBOARD_V2.md',
    socialPending: 'ChallengeV1Views.swift:551 retry/abandon and :697 detail recovery'
  };
  const notes = [
    'People, invitations and safety actions belong to a shared challenge. Exact username lookup is case-insensitive. The creator chooses 2–6 people; each person proposes their own goal and consents separately. Links grant access and request a place; they do not create friendship or agreement.',
    'Neutral activity readouts, ruled participant rows and explicit action controls extend the approved Signal system. The four-metric leaderboard shows only saved scores, update times and the deadline. It has no targets or invented daily friend history.',
    'Every person and response is fictional. Buttons change this page only. The share screen illustrates native sharing without sending or copying anything. Failure and pending fixtures do not become successful when Refresh or Retry is tapped. Other participants’ decisions are fixed sample records, never made by your consent.'
  ];
  function scenarios(route) {
    if (!routes[route]) return null;
    if (route === 'socialLeaderboard') return ['populated', 'empty', 'loading', 'offline', 'unavailable', 'pending', 'tie', 'historical'];
    if (route === 'socialLeaderboardResult') return ['populated', 'pending', 'tie', 'fewScores', 'offline'];
    if (route === 'socialLeaderboardReview') return ['populated', 'loading', 'offline'];
    if (route === 'socialLeaderboardExit') return ['populated', 'offline', 'pending'];
    if (route === 'socialLeaderboardRules') return ['populated', 'historical'];
    if (['socialLink', 'socialShare'].includes(route)) return ['populated', 'offline', 'unavailable', 'pending', 'expired'];
    if (['socialInvite', 'socialRoster', 'socialProposal', 'socialRosterAgreement', 'socialReport', 'socialBlock'].includes(route)) return ['populated', 'loading', 'offline', 'pending'];
    if (route === 'socialFriends') return ['populated', 'empty', 'loading', 'offline'];
    return ['populated'];
  }
  function render(route, c) {
    if (!routes[route]) return null;
    const { state: s, esc, button, row, facts, notice, disclosure, heading, section, actions } = c;
    init(s);
    const config = lobbyContext(s, route);
    const agreementConfig = route === 'socialRosterAgreement' && s.socialFrozen ? s.socialFrozen.config : config;
    const hasGoals = config.kind !== 'leaderboard';
    const goalFor = i => s.socialProposals[i];
    const b = (label, action, kind = 'secondary', attributes = '') => button(label, 'social-' + action, kind, attributes);
    const link = (label, target, kind = 'secondary') => `<button type="button" class="${kind}" data-go="${target}">${esc(label)}</button>`;
    const p = text => `<p class="muted">${esc(text)}</p>`;
    const selectedPerson = people[s.socialChosenPerson] || people[1];
    const safeName = s.socialBlocked ? 'Former participant' : selectedPerson.name;
    const readout = (value, unit, label) => `<section class="section"><p class="eyebrow">${esc(label)}</p><div class="metric">${esc(value)}<span class="unit">${esc(unit)}</span></div></section>`;
    const period = (d = agreementConfig) => facts([['Activity', metrics[d.metric].label], ['Starts', dateLabel(d) + ' · midnight'], ['Ends', dateLabel(d, Number(d.days)) + ' · midnight'], ['Time zone', d.zone], ['Simulated entry', '$' + Number(d.amount) + ' per person · Fee $0'], ...(d.metric === 'timed' ? [['Whole run', d.distance + ' km']] : [])]);
    const stale = ['offline', 'loading', 'pending'].includes(s.scenario);
    const disabled = stale ? 'disabled' : '';
    const stateNotice = () => s.scenario === 'offline'
      ? notice('We couldn’t check the latest details. Your saved view is here. Refresh before making a choice.') + b('Refresh', 'refresh')
      : s.scenario === 'loading' ? notice('Checking for an update… You can go back while we check.')
      : s.scenario === 'pending' ? notice('An action is waiting to finish. Check the saved action before making another choice.') + link('View saved action', 'socialPending') : '';
    const readMessage = () => s.socialReadMessage ? notice(esc(s.socialReadMessage)) : '';
    const personRow = (person, index, sub, value, target = true) => `<div class="row"><span class="row-copy"><strong class="row-title">${esc(person.name)}</strong><span class="row-sub">${esc(sub)}</span></span><span class="row-value">${esc(value)}</span>${target && index !== 0 ? b('Details', 'person:' + index, 'text-button', `aria-label="View ${esc(person.name)}"`) : ''}</div>`;
    const names = s.socialSelected.filter(i => !s.socialDeclined.includes(i));
    if (s.socialBlocked && ['socialInvite', 'socialLink', 'socialShare', 'socialRevoke', 'socialRosterAgreement', 'socialProposal', 'socialLeaderboardRules'].includes(route)) return heading('Shared details are hidden') + p('Your own agreements and final history remain available after the safety action.') + link('View your record', 'socialBlocked', 'primary');

    if (route === 'socialFriends') {
      let html = heading('People in this challenge', config.name || metrics[config.metric].label + ' with friends');
      if (s.socialBlocked) return html + notice('Shared details are hidden. Your own agreements and final history remain available.') + link('View your record', 'socialBlocked', 'primary');
      if (s.scenario === 'loading') return html + stateNotice() + link('Back to Challenges', 'challenges');
      if (s.scenario === 'empty' || s.socialAvailable.length === 1) html += section('No requests yet', p('Invite someone by username or share an invitation link. They choose whether to request a place.'));
      html += (s.scenario === 'empty' ? [0] : s.socialAvailable).map(i => s.socialDeclined.includes(i) ? '' : personRow(people[i], i, i === 0 ? 'Creator' : '@' + people[i].username, hasGoals ? targetText(config.metric, goalFor(i)) : names.includes(i) ? 'Selected' : 'Requested')).join('');
      return html + period(config) + stateNotice() + readMessage() + actions(link('Invite by username', 'socialInvite', 'primary') + link('Invitation link', 'socialLink') + link('Choose the roster', 'socialRoster'));
    }
    if (route === 'socialInvite') {
      return heading('Invite by username') + p('Enter the exact username. Uppercase and lowercase letters are treated the same.') +
        `<div class="fields"><label>Username<input data-field="socialUsername" value="${esc(s.socialUsername)}" autocapitalize="none" autocorrect="off" spellcheck="false" placeholder="samparker" aria-label="Exact friend username" ${disabled}></label></div>` +
        stateNotice() + readMessage() + (s.socialInviteSaved ? notice('Your invitation to @samparker is saved. It does not agree for Sam or add them to a roster.') + link('View invitation', 'socialInviteReceipt', 'primary') : actions(b('Invite friend', 'invite', 'primary', disabled))) + p('For this fictional example, use samparker. No message leaves this preview.');
    }
    if (route === 'socialInviteReceipt') return heading(s.socialInviteSaved ? 'Invitation saved' : 'No invitation saved') + (s.socialInviteSaved ? facts([['Username', '@samparker'], ['Challenge', config.name], ['Activity', metrics[config.metric].label], ['Invitation', 'Waiting for a response'], ['Roster place', 'Not selected by this invitation']]) + p('Sam still chooses whether to take part. Everyone reviews the complete agreement separately.') : p('Go back to invite someone by exact username.')) + actions(link('People in this challenge', 'socialFriends', 'primary'));
    if (route === 'socialLink') {
      let html = heading('Invitation link') + p('A person signs in and confirms they’re 21 or older before requesting a place. You choose the roster.');
      if (s.socialLinkRevoked) return html + notice('This link is off. Existing access and saved requests remain unchanged.') + link('View saved status', 'socialLinkReceipt', 'primary');
      if (s.scenario === 'unavailable') return html + notice('Invitation links aren’t available yet. Try again later.') + link('Invite by username', 'socialInvite', 'primary');
      if (s.scenario === 'expired') return html + notice('This invitation link has expired. Existing access and requests stay unchanged.') + facts([['Expired', 'Oct 21, 2026 · 10:00 AM Pacific']]) + link('People in this challenge', 'socialFriends');
      html += stateNotice() + readMessage();
      if (!s.socialLinkIssued) return html + actions(b('Create invitation link', 'issue', 'primary', disabled));
      return html + facts([['Created', 'Sep 21, 2026 · 10:00 AM Pacific'], ['Expires', 'Oct 21, 2026 · 10:00 AM Pacific'], ['Requests', 'Up to 20 different accounts'], ['Access', 'Lobby must remain open']]) + p('A link requests a place. It does not create friendship or agreement.') + actions(link('Share invitation', 'socialShare', 'primary') + link('Turn off this link', 'socialRevoke'));
    }
    if (route === 'socialShare') return heading('Share invitation') + (!s.socialLinkIssued || s.socialLinkRevoked ? notice('There is no active invitation link. Create a link before sharing.') + link('Invitation link', 'socialLink', 'primary') : s.scenario === 'expired' ? notice('This link has expired. Go back to review its status.') + link('Invitation link', 'socialLink') : section(config.name, p(dateLabel(config) + '–' + dateLabel(config, Number(config.days) - 1) + ' · Request a place')) + period(config) + notice('Native share sheet preview. Choose a destination on iPhone; this browser preview sends nothing.') + stateNotice() + actions(b(s.socialShared ? 'Share preview opened' : 'Preview native share sheet', 'share', 'primary', disabled)) + (s.socialShared ? section('Share sheet', facts([['Preview item', config.name + ' invitation'], ['Suggested actions', 'Messages · Mail · Copy'], ['Delivery', 'Nothing sent or copied']])) : '') + link('Done', 'socialLink'));
    if (route === 'socialRevoke') return heading('Turn off this link?') + p('New people won’t be able to use it. People who already used the link keep their access and their saved requests.') + p('This does not cancel the challenge or remove anyone from the roster.') + actions(b('Turn off link', 'revoke', 'primary') + link('Keep link active', 'socialLink'));
    if (route === 'socialLinkReceipt') return heading(s.socialLinkRevoked ? 'Invitation link is off' : 'Link is still active') + (s.socialLinkRevoked ? facts([['Changed', 'Sep 21, 2026 · 10:00 AM Pacific'], ['New link requests', 'Closed'], ['Existing access and requests', 'Unchanged']]) : p('Review the link before turning it off.')) + actions(link('People in this challenge', 'socialFriends', 'primary'));
    if (route === 'socialRoster') {
      if (s.socialBlocked) return heading('Shared details are hidden') + link('View your record', 'socialBlocked', 'primary');
      if (s.socialFrozen) return heading(hasGoals ? 'Roster and goals saved' : 'Roster saved') + p('The saved version stays unchanged. Reopen the lobby to change it; everyone will need to agree again.') + actions(link('Review saved roster', 'socialRosterAgreement', 'primary') + b('Reopen lobby and ask everyone again', 'reopen'));
      let html = heading('Choose the roster', 'YOUR CREATOR VIEW') + p((hasGoals ? 'Each person proposes their own goal. ' : 'No target is needed for this leaderboard. ') + 'Select 2–6 people, including you.') + stateNotice() + readMessage();
      html += s.socialAvailable.map(i => s.socialDeclined.includes(i) ? '' : `<section class="section"><div class="row"><span class="row-copy"><strong>${esc(people[i].name)}</strong><span class="row-sub">${i === 0 ? 'Creator' : '@' + esc(people[i].username)}</span></span><strong>${esc(hasGoals ? targetText(config.metric, goalFor(i)) : names.includes(i) ? 'Selected' : 'Requested')}</strong></div>${i === 0 ? hasGoals ? link('Edit my proposal', 'socialProposal') : '' : actions(b(names.includes(i) ? 'Remove from roster' : 'Select for roster', 'select:' + i, 'secondary', disabled) + (!names.includes(i) ? b('Decline request', 'decline:' + i, 'text-button', disabled) : ''))}</section>`).join('');
      if (s.socialAvailable.length === 1) html += notice('No one has requested a place yet. An invitation does not add someone to your roster.');
      return html + period(config) + facts([['Selected', names.length + ' of 6'], ['Everyone’s agreement', 'Still required']]) + actions(b(hasGoals ? 'Lock in roster and goals' : 'Lock in roster', 'freeze', 'primary', stale || names.length < 2 || (hasGoals && names.some(i => goalFor(i) === null)) ? 'disabled' : ''));
    }
    if (route === 'socialProposal') {
      if (!hasGoals) return heading('No target needed') + p('This leaderboard compares saved activity. Everyone agrees to the same activity and dates.') + period(config) + link('Choose the roster', 'socialRoster', 'primary');
      const label = config.metric === 'timed' ? 'Time to beat' : 'Your goal';
      return heading('Your ' + metrics[config.metric].label.toLowerCase() + ' goal') + p('Only you can change your proposal. The other people’s targets stay theirs.') + `<div class="fields"><label>${label}<input class="big-input" data-field="socialTarget" value="${esc(s.socialTarget)}" inputmode="${config.metric === 'steps' ? 'numeric' : config.metric === 'distance' ? 'decimal' : 'text'}" aria-label="${label}" ${s.socialFrozen || stale ? 'disabled' : ''}><span class="muted">${esc(targetHelp[config.metric])}</span></label></div>` + period(config) + (config.metric === 'timed' ? p('Finish strictly under this time. A time equal to your goal does not meet it. Pauses count.') : '') + stateNotice() + actions(s.socialFrozen ? link('View saved agreement', 'socialRosterAgreement', 'primary') : b('Save my proposal', 'propose', 'primary', disabled));
    }
    if (route === 'socialRosterAgreement') {
      if (!s.socialFrozen) return heading('Choose a roster first') + p('Lock in the selected people before reviewing the complete agreement.') + link('Choose the roster', 'socialRoster', 'primary');
      const d = s.socialFrozen.config, goals = d.kind !== 'leaderboard', metric = metrics[d.metric];
      const scoring = goals
        ? d.metric === 'timed' ? 'Finish an eligible whole run strictly under your agreed time. A time equal to your goal does not meet it. Pauses count.' : 'Reach at least your agreed total during the challenge to meet your goal.'
        : d.metric === 'timed' ? 'Your fastest eligible whole run saved by the deadline wins. A missing run cannot improve your saved time. Equal times share the win.' : 'The highest eligible total saved by the deadline wins. A partial saved total ranks at that total. Equal totals share the win.';
      const allocation = goals ? 'People who meet their goals recover their simulated entries and share confirmed misses evenly. Any remainder and an all-miss pool stay unallocated.' : 'Winners split the remaining simulated pool evenly. Any indivisible remainder stays unallocated.';
      const missing = goals ? 'Missing or unclear activity never proves a missed goal. That person’s simulated entry returns. With fewer than two confirmed results, the challenge does not count and every entry returns.' : 'With no valid saved score, you’re unranked and your simulated entry returns. Fewer than two valid saved scores means the challenge does not count and every entry returns.';
      const source = d.metric === 'timed' ? 'Eligible whole outdoor runs recorded by Apple’s Workout app on Apple Watch. Time from start to finish includes pauses and rounds up to whole seconds. The entire run must fit inside the challenge dates.' : metric.source;
      let html = heading(goals ? 'Roster and goals' : 'Your leaderboard agreement', s.socialAllAgreed ? 'SCHEDULED' : s.socialOwnConsent ? 'YOUR AGREEMENT IS SAVED' : 'REVIEW BEFORE AGREEING') + s.socialFrozen.people.map((x, i) => personRow(x, i, i === 0 ? s.socialOwnConsent ? 'You agreed · Sep 21, 10:00 AM' : 'You have not agreed' : s.socialAllAgreed ? 'Agreement saved' : 'Waiting for their own agreement', goals ? targetText(d.metric, x.goal) : 'Selected', false)).join('') + period(d);
      html += p(scoring) + p(missing) + p(allocation) + p('You may leave before the result is final. Ask for a review within 48 hours of the actual result notice.');
      html += disclosure('Full challenge rules', p(source) + (d.metric === 'timed' ? p('Whole run: ' + d.distance + ' km to ' + (Math.round(Number(d.distance) * 102000000) / 100000000) + ' km, including both distances.') : '') + period(d) + (goals ? p('Initial updates through ' + dateLabel(d, Number(d.days) + 1) + ' at midnight. Corrections through ' + dateLabel(d, Number(d.days) + 2) + ' at midnight · ' + d.zone + '.') : p('Save activity by ' + dateLabel(d, Number(d.days) + 2) + ' at midnight · ' + d.zone + '. First updates and corrections count through the exact deadline.')) + p(scoring) + p(missing) + p(allocation) + p('Everyone must agree to the same people, dates, amount and goals when this format has goals. Any change requires everyone to agree again. Incomplete agreement at the start cancels the challenge and returns every entry.') + p('You may leave before the result is final. Your entry returns. The challenge continues only if at least two eligible people remain.') + p('Your review window lasts 48 hours after the actual result notice. Filing a review pauses the final result and simulated return. Reviewers have 72 hours after filing; delays never shorten these periods.') + p('Your challenge facts are visible to the selected participants. Activity outside this challenge stays private. Assigned reviewers can inspect the limited facts needed for a review. Nothing can be paid out or redeemed. No real money moves.'));
      if (s.socialAllAgreed) return html + notice('Everyone has agreed. Your challenge starts ' + dateLabel(d) + ' at midnight · ' + d.zone + '.') + actions(link('Back to people', 'socialFriends', 'primary'));
      if (s.socialOwnConsent) return html + notice('We’re waiting for the other ' + (s.socialFrozen.people.length - 1) + ' ' + (s.socialFrozen.people.length === 2 ? 'person' : 'people') + ' to agree. Your agreement does not agree for them.') + actions(link('Back to people', 'socialFriends', 'primary'));
      const activityReady = s.socialOwnReady && s.readiness === 'ready' && !stale;
      const activityMessage = activityReady ? 'Matching activity was found in this sample. This does not establish a complete activity history.' : s.readiness === 'noData' ? 'No matching activity is available yet. Sync your Watch and check again.' : s.readiness === 'stale' ? 'Your activity needs another check. Refresh after your Watch syncs.' : s.readiness === 'unavailable' ? 'We can’t use this activity with these rules yet. Check again later.' : 'Check for eligible activity before agreeing.';
      html += stateNotice() + section(activityReady ? 'Activity found' : 'Check your activity', p(activityMessage)) + b('Check activity', 'ready', 'secondary', disabled);
      return html + `<label class="consent"><input type="checkbox" data-check="socialConsent" ${s.socialConsent ? 'checked' : ''} ${disabled}><span>I have read the complete rules and agree</span></label>` + actions(b('Agree to this challenge', 'agree', 'primary', stale || !activityReady || !s.socialConsent ? 'disabled' : ''));
    }
    if (route === 'socialPerson') {
      const boardPerson = s.socialPersonSource === 'leaderboard';
      return heading(safeName) + (s.socialBlocked ? notice('Shared details are hidden. Your previous final results remain in your own history.') + link('View your record', 'socialBlocked', 'primary') : facts([['Username', '@' + selectedPerson.username], ['Challenge', boardPerson ? metrics[s.socialMetric].label + ' with friends' : config.name], ...(boardPerson || !hasGoals ? [] : [['Proposed goal', targetText(config.metric, goalFor(s.socialChosenPerson))]])]) + actions(link('Report this account', 'socialReport') + link('Block this account', 'socialBlock')));
    }
    if (route === 'socialReport') return heading('Report ' + safeName) + p('Choose what happened. This report goes to the people who review safety reports.') + `<div class="choices">${[['username', 'Report username'], ['unwanted_contact', 'Report unwanted contact'], ['unsafe_behavior', 'Report unsafe behavior']].map(([id, label]) => `<label class="choice-check"><input type="radio" name="social-reason" data-field="socialReportReason" value="${id}" ${s.socialReportReason === id ? 'checked' : ''} ${disabled}><span>${label}</span></label>`).join('')}</div>` + stateNotice() + actions(b('Save report', 'report', 'primary', stale ? 'disabled' : ''));
    if (route === 'socialReportReceipt') return heading(s.socialReportSaved ? 'Your report is saved' : 'No report saved') + (s.socialReportSaved ? facts([['About', s.socialReportSaved.name], ['Reason', s.socialReportSaved.reason], ['Saved', 'Sep 21, 2026 · 10:00 AM Pacific']]) + p('Reporting does not block the account. You can choose to block it separately.') : p('Choose a reason before saving a report.')) + actions(link('Back to participant', 'socialPerson', 'primary') + link('Block this account', 'socialBlock'));
    if (route === 'socialBlock') return heading('Block this account?') + p('Shared details are hidden and affected participation ends safely. Previous final results remain in your own history.') + facts([['Account', safeName], ['Your final records', 'Remain available']]) + stateNotice() + actions(b('Block account', 'block', 'primary', disabled) + link('Keep account unblocked', 'socialPerson'));
    if (route === 'socialBlocked') return heading(s.socialBlocked ? 'Shared details are hidden' : 'Account is not blocked') + (s.socialBlocked ? notice('Your block is saved. Affected participation has ended safely. Your own earlier final records remain available.') + p('A saved safety action does not claim that a simulated return has already been recorded.') : p('Open a participant to report or block the account.')) + actions(link('Your saved history', 'history', 'primary') + link('Back to Challenges', 'challenges'));

    if (route === 'socialLeaderboardExit') return heading('Leave this leaderboard?') + facts([['Challenge', metrics[s.socialMetric].label + ' with friends'], ['Dates', 'Sep 18–24, 2026'], ['Your simulated entry', '$20'], ['After leaving', 'Your entry returns']]) + p('Your participation ends. The challenge continues only while at least two eligible people remain. Leaving is not a loss.') + p('A saved exit comes before any recorded simulated return. No real money moves.') + stateNotice() + actions(b('Leave leaderboard', 'confirm-board-exit', 'primary', disabled) + link('Keep participating', 'socialLeaderboard'));
    if (route === 'socialLeaderboardExitReceipt') return heading(s.socialBoardExit ? 'Your exit is saved' : 'No exit saved') + (s.socialBoardExit ? facts([['Challenge', s.socialBoardExit + ' with friends'], ['Left', 'Sep 21, 2026 · 10:00 AM Pacific'], ['Simulated return', 'Update pending']]) + p('You do not need to continue this activity. Your saved agreement remains available.') : p('Open the leaderboard to review your next action.')) + actions(link('Back to saved scores', 'socialLeaderboard', 'primary'));
    if (route === 'socialLeaderboardReview' || route === 'socialLeaderboardReviewReceipt') {
      const label = metrics[s.socialMetric].label;
      if (route === 'socialLeaderboardReviewReceipt') return heading(s.socialBoardReviewSaved ? 'Your review request is saved' : 'No review request saved') + (s.socialBoardReviewSaved ? facts([['Challenge', 'Earlier ' + s.socialBoardReviewSaved.metric.toLowerCase() + ' leaderboard'], ['Reason', s.socialBoardReviewSaved.reason], ['Saved', 'Sep 21, 2026 · 10:00 AM Pacific'], ['Notice reviewed', 'Sep 20, 2026 · 12:00 PM Pacific']]) + p('The final result and simulated return are paused. We’ll update the challenge when the review is complete.') : p('Open the result and check whether review is available.')) + actions(link('Back to earlier result', 'socialLeaderboardResult', 'primary'));
      if (s.socialBoardReviewSaved) return heading('Your request is saved') + link('View saved request', 'socialLeaderboardReviewReceipt', 'primary');
      return heading('What should we check?') + facts([['Challenge', 'Earlier ' + label.toLowerCase() + ' leaderboard'], ['Result notice', 'Sep 20, 2026 · 12:00 PM Pacific'], ['Ask by', 'Sep 22, 2026 · 12:00 PM Pacific']]) + p('Filing a review pauses the final result and simulated return.') + (stale ? notice('We couldn’t confirm that review is open. Refresh before saving your request.') + b('Refresh', 'refresh') : '') + `<div class="fields"><label>Reason<select data-field="socialBoardReviewReason" ${disabled}><option value="">Choose a reason</option>${['My total looks wrong', 'Activity is missing', 'My result looks wrong'].map(x => `<option value="${esc(x)}" ${s.socialBoardReviewReason === x ? 'selected' : ''}>${esc(x)}</option>`).join('')}</select></label></div>` + actions(b('Ask us to review', 'board-review', 'primary', disabled));
    }
    if (route === 'socialLeaderboard' || route === 'socialLeaderboardRules' || route === 'socialLeaderboardResult') {
      const savedReviewMetric = route === 'socialLeaderboardResult' && s.socialBoardReviewSaved?.key;
      const metricKey = savedReviewMetric || s.socialMetric;
      const metric = metrics[metricKey], timed = metricKey === 'timed';
      const display = value => value === null ? '—' : timed ? Math.floor(value / 60) + ':' + String(value % 60).padStart(2, '0') : value.toLocaleString('en-US');
      const choices = savedReviewMetric ? '' : `<div class="segments" aria-label="Leaderboard activity">${Object.entries(metrics).map(([id, m]) => b(id === 'minutes' ? 'Activity min' : id === 'distance' ? 'Running km' : m.label, 'metric:' + id, '', `aria-pressed="${id === metricKey}"`)).join('')}</div>`;
      const historical = s.scenario === 'historical';
      if (route === 'socialLeaderboardRules' && historical) return heading('Your earlier leaderboard rules') + notice('This agreement requires complete activity history. We can’t confirm that history, so the leaderboard remains unavailable.') + facts([['Agreement', 'Original complete-history rules'], ['Activity', metric.label], ['Simulated entry', '$20 per person · Fee $0']]) + p('If the results remain unresolved, the challenge does not count and everyone’s simulated entry returns. Your original agreement, review and safe exit remain available.') + p('The newer saved-score rules do not change this agreement.') + actions(link('Back to leaderboard', 'socialLeaderboard', 'primary'));
      if (route === 'socialLeaderboardRules') return heading('Leaderboard rules') + section(metric.label, p(timed ? 'Fastest eligible whole run wins. There is no goal time.' : 'Highest eligible saved total wins. There is no target.')) + p(metric.source) + facts([['Starts', 'Sep 18, 2026 · 12:00 AM Pacific'], ['Ends', 'Sep 25, 2026 · 12:00 AM Pacific'], ['Save activity by', 'Sep 27, 2026 · 12:00 AM Pacific'], ['Simulated entry', '$20 each · Fee $0']]) + p('First updates and corrections count through the save deadline, including the exact deadline. A partial saved total ranks at that total. A missing run cannot improve a saved time.') + p('No valid saved score means unranked, with that person’s entry returned. Fewer than two valid scores means the challenge does not count and every entry returns. Equal normalized scores share the win.') + p('You can leave before the result is final. You have 48 hours after the actual result notice to ask for a review. Reviewers have 72 hours after filing; delays never shorten these windows.') + p('Selected friends see only this challenge’s roster, scores and results. No raw records, routes or unrelated activity are shared.') + p('Nothing can be paid out or redeemed. No real money moves.') + actions(link('Back to saved scores', 'socialLeaderboard', 'primary'));
      if (route === 'socialLeaderboardResult') {
        const pending = s.scenario === 'pending' || !!s.socialBoardReviewSaved, few = s.scenario === 'fewScores', tie = s.scenario === 'tie', offline = s.scenario === 'offline';
        const status = few ? 'This challenge didn’t count' : pending ? 'Result ready to review' : tie ? 'Shared winning result' : 'Result confirmed';
        return heading('Earlier ' + metric.label.toLowerCase() + ' result', 'SEP 7–13, 2026') + choices + section(status, p(few ? 'Only one valid score was saved. At least two are needed.' : tie ? 'Your normalized score and Sam’s are equal. All six people have valid saved scores.' : 'All six people have valid saved scores. This is a separate finished challenge, with its own saved result.')) + facts([['Your result', few ? 'No valid saved score' : tie ? 'Shared winner' : 'Winner'], ['Review', s.socialBoardReviewSaved ? 'Under review' : pending ? 'Open until Sep 22 · 12:00 PM Pacific' : 'Complete'], ['Your simulated entry', '$20'], ['Simulated return', pending ? 'Update pending' : few ? '$20 recorded' : tie ? '$60 recorded' : '$120 recorded']]) + (offline ? notice('We couldn’t refresh this result. Your saved record is still here. Refresh before requesting a review.') + b('Refresh', 'refresh') : '') + p('Nothing can be paid out or redeemed. No real money moved.') + (pending ? notice('Your final result and simulated return are paused. No return has been recorded.') + link(s.socialBoardReviewSaved ? 'View review request' : 'Ask for a review', s.socialBoardReviewSaved ? 'socialLeaderboardReviewReceipt' : 'socialLeaderboardReview', 'primary') : '') + actions(link('Current saved scores', 'socialLeaderboard'));
      }
      let html = heading(metric.label + ' with friends', 'SEP 18–24, 2026 · 6 PEOPLE') + choices;
      if (s.socialBoardExit) return html + notice('You left this leaderboard. Your saved exit and agreement remain available.') + actions(link('View exit receipt', 'socialLeaderboardExitReceipt', 'primary') + link('Saved rules', 'socialLeaderboardRules'));
      if (s.socialBlocked) return html + notice('Shared details are hidden after a safety action. Your own final records remain available.') + link('View your record', 'socialBlocked', 'primary');
      if (historical) return html + section('Leaderboard — Not available yet', p('This older agreement requires a complete history that we can’t confirm. It keeps its original rules.')) + p('You can still review your records or leave the challenge safely.') + actions(link('Saved rules', 'socialLeaderboardRules') + b('Leave this challenge', 'leaderboard-exit'));
      if (s.scenario === 'loading') return html + readout('—', metric.unit, 'Your saved score') + notice('Checking saved scores… You can return to Challenges while we check.') + link('Back to Challenges', 'challenges');
      const values = metric.values.slice();
      if (['empty', 'unavailable'].includes(s.scenario)) values[0] = null;
      if (s.scenario === 'tie') values[0] = values[1];
      html += readout(display(values[0]), metric.unit, 'Your saved score') + p(values[0] === null ? 'Unranked — no valid saved score. Your simulated entry returns if this remains your final result.' : 'Last saved update · Sep 21, 2026 · 9:35 AM Pacific');
      html += facts([['Save activity by', 'Sep 27, 2026 · 12:00 AM Pacific']]);
      if (s.scenario === 'pending') html += notice('We haven’t confirmed this update. The score above is your last saved score. Refresh to recover it; if your result is still wrong, ask for a review before the deadline.');
      if (s.scenario === 'offline') html += notice('We couldn’t refresh the saved scores. Your last update remains here. Try Refresh when you reconnect.');
      if (s.scenario === 'unavailable') html += notice('No eligible update is available for you. Missing activity never becomes a zero. Check Apple Health and try Refresh after your Watch syncs.');
      html += actions(b('Refresh', 'refresh')) + readMessage();
      const ranked = people.map((person, i) => ({ person, index: i, value: values[i] })).sort((a, z) => a.value === null ? 1 : z.value === null ? -1 : timed ? a.value - z.value : z.value - a.value);
      html += section('Saved scores', ranked.map((x, i) => {
        const rank = x.value === null ? '—' : 1 + ranked.filter(z => z.value !== null && (timed ? z.value < x.value : z.value > x.value)).length;
        return `<div class="row"><span class="row-value" style="min-width:28px;text-align:left">${rank}</span><span class="row-copy"><strong class="row-title">${esc(x.person.name)}</strong><span class="row-sub">${x.value === null ? 'Unranked · no saved score' : 'Saved Sep 21 · 9:35 AM'}</span></span><span class="row-value">${display(x.value)}<small class="row-sub">${x.value === null ? '' : esc(metric.unit)}</small></span>${x.index ? b('Details', 'person:' + x.index, 'text-button', `aria-label="View ${esc(x.person.name)}"`) : ''}</div>`;
      }).join(''));
      return html + p(timed ? 'A missing run cannot improve your saved time. Equal times share the win.' : 'Partial saved totals rank at those totals. Missing or late activity does not count.') + actions(link('Leaderboard rules', 'socialLeaderboardRules') + link('Earlier result', 'socialLeaderboardResult') + b('Leave this challenge', 'leaderboard-exit'));
    }
    if (route === 'socialPending') return heading(s.socialStopConfirmed ? 'Waiting stopped' : 'An action is waiting to finish') + (s.socialStopConfirmed ? p('The sample response confirms that the action did not complete. Your earlier saved records stay unchanged.') : p('Your action is saved on this phone. Retry checks that same action; it does not start another one.')) + facts([['Action', s.socialPendingAction || 'Save invitation'], ['Status', s.socialStopConfirmed ? 'Not completed' : 'Waiting for confirmation']]) + (s.socialRetryText ? notice(esc(s.socialRetryText)) : '') + (!s.socialStopConfirmed ? actions(b('Retry saved action', 'retry', 'primary') + b('Stop waiting for this action', 'stop')) : '') + p('Stopping first checks whether the action completed and prevents a late request from changing anything.') + link('Back to people', 'socialFriends');
    return null;
  }
  function act(action, c) {
    if (!action.startsWith('social-')) return false;
    const { state: s, go, render: redraw, error } = c;
    init(s);
    const config = lobbyContext(s, s.route);
    const [name, value] = action.slice(7).split(':');
    const rerender = () => { redraw(); return true; };
    const navigate = route => { go(route); return true; };
    const fail = message => { error(message); return true; };
    const blocked = () => {
      if (s.scenario === 'pending') { s.socialPendingAction = 'Save ' + (name === 'invite' ? 'invitation' : name === 'report' ? 'report' : 'challenge change'); go('socialPending'); return true; }
      if (['loading', 'offline'].includes(s.scenario)) { error('We couldn’t confirm this change. Refresh the latest details before trying again.'); return true; }
      return false;
    };
    if (name === 'refresh') {
      s.socialReadMessage = ['offline', 'pending', 'unavailable'].includes(s.scenario) ? 'We still couldn’t confirm a new update. Your last saved information stays here. Try again later.' : 'The saved information is up to date. No new activity was added.';
      return rerender();
    }
    if (name === 'metric' && metrics[value]) { s.socialMetric = value; s.socialReadMessage = ''; return rerender(); }
    if (name === 'demo-requests') {
      if (s.socialFrozen) return fail('Reopen the lobby before adding sample requests.');
      const samples = { steps: ['50000', '60000', '42000', '48000', '55000', '36000'], minutes: ['150:00', '180:00', '120:00', '140:00', '165:00', '100:00'], distance: ['20', '24', '16', '18', '22', '14'], timed: ['30:00', '28:00', '32:00', '31:00', '29:00', '35:00'] };
      s.socialAvailable = [0, 1, 2, 3, 4, 5];
      const own = s.socialProposals[0];
      s.socialProposals = samples[config.metric].map(x => parseTarget(config.metric, x));
      s.socialProposals[0] = own;
      return rerender();
    }
    if (name === 'demo-consents') { if (!s.socialOwnConsent) return fail('Save your own agreement before advancing the sample participants.'); s.socialAllAgreed = true; return rerender(); }
    if (name === 'demo-sample') { switchLobby(s, 'sample', sampleConfig); return s.route === 'socialFriends' ? rerender() : navigate('socialFriends'); }
    if (name === 'demo-created') { if (s.created && s.created.kind !== 'personal') switchLobby(s, 'created:' + JSON.stringify(s.created), s.created); return s.route === 'socialFriends' ? rerender() : navigate('socialFriends'); }
    if (name === 'person') { s.socialChosenPerson = Number(value); s.socialPersonSource = s.route?.startsWith('socialLeaderboard') ? 'leaderboard' : 'lobby'; return navigate('socialPerson'); }
    if (name === 'leaderboard-exit') return navigate('socialLeaderboardExit');
    if (name === 'confirm-board-exit') { if (blocked()) return true; s.socialBoardExit = metrics[s.socialMetric].label; return navigate('socialLeaderboardExitReceipt'); }
    if (name === 'invite') {
      if (blocked()) return true;
      const username = s.socialUsername.trim().replace(/^@/, '').toLowerCase();
      if (!username) return fail('Enter the exact username before inviting a friend.');
      if (username === 'alexlee') return fail('That’s your username. Enter your friend’s username.');
      if (username !== 'samparker') return fail('We couldn’t find that username. Check the spelling and try again.');
      if (s.socialBlocked) return fail('This account is blocked. Return to your saved challenge.');
      s.socialInviteSaved = true; return navigate('socialInviteReceipt');
    }
    if (name === 'issue') { if (blocked()) return true; if (s.scenario === 'unavailable') return fail('Invitation links aren’t available. Invite by username or try later.'); s.socialLinkIssued = true; s.socialLinkRevoked = false; return rerender(); }
    if (name === 'share') { if (blocked()) return true; if (!s.socialLinkIssued || s.socialLinkRevoked) return fail('There is no active invitation link. Return to Invitation link.'); s.socialShared = true; return rerender(); }
    if (name === 'revoke') { if (blocked()) return true; if (!s.socialLinkIssued) return fail('No invitation link has been created. Return to people in this challenge.'); s.socialLinkRevoked = true; return navigate('socialLinkReceipt'); }
    if (name === 'select') {
      if (blocked()) return true; if (s.socialFrozen) return fail('Reopen the lobby before changing the roster. Everyone will need to agree again.');
      const i = Number(value); if (i < 1 || i > 5 || !s.socialAvailable.includes(i) || s.socialDeclined.includes(i)) return true;
      s.socialSelected = s.socialSelected.includes(i) ? s.socialSelected.filter(x => x !== i) : [...s.socialSelected, i]; return rerender();
    }
    if (name === 'decline') { if (blocked()) return true; const i = Number(value); if (!s.socialSelected.includes(i)) s.socialDeclined.push(i); return rerender(); }
    if (name === 'propose') { if (blocked()) return true; if (config.kind === 'leaderboard') return navigate('socialRoster'); if (parseTarget(config.metric, s.socialTarget) === null) return fail(targetHelp[config.metric]); if (s.socialFrozen) return fail('Reopen the lobby before editing this proposal.'); s.socialProposals[0] = parseTarget(config.metric, s.socialTarget); return navigate('socialRoster'); }
    if (name === 'freeze') {
      if (blocked()) return true;
      const hasGoals = config.kind !== 'leaderboard', ownGoal = s.socialProposals[0];
      if (hasGoals && ownGoal === null) return fail('Save your own goal proposal before locking in the roster.');
      const selected = s.socialSelected.filter(i => s.socialAvailable.includes(i) && !s.socialDeclined.includes(i));
      if (selected.length < 2 || selected.length > 6 || !selected.includes(0)) return fail('Select 2–6 people, including you, before locking in the roster.');
      if (hasGoals && selected.some(i => i !== 0 && s.socialProposals[i] === null)) return fail('Wait for each selected person to propose a goal before locking in the roster.');
      s.socialFrozen = { config: clone(config), people: selected.map(i => ({ ...people[i], goal: hasGoals ? i === 0 ? ownGoal : s.socialProposals[i] : null })) };
      s.socialOwnConsent = false; s.socialConsent = false; s.socialOwnReady = false; s.socialAllAgreed = false; return navigate('socialRosterAgreement');
    }
    if (name === 'reopen') { if (blocked()) return true; s.socialFrozen = null; s.socialOwnConsent = false; s.socialConsent = false; s.socialOwnReady = false; s.socialAllAgreed = false; return navigate('socialRoster'); }
    if (name === 'ready') {
      s.socialOwnReady = false;
      if (blocked()) return true;
      if (s.readiness !== 'ready') return fail(s.readiness === 'notConnected' ? 'Connect Apple Health before checking your activity again.' : s.readiness === 'checking' ? 'We’re still checking. Wait for an update before agreeing.' : s.readiness === 'unsupported' ? 'This source doesn’t match the challenge rules. Check supported Apple Watch activity, then try again.' : s.readiness === 'unavailable' ? 'We can’t use this activity with these rules yet. Check again later.' : 'We couldn’t find enough matching activity. Sync your Watch and check again.');
      s.socialOwnReady = true; return rerender();
    }
    if (name === 'agree') { if (blocked()) return true; if (!s.socialFrozen || !s.socialConsent || !s.socialOwnReady || s.readiness !== 'ready') return fail('Review the saved roster, check your activity and choose whether to agree.'); s.socialOwnConsent = true; return rerender(); }
    if (name === 'report') {
      if (blocked()) return true;
      const reasons = { username: 'Username', unwanted_contact: 'Unwanted contact', unsafe_behavior: 'Unsafe behavior' };
      if (!reasons[s.socialReportReason]) return fail('Choose what happened before saving your report.');
      s.socialReportSaved = { name: s.socialBlocked ? 'Former participant' : people[s.socialChosenPerson].name, reason: reasons[s.socialReportReason] };
      return navigate('socialReportReceipt');
    }
    if (name === 'block') { if (blocked()) return true; s.socialBlocked = true; return navigate('socialBlocked'); }
    if (name === 'board-review') { if (blocked()) return true; if (!s.socialBoardReviewReason) return fail('Choose what you’d like us to check before saving your request.'); s.socialBoardReviewSaved = { key: s.socialMetric, metric: metrics[s.socialMetric].label, reason: s.socialBoardReviewReason }; return navigate('socialLeaderboardReviewReceipt'); }
    if (name === 'retry') { s.socialRetryText = 'We still couldn’t confirm this action. It remains saved. Try again later or stop waiting.'; return rerender(); }
    if (name === 'stop') { s.socialStopConfirmed = true; s.socialRetryText = ''; return rerender(); }
    return true;
  }
  window.SignalSocial = { routes, notes, sourceMap, render, scenarios, act, reviewerControls, scenarioLabels: { tie: 'Equal saved scores', fewScores: 'Fewer than two valid scores', historical: 'Older unavailable policy' } };
})();
