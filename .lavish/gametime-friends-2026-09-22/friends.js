/* GameTime friends mocks — local, fictional, no network. Each .phone renders
   one screen from data-screen and keeps its own state. Nothing here sends a
   request, stores data, or reaches another person. */
(() => {
  const ICON = {
    chevron: '<path d="M9 5l7 7-7 7"/>',
    back: '<path d="M15 5l-7 7 7 7"/>',
    x: '<path d="M6 6l12 12M18 6L6 18"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    personAdd: '<circle cx="10" cy="8" r="3.6"/><path d="M3.5 19.5c.8-3.4 3.4-5.2 6.5-5.2s5.7 1.8 6.5 5.2M19 7.5v6M16 10.5h6"/>',
    people: '<circle cx="9" cy="8.5" r="3.3"/><circle cx="16.5" cy="9.5" r="2.6"/><path d="M3 19c.7-3.2 3-4.9 6-4.9s5.3 1.7 6 4.9M15.5 14.3c2.6-.3 4.8 1.1 5.5 4.2"/>',
    check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
    share: '<path d="M12 3.5v11M8 7.5l4-4 4 4M6 11H5v9.5h14V11h-1"/>',
    copy: '<rect x="8" y="8" width="11.5" height="11.5" rx="2.5"/><path d="M16 8V6a2 2 0 00-2-2H6.5a2 2 0 00-2 2v7.5a2 2 0 002 2H8"/>',
    hand: '<path d="M8 12V6.2a1.6 1.6 0 013.2 0V11M11.2 11V4.6a1.6 1.6 0 013.2 0V11M14.4 11V6a1.6 1.6 0 013.2 0v7.5c0 4-2.6 7-6.5 7-2.6 0-4.3-1.3-5.6-3.4L3.8 13.6a1.6 1.6 0 012.6-1.8L8 13.8"/>',
    flag: '<path d="M5.5 21V4.5M5.5 4.5c4-2 6.8 2 11.5 0v8.5c-4.7 2-7.5-2-11.5 0"/>',
    personMinus: '<circle cx="10" cy="8" r="3.6"/><path d="M3.5 19.5c.8-3.4 3.4-5.2 6.5-5.2s5.7 1.8 6.5 5.2M16 10.5h6"/>',
    wifiOff: '<path d="M3 3l18 18M8.5 16.5a5 5 0 017 0M5 12.8a10 10 0 015.2-2.7M14.5 10.3A10 10 0 0119 12.8M2 9.3a15 15 0 015.4-3M12 5.2a15 15 0 0110 4.1"/><circle cx="12" cy="20" r=".9" fill="currentColor"/>',
    watch: '<rect x="6.5" y="6.5" width="11" height="11" rx="3"/><path d="M9 6.5l.7-3.5h4.6l.7 3.5M9 17.5l.7 3.5h4.6l.7-3.5M12 9.5V12l1.6 1.2"/>',
    lock: '<rect x="5.5" y="10.5" width="13" height="9.5" rx="2.5"/><path d="M8.5 10.5V8a3.5 3.5 0 017 0v2.5"/>',
    home: '<path d="M4 10.5L12 4l8 6.5V20h-5.5v-5.5h-5V20H4z"/>',
    flagTab: '<path d="M6 21V4M6 4.5c4.5-2 7.5 2.5 12.5.3V13c-5 2.2-8-2.3-12.5-.3"/>',
    person: '<circle cx="12" cy="8" r="4"/><path d="M4.5 20.5c1-4 3.8-6 7.5-6s6.5 2 7.5 6"/>',
    gear: '<circle cx="12" cy="12" r="3.2"/><path d="M12 3v2.4M12 18.6V21M3 12h2.4M18.6 12H21M5.6 5.6l1.7 1.7M16.7 16.7l1.7 1.7M5.6 18.4l1.7-1.7M16.7 7.3l1.7-1.7"/><circle cx="12" cy="12" r="6.6"/>',
    arrow: '<path d="M4.5 12h14M13 6.5l5.5 5.5-5.5 5.5"/>',
    calendar: '<rect x="4" y="5.5" width="16" height="14.5" rx="3"/><path d="M4 10h16M8.5 3.5v4M15.5 3.5v4"/>',
    invite: '<rect x="3.5" y="6" width="17" height="12.5" rx="3"/><path d="M4 7l8 6 8-6"/>',
    clock: '<circle cx="12" cy="12" r="8.2"/><path d="M12 7.5V12l3 2"/>',
    info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5M12 7.8v.4"/>',
    signal: '<path d="M4 18h2M9 15v3M14 12v6M19 9v9" stroke-width="2.6"/>',
    wifi: '<path d="M5 11a10 10 0 0114 0M8 14.2a5.5 5.5 0 018 0"/><circle cx="12" cy="18" r="1.2" fill="currentColor"/>',
    battery: '<rect x="2.5" y="7.5" width="17" height="9" rx="2.5"/><rect x="4.5" y="9.5" width="13" height="5" rx="1" fill="currentColor"/><path d="M21.5 10.5v3"/>',
  };
  const ic = (name, size = 22, stroke = 1.8) =>
    `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${stroke}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICON[name]}</svg>`;

  // Fictional people. Initials only: profile photos stay deferred in the product.
  const P = {
    alex: { name: 'Alex Lee', user: 'alexlee' },
    sam: { name: 'Sam Rivera', user: 'samr', since: 'Sep 12' },
    jordan: { name: 'Jordan Blake', user: 'jordanb', since: 'Sep 12' },
    priya: { name: 'Priya Nair', user: 'priya_n', since: 'Sep 14' },
    morgan: { name: 'Morgan Diaz', user: 'morgand', since: 'today' },
    taylor: { name: 'Taylor Kim', user: 'taylork' },
    riley: { name: 'Riley Chen', user: 'rileyc' },
    drew: { name: 'Drew Park', user: 'drew_p' },
    casey: { name: 'Casey Wu', user: 'casey_w' },
  };
  const initials = p => p.name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase();
  const av = (p, cls = '') => `<span class="av ${cls}" aria-hidden="true">${initials(p)}</span>`;
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  const statusBar = () => `<div class="status" aria-hidden="true"><span>9:41</span><span class="icons">${ic('signal', 18, 1)}${ic('wifi', 18, 2)}${ic('battery', 24, 1.4)}</span></div>`;
  const tabbar = on => `<nav class="tabbar" aria-label="Tabs">${[['home', 'Home'], ['flagTab', 'Challenges'], ['person', 'You']]
    .map(([i, l]) => `<button class="${l === on ? 'on' : ''}" ${l === on ? 'aria-current="page"' : ''}>${ic(i, 26, l === on ? 2 : 1.6)}<span>${l}</span></button>`).join('')}</nav>`;
  const chrome = (title, { back = true, close = false, trailing = '' } = {}) =>
    `<div class="chrome center">${back ? `<button class="round clear" data-act="noop" aria-label="Back">${ic('back', 24, 2)}</button>` : '<span style="width:44px"></span>'}<h1>${title}</h1>${close ? `<button class="round" data-act="noop" aria-label="Close">${ic('x', 20, 2)}</button>` : trailing || '<span style="width:44px"></span>'}</div>`;

  // ---------- Screens ----------
  const S = {};

  S.you = () => `${statusBar()}<div class="screen"><div class="scroll">
    <div style="display:flex;justify-content:space-between;align-items:center"><h1 class="title-l" style="font-size:34px;letter-spacing:-1.6px">You</h1><button class="round" style="background:var(--surface);box-shadow:0 0 0 1px var(--divider)" aria-label="Settings">${ic('gear', 22)}</button></div>
    <div style="display:flex;align-items:center;gap:16px;margin-top:22px">${av(P.alex, 'lg')}<div style="flex:1"><div style="font-size:24px;font-weight:700;letter-spacing:-.8px">Alex Lee</div><div style="font-size:15px;color:var(--sub);margin-top:3px">@alexlee</div></div><span class="caption" style="display:flex;gap:5px;align-items:center">${ic('lock', 15)}Private</span></div>
    <div class="list" style="margin-top:22px">
      <button class="nav-row" style="padding:0 14px" data-go="friends"><span class="icon-tile">${ic('people', 20)}</span><span class="grow">Friends</span>${ic('chevron', 18, 2).replace('<svg', '<svg class="chev"')}</button>
    </div>
    <div style="border-top:1px solid var(--divider);margin-top:24px;padding-top:16px;display:flex;justify-content:space-between;font-size:14px;color:var(--sub)"><span>Your record</span><span>2026</span></div>
    <div style="display:grid;grid-template-columns:1fr 1fr;margin-top:10px">
      <div style="display:flex;align-items:baseline;gap:10px"><span class="metric" style="font-size:56px;margin:0;letter-spacing:-3px">2</span><span style="color:var(--sub)">Goals met</span></div>
      <div style="display:flex;align-items:baseline;gap:10px;border-left:1px solid var(--divider);padding-left:20px"><span class="metric" style="font-size:56px;margin:0;letter-spacing:-3px">3</span><span style="color:var(--sub)">Challenges<br>finished</span></div>
    </div>
    <div class="section-h" style="margin-top:28px"><h2 style="font-size:19px">Finished</h2><span>3 challenges</span></div>
    <div class="card" style="padding:18px 20px"><div style="font-size:21px;font-weight:700;letter-spacing:-.7px">September steps</div><div class="caption" style="font-size:14px;margin-top:4px">Sep 7–13</div></div>
  </div>${tabbar('You')}</div>`;

  const friendsHeader = (disabled = false) => chrome('Friends', { trailing: `<button class="round clear" data-go="add" ${disabled ? 'disabled style="opacity:.4"' : ''} aria-label="Add a friend">${ic('personAdd', 24, 1.8)}</button>` });

  S.friends = st => {
    const inc = st.incoming.map(k => `<div class="item" data-k="${k}">${av(P[k])}<div class="who"><div class="name">${P[k].name}</div><div class="meta">@${P[k].user}</div></div><div class="actions"><button class="pill quiet" data-act="decline" data-k="${k}">Decline</button><button class="pill fill" data-act="accept" data-k="${k}">Accept</button></div></div>`).join('');
    const fr = st.friends.map(k => `<button class="item" data-act="friend" data-k="${k}">${av(P[k])}<div class="who"><div class="name">${P[k].name}</div><div class="meta">@${P[k].user}</div></div>${ic('chevron', 18, 2).replace('<svg', '<svg class="chev"')}</button>`).join('');
    const sent = st.sent.map(k => `<div class="item">${av(P[k])}<div class="who"><div class="name">${P[k].name}</div><div class="meta">@${P[k].user} · Sent today</div></div><button class="pill text" data-act="cancel" data-k="${k}">Cancel</button></div>`).join('');
    return `${statusBar()}<div class="screen">${friendsHeader()}<div class="scroll" style="padding-top:4px">
      ${st.incoming.length ? `<div class="section-h" style="margin-top:8px"><h2>Requests for you</h2></div><div class="list">${inc}</div><p class="caption" style="margin:8px 4px 0">If you decline, the request goes away. We don’t tell them.</p>` : ''}
      <div class="section-h"><h2>Friends</h2></div>
      ${st.friends.length ? `<div class="list">${fr}</div>` : `<p class="caption" style="font-size:14px">No friends yet.</p>`}
      ${st.sent.length ? `<div class="section-h"><h2>Requests you sent</h2></div><div class="list">${sent}</div>` : ''}
      <div class="list" style="margin-top:28px"><button class="nav-row" style="padding:0 14px" data-go="add"><span class="icon-tile" style="background:var(--selection);color:var(--accent)">${ic('personAdd', 20)}</span><span class="grow">Add a friend</span></button><button class="nav-row" style="padding:0 14px" data-go="blocked"><span class="icon-tile">${ic('hand', 19)}</span><span class="grow">Blocked people</span>${ic('chevron', 18, 2).replace('<svg', '<svg class="chev"')}</button></div>
      <p class="caption" style="margin:12px 4px 0">Only you see your friends list.</p>
    </div></div>${st.toast ? `<div class="toast" role="status">${ic('check', 18, 2.2)}<span>${st.toast}</span></div>` : ''}${sheet(st)}`;
  };
  S.friends.init = { incoming: ['taylor'], friends: ['sam', 'jordan', 'priya', 'morgan'], sent: ['riley'] };

  S['friends-empty'] = () => `${statusBar()}<div class="screen">${friendsHeader()}<div class="scroll">
    <div class="empty"><div class="glyph-lg">${ic('people', 30, 1.6)}</div><h2>Add your first friend</h2><p>Friends can invite each other to challenges. Ask them for their GameTime username, then send a request.</p></div>
    <div style="margin-top:22px;display:grid;gap:10px"><button class="primary" data-go="add">${ic('personAdd', 20, 2)}Add a friend</button><button class="secondary" data-go="share">${ic('share', 19, 2)}Share your username</button></div>
    <p class="caption" style="text-align:center;margin-top:16px">We don’t suggest people or read your contacts.</p>
  </div></div>`;

  S['friends-loading'] = () => `${statusBar()}<div class="screen">${friendsHeader(true)}<div class="scroll" aria-busy="true" aria-label="Loading your friends">
    <div class="section-h" style="margin-top:8px"><h2>Friends</h2></div>
    <div class="list">${[0, 1, 2].map(() => `<div class="item"><span class="av skeleton"></span><div class="who"><div class="skeleton" style="height:14px;width:55%"></div><div class="skeleton" style="height:11px;width:35%;margin-top:8px"></div></div></div>`).join('')}</div>
    <p class="caption" style="margin:14px 4px 0;display:flex;gap:8px;align-items:center"><span class="spinner" aria-hidden="true"></span>Loading your friends…</p>
  </div></div>`;

  S['friends-offline'] = () => `${statusBar()}<div class="screen">${friendsHeader(true)}<div class="scroll" style="padding-top:4px">
    <div class="banner" role="status">${ic('wifiOff', 20)}<div><b>You’re offline</b>This is your last saved list, from 9:12 AM. Connect to accept requests or add friends.</div></div>
    <div class="section-h"><h2>Requests for you</h2></div>
    <div class="list"><div class="item">${av(P.taylor)}<div class="who"><div class="name">${P.taylor.name}</div><div class="meta">@${P.taylor.user}</div></div><div class="actions"><button class="pill quiet" disabled>Decline</button><button class="pill fill" disabled>Accept</button></div></div></div>
    <div class="section-h"><h2>Friends</h2></div>
    <div class="list">${['sam', 'jordan', 'priya'].map(k => `<div class="item">${av(P[k])}<div class="who"><div class="name">${P[k].name}</div><div class="meta">@${P[k].user}</div></div></div>`).join('')}</div>
    <button class="secondary" style="margin-top:22px">Try again</button>
  </div></div>`;

  // Add a friend
  const LOOKUP = {
    drew_p: { kind: 'found', k: 'drew' },
    samr: { kind: 'friends', k: 'sam' },
    taylork: { kind: 'incoming', k: 'taylor' },
    rileyc: { kind: 'sent', k: 'riley' },
    limit: { kind: 'limit' },
    busy: { kind: 'busy' },
  };
  S.add = st => {
    const r = st.result;
    let body = '';
    if (r?.kind === 'found') body = `<div class="card white found" style="margin-top:16px">${av(P[r.k])}<div style="flex:1"><div style="font-size:16px;font-weight:600">${P[r.k].name}</div><div class="caption" style="font-size:13px">@${P[r.k].user}</div></div>${st.sent ? `<span class="pill quiet" style="color:var(--sub)">${ic('check', 16, 2.2)}Sent</span>` : `<button class="pill fill" data-act="send">Send request</button>`}</div>${st.sent ? `<p class="msg">Request sent. ${P[r.k].name.split(' ')[0]} will see it in GameTime and can accept or decline.</p>` : ''}`;
    else if (r?.kind === 'friends') body = `<div class="card white found" style="margin-top:16px">${av(P[r.k])}<div style="flex:1"><div style="font-size:16px;font-weight:600">${P[r.k].name}</div><div class="caption" style="font-size:13px">@${P[r.k].user} · Already your friend</div></div></div>`;
    else if (r?.kind === 'incoming') body = `<div class="card white" style="margin-top:16px"><div class="found">${av(P[r.k])}<div style="flex:1"><div style="font-size:16px;font-weight:600">${P[r.k].name}</div><div class="caption" style="font-size:13px">@${P[r.k].user}</div></div></div><p class="msg" style="color:var(--text)">${P[r.k].user} already sent you a request. Accept it to become friends.</p><div style="display:flex;gap:8px;margin-top:12px"><button class="pill quiet" data-act="noop">Decline</button><button class="pill fill" data-act="noop">Accept</button></div></div>`;
    else if (r?.kind === 'sent') body = `<p class="msg">You already sent @${P[r.k].user} a request. You can cancel it from Friends.</p>`;
    else if (r?.kind === 'limit') body = `<p class="msg warn">You’ve reached today’s limit for friend requests. Try again tomorrow.</p>`;
    else if (r?.kind === 'busy') body = `<p class="msg warn">Too many searches. Wait a minute and try again.</p>`;
    else if (r?.kind === 'none') body = `<p class="msg warn">We couldn’t find @${esc(st.q)}. Usernames need to match exactly — check the spelling with your friend.</p>`;
    return `${statusBar()}<div class="screen">${chrome('Add a friend', { back: false, close: true })}<div class="scroll">
      <p class="lede" style="margin-top:4px">Enter your friend’s exact username. They’ll need to accept before you can invite them to a challenge.</p>
      <form data-form="lookup" style="margin-top:20px"><div class="field ${r && ['none', 'limit', 'busy'].includes(r.kind) ? 'error' : ''}"><span class="at">@</span><input name="q" value="${esc(st.q || '')}" placeholder="username" autocapitalize="none" autocomplete="off" spellcheck="false" aria-label="Friend’s username"><button class="pill link" type="submit">Find</button></div></form>
      ${body}
      <p class="caption" style="margin-top:14px">Try <b>drew_p</b>, <b>samr</b>, <b>taylork</b>, <b>rileyc</b>, <b>limit</b> or <b>busy</b> in this mock.</p>
      <div style="border-top:1px solid var(--divider);margin-top:28px;padding-top:22px">
        <div class="field-label" style="color:var(--sub);font-weight:500">Your username</div>
        <div class="card" style="display:flex;align-items:center;gap:12px;padding:14px 16px"><span style="flex:1;font-size:20px;font-weight:700;letter-spacing:-.5px">@alexlee</span><button class="round" style="background:var(--surface)" data-act="copy" aria-label="Copy username">${ic('copy', 19)}</button><button class="round" style="background:var(--surface)" data-go="share" aria-label="Share username">${ic('share', 19)}</button></div>
        <p class="caption" style="margin-top:8px">Send it to a friend so they can add you.</p>
      </div>
    </div></div>${st.toast ? `<div class="toast" role="status">${ic('check', 18, 2.2)}<span>${st.toast}</span></div>` : ''}`;
  };
  S.add.init = { q: 'drew_p', result: { kind: 'found', k: 'drew' } };
  S['add-incoming'] = st => S.add(st); S['add-incoming'].initFor = { q: 'taylork', result: { kind: 'incoming', k: 'taylor' } };

  S.share = () => `${S.add({ q: '' }).replace(/<div class="toast[\s\S]*$/, '')}<div class="scrim static"></div><div class="sheet static" role="dialog" aria-label="Share your username"><div class="grab"></div>
    <div style="display:flex;gap:12px;align-items:center;padding:6px 2px 14px;border-bottom:1px solid var(--divider)"><span class="icon-tile" style="width:48px;height:48px;border-radius:12px;background:var(--selection);color:var(--accent);font-weight:800;font-size:13px">GT</span><div style="flex:1;min-width:0"><div style="font-size:15px;font-weight:600">I’m @alexlee on GameTime. Add me as a friend.</div><div class="caption">Plain text · no link</div></div></div>
    <div style="display:flex;gap:18px;padding:18px 2px 8px;overflow:hidden">${['Messages', 'Mail', 'Notes', 'Copy'].map(n => `<div style="display:flex;flex-direction:column;align-items:center;gap:6px;font-size:11px;color:var(--sub)"><span style="width:58px;height:58px;border-radius:14px;background:var(--soft)"></span>${n}</div>`).join('')}</div>
    <p class="caption" style="margin-top:8px">The system share sheet. GameTime only hands it this sentence — no link, no contact list.</p></div>`;

  // Friend detail + safety
  const friendSheet = k => `<div class="scrim" data-act="close"></div><div class="sheet" role="dialog" aria-label="${P[k].name}"><div class="grab"></div>
    <div style="display:flex;flex-direction:column;align-items:center;text-align:center;padding:6px 0 18px">${av(P[k], 'lg')}<div style="font-size:22px;font-weight:700;letter-spacing:-.6px;margin-top:12px">${P[k].name}</div><div class="caption" style="font-size:14px;margin-top:2px">@${P[k].user} · Friends since ${P[k].since}</div></div>
    <div class="list">
      <button class="nav-row" style="padding:0 14px" data-act="ask-remove" data-k="${k}"><span class="icon-tile">${ic('personMinus', 19)}</span><span class="grow">Remove friend</span></button>
      <button class="nav-row" style="padding:0 14px" data-act="ask-block" data-k="${k}"><span class="icon-tile">${ic('hand', 19)}</span><span class="grow">Block</span></button>
      <button class="nav-row" style="padding:0 14px" data-act="report" data-k="${k}"><span class="icon-tile">${ic('flag', 19)}</span><span class="grow">Report</span></button>
    </div>
    <p class="caption" style="margin:12px 4px 0">We don’t send a notice when you remove, block or report someone.</p></div>`;

  const alert = (title, text, confirm, act, k) => `<div class="scrim" data-act="close"></div><div class="sheet alert" role="alertdialog" aria-label="${title}"><h3>${title}</h3><p>${text}</p><div class="alert-actions"><button class="confirm" data-act="${act}" data-k="${k}">${confirm}</button><button class="cancel" data-act="close">Cancel</button></div></div>`;

  // One sentence per server reason code: username, unwanted_contact, unsafe_behavior.
  const REASONS = ['Their name or username', 'Unwanted requests or invitations', 'Something that feels unsafe'];
  const reportSheet = (k, st) => st.reported
    ? `<div class="scrim" data-act="close"></div><div class="sheet" role="dialog" aria-label="Report sent"><div class="grab"></div><div class="empty" style="padding-top:12px"><div class="glyph-lg" style="background:var(--selection);color:var(--accent)">${ic('check', 30, 2.2)}</div><h2>Thanks for telling us</h2><p>We’ll look into it. You can also block them.</p></div><div style="display:grid;gap:8px;margin-top:16px"><button class="secondary" data-act="ask-block" data-k="${k}">${ic('hand', 19)}Block ${P[k].name.split(' ')[0]}</button><button class="quiet-link" data-act="close">Done</button></div></div>`
    : `<div class="scrim" data-act="close"></div><div class="sheet" role="dialog" aria-label="Report ${P[k].name}"><div class="grab"></div>
      <h3 style="font-size:22px;font-weight:700;letter-spacing:-.6px">Report ${P[k].name.split(' ')[0]}</h3><p class="lede" style="font-size:14px;margin-top:6px">Tell us what’s wrong. We read every report. ${P[k].name.split(' ')[0]} isn’t told.</p>
      <div class="list" style="margin-top:16px" role="radiogroup">${REASONS.map((r, i) => `<button class="radio" role="radio" aria-checked="${st.reason === i}" data-act="reason" data-i="${i}"><span class="dotsel"></span>${r}</button>`).join('')}</div>
      <button class="primary" style="margin-top:14px" data-act="send-report" data-k="${k}" ${st.reason == null ? 'disabled' : ''}>Send report</button></div>`;

  function sheet(st) {
    if (!st.sheet) return '';
    const { kind, k } = st.sheet;
    const first = P[k]?.name.split(' ')[0];
    if (kind === 'friend') return friendSheet(k);
    if (kind === 'remove') return alert(`Remove ${first}?`, `You’ll stop being friends. Challenges you already share stay as they are.`, 'Remove', 'do-remove', k);
    if (kind === 'block') return alert(`Block ${first}?`, `${first} won’t be able to find you or send you requests, and you’ll stop being friends. If you share a challenge that hasn’t finished, you both leave it. If fewer than two people are left, it won’t count.`, 'Block', 'do-block', k);
    if (kind === 'report') return reportSheet(k, st);
    if (kind === 'unblock') return alert(`Unblock ${first}?`, `${first} will be able to find you and send you requests again. You won’t become friends unless you both agree.`, 'Unblock', 'do-unblock', k);
    return '';
  }

  S['friend-sheet'] = st => S.friends(st); S['friend-sheet'].initFor = { ...S.friends.init, sheet: { kind: 'friend', k: 'sam' } };
  S['block-confirm'] = st => S.friends(st); S['block-confirm'].initFor = { ...S.friends.init, sheet: { kind: 'block', k: 'sam' } };
  S.report = st => S.friends(st); S.report.initFor = { ...S.friends.init, sheet: { kind: 'report', k: 'sam' }, reason: 1 };

  S.blocked = st => `${statusBar()}<div class="screen">${chrome('Blocked people')}<div class="scroll">
    <p class="lede" style="font-size:14px;margin-top:4px">Blocked people can’t find you or send you requests. They aren’t told.</p>
    ${st.blocked.length ? `<div class="list" style="margin-top:18px">${st.blocked.map(k => `<div class="item">${av(P[k])}<div class="who"><div class="name">${P[k].name}</div><div class="meta">@${P[k].user}</div></div><button class="pill quiet" data-act="ask-unblock" data-k="${k}">Unblock</button></div>`).join('')}</div>` : `<div class="empty"><h2 style="font-size:17px">No one is blocked</h2><p>You can block someone from their name in Friends, or from a challenge.</p></div>`}
  </div></div>${st.toast ? `<div class="toast" role="status">${ic('check', 18, 2.2)}<span>${st.toast}</span></div>` : ''}${sheet(st)}`;
  S.blocked.init = { blocked: ['casey'] };

  // Home action rows
  // One compact group, most urgent first, at most three rows. Each row has one
  // factual line and one action; it leaves once handled.
  const ROWS = {
    agree: () => `<div class="actrow"><span class="glyph">${ic('calendar', 18)}</span><div class="txt"><div class="t">Agree to Park runs</div><div class="d due">Before Oct 5, 12:00 AM</div></div><button class="pill fill" data-act="noop">Review</button></div>`,
    incoming: () => `<div class="actrow">${av(P.taylor, 'rowav')}<div class="txt"><div class="t">Taylor Kim</div><div class="d">Friend request</div></div><div class="actions"><button class="pill quiet" data-act="row-done" data-row="incoming" data-toast="Request declined." aria-label="Decline Taylor Kim’s request">Decline</button><button class="pill fill" data-act="row-done" data-row="incoming" data-toast="You and Taylor are now friends." aria-label="Accept Taylor Kim’s request">Accept</button></div></div>`,
    invitation: () => `<div class="actrow"><span class="glyph">${ic('invite', 18)}</span><div class="txt"><div class="t">October runs</div><div class="d">From Jordan · Sep 28–Oct 4</div></div><button class="pill quiet" data-act="noop">Review</button></div>`,
    accepted: () => `<div class="actrow">${av(P.morgan, 'rowav')}<div class="txt"><div class="t">Morgan Diaz</div><div class="d">Accepted your request</div></div><button class="x" data-act="row-done" data-row="accepted" aria-label="Dismiss">${ic('x', 16, 2)}</button></div>`,
  };
  const ORDER = ['agree', 'incoming', 'invitation', 'accepted'];
  const rowsHTML = st => {
    const live = ORDER.filter(r => st.rows.includes(r));
    if (!live.length) return '';
    const shown = st.allRows ? live : live.slice(0, 3);
    const more = live.length - shown.length;
    return `<section class="actrows" aria-label="Needs you">${shown.map(r => ROWS[r]()).join('')}${more ? `<button class="more" data-act="more">Show ${more} more</button>` : ''}</section>`;
  };
  S.home = st => `${statusBar()}<div class="screen"><div class="scroll" style="padding-top:18px">
    ${rowsHTML(st) ? `${rowsHTML(st)}<div style="height:24px"></div>` : ''}
    <div class="home-head"><div><h1>September runs</h1><div class="home-meta"><span>Sep 21–27</span><span class="state">On track</span></div></div>${av(P.alex, 'sm')}</div>
    <div class="metric-card"><div class="metric-top"><span>Your distance</span><span>20 km goal</span></div><div class="metric">6.4<small>km</small></div><div class="rail"><i></i></div><div class="metric-foot"><span>13.6 km to go</span><span>Ends Sunday</span></div></div>
    <div class="section-h" style="margin-top:24px"><h2 style="font-size:19px;letter-spacing:-.4px">With you</h2><span>3 friends ↗</span></div>
    <div style="display:flex;justify-content:space-around;margin-top:6px">${['sam', 'jordan', 'priya'].map((k, i) => `<div style="text-align:center">${av(P[k], 'ring').replace('class="av ring"', `class="av" style="--size:60px;box-shadow:0 0 0 2px var(--canvas),0 0 0 4px ${i === 1 ? 'var(--divider)' : 'var(--accent)'}"`)}<div style="font-size:15px;margin-top:10px">${P[k].name.split(' ')[0]}</div><div style="font-size:14px;font-weight:600;color:${i === 1 ? 'var(--warn)' : 'var(--accent)'}">${['On track', 'Behind', 'Done'][i]}</div></div>`).join('')}</div>
  </div>${st.toast ? `<div class="toast" role="status" style="bottom:100px">${ic('check', 18, 2.2)}<span>${st.toast}</span></div>` : ''}${tabbar('Home')}</div>`;
  S.home.init = { rows: ['incoming', 'accepted', 'invitation', 'agree'] };

  S['home-quiet'] = st => `${statusBar()}<div class="screen"><div class="scroll" style="padding-top:18px">
    <div class="home-head"><h1>Home</h1>${av(P.alex, 'sm')}</div>
    <div style="margin-top:22px">${rowsHTML(st)}</div>
    <div class="card" style="margin-top:${rowsHTML(st) ? 22 : 0}px"><h2 style="font-size:24px;font-weight:700;letter-spacing:-.8px">No active challenge</h2><p class="lede" style="font-size:14px;margin-top:10px">Your finished goals are in You.</p><button class="primary" style="margin-top:18px">Create a challenge</button></div>
  </div>${tabbar('Home')}</div>`;
  S['home-quiet'].init = { rows: ['agree'] };

  // Invite step: accepted friends picker
  const FRIENDS = ['sam', 'jordan', 'priya', 'morgan'];
  S.invite = st => {
    const sel = st.sel;
    const full = sel.length >= 5;
    const list = st.friends.map(k => {
      const on = sel.includes(k);
      return `<button class="item" role="checkbox" aria-checked="${on}" ${!on && full ? 'aria-disabled="true"' : ''} data-act="pick" data-k="${k}">${av(P[k])}<div class="who"><div class="name">${P[k].name}</div><div class="meta">@${P[k].user}</div></div><span class="check">${on ? ic('check', 15, 2.6) : ''}</span></button>`;
    }).join('');
    return `${statusBar()}<div class="screen"><div class="chrome"><h1>Create challenge</h1><button class="round" aria-label="Close">${ic('x', 20, 2)}</button></div><div class="scroll" style="padding-top:6px">
      <div class="progress" aria-label="Step 3 of 3, Friends"><span class="step"><span class="dot">${ic('check', 12, 3)}</span>Goal</span><hr><span class="step"><span class="dot">${ic('check', 12, 3)}</span>Challenge</span><hr><span class="step cur"><span class="dot">3</span>Friends</span></div>
      <h2 class="title-xl" style="margin-top:22px">Invite friends.</h2>
      <p class="lede" style="margin-top:8px">Choose up to 5. They’ll each review the rules and choose their own goal.</p>
      ${st.friends.length ? `<div class="section-h"><h2>Your friends</h2><span>${sel.length} of 5 chosen</span></div><div class="list" aria-label="Your friends">${list}</div>` : `<div class="card" style="margin-top:22px;text-align:center"><div class="glyph-lg" style="width:52px;height:52px;border-radius:50%;background:var(--surface);display:grid;place-items:center;margin:0 auto 12px">${ic('people', 26, 1.6)}</div><div style="font-size:17px;font-weight:650">No friends yet</div><p class="caption" style="font-size:14px;margin-top:6px">Send a request by username. Once they accept, they’ll show up here and you can invite them. Your challenge is saved while you wait.</p></div>`}
      <button class="nav-row" style="margin-top:10px;color:var(--accent);font-weight:600;font-size:15px;min-height:48px" data-act="inline-add">${ic('personAdd', 20)}<span class="grow">Add a friend by username</span></button>
      ${st.inlineAdd ? `<div style="margin-top:4px"><div class="field" style="min-height:50px;font-size:16px"><span class="at">@</span><input value="drew_p" aria-label="Friend’s username"><button class="pill link" data-act="inline-send">Send request</button></div><p class="msg">${st.inlineSent ? 'Request sent to Drew Park. They’ll appear in your list once they accept.' : 'They’ll need to accept before you can invite them.'}</p></div>` : ''}
      <p class="caption" style="margin-top:18px">You pick the final roster from the friends who accept. Everyone on it agrees before the start.</p>
    </div><div class="dock"><button class="primary" ${sel.length ? '' : ''}>${sel.length ? `Invite ${sel.length} ${sel.length === 1 ? 'friend' : 'friends'}` : 'Skip for now'}${ic('arrow', 20, 2)}</button></div></div>`;
  };
  S.invite.init = { friends: FRIENDS, sel: ['sam', 'jordan', 'priya'] };
  S['invite-empty'] = st => S.invite(st); S['invite-empty'].initFor = { friends: [], sel: [], inlineAdd: true };

  // Onboarding
  S['onboard-age'] = st => `${statusBar()}<div class="screen"><div class="scroll" style="padding-top:20px">
    <div class="steps-dots" aria-label="Step 1 of 2"><i class="on"></i><i></i></div>
    <h1 class="title-xl" style="margin-top:22px">Before you start</h1>
    <p class="lede" style="margin-top:10px">A couple of things to know about GameTime.</p>
    <div style="margin-top:24px">
      <div class="fact"><span class="icon-tile">${ic('watch', 20)}</span><div><b>You need an Apple Watch</b><span>Your activity has to come from an Apple Watch that records to Apple Health on this iPhone. Activity recorded only by iPhone doesn’t count.</span></div></div>
      <div class="fact"><span class="icon-tile">${ic('info', 20)}</span><div><b>Stakes are simulated</b><span>No real money moves. Nothing can be paid out or redeemed.</span></div></div>
    </div>
    <button class="toggle-row" style="margin-top:28px" role="switch" aria-checked="${!!st.age}" data-act="age"><span class="grow">I confirm I am 21 or older</span><span class="switch"></span></button>
    <p class="caption" style="margin:10px 4px 0">GameTime is only for people 21 and older.</p>
  </div><div class="dock"><button class="primary" ${st.age ? '' : 'disabled'} data-go="onboard-profile">Continue${ic('arrow', 20, 2)}</button><button class="quiet-link" data-act="under21">I’m under 21</button></div></div>${st.under21 ? `<div class="scrim" data-act="close"></div><div class="sheet alert" role="alertdialog" aria-label="GameTime is for adults"><h3>GameTime is for people 21 and older</h3><p>You can’t use GameTime yet. We haven’t saved a profile for you. You can sign out, or use a different Apple account.</p><div class="alert-actions"><button class="confirm" data-act="close">Sign out</button><button class="cancel" data-act="close">Go back</button></div></div>` : ''}`;
  S['onboard-age'].init = { age: false };

  S['onboard-profile'] = () => `${statusBar()}<div class="screen"><div class="scroll" style="padding-top:20px">
    <div class="steps-dots" aria-label="Step 2 of 2"><i class="on"></i><i class="on"></i></div>
    <h1 class="title-xl" style="margin-top:22px">Your profile</h1>
    <p class="lede" style="margin-top:10px">Add your name and the username friends will use to find you.</p>
    <div style="margin-top:24px"><div class="field-label">Your name</div><div class="field"><input value="Alex Lee" aria-label="Your name"></div><p class="msg">Name: 1–50 characters</p></div>
    <div style="margin-top:18px"><div class="field-label">Username</div><div class="field"><span class="at">@</span><input value="alexlee" aria-label="Username"></div><p class="msg">Username: 3–30 letters, numbers, or underscores; starts with a letter</p></div>
    <p class="caption" style="margin-top:14px">Pick carefully — you can’t change your username yet. Friends need it to send you a request.</p>
  </div><div class="dock"><button class="primary">Enter GameTime</button><button class="quiet-link">Use a different Apple account</button></div></div>`;

  // After a friend lobby saves
  S['lobby-saved'] = () => `${statusBar()}<div class="screen"><div class="chrome" style="justify-content:flex-end"><button class="round" aria-label="Close">${ic('x', 20, 2)}</button></div><div class="scroll" style="padding-top:4px">
    <span style="width:34px;height:34px;border-radius:50%;background:var(--selection);color:var(--accent);display:grid;place-items:center">${ic('invite', 19, 2)}</span>
    <h1 class="title-xl" style="margin-top:14px">Challenge saved.</h1>
    <p class="lede" style="margin-top:8px">October runs · Sep 28–Oct 4</p>
    <p class="caption" style="margin-top:6px">$20 simulated · fee $0</p>
    <div class="lobby-card"><div style="display:flex;justify-content:space-between;font-size:14px"><b style="font-weight:600">Invited</b><span style="color:var(--sub)">Nobody has agreed yet</span></div>
      <div class="people">${['sam', 'jordan', 'priya'].map(k => `<div class="p">${av(P[k])}${P[k].name.split(' ')[0]}<em>Invited</em></div>`).join('')}</div></div>
    <div class="next-steps">
      <div class="ns done"><i>${ic('check', 13, 3)}</i><div><b>You invited 3 friends</b><span>They’ll see it in GameTime and choose their own goal.</span></div></div>
      <div class="ns"><i>2</i><div><b>You pick the roster</b><span>Choose who’s in from the friends who accept.</span></div></div>
      <div class="ns"><i>3</i><div><b>Everyone agrees before Sep 28</b><span>It locks in when everyone on the roster agrees. If anyone hasn’t by the start, it’s cancelled and nothing counts.</span></div></div>
    </div>
  </div><div class="dock"><button class="primary">Go to Home${ic('arrow', 20, 2)}</button><button class="quiet-link">View challenge</button></div></div>`;

  // ---------- Wiring ----------
  function mount(phone) {
    const name = phone.dataset.screen;
    const fn = S[name];
    if (!fn) { phone.textContent = `Unknown screen ${name}`; return; }
    const base = fn.initFor || fn.init || {};
    phone._st = JSON.parse(JSON.stringify(base));
    phone._name = name;
    draw(phone);
    phone.addEventListener('click', e => onClick(phone, e));
    phone.addEventListener('submit', e => onSubmit(phone, e));
    phone.addEventListener('keydown', e => { if (e.key === 'Escape' && phone._st.sheet) { phone._st.sheet = null; draw(phone); } });
  }
  function draw(phone) {
    const scroll = phone.querySelector('.scroll');
    const top = scroll ? scroll.scrollTop : 0;
    phone.innerHTML = S[phone._name](phone._st);
    const s2 = phone.querySelector('.scroll'); if (s2) s2.scrollTop = top;
    const dlg = phone.querySelector('[role="dialog"],[role="alertdialog"]');
    if (dlg) (dlg.querySelector('button:not([disabled])') || dlg).focus({ preventScroll: true });
  }
  function toast(phone, text) {
    phone._st.toast = text; draw(phone);
    clearTimeout(phone._t); phone._t = setTimeout(() => { phone._st.toast = null; draw(phone); }, 2600);
  }
  const standalone = document.body.classList.contains('standalone-body');
  function go(phone, screen) {
    if (!standalone) return; // board phones stay on their own screen
    const u = new URL(location.href); u.searchParams.set('screen', screen); location.href = u;
  }
  function onSubmit(phone, e) {
    e.preventDefault();
    const q = new FormData(e.target).get('q')?.toString().trim().replace(/^@/, '').toLowerCase() || '';
    const st = phone._st; st.q = q; st.sent = false;
    st.result = LOOKUP[q] || (q ? { kind: 'none' } : null);
    draw(phone);
  }
  function onClick(phone, e) {
    const t = e.target.closest('[data-act],[data-go]');
    if (!t || t.disabled) return;
    const st = phone._st; const k = t.dataset.k;
    if (t.dataset.go) return go(phone, t.dataset.go);
    switch (t.dataset.act) {
      case 'accept': st.incoming = st.incoming.filter(x => x !== k); st.friends.unshift(k); P[k].since = 'today'; return toast(phone, `You and ${P[k].name.split(' ')[0]} are now friends.`);
      case 'decline': st.incoming = st.incoming.filter(x => x !== k); return toast(phone, 'Request declined.');
      case 'cancel': st.sent = st.sent.filter(x => x !== k); return toast(phone, 'Request cancelled.');
      case 'friend': st.sheet = { kind: 'friend', k }; st.reason = null; st.reported = false; return draw(phone);
      case 'ask-remove': st.sheet = { kind: 'remove', k }; return draw(phone);
      case 'ask-block': st.sheet = { kind: 'block', k }; return draw(phone);
      case 'ask-unblock': st.sheet = { kind: 'unblock', k }; return draw(phone);
      case 'report': st.sheet = { kind: 'report', k }; st.reason = null; st.reported = false; return draw(phone);
      case 'reason': st.reason = Number(t.dataset.i); return draw(phone);
      case 'send-report': st.reported = true; return draw(phone);
      case 'do-remove': st.friends = st.friends.filter(x => x !== k); st.sheet = null; return toast(phone, `${P[k].name.split(' ')[0]} is no longer your friend.`);
      case 'do-block': if (st.friends) st.friends = st.friends.filter(x => x !== k); st.sheet = null; return toast(phone, `${P[k].name.split(' ')[0]} is blocked. Find them in Blocked people.`);
      case 'do-unblock': st.blocked = st.blocked.filter(x => x !== k); st.sheet = null; return toast(phone, `${P[k].name.split(' ')[0]} is unblocked.`);
      case 'close': st.sheet = null; st.under21 = false; return draw(phone);
      case 'send': st.sent = true; return draw(phone);
      case 'copy': return toast(phone, 'Username copied.');
      case 'row-done': st.rows = st.rows.filter(r => r !== t.dataset.row); if (t.dataset.toast) return toast(phone, t.dataset.toast); return draw(phone);
      case 'pick': { if (t.getAttribute('aria-disabled') === 'true') return; st.sel = st.sel.includes(k) ? st.sel.filter(x => x !== k) : [...st.sel, k]; return draw(phone); }
      case 'inline-add': st.inlineAdd = !st.inlineAdd; st.inlineSent = false; return draw(phone);
      case 'inline-send': st.inlineSent = true; return draw(phone);
      case 'more': st.allRows = true; return draw(phone);
      case 'age': st.age = !st.age; return draw(phone);
      case 'under21': st.under21 = true; return draw(phone);
      default: return;
    }
  }

  // Standalone page: ?screen=name
  const p = new URLSearchParams(location.search);
  document.querySelectorAll('.phone[data-screen]').forEach(ph => {
    if (standalone && p.get('screen')) ph.dataset.screen = p.get('screen');
    mount(ph);
  });
  if (p.get('large') === '1') document.body.classList.add('large-text');
  if (p.get('capture') === '1') document.body.classList.add('capture');
})();
