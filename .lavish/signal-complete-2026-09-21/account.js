/* Signal account and Health review screens. Fictional, in-memory interaction only.
 * Native source: LaunchingView, GameTimeApp, AppleSignIn, YouView,
 * ChallengeV1EntryViews, ChallengeHealthViews and ChallengeV1Views.
 * OS authentication, Health permission, Mail and external documents are labeled
 * review stand-ins. No credential, permission, message or account is changed.
 */
(function () {
  'use strict';

  const titles = {
    launch: 'Opening GameTime', signin: 'Sign in', signedOut: 'Sign in',
    appleSignIn: 'Apple sign-in', onboarding: 'Set your profile',
    ageConfirmation: 'Age confirmation', settings: 'Settings', privacy: 'Your privacy',
    healthSettings: 'Activity & dates', healthCheck: 'Check your activity',
    healthPermission: 'Apple Health access', healthHelp: 'Apple Health help',
    legacyPrivacy: 'Your Personal privacy', legacyHealth: 'Personal steps access',
    accountSupport: 'Account & support', support: 'Contact beta support',
    supportDraft: 'Support message', supportSaved: 'Support draft',
    privacyPolicy: 'Privacy Policy', betaTerms: 'Beta Terms',
    deleteAccount: 'Delete account', reauthenticate: 'Confirm with Apple',
    deletionSaving: 'Saving account deletion', deletionReceipt: 'Account deletion',
    deletionReview: 'Review a saved result', deletionAppeal: 'Appeal an account decision',
    deletionRightsSaved: 'Your request is saved', accountPaused: 'Account access',
    accountAppeal: 'Review your account', accountAppealSaved: 'Account review request'
  };
  const routes = Object.fromEntries(Object.entries(titles).map(([id, title]) => [id, [title, 'Account & Health', 'support']]));
  const states = {
    notConnected: ['Connect Apple Health', 'Connect Apple Health when you’re ready to check your activity. You can keep browsing without connecting.'],
    checking: ['Checking your activity', 'We’re checking the activity on this phone. You can leave and refresh when you return.'],
    ready: ['Activity found', 'We found matching activity. This doesn’t mean your entire activity history is available.'],
    noMatching: ['No matching activity yet', 'We couldn’t find matching activity in the last 30 days. Check your Apple Health settings and refresh after your Watch has synced.'],
    unavailable: ['Activity temporarily unavailable', 'Check your connection and try Refresh. Missing activity doesn’t count against you.'],
    incomplete: ['Activity needs another check', 'Some activity changed or couldn’t be read. Try Refresh after your Watch has synced. We won’t treat missing activity as zero.'],
    unsupported: ['Activity not available yet', 'We can’t use this activity with these rules yet. Choose another activity or check again later.']
  };
  const sources = {
    steps: ['Steps', 'Apple Watch', 'We count eligible steps recorded by Apple Watch in Apple Health. Entries marked as manual and records from unsupported apps or devices don’t count.'],
    minutes: ['Activity minutes', 'Apple Watch · Apple Exercise credit', 'Activity minutes use Apple Exercise credit recorded by Apple Watch. They don’t represent every minute you move. We exclude entries marked as manual and identifiable unsupported apps or devices. Apple Health doesn’t tell us which activity caused every credit, so indirectly derived credit may count.'],
    distance: ['Running distance', 'Apple Watch · Apple Workout', 'We count eligible outdoor runs recorded by Apple’s Workout app on Apple Watch. A whole run must fit inside your challenge dates; a run crossing either boundary doesn’t count.'],
    timed: ['Timed run', 'Apple Watch · Apple Workout', 'We use whole outdoor runs recorded by Apple’s Workout app on Apple Watch. Time from start to finish includes pauses. You must finish strictly under your goal time.']
  };
  const stamp = 'Sep 21, 2026 · 10:00 AM Pacific';

  function init(s) {
    const defaults = {
      accountName: s.accountSignedIn === false ? '' : 'Alex Lee', accountUsername: '', accountAge: false,
      accountAgeSaved: false, accountProfileSaved: false, accountSignedIn: true,
      accountHealthMetric: 'steps', accountHealthState: 'notConnected',
      accountHealthReturn: 'healthCheck', accountHealthPermission: false,
      accountSupportSubject: 'GameTime support', accountSupportMessage: '',
      accountSupportReceipt: null, accountDeletionState: 'held',
      accountDeletionSaved: false, accountDeletionConfirmed: false,
      accountDeletionReviewReason: 'wrong_total', accountDeletionRequest: null,
      accountDeletionReviewSaved: null, accountDeletionAppealSaved: null,
      accountDeletionPending: null, accountAppealSaved: false,
      accountAuthPurpose: 'signin', accountAuthReturn: 'onboarding'
    };
    Object.entries(defaults).forEach(([key, value]) => { if (s[key] === undefined) s[key] = value; });
  }

  // Root owns challenge history, drafts and other private product state. This
  // handshake clears both owners and carries forward only the signed-out
  // deletion receipt and the open rights attached to that receipt.
  function clearAccount(ctx) {
    const previous = ctx.state;
    const retained = { accountSignedIn: false, scenario: 'populated' };
    if (previous.accountDeletionSaved) {
      for (const key of [
        'accountDeletionSaved', 'accountDeletionState', 'accountDeletionRequest',
        'accountDeletionReviewSaved', 'accountDeletionAppealSaved', 'accountDeletionPending'
      ]) {
        if (previous[key] !== undefined) retained[key] = previous[key];
      }
    }
    for (const key of Object.keys(previous)) if (key.startsWith('account')) delete previous[key];
    const replacement = ctx.clearAccountState?.();
    const active = replacement && typeof replacement === 'object' ? replacement : ctx.state;
    Object.assign(active, retained);
    ctx.state = active;
    return active;
  }
  const routeButton = (ctx, label, target, style = 'secondary') => `<button type="button" class="${style}" data-go="${ctx.esc(target)}">${ctx.esc(label)}</button>`;
  const field = (ctx, label, key, help = '', attrs = '') => `<label>${ctx.esc(label)}<input data-field="${key}" value="${ctx.esc(ctx.state[key])}" ${attrs}>${help ? `<span class="muted">${ctx.esc(help)}</span>` : ''}</label>`;
  const refresh = ctx => ctx.button('Refresh', 'account-refresh', 'secondary');
  const stale = s => ['offline', 'loading', 'unavailable'].includes(s.scenario);
  const receiptMark = '<div class="receipt-mark" aria-hidden="true">✓</div>';
  const systemNote = text => `<div class="notice"><p class="eyebrow">SYSTEM SCREEN · REVIEW PREVIEW</p><p>${text}</p></div>`;
  const linkNote = text => `<p class="muted">${text}</p>`;

  function loading(ctx, title, text) {
    return ctx.heading(title) + `<div role="status"><p class="eyebrow">PLEASE WAIT</p><p>${text}</p></div>`;
  }

  function signedOut(ctx) {
    const { state: s, heading, section, notice, button, actions } = ctx;
    let html = '<p class="eyebrow">GAMETIME</p>' + heading('Choose a goal.<br>Set your dates.') + '<p class="muted">Follow your activity and see how you’re doing.</p>';
    if (s.scenario === 'loading') html += notice('Signing in…');
    else if (s.scenario === 'offline') html += notice('We couldn’t sign you in. Check your connection and try again.');
    else if (s.scenario === 'unavailable') html += notice('Apple sign-in didn’t finish. Try again or contact beta support.');
    html += actions(button('Sign in with Apple', 'account-signin', 'apple-sign-in', s.scenario === 'loading' ? 'disabled' : ''));
    if (s.accountDeletionSaved || s.scenario === 'pending') html += section('Your account', notice('Normal account access is closed. Your saved account-deletion receipt is still available.') + routeButton(ctx, 'Check account deletion', 'deletionReceipt'));
    html += section('Before you start', '<p>Review the full agreement before you start.</p>') + '<p class="muted">Signing in creates your private account. Apple only shares your name the first time, and you can change it on the next screen.</p>';
    html += actions(button('Try demo mode', 'account-demo', 'secondary'));
    html += section('Help & documents', ctx.row('Privacy Policy', 'How GameTime handles your data', '', 'privacyPolicy') + ctx.row('Beta Terms', 'The terms for this beta release', '', 'betaTerms') + ctx.row('Contact beta support', 'Tell us what happened', '', 'support'));
    return html;
  }

  function appleAuth(ctx, isDeletion) {
    const { state: s, heading, notice, button, actions } = ctx;
    let html = heading(isDeletion ? 'Confirm with Apple' : 'Sign in with Apple');
    html += systemNote('Apple presents its own secure confirmation on your iPhone. This browser mockup cannot sign you in or confirm your identity.');
    if (s.scenario === 'offline') html += notice('We couldn’t get Apple confirmation. Check your connection and try again.');
    else if (s.scenario === 'unavailable') html += notice('Apple confirmation didn’t finish. Try again.');
    else if (s.scenario === 'loading') return html + '<p role="status">Waiting for Apple…</p><p class="muted">Complete or cancel the Apple prompt on your iPhone.</p>';
    html += ctx.facts([['App', 'GameTime'], ['Next', isDeletion ? 'Save account deletion' : 'Set your profile']]);
    html += actions(button('Continue with fictional account', isDeletion ? 'account-delete-confirmed' : 'account-auth-complete', 'primary') + button('Cancel', 'account-auth-cancel', 'secondary'));
    return html + linkNote('Review control only. No Apple account is accessed.');
  }

  function onboarding(ctx) {
    const { state: s, heading, notice, actions, button } = ctx;
    const busy = s.scenario === 'loading';
    let html = heading('Make GameTime yours') + '<p class="muted">Add your name and choose the username you’ll use in GameTime.</p>';
    html += `<div class="fields">${field(ctx, 'Your name', 'accountName', 'Name: 1–50 characters', `autocomplete="name" maxlength="50" ${busy ? 'disabled' : ''}`)}${field(ctx, 'Username', 'accountUsername', 'Username: 3–30 letters, numbers, or underscores; starts with a letter', `autocomplete="username" autocapitalize="none" spellcheck="false" maxlength="30" ${busy ? 'disabled' : ''}`)}</div><p class="muted">Pick carefully — you can’t change your username yet.</p>`;
    if (s.scenario === 'offline') html += notice('We couldn’t save your profile. Your entries are still here. Check your connection and try again.');
    if (s.scenario === 'unavailable') html += notice('That username isn’t available. Choose another one and try again.');
    if (s.scenario === 'pending') html += notice('We haven’t confirmed whether your profile was saved. Try again with the same name and username.');
    html += actions(button(busy ? 'Saving profile…' : 'Enter GameTime', 'account-profile-save', 'primary', busy || !s.accountName.trim() || !s.accountUsername.trim() ? 'disabled' : '') + button('Use a different Apple account', 'account-sign-out', 'secondary', busy ? 'disabled' : ''));
    return html;
  }

  function age(ctx) {
    const { state: s, heading, notice, button, actions, facts } = ctx;
    if (s.accountAgeSaved) return receiptMark + heading('Age confirmation saved') + facts([['Confirmation', '21 or older'], ['Saved', stamp]]) + '<p>We keep your confirmation. We don’t ask for your date of birth or an identity document.</p>' + actions(routeButton(ctx, 'Continue to Challenges', 'challenges', 'primary'));
    let html = heading('Are you 21 or older?') + '<p>You need to be 21 or older to take part.</p><p class="muted">We save this confirmation and when you made it. We don’t ask for your date of birth or an identity document.</p>';
    if (stale(s)) html += notice(s.scenario === 'loading' ? 'Checking your account…' : 'We couldn’t check your account. Refresh before saving your confirmation.');
    if (s.scenario === 'pending') return html + notice('Your confirmation is saved on this phone, but we haven’t confirmed the response. Try the saved action again.') + actions(button('Retry saved confirmation', 'account-age-retry', 'primary') + routeButton(ctx, 'Back to Challenges', 'challenges'));
    html += `<label class="consent"><input type="checkbox" data-check="accountAge" ${s.accountAge ? 'checked' : ''} ${stale(s) ? 'disabled' : ''}><span>I confirm I am 21 or older</span></label>`;
    html += actions(button('Save age confirmation', 'account-age-save', 'primary', !s.accountAge || stale(s) ? 'disabled' : '') + (stale(s) ? refresh(ctx) : routeButton(ctx, 'Not now', 'challenges')));
    return html;
  }

  function settings(ctx) {
    return ctx.heading('Settings') + ctx.section('Activity & dates', ctx.row('Apple Health', 'Connect activity from a goal when you’re ready', '', 'healthSettings') + ctx.facts([['Time zone', 'Pacific time · Los Angeles']]) + '<p class="muted">Existing challenges keep their agreed dates and time zone.</p>') + ctx.section('Your account', ctx.row('Your privacy', 'What we read, what we send, and what stays on your phone', '', 'privacy') + ctx.row('Account & support', 'Documents, support, sign out, and account deletion', '', 'accountSupport')) + ctx.section('Demo', '<p class="muted">Explore fictional challenges without changing your account.</p>' + ctx.button('Open demo mode', 'account-demo', 'secondary'));
  }

  function privacy(ctx, legacy) {
    const { heading, section } = ctx;
    if (legacy) return heading('Your privacy') + section('Only you can see your challenges', '<p>Your goal, your progress, and how each week turned out are yours alone. Nobody else can look them up.</p>') + section('We read steps, not your health history', '<p>We only read step counts from Apple Health. Steps Apple marks as manually entered aren’t counted, and nothing else in Apple Health is ever read.</p>') + section('If we can’t see your data, you don’t lose', '<p>When steps go missing or don’t add up, the week doesn’t count — it’s never treated as a miss. If the problem is on our end, that’s on us.</p>') + section('Private challenge and test payment details', '<p>Your goal and progress stay private. Our payment provider handles test payment details; GameTime keeps only the test payment references and status needed for payment tests.</p>') + ctx.actions(routeButton(ctx, 'Apple Health access', 'legacyHealth') + routeButton(ctx, 'Account & support', 'accountSupport'));
    return heading('Your privacy') + section('You choose what you share', '<p>Your personal goals stay private. Selected friends can see the username, agreed goal, activity and result for your shared challenge.</p>') + section('Activity for your goal', '<p>With your permission, we read the Apple Health activity needed for the goal you choose. We send the scoring details needed for that challenge. We don’t share raw Health records or routes with friends.</p>') + section('Missing activity isn’t a loss', '<p>Missing data alone never proves a missed goal. Best-result challenges use their agreed scoring rules and deadline. Open any challenge to see its rules or ask for a review.</p>') + section('You can leave or get help', '<p>Open a challenge to leave, report a problem or block an account. Account & support includes your documents, support and account deletion.</p>') + ctx.actions(routeButton(ctx, 'Activity & dates', 'healthSettings') + routeButton(ctx, 'Account & support', 'accountSupport'));
  }

  function healthSettings(ctx, legacy) {
    const { heading, section, row, facts, actions, button, state: s } = ctx;
    if (legacy) {
      const connected = s.accountHealthState === 'ready' || s.scenario === 'ready';
      return heading('Apple Health') + section(connected ? 'Health connected' : 'Steps', `<p>${connected ? 'GameTime can update your challenge automatically from your Apple Health step history.' : 'Connect Apple Health so GameTime can update your challenge automatically from your step history.'}</p>`) + (s.scenario === 'unavailable' ? ctx.notice('Health connection checks aren’t available yet. Check again later.') : actions(button(connected ? 'Refresh activity check' : 'Connect Apple Health', 'account-legacy-health', 'primary'))) + section('Your choice', '<p>Change app access in Apple Health. Missing final step data does not count against you.</p>') + row('Apple Health help', 'Manage activity access and permissions', '', 'healthHelp');
    }
    return heading('Activity & dates') + section('Apple Health', '<p>Connect activity from a goal when you’re ready. GameTime checks the source and dates for that goal.</p>') + facts([['Time zone', 'Pacific time · Los Angeles']]) + '<p class="muted">Change app access in Apple Health. Existing challenges keep their agreed dates and time zone.</p>' + row('Apple Health help', 'Manage activity access and permissions', '', 'healthHelp') + section('Continue with a goal', row('Your running goal', 'View the activity saved for Sep 21–27', '', 'personalDetail'));
  }

  function healthState(s) {
    return ({ ready: 'ready', empty: 'noMatching', loading: 'checking', offline: 'unavailable', unavailable: 'unsupported', incomplete: 'incomplete', denied: 'notConnected', pending: 'ready' })[s.scenario] || s.accountHealthState;
  }

  function health(ctx) {
    const { state: s, heading, facts, section, notice, button, actions, esc } = ctx;
    const status = healthState(s), source = sources[s.accountHealthMetric] || sources.steps;
    let explanation = states[status][1];
    if (status === 'noMatching' && s.accountHealthMetric === 'timed') explanation = 'We couldn’t find a comparable outdoor run in the last 90 days. Check your Apple Health settings and refresh after your Watch has synced.';
    let html = heading(states[status][0], source[0].toUpperCase()) + `<p>${explanation}</p>` + facts([['Activity', source[0]], ['Source', source[1]]]);
    html += section('What counts', `<p>${source[2]}</p>`);
    if (s.accountHealthMetric === 'timed') html += facts([['Whole outdoor run', '5 to 5.1 km'], ['Time', 'Start to finish, including pauses']]);
    if (status === 'ready') html += facts([['Checked on this phone', stamp], ['Readiness', s.scenario === 'pending' ? 'Waiting to send this activity check' : 'Matching activity found']]) + notice(s.scenario === 'pending' ? 'Finish sending this activity check before you agree. Try Refresh.' : 'This check does not agree to a challenge for you. Review its full rules before you decide.');
    if (s.scenario === 'denied') html += notice('We can’t confirm access to matching activity. Check GameTime’s access in Apple Health, then try Refresh.');
    if (status === 'unsupported') html += actions(routeButton(ctx, 'Choose another activity', 'createActivity', 'primary') + routeButton(ctx, 'Apple Health help', 'healthHelp'));
    else html += actions(button(status === 'notConnected' ? 'Connect Apple Health' : status === 'checking' ? 'Checking…' : 'Refresh activity check', status === 'notConnected' ? 'account-health-connect' : 'account-health-refresh', 'primary', status === 'checking' ? 'disabled' : '') + routeButton(ctx, 'Apple Health help', 'healthHelp'));
    if (status === 'ready' && s.scenario !== 'pending') html += actions(button('Back to my goal', 'account-health-back', 'secondary'));
    html += ctx.disclosure('Why we check first', '<p>Steps, Activity minutes and Running distance need a matching record from the last 30 days. Timed runs need a comparable outdoor run from the last 90 days.</p><p>A permission prompt or an empty read doesn’t confirm activity. You can browse without connecting Apple Health.</p>');
    return html;
  }

  function healthPermission(ctx) {
    return ctx.heading('Apple Health access') + systemNote('Apple Health presents the permission sheet on your iPhone. GameTime requests the activity needed for your selected goal. This mockup changes no permissions.') + ctx.facts([['App', 'GameTime'], ['Requested activity', (sources[ctx.state.accountHealthMetric] || sources.steps)[0]]]) + '<p>You choose what to share. You can change access later in Apple Health.</p>' + ctx.actions(ctx.button('Preview allowed access', 'account-health-allowed', 'primary') + ctx.button('Preview no access', 'account-health-denied', 'secondary')) + linkNote('These review controls only choose a fictional permission response. A separate activity check still has to succeed.');
  }

  function healthHelp(ctx) {
    return ctx.heading('Apple Health help') + ctx.section('Check GameTime’s access', '<p>Open Apple Health and review the data GameTime can read. Let your Apple Watch sync before checking your activity again.</p>') + ctx.section('Your existing challenges', '<p>Changing access doesn’t change a challenge’s dates or the rules you agreed to. Open the challenge to view its saved activity, leave or ask for a review.</p>') + ctx.actions(ctx.button('Open Apple Health help', 'account-open-health-help', 'primary') + routeButton(ctx, 'Back to activity', 'healthCheck')) + (ctx.state.accountHealthHelpOpen ? systemNote('In the app, this opens Apple’s Health support page in your browser. No external page was opened by this preview.') : '');
  }

  function accountSupport(ctx) {
    const { heading, section, row, actions, button, state: s } = ctx;
    let html = heading('Account & support') + section('Help & documents', row('Apple Health help', 'Manage activity access and Health permissions', '', 'healthHelp') + row('Contact beta support', 'Tell us what happened', '', 'support') + row('Privacy Policy', 'How GameTime handles your data', '', 'privacyPolicy') + row('Beta Terms', 'The terms for this beta release', '', 'betaTerms'));
    if (s.scenario === 'pending' || s.accountAppealSaved) html += section('Account status', row('New challenges are paused', s.accountAppealSaved ? 'Your account review request is saved' : 'Check your options or ask for a review', '', 'accountPaused'));
    html += section('Account', actions(button(s.scenario === 'loading' ? 'Signing out…' : 'Sign out', 'account-sign-out', 'secondary', s.scenario === 'loading' ? 'disabled' : '') + routeButton(ctx, 'Delete account', 'deleteAccount')));
    if (s.accountDeletionSaved) html += row('Check account deletion', 'Your saved receipt and open review options', '', 'deletionReceipt');
    return html;
  }

  function support(ctx) {
    const { state: s, heading, notice, section, actions } = ctx;
    if (s.scenario === 'unavailable') return heading('Beta support') + notice('Support isn’t available here yet. Open a challenge to check its rules and review options.') + actions(routeButton(ctx, 'Your challenges', 'challenges', 'primary') + routeButton(ctx, 'Account & support', 'accountSupport'));
    return heading('Contact beta support') + '<p>Tell us what happened and which challenge needs help.</p>' + section('What to include', '<p>Include the challenge name, what you expected and what happened. Don’t include your password, payment details or raw Apple Health records.</p>') + (s.scenario === 'offline' ? notice('You can draft a message while offline. Your mail app will need a connection to send it.') : '') + actions(routeButton(ctx, 'Write a message', 'supportDraft', 'primary') + routeButton(ctx, 'Check a challenge', 'challenges')) + linkNote('The native app opens your mail app. This review uses a local draft; it sends nothing.');
  }

  function supportDraft(ctx) {
    return ctx.heading('Support message') + systemNote('This stands in for your mail app. The preview keeps only an in-memory draft and never sends a message.') + `<div class="fields">${field(ctx, 'Subject', 'accountSupportSubject')}<label>Message<textarea data-field="accountSupportMessage" rows="6" placeholder="Tell us what happened">${ctx.esc(ctx.state.accountSupportMessage)}</textarea></label></div>` + ctx.actions(ctx.button('Save preview draft', 'account-support-save', 'primary', !ctx.state.accountSupportMessage.trim() ? 'disabled' : '') + routeButton(ctx, 'Cancel', 'support'));
  }

  function documentPreview(ctx, privacyPolicy) {
    const title = privacyPolicy ? 'Privacy Policy' : 'Beta Terms';
    if (ctx.state.scenario === 'unavailable') return ctx.heading(title) + ctx.notice('This document isn’t available here yet. Contact beta support or check again later.') + ctx.actions(routeButton(ctx, 'Contact beta support', 'support', 'primary') + routeButton(ctx, 'Account & support', 'accountSupport'));
    return ctx.heading(title) + systemNote(`GameTime opens its ${privacyPolicy ? 'Privacy Policy' : 'Beta Terms'} in the system browser. The document’s approved wording stays unchanged.`) + ctx.section('External document', `<p>${privacyPolicy ? 'How GameTime handles your data.' : 'The terms for this beta release.'}</p><p class="muted">The full document is outside this app mockup. This is a navigation preview, not replacement legal text.</p>`) + ctx.actions(routeButton(ctx, 'Back to Account & support', 'accountSupport', 'primary'));
  }

  function deleteAccount(ctx) {
    return ctx.heading('Delete your account?') + '<p>Deleting your GameTime account ends normal access to this Beta and your existing Personal account.</p>' + ctx.section('What happens next', '<p>We’ll stop new participation and sharing right away.</p><p>We’ll remove account details and unneeded Beta drafts within seven days, while keeping what we need to finish results, reviews, and appeals.</p>') + ctx.section('Your saved receipt', '<p>You can check a saved account-deletion receipt after signing out.</p>') + ctx.notice('This can’t be undone.') + ctx.actions(ctx.button('Continue', 'account-delete-start', 'primary') + routeButton(ctx, 'Cancel', 'accountSupport'));
  }

  function reauthenticate(ctx) {
    const s = ctx.state;
    if (s.scenario === 'unavailable' || s.scenario === 'offline') return ctx.heading('Deletion didn’t finish') + ctx.notice(s.scenario === 'offline' ? 'We couldn’t reach your account. Check your connection and try again.' : 'We couldn’t get Apple confirmation. Try again.') + ctx.actions(ctx.button('Try again', 'account-reauth-retry', 'primary') + routeButton(ctx, 'Contact beta support', 'support'));
    return ctx.heading('Confirm with Apple') + '<p>Deleting your GameTime account ends normal access to this Beta and your existing Personal account. We’ll stop new challenges and sharing right away. We keep the small set of records needed to finish results and reviews.</p><p>Apple asks you to confirm before we start. You can check the saved account-deletion receipt after signing out.</p>' + ctx.actions(ctx.button('Continue with Apple', 'account-reauth-apple', 'apple-sign-in') + routeButton(ctx, 'Cancel', 'accountSupport'));
  }

  function deletionReceipt(ctx) {
    const { state: s, heading, section, facts, notice, button, actions, row } = ctx;
    if (s.scenario === 'loading') return loading(ctx, 'Checking your account deletion…', 'Your saved receipt stays on this phone while we check.');
    if (s.scenario === 'empty') return heading('No saved receipt on this phone') + notice('We couldn’t find an account-deletion receipt here. Contact beta support for help.') + actions(routeButton(ctx, 'Contact beta support', 'support', 'primary'));
    if (s.scenario === 'offline' || s.scenario === 'unavailable') return heading('Account deletion') + notice('We couldn’t check your account deletion. Your saved receipt is still on this phone. Try again when you reconnect.') + actions(refresh(ctx) + routeButton(ctx, 'Contact beta support', 'support'));
    const status = ({ providerPending: 'provider', closurePending: 'closing', complete: 'completed' })[s.scenario] || s.accountDeletionState;
    let html = heading(status === 'provider' ? 'We stopped normal account access' : status === 'closing' ? 'Finishing account closure' : status === 'completed' ? 'Account closure is complete' : 'Account access is closed');
    if (status === 'provider') html += '<p>Confirm with Apple again so we can finish account closure. Your saved receipt keeps this as the same request.</p>' + actions(button('Continue with Apple', 'account-resume-apple', 'apple-sign-in'));
    else if (status === 'closing') html += '<p>Apple confirmation is complete. We can finish closing the account now.</p>' + actions(button('Finish account closure', 'account-close-finish', 'primary'));
    else if (status === 'completed') html += '<p>Normal sign-in and new participation are closed.</p>';
    else html += '<p>A review or appeal is still open. We keep only the records needed to finish it.</p>';
    html += facts([['Normal access closed', stamp], ['Receipt available until', 'Oct 21, 2026']]);
    html += section('What we still keep', facts(status === 'completed' ? [['Account details', 'Removal complete'], ['Unneeded drafts', 'Removal complete'], ['Result records', 'Kept until Oct 21, 2026']] : [['Account details & unneeded drafts', 'Removal by Sep 28, 2026'], ['Open results and reviews', 'Until the assigned decision is complete'], ['Account appeal', 'Until the assigned decision is complete']]) + '<p class="muted">These dates belong to this fictional saved receipt.</p>');
    if (status === 'held') {
      const reviewRow = row('Review your September result', 'Ask by Sep 23, 2026 · 10:00 AM Pacific', s.accountDeletionReviewSaved ? 'Saved' : '', 'deletionReview');
      const appealRow = row('Appeal the account decision', 'An independent review of your account decision', s.accountDeletionAppealSaved ? 'Saved' : '', 'deletionAppeal');
      html += section('Your open options', (s.accountDeletionReviewSaved ? reviewRow.replace('data-go="deletionReview"', 'data-action="account-view-deletion-review"') : reviewRow) + (s.accountDeletionAppealSaved ? appealRow.replace('data-go="deletionAppeal"', 'data-action="account-view-deletion-appeal"') : appealRow) + '<p class="muted">We will check the open review or appeal every 30 days. It stays open until the assigned decision is complete.</p>');
    }
    if (s.scenario === 'pending' || s.accountDeletionPending) html += notice('A saved review or appeal request still needs a response from us.') + actions(button('Retry saved request', 'account-rights-retry', 'primary'));
    return html + actions(refresh(ctx) + routeButton(ctx, 'Done', 'signedOut'));
  }

  function deletionReview(ctx) {
    const { state: s, heading, facts, notice, actions, button, esc } = ctx;
    const options = [['wrong_total', 'My total looks wrong'], ['missing_activity', 'Activity is missing'], ['wrong_result', 'My result looks wrong']];
    return heading('Review this result') + facts([['Challenge', 'September steps'], ['Result notice', 'Sep 21, 2026 · 10:00 AM Pacific'], ['Ask by', 'Sep 23, 2026 · 10:00 AM Pacific']]) + notice(stale(s) ? 'We couldn’t confirm that review is open. Refresh before sending your request.' : 'You can still ask for review after closing your account. Your final result stays paused while we review it.') + `<div class="fields"><label>Reason<select data-field="accountDeletionReviewReason" ${stale(s) ? 'disabled' : ''}>${options.map(([value, label]) => `<option value="${value}" ${s.accountDeletionReviewReason === value ? 'selected' : ''}>${esc(label)}</option>`).join('')}</select></label></div>` + actions(button('Ask us to review', 'account-deletion-review', 'primary', stale(s) ? 'disabled' : '') + (stale(s) ? refresh(ctx) : routeButton(ctx, 'Not now', 'deletionReceipt')));
  }

  function deletionAppeal(ctx) {
    return ctx.heading('Appeal the account decision') + '<p>You can ask for an independent appeal of the account decision.</p>' + ctx.facts([['Account access', 'Closed'], ['What stays available', 'Your saved receipt and open review options']]) + (stale(ctx.state) ? ctx.notice('We couldn’t confirm your open options. Refresh before asking for an appeal.') : '<p>We keep the records needed to finish the appeal. Asking for an appeal does not reopen normal account access.</p>') + ctx.actions(ctx.button('Ask for an appeal', 'account-deletion-appeal', 'primary', stale(ctx.state) ? 'disabled' : '') + (stale(ctx.state) ? refresh(ctx) : routeButton(ctx, 'Not now', 'deletionReceipt')));
  }

  function paused(ctx) {
    return ctx.heading('New challenges are paused') + '<p>New challenges are paused for your account.</p>' + ctx.section('Your existing challenges', '<p>You can still check saved records, leave an unfinished challenge or ask for a review. Pausing new challenges doesn’t cancel an existing agreement.</p>') + ctx.actions(routeButton(ctx, ctx.state.accountAppealSaved ? 'View your saved request' : 'Ask us to review your account', ctx.state.accountAppealSaved ? 'accountAppealSaved' : 'accountAppeal', 'primary') + routeButton(ctx, 'View existing challenges', 'challenges')) + ctx.row('Contact beta support', 'Get help with your account', '', 'support');
  }

  function render(route, ctx) {
    if (!routes[route]) return null;
    init(ctx.state);
    const { state: s, heading, notice, actions, button, facts } = ctx;
    switch (route) {
      case 'launch': return s.scenario === 'offline' || s.scenario === 'unavailable' ? '<p class="eyebrow">GAMETIME</p>' + heading('Couldn’t load your challenges') + notice('Check your connection and try again.') + actions(button('Try again', 'account-launch-retry', 'primary')) : '<p class="eyebrow">GAMETIME</p>' + loading(ctx, 'Loading…', 'Opening your saved account.');
      case 'signin': case 'signedOut': return signedOut(ctx);
      case 'appleSignIn': return appleAuth(ctx, s.accountAuthPurpose === 'deletion' || s.accountAuthPurpose === 'resume');
      case 'onboarding': return onboarding(ctx);
      case 'ageConfirmation': return age(ctx);
      case 'settings': return settings(ctx);
      case 'privacy': return privacy(ctx, false);
      case 'legacyPrivacy': return privacy(ctx, true);
      case 'healthSettings': return healthSettings(ctx, false);
      case 'legacyHealth': return healthSettings(ctx, true);
      case 'healthCheck': return health(ctx);
      case 'healthPermission': return healthPermission(ctx);
      case 'healthHelp': return healthHelp(ctx);
      case 'accountSupport': return accountSupport(ctx);
      case 'support': return support(ctx);
      case 'supportDraft': return supportDraft(ctx);
      case 'supportSaved': return s.accountSupportReceipt ? receiptMark + heading('Your preview draft is saved') + notice('Nothing was sent. In the app, your mail app handles the message and its sending status.') + facts([['Subject', s.accountSupportReceipt.subject], ['Saved in this preview', stamp]]) + ctx.section('Your message', `<p style="white-space:pre-wrap">${ctx.esc(s.accountSupportReceipt.message)}</p>`) + actions(routeButton(ctx, 'Back to Account & support', 'accountSupport', 'primary')) : heading('No saved draft') + actions(routeButton(ctx, 'Write a message', 'supportDraft', 'primary'));
      case 'privacyPolicy': return documentPreview(ctx, true);
      case 'betaTerms': return documentPreview(ctx, false);
      case 'deleteAccount': return deleteAccount(ctx);
      case 'reauthenticate': return reauthenticate(ctx);
      case 'deletionSaving': return loading(ctx, 'Saving your account deletion…', 'We’re ending normal access and clearing saved account data from this phone.');
      case 'deletionReceipt': return deletionReceipt(ctx);
      case 'deletionReview': return deletionReview(ctx);
      case 'deletionAppeal': return deletionAppeal(ctx);
      case 'deletionRightsSaved': return s.accountDeletionRequest ? receiptMark + heading(s.accountDeletionRequest.type === 'review' ? 'Your review request is saved' : 'Your appeal request is saved') + facts([['Request', s.accountDeletionRequest.type === 'review' ? 'Review September steps' : 'Independent account appeal'], ['Saved', stamp], ...(s.accountDeletionRequest.reason ? [['Reason', s.accountDeletionRequest.reason]] : [])]) + '<p>Normal account access remains closed. Your saved receipt stays available while we finish the request.</p>' + actions(routeButton(ctx, 'Account-deletion receipt', 'deletionReceipt', 'primary')) : heading('No saved request yet') + actions(routeButton(ctx, 'View your open options', 'deletionReceipt', 'primary'));
      case 'accountPaused': return paused(ctx);
      case 'accountAppeal': return heading('Review your account') + '<p>Ask us to review the decision to pause new challenges on your account.</p>' + (stale(s) ? notice('We couldn’t check your account status. Refresh before sending your request.') : '<p>Your saved challenges and safe exits stay available while we review the request.</p>') + actions(button('Ask us to review your account', 'account-appeal-save', 'primary', stale(s) ? 'disabled' : '') + (stale(s) ? refresh(ctx) : routeButton(ctx, 'Not now', 'accountPaused')));
      case 'accountAppealSaved': return receiptMark + heading('Your account review request is saved') + facts([['Account status', 'New challenges paused'], ['Request saved', stamp]]) + '<p>Your existing challenges remain available. Check your account for an update.</p>' + actions(routeButton(ctx, 'View existing challenges', 'challenges', 'primary') + routeButton(ctx, 'Account & support', 'accountSupport'));
      default: return null;
    }
  }

  function act(action, ctx) {
    if (!action.startsWith('account-')) return false;
    const s = ctx.state;
    init(s);
    const go = route => { s.scenario = 'populated'; ctx.go(route); };
    const redraw = () => ctx.render();
    const fail = text => ctx.error(text);
    switch (action) {
      case 'account-launch-retry': clearAccount(ctx); ctx.go('signedOut'); break;
      case 'account-signin': s.accountAuthPurpose = 'signin'; go('appleSignIn'); break;
      case 'account-auth-complete':
        if (s.accountDeletionSaved) { fail('This account is closed. Check your saved account-deletion receipt for your open options.'); break; }
        s.accountSignedIn = true; s.accountName ||= 'Alex Lee'; go(s.accountProfileSaved ? 'home' : 'onboarding'); break;
      case 'account-auth-cancel': go(s.accountAuthPurpose === 'signin' ? 'signedOut' : s.accountAuthPurpose === 'resume' ? 'deletionReceipt' : 'reauthenticate'); break;
      case 'account-profile-save': {
        if (s.scenario === 'loading') break;
        const name = s.accountName.trim(), username = s.accountUsername.trim().replace(/^@/, '');
        if (!name || name.length > 50) { fail('Your name needs to be between 1 and 50 characters.'); break; }
        if (!/^[a-z][a-z0-9_]{2,29}$/i.test(username)) { fail('Usernames are 3–30 letters, numbers, or underscores, and start with a letter.'); break; }
        if (s.scenario === 'offline') { fail('We couldn’t save your profile. Check your connection and try again.'); break; }
        if (s.scenario === 'unavailable') { fail('That username isn’t available. Choose another one and try again.'); break; }
        s.accountName = name; s.accountUsername = username; s.accountProfileSaved = true; go('ageConfirmation'); break;
      }
      case 'account-age-save': if (s.accountAge && !stale(s)) { s.accountAgeSaved = true; redraw(); } break;
      case 'account-age-retry': s.accountAgeSaved = true; s.accountAge = true; s.scenario = 'populated'; redraw(); break;
      case 'account-demo': s.accountDemo = true; go('home'); break;
      case 'account-sign-out': clearAccount(ctx); ctx.go('signedOut'); break;
      case 'account-refresh': s.scenario = 'populated'; redraw(); break;
      case 'account-health-connect': s.accountHealthReturn = 'healthCheck'; go('healthPermission'); break;
      case 'account-legacy-health': s.accountHealthReturn = 'legacyHealth'; go('healthPermission'); break;
      case 'account-health-allowed': s.accountHealthPermission = true; s.accountHealthState = 'noMatching'; s.readiness = 'noMatching'; go(s.accountHealthReturn); break;
      case 'account-health-denied': s.accountHealthPermission = false; s.accountHealthState = 'notConnected'; s.readiness = 'notConnected'; go(s.accountHealthReturn); s.scenario = 'denied'; redraw(); break;
      case 'account-health-refresh':
        if (healthState(s) === 'checking' || healthState(s) === 'unsupported') break;
        if (s.scenario === 'ready' || s.scenario === 'pending' || s.accountHealthState === 'ready') { s.accountHealthState = 'ready'; s.readiness = 'ready'; s.scenario = 'ready'; }
        else { s.accountHealthState = s.accountHealthPermission ? 'noMatching' : 'notConnected'; s.scenario = 'populated'; }
        redraw(); break;
      case 'account-health-back': if (healthState(s) === 'ready' && s.scenario !== 'pending') s.readiness = 'ready'; go(s.accountGoalReturn || 'personalDetail'); break;
      case 'account-open-health-help': s.accountHealthHelpOpen = true; redraw(); break;
      case 'account-support-save':
        if (!s.accountSupportMessage.trim()) { fail('Add a message before saving the draft.'); break; }
        s.accountSupportReceipt = Object.freeze({ subject: s.accountSupportSubject.trim() || 'GameTime support', message: s.accountSupportMessage.trim() }); go('supportSaved'); break;
      case 'account-delete-start': s.accountDeletionConfirmed = true; go('reauthenticate'); break;
      case 'account-reauth-retry': s.scenario = 'populated'; redraw(); break;
      case 'account-reauth-apple': s.accountAuthPurpose = 'deletion'; go('appleSignIn'); break;
      case 'account-resume-apple': s.accountAuthPurpose = 'resume'; go('appleSignIn'); break;
      case 'account-delete-confirmed':
        if (!s.accountDeletionConfirmed && s.accountAuthPurpose !== 'resume') { go('deleteAccount'); break; }
        s.accountDeletionSaved = true; s.accountDeletionState = s.accountAuthPurpose === 'resume' ? 'closing' : 'held'; clearAccount(ctx); ctx.go('deletionReceipt'); break;
      case 'account-preview-launch': clearAccount(ctx); ctx.go('signedOut'); break;
      case 'account-preview-deletion-saved':
        s.accountDeletionSaved = true; s.accountDeletionState = 'held'; clearAccount(ctx); ctx.go('deletionReceipt'); break;
      case 'account-close-finish': s.accountDeletionState = 'held'; s.accountDeletionSaved = true; clearAccount(ctx); ctx.go('deletionReceipt'); break;
      case 'account-deletion-review': {
        if (stale(s)) break;
        const reason = { wrong_total: 'My total looks wrong', missing_activity: 'Activity is missing', wrong_result: 'My result looks wrong' }[s.accountDeletionReviewReason];
        if (!reason) { fail('Choose what you’d like us to review.'); break; }
        s.accountDeletionReviewSaved ||= Object.freeze({ type: 'review', reason }); s.accountDeletionRequest = s.accountDeletionReviewSaved; go('deletionRightsSaved'); break;
      }
      case 'account-deletion-appeal': if (!stale(s)) { s.accountDeletionAppealSaved ||= Object.freeze({ type: 'appeal' }); s.accountDeletionRequest = s.accountDeletionAppealSaved; go('deletionRightsSaved'); } break;
      case 'account-view-deletion-review': if (s.accountDeletionReviewSaved) { s.accountDeletionRequest = s.accountDeletionReviewSaved; go('deletionRightsSaved'); } break;
      case 'account-view-deletion-appeal': if (s.accountDeletionAppealSaved) { s.accountDeletionRequest = s.accountDeletionAppealSaved; go('deletionRightsSaved'); } break;
      case 'account-rights-retry':
        s.accountDeletionRequest = s.accountDeletionPending || s.accountDeletionReviewSaved || Object.freeze({ type: 'review', reason: 'My total looks wrong' });
        if (s.accountDeletionRequest.type === 'review') s.accountDeletionReviewSaved = s.accountDeletionRequest;
        else s.accountDeletionAppealSaved = s.accountDeletionRequest;
        s.accountDeletionPending = null; go('deletionRightsSaved'); break;
      case 'account-appeal-save': if (!stale(s)) { s.accountAppealSaved = true; go('accountAppealSaved'); } break;
      default: return false;
    }
    return true;
  }

  function scenarios(route) {
    if (!routes[route]) return null;
    if (route === 'launch') return ['populated', 'loading', 'offline', 'unavailable'];
    if (['signin', 'signedOut', 'onboarding'].includes(route)) return ['populated', 'loading', 'offline', 'unavailable', 'pending'];
    if (['appleSignIn', 'reauthenticate'].includes(route)) return ['populated', 'loading', 'offline', 'unavailable'];
    if (route === 'healthCheck') return ['populated', 'ready', 'empty', 'loading', 'offline', 'unavailable', 'incomplete', 'denied', 'pending'];
    if (route === 'legacyHealth') return ['populated', 'ready', 'unavailable', 'denied'];
    if (route === 'deletionReceipt') return ['populated', 'loading', 'offline', 'unavailable', 'providerPending', 'closurePending', 'complete', 'pending', 'empty'];
    if (['deletionReview', 'deletionAppeal', 'ageConfirmation', 'accountAppeal'].includes(route)) return ['populated', 'loading', 'offline', 'unavailable', 'pending'];
    if (route === 'accountSupport') return ['populated', 'loading', 'pending'];
    if (['support', 'privacyPolicy', 'betaTerms'].includes(route)) return ['populated', 'offline', 'unavailable'];
    return ['populated'];
  }

  window.SignalAccount = {
    routes, render, scenarios, act,
    reviewerControls(route, ctx) {
      if (route === 'launch') return ctx.button('Advance launch preview', 'account-preview-launch', 'secondary') + '<p>Review control: show the signed-out destination after loading. This button is outside the app.</p>';
      if (route === 'deletionSaving') return ctx.button('Show saved deletion receipt', 'account-preview-deletion-saved', 'secondary') + '<p>Review control: finish this fictional request and clear the old account’s local preview. No real account is changed.</p>';
      return '';
    },
    scenarioLabels: { ready: 'Matching activity found', incomplete: 'Activity changed / incomplete', denied: 'Access not confirmed', providerPending: 'Apple confirmation pending', closurePending: 'Account closure pending', complete: 'Account closure complete' },
    notes: [
      'Existing native paths cover launch, Apple sign-in, name and username setup, 21+ confirmation, settings, distinct Personal and challenge privacy, goal-specific Health readiness, support/document links, sign-out, deletion recovery, result review and independent appeal. Permission alone never means Activity found. Existing agreements and records keep their own rules.',
      'All screens use the approved Signal cool neutral canvas, open ruled groups and a separate native control layer. Forms keep explicit labels, field help and one main action. Account and privacy screens use no activity hero, lifetime total, streak, join date, financial celebration or decorative blue slab.',
      'Apple authentication, Apple Health permission, Mail and external document screens are labeled review stand-ins; real OS UI is not reproduced or accessed. Native support opens configured mailto, not an in-app messaging API. Every draft, deletion receipt, date and request here is fictional and in memory. Generic Ready is an explicit fixture, never inferred from a granted permission. Native implementation and route screenshots require owner approval first.'
    ],
    sourceMap: {
      launch: 'LaunchingView.swift',
      signedOut: 'GameTimeApp.swift: SignedOutView',
      onboarding: 'GameTimeApp.swift: OnboardingView; AppModel.completeOnboarding',
      ageConfirmation: 'ChallengeV1EntryViews.swift: ChallengeEntryPanel',
      settings: 'YouView.swift: settingsOnly / challengeActivitySettings',
      privacy: 'YouView.swift: TrustAndPrivacyView',
      healthCheck: 'ChallengeHealthViews.swift: ChallengeHealthStatusView / ChallengeHealthCopy',
      accountSupport: 'YouView.swift: AccountSupportView / PublicSupportLinksView',
      deletionReceipt: 'YouView.swift: DeleteAccountView / AccountDeletionReceiptView; AppleSignIn.swift',
      accountPaused: 'ChallengeV1Views.swift: suspended account controls'
    }
  };
}());
