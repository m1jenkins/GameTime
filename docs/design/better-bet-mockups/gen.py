#!/usr/bin/env python3
"""Generate 6 HTML mockup screens (3 directions x 2 screens) for Better Bet."""
import os

OUT = os.path.dirname(os.path.abspath(__file__))
W, H = 853, 1844

STATUS = """
<div class="statusbar"><span class="stime">9:41</span>
<span class="sicons"><svg width="34" height="22" viewBox="0 0 20 12" fill="currentColor"><rect x="0" y="7" width="3" height="5" rx="1"/><rect x="5" y="5" width="3" height="7" rx="1"/><rect x="10" y="2" width="3" height="10" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1" opacity=".35"/></svg>
<svg width="30" height="22" viewBox="0 0 16 12" fill="currentColor"><path d="M8 9.5a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3zM8 5C5.8 5 3.8 5.8 2.3 7.2l1.5 1.6A6.3 6.3 0 0 1 8 7.2c1.6 0 3 .6 4.2 1.6l1.5-1.6A8.9 8.9 0 0 0 8 5zM8 0C4.7 0 1.7 1.2-.4 3.3L1.1 4.9A11 11 0 0 1 8 2.2c2.7 0 5.2 1 7 2.7l1.4-1.6A13.4 13.4 0 0 0 8 0z" transform="translate(0,-1) scale(0.85)"/></svg>
<svg width="50" height="22" viewBox="0 0 25 12"><rect x="0" y="0.5" width="21" height="11" rx="3.5" fill="none" stroke="currentColor" opacity=".4"/><rect x="2" y="2.5" width="15" height="7" rx="1.8" fill="currentColor"/><path d="M23 4v4a2.2 2.2 0 0 0 0-4z" fill="currentColor" opacity=".4"/></svg></span></div>
"""

HOME_INDICATOR = '<div class="home-indicator"></div>'

def tabbar(active, theme):
    """theme: dict with colors"""
    items = [
        ("Today", "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 5v5l3.5 2"),
        ("Challenges", "M8 21h8m-4-4v4m-6-17h12v5a6 6 0 0 1-12 0V4zM4 6H2v2a4 4 0 0 0 4 4m14-6h2v2a4 4 0 0 1-4 4"),
        ("You", "M12 8a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm-8 12a8 8 0 0 1 16 0"),
    ]
    cells = ""
    for name, d in items:
        on = name == active
        color = theme["tab_active"] if on else theme["tab_idle"]
        cells += f'''<div class="tab" style="color:{color}">
        <svg width="52" height="52" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="{d}"/></svg>
        <span>{name}</span></div>'''
    return f'<div class="tabbar" style="background:{theme["tab_bg"]};border-top:1px solid {theme["tab_line"]}">{cells}</div>{HOME_INDICATOR}'

def page(title, css, body):
    return f"""<!DOCTYPE html><html><head><meta charset="utf-8"><title>{title}</title><style>
* {{ margin:0; padding:0; box-sizing:border-box; -webkit-font-smoothing:antialiased; }}
html,body {{ width:{W}px; height:{H}px; overflow:hidden; }}
body {{ font-family:-apple-system,'Helvetica Neue',Arial,sans-serif; position:relative; }}
.num {{ font-variant-numeric:tabular-nums; font-feature-settings:"tnum"; }}
.statusbar {{ position:absolute; top:0; left:0; right:0; height:100px; display:flex; justify-content:space-between; align-items:center; padding:18px 56px 0; z-index:5; }}
.stime {{ font-size:34px; font-weight:600; }}
.sicons {{ display:flex; align-items:center; gap:12px; }}
.tabbar {{ position:absolute; bottom:0; left:0; right:0; height:176px; display:flex; padding:18px 40px 56px; }}
.tab {{ flex:1; display:flex; flex-direction:column; align-items:center; gap:8px; font-size:26px; font-weight:500; }}
.home-indicator {{ position:absolute; bottom:18px; left:50%; transform:translateX(-50%); width:280px; height:10px; border-radius:5px; background:currentColor; opacity:.85; z-index:6; }}
{css}
</style></head><body>{STATUS}{body}</body></html>"""

# ---------------------------------------------------------------- data
DAYS = [
    ("MON", 12430, "met"), ("TUE", 11980, "met"), ("WED", 10590, "met"),
    ("THU", 7350, "live"), ("FRI", None, "future"), ("SAT", None, "future"), ("SUN", None, "future"),
]
CUM = [12430, 24410, 35000, 42350]
GOAL = 70000

def fmt(n): return f"{n:,}"

# ---------------------------------------------------------------- A: POSITION (dark, money)
A = dict(bg="#0C0C0E", ink="#FFFFFF", sub="rgba(255,255,255,.52)", faint="rgba(255,255,255,.28)",
         line="rgba(255,255,255,.14)", green="#00FF23", red="#FF4D3D", card="#141416",
         tab_bg="#0C0C0E", tab_line="rgba(255,255,255,.14)", tab_active="#FFFFFF", tab_idle="rgba(255,255,255,.38)")

def chart_A(width=789, height=560):
    top, bot = 40, height - 60
    ymax = 77000.0
    def X(i): return 40 + i / 6.0 * (width - 80)
    def Y(v): return bot - v / ymax * (bot - top)
    pts = " ".join(f"{X(i):.1f},{Y(v):.1f}" for i, v in enumerate(CUM))
    pace = f"{X(0):.1f},{Y(0):.1f} {X(6):.1f},{Y(GOAL):.1f}"
    gy = Y(GOAL)
    dots = "".join(f'<circle cx="{X(i):.1f}" cy="{Y(v):.1f}" r="9" fill="#0C0C0E" stroke="#00FF23" stroke-width="5"/>' for i, v in enumerate(CUM[:-1]))
    labels = "".join(f'<text x="{X(i):.1f}" y="{height-14}" fill="rgba(255,255,255,.4)" font-size="24" text-anchor="middle" font-weight="500">{d[0][0]}{d[0][1:].lower()}</text>' for i, d in enumerate(DAYS))
    return f"""<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<line x1="0" y1="{gy:.1f}" x2="{width}" y2="{gy:.1f}" stroke="rgba(255,255,255,.35)" stroke-width="2" stroke-dasharray="10 10"/>
<text x="{width}" y="{gy-14:.1f}" fill="rgba(255,255,255,.55)" font-size="24" text-anchor="end" font-weight="600">70,000 GOAL</text>
<polyline points="{pace}" fill="none" stroke="rgba(255,255,255,.30)" stroke-width="3" stroke-dasharray="4 14" stroke-linecap="round"/>
<line x1="{X(3):.1f}" y1="{top-10}" x2="{X(3):.1f}" y2="{bot}" stroke="rgba(255,255,255,.18)" stroke-width="2"/>
<polyline points="{pts}" fill="none" stroke="#00FF23" stroke-width="14" stroke-linecap="round" stroke-linejoin="round" opacity=".18"/>
<polyline points="{pts}" fill="none" stroke="#00FF23" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
{dots}
<circle cx="{X(3):.1f}" cy="{Y(CUM[3]):.1f}" r="12" fill="#00FF23"/>
<text x="{X(3)+24:.1f}" y="{Y(CUM[3])-18:.1f}" fill="#00FF23" font-size="28" font-weight="700">42,350</text>
{labels}</svg>"""

CSS_A = f"""
body {{ background:{A['bg']}; color:{A['ink']}; }}
.content {{ position:absolute; top:100px; left:0; right:0; bottom:176px; padding:36px 32px 0; display:flex; flex-direction:column; }}
.eyebrow {{ font-size:26px; font-weight:600; letter-spacing:4px; color:{A['sub']}; text-transform:uppercase; }}
.hero {{ font-size:196px; font-weight:700; letter-spacing:-6px; line-height:1; margin-top:18px; }}
.hero-sub {{ font-size:38px; color:{A['sub']}; margin-top:6px; font-weight:500; }}
.delta {{ display:inline-flex; align-items:center; gap:10px; margin-top:26px; font-size:28px; font-weight:700; color:{A['green']}; }}
.row {{ display:flex; justify-content:space-between; align-items:baseline; padding:25px 0; border-top:1px solid {A['line']}; font-size:32px; }}
.row .k {{ color:{A['sub']}; font-weight:500; }}
.row .v {{ font-weight:600; }}
.cta {{ display:block; margin:auto 0 28px; background:{A['green']}; color:#000; text-align:center; font-size:36px; font-weight:700; padding:34px 0; border-radius:60px; }}
.cta.ghost {{ background:transparent; color:{A['ink']}; border:2px solid {A['line']}; }}
"""

def a_today():
    body = f"""
<div class="content">
  <div class="eyebrow">Thursday · Day 4 of 7</div>
  <div class="hero num">7,350</div>
  <div class="hero-sub">steps today</div>
  <div class="delta"><svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><path d="M12 19V5m-7 7 7-7 7 7"/></svg>73% of daily goal</div>
  <div style="margin-top:44px">
    <div style="position:relative;height:10px;background:rgba(255,255,255,.12);border-radius:5px">
      <div style="position:absolute;left:0;top:0;bottom:0;width:73.5%;background:{A['green']};border-radius:5px"></div>
      <div style="position:absolute;left:73.5%;top:50%;transform:translate(-50%,-50%);width:26px;height:26px;border-radius:50%;background:{A['green']};box-shadow:0 0 24px {A['green']}"></div>
    </div>
    <div style="display:flex;justify-content:space-between;margin-top:20px;font-size:26px;color:{A['sub']}"><span class="num" style="color:{A['ink']};font-weight:600">2,650 to go</span><span>Ends 11:59 PM CDT</span></div>
  </div>
  <div style="margin-top:64px">{chart_A()}</div>
  <div style="margin-top:40px">
    <div class="row"><span class="k">Apple Health</span><span class="v" style="color:{A['green']};font-size:28px">SYNCED 3 SEC AGO</span></div>
    <div class="row"><span class="k">Stakes on this week</span><span class="v num">$10.00</span></div>
  </div>
  <a class="cta">Sync now</a>
</div>{tabbar("Today", A)}"""
    return page("A · Today", CSS_A, body)

def a_week():
    rows = ""
    for name, v, st in DAYS:
        if st == "met":
            rows += f'''<div class="row"><span style="font-weight:600">{name.title()}</span><span style="display:flex;align-items:baseline;gap:24px"><span class="num" style="font-weight:600">{fmt(v)}</span><span style="color:{A['green']};font-size:26px;font-weight:700;letter-spacing:2px">MET ✓</span></span></div>'''
        elif st == "live":
            rows += f'''<div class="row" style="background:{A['card']};margin:0 -32px;padding-left:32px;padding-right:32px;border-top:1px solid {A['line']}"><span style="font-weight:700;color:{A['green']}">Today</span><span style="display:flex;align-items:baseline;gap:24px"><span class="num" style="font-weight:700">{fmt(v)}</span><span style="color:{A['green']};font-size:26px;font-weight:700;letter-spacing:2px">LIVE ●</span></span></div>'''
        else:
            rows += f'''<div class="row"><span style="color:{A['faint']};font-weight:500">{name.title()}</span><span class="num" style="color:{A['faint']}">—</span></div>'''
    body = f"""
<div class="content">
  <div class="eyebrow">Week 1 · Ends Friday 11:59 PM</div>
  <div class="hero num">42,350</div>
  <div class="hero-sub">steps this week</div>
  <div class="delta"><svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><path d="M12 19V5m-7 7 7-7 7 7"/></svg>+2,350 ahead of pace</div>
  <div style="margin-top:40px">{chart_A(width=789, height=380)}</div>
  <div style="margin-top:20px">{rows}</div>
  <div class="row" style="border-top:1px solid {A['line']}"><span class="k">Your stake</span><span class="v num">$10.00 <span style="color:{A['sub']};font-weight:400;font-size:26px">→ returned at 70,000</span></span></div>
</div>{tabbar("Challenges", A)}"""
    return page("A · Week", CSS_A, body)

# ---------------------------------------------------------------- B: TRAINING LOG (light, athletic)
B = dict(bg="#F7F6F2", ink="#111111", sub="rgba(17,17,17,.55)", faint="rgba(17,17,17,.28)",
         line="rgba(17,17,17,.14)", orange="#FF4D00", green="#1D7A3D",
         tab_bg="#F7F6F2", tab_line="rgba(17,17,17,.12)", tab_active="#111111", tab_idle="rgba(17,17,17,.35)")

CSS_B = f"""
body {{ background:{B['bg']}; color:{B['ink']}; }}
.content {{ position:absolute; top:100px; left:0; right:0; bottom:176px; padding:36px 32px 0; display:flex; flex-direction:column; }}
.eyebrow {{ font-size:26px; font-weight:800; letter-spacing:4px; color:{B['orange']}; text-transform:uppercase; }}
.hero {{ font-size:176px; font-weight:800; letter-spacing:-6px; line-height:1; margin-top:14px; }}
.hero-sub {{ font-size:38px; color:{B['sub']}; margin-top:8px; font-weight:500; }}
.cta {{ display:block; margin:auto 0 28px; background:{B['orange']}; color:#FFF; text-align:center; font-size:36px; font-weight:800; padding:34px 0; border-radius:60px; }}
.feedrow {{ display:flex; align-items:center; gap:28px; padding:26px 0; border-top:1px solid {B['line']}; }}
"""

def bars_B():
    cells = ""
    maxv = 13000.0
    for name, v, st in DAYS:
        if st == "met":
            bar = f'<div style="width:64px;height:{int(v/maxv*230)}px;background:#111;border-radius:8px 8px 0 0"></div>'
            val = f'<div style="font-size:22px;font-weight:700" class="num">{fmt(v)}</div>'
        elif st == "live":
            h = int(v/maxv*230)
            bar = f'''<div style="position:relative;width:64px;height:230px">
              <div style="position:absolute;bottom:0;width:64px;height:230px;border:3px dashed rgba(17,17,17,.25);border-radius:8px 8px 0 0"></div>
              <div style="position:absolute;bottom:0;width:64px;height:{h}px;background:{B['orange']};border-radius:8px 8px 0 0"></div></div>'''
            val = f'<div style="font-size:22px;font-weight:800;color:{B["orange"]}" class="num">{fmt(v)}</div>'
        else:
            bar = f'<div style="width:64px;height:230px;border:3px dashed rgba(17,17,17,.18);border-radius:8px 8px 0 0;box-sizing:border-box"></div>'
            val = f'<div style="font-size:22px;color:{B["faint"]}" class="num">·</div>'
        cells += f'''<div style="flex:1;display:flex;flex-direction:column;align-items:center;gap:14px">
        {val}<div style="height:230px;display:flex;align-items:flex-end">{bar}</div>
        <div style="font-size:24px;font-weight:{'800' if st=='live' else '500'};color:{B['ink'] if st!='future' else B['faint']}">{name[0]}{name[1:].lower()}</div></div>'''
    return f'''<div style="position:relative">
    <div style="position:absolute;left:0;right:0;bottom:{int(10000/maxv*230)+98}px;border-top:3px dashed rgba(17,17,17,.3)"></div>
    <div style="position:absolute;left:0;bottom:{int(10000/maxv*230)+108}px;font-size:20px;font-weight:700;color:rgba(17,17,17,.45);letter-spacing:1px">10K GOAL</div>
    <div style="display:flex;gap:8px">{cells}</div></div>'''

def b_today():
    body = f"""
<div class="content">
  <div class="eyebrow">Thursday · Day 4 of 7</div>
  <div class="hero num">7,350</div>
  <div class="hero-sub">of 10,000 steps · <b style="color:{B['ink']}">2,650 to go</b></div>
  <div style="margin-top:40px">
    <div style="height:22px;background:rgba(17,17,17,.08);border-radius:11px;overflow:hidden">
      <div style="width:73.5%;height:100%;background:{B['orange']};border-radius:11px"></div>
    </div>
    <div style="display:flex;justify-content:space-between;margin-top:18px;font-size:26px;color:{B['sub']}"><span>Today ends 11:59 PM CDT</span><span class="num" style="font-weight:700;color:{B['ink']}">73%</span></div>
  </div>
  <div style="margin-top:56px">{bars_B()}</div>
  <div style="margin-top:48px">
    <div class="feedrow"><div style="width:20px;height:20px;border-radius:50%;background:{B['orange']}"></div><div style="flex:1"><div style="font-size:32px;font-weight:700">Apple Health</div><div style="font-size:26px;color:{B['sub']}">Synced 3 seconds ago</div></div><div style="font-size:26px;font-weight:800;color:{B['orange']};letter-spacing:1px">SYNC</div></div>
    <div class="feedrow"><div style="flex:1;font-size:32px;color:{B['sub']}">Riding on this week</div><div style="font-size:36px;font-weight:800" class="num">$10.00</div></div>
  </div>
  <a class="cta">View challenge</a>
</div>{tabbar("Today", B)}"""
    return page("B · Today", CSS_B, body)

def b_week():
    entries = ""
    for name, v, st in DAYS:
        pct = (v or 0) / 10000.0 * 100
        if st == "met":
            bar = f'<div style="height:12px;background:rgba(17,17,17,.08);border-radius:6px;margin-top:20px"><div style="width:100%;height:100%;background:#111;border-radius:6px"></div></div>'
            entries += f'''<div class="feedrow" style="display:block"><div style="display:flex;justify-content:space-between;align-items:baseline"><span style="font-size:34px;font-weight:800">{name.title()}</span><span style="font-size:26px;font-weight:700;color:{B['green']}">GOAL MET ✓</span></div><div style="font-size:44px;font-weight:800;margin-top:6px" class="num">{fmt(v)} <span style="font-size:26px;font-weight:500;color:{B['sub']}">steps</span></div>{bar}</div>'''
        elif st == "live":
            entries += f'''<div style="background:#111;color:#FFF;border-radius:24px;padding:30px 36px;margin:24px -8px">
            <div style="display:flex;justify-content:space-between;align-items:baseline"><span style="font-size:34px;font-weight:800">Today</span><span style="font-size:26px;font-weight:800;color:{B['orange']};letter-spacing:2px">● IN PROGRESS</span></div>
            <div style="font-size:72px;font-weight:800;letter-spacing:-3px;margin-top:8px" class="num">{fmt(v)}</div>
            <div style="font-size:28px;color:rgba(255,255,255,.6)">of 10,000 · 2,650 to go by 11:59 PM</div>
            <div style="height:14px;background:rgba(255,255,255,.15);border-radius:7px;margin-top:22px"><div style="width:73.5%;height:100%;background:{B['orange']};border-radius:7px"></div></div></div>'''
        else:
            entries += f'''<div class="feedrow" style="display:block"><div style="display:flex;justify-content:space-between;align-items:baseline"><span style="font-size:34px;font-weight:600;color:{B['faint']}">{name.title()}</span><span style="font-size:26px;color:{B['faint']}">UP NEXT</span></div><div style="font-size:44px;font-weight:700;color:{B['faint']};margin-top:6px" class="num">—</div></div>'''
    body = f"""
<div class="content">
  <div class="eyebrow">Week 1 · Ends Friday</div>
  <div style="display:flex;align-items:baseline;gap:20px;margin-top:14px"><span style="font-size:80px;font-weight:800;letter-spacing:-3px" class="num">42,350</span><span style="font-size:32px;font-weight:700;color:{B['green']}" class="num">+2,350 ahead</span></div>
  <div class="hero-sub">steps this week · goal 70,000</div>
  <div style="margin-top:16px">{entries}</div>
</div>{tabbar("Challenges", B)}"""
    return page("B · Week", CSS_B, body)

# ---------------------------------------------------------------- C: NIGHT SPLITS (dark athletic fusion)
C = dict(bg="#151515", ink="#FFFFFF", sub="#8A93A6", faint="#4A5261",
         line="rgba(255,255,255,.10)", green="#48D08C", blue="#4D6BFE", coral="#FF453A",
         tab_bg="#151515", tab_line="rgba(255,255,255,.10)", tab_active="#FFFFFF", tab_idle="#5A6270")

CSS_C = f"""
body {{ background:{C['bg']}; color:{C['ink']}; }}
.content {{ position:absolute; top:100px; left:0; right:0; bottom:176px; padding:36px 0 0; display:flex; flex-direction:column; }}
.eyebrow {{ font-size:26px; font-weight:600; letter-spacing:4px; color:{C['sub']}; text-transform:uppercase; padding:0 32px; }}
.split {{ display:flex; align-items:center; gap:28px; padding:30px 32px; border-top:1px solid {C['line']}; }}
.split .day {{ width:120px; font-size:30px; font-weight:600; }}
.split .val {{ flex:1; text-align:right; font-size:34px; font-weight:600; }}
.split .st {{ width:170px; text-align:right; font-size:24px; font-weight:700; letter-spacing:2px; }}
.liveband {{ background:{C['coral']}; color:#FFF; padding:44px 32px 40px; }}
.cta {{ display:block; margin:auto 32px 28px; background:#FFF; color:#151515; text-align:center; font-size:36px; font-weight:700; padding:34px 0; border-radius:60px; }}
"""

def c_today():
    splits = ""
    for name, v, st in DAYS[:3]:
        splits += f'''<div class="split"><span class="day">{name.title()}</span><span class="val num">{fmt(v)}</span><span class="st" style="color:{C['green']}">MET ✓</span></div>'''
    future = ""
    for name, v, st in DAYS[4:]:
        future += f'''<div class="split"><span class="day" style="color:{C['faint']}">{name.title()}</span><span class="val num" style="color:{C['faint']}">—</span><span class="st" style="color:{C['faint']}">QUEUED</span></div>'''
    body = f"""
<div class="content">
  <div class="eyebrow">Week 1 · Day 4 of 7</div>
  <div style="margin-top:36px">{splits}</div>
  <div class="liveband">
    <div style="display:flex;justify-content:space-between;align-items:baseline"><span style="font-size:30px;font-weight:800;letter-spacing:3px">TODAY · THURSDAY</span><span style="font-size:26px;font-weight:600;opacity:.8">ENDS 11:59 PM CDT</span></div>
    <div style="font-size:160px;font-weight:800;letter-spacing:-5px;line-height:1.05;margin-top:16px" class="num">7,350</div>
    <div style="font-size:32px;opacity:.85;font-weight:500">of 10,000 · <b>2,650 to go</b></div>
    <div style="height:12px;background:rgba(255,255,255,.28);border-radius:6px;margin-top:30px"><div style="width:73.5%;height:100%;background:#FFF;border-radius:6px"></div></div>
    <div style="display:flex;align-items:center;gap:12px;margin-top:28px;font-size:26px;font-weight:600;color:#EAF0FF">
      <svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor"><path d="M12 21s-7.5-4.9-9.7-9A5.6 5.6 0 0 1 12 5.6 5.6 5.6 0 0 1 21.7 12c-2.2 4.1-9.7 9-9.7 9z"/></svg>
      Apple Health · updated 3 sec ago</div>
  </div>
  <div>{future}</div>
  <div class="split" style="border-top:1px solid {C['line']}"><span class="day" style="color:{C['sub']};width:auto">Test commitment</span><span class="val num" style="font-size:30px">$10.00</span></div>
  <a class="cta">View week</a>
</div>{tabbar("Today", C)}"""
    return page("C · Today", CSS_C, body)

def c_week():
    bars = ""
    maxv = 13000.0
    for name, v, st in DAYS:
        if st == "met":
            fill = f'<div style="width:{v/maxv*100:.1f}%;height:100%;background:{C["green"]};border-radius:8px"></div>'
            val = f'<span class="num" style="font-weight:700">{fmt(v)}</span>'
            tag = f'<span style="color:{C["green"]}">✓</span>'
        elif st == "live":
            fill = f'<div style="width:{v/maxv*100:.1f}%;height:100%;background:{C["coral"]};border-radius:8px"></div>'
            val = f'<span class="num" style="font-weight:700;color:{C["coral"]}">{fmt(v)}</span>'
            tag = f'<span style="color:{C["coral"]};font-weight:700">LIVE</span>'
        else:
            fill = ''
            val = '<span class="num" style="color:#4A5261">—</span>'
            tag = ''
        bars += f'''<div style="display:flex;align-items:center;gap:24px;padding:26px 0;border-top:1px solid {C['line']}">
        <span style="width:96px;font-size:28px;font-weight:600;color:{C['ink'] if st!='future' else C['faint']}">{name.title()}</span>
        <div style="flex:1;height:44px;background:rgba(255,255,255,.06);border-radius:8px;position:relative">{fill}
        <div style="position:absolute;left:{10000/maxv*100:.1f}%;top:-6px;bottom:-6px;width:3px;background:rgba(255,255,255,.4)"></div></div>
        <span style="width:150px;text-align:right;font-size:30px">{val}</span>
        <span style="width:70px;text-align:right;font-size:24px">{tag}</span></div>'''
    body = f"""
<div class="content" style="padding:36px 32px 0">
  <div class="eyebrow" style="padding:0">Week 1 · Ends Friday 11:59 PM</div>
  <div style="display:flex;align-items:baseline;gap:24px;margin-top:20px"><span style="font-size:120px;font-weight:800;letter-spacing:-4px" class="num">42,350</span></div>
  <div style="font-size:32px;font-weight:600;color:{C['green']};margin-top:4px" class="num">+2,350 ahead of required pace</div>
  <div style="font-size:26px;color:{C['sub']};margin-top:8px">Goal 70,000 · America/Chicago</div>
  <div style="margin-top:44px">{bars}</div>
  <div style="display:flex;justify-content:space-between;align-items:center;margin-top:auto;margin-bottom:28px;padding:30px 0;border-top:1px solid {C['line']}">
    <span style="font-size:28px;color:{C['sub']}">Test commitment · verified by Apple Health</span>
    <span class="num" style="font-size:34px;font-weight:700">$10.00</span></div>
</div>{tabbar("Challenges", C)}"""
    return page("C · Week", CSS_C, body)

# ---------------------------------------------------------------- write
screens = {
    "a-position-today": a_today(),
    "a-position-week": a_week(),
    "b-traininglog-today": b_today(),
    "b-traininglog-week": b_week(),
    "c-nightsplits-today": c_today(),
    "c-nightsplits-week": c_week(),
}
for name, html in screens.items():
    with open(os.path.join(OUT, name + ".html"), "w") as f:
        f.write(html)

# contact sheet
cells = "".join(f'<iframe src="{n}.html" style="width:{W}px;height:{H}px;border:none;transform:scale(0.36);transform-origin:top left"></iframe>' for n in screens)
frames = "".join(f'<div style="width:{int(W*0.36)}px;height:{int(H*0.36)}px;overflow:hidden;flex:none"><iframe src="{n}.html" style="width:{W}px;height:{H}px;border:none;transform:scale(0.36);transform-origin:top left"></iframe><div style="position:relative;top:-{int(H*0.36)+40}px"></div></div>' for n in screens)
labels = "".join(f'<div style="width:{int(W*0.36)}px"><div style="height:{int(H*0.36)}px;overflow:hidden"><iframe src="{n}.html" style="width:{W}px;height:{H}px;border:none;transform:scale(0.36);transform-origin:top left" scrolling="no"></iframe></div><div style="color:#888;font:500 15px -apple-system;margin-top:14px;letter-spacing:.5px">{n.upper()}</div></div>' for n in screens)
sheet = f"""<!DOCTYPE html><html><head><meta charset="utf-8"><style>*{{margin:0;box-sizing:border-box}}body{{background:#0A0A0B;padding:56px;font-family:-apple-system}}</style></head>
<body><div style="color:#FFF;font:800 34px -apple-system;letter-spacing:-.5px">BETTER BET — three directions</div>
<div style="color:#666;font:500 17px -apple-system;margin:10px 0 40px">A · Position (dark money) &nbsp;&nbsp; B · Training Log (light athletic) &nbsp;&nbsp; C · Night Splits (dark athletic)</div>
<div style="display:flex;gap:44px;flex-wrap:wrap">{labels}</div></body></html>"""
with open(os.path.join(OUT, "sheet.html"), "w") as f:
    f.write(sheet)
print("generated:", ", ".join(screens), "+ sheet")
