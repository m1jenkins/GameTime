"""Assemble the original Fieldwork study and its connected screen extension."""
from pathlib import Path
import re
import json
import base64

HERE = Path(__file__).resolve().parent
source = (HERE / 'reference.html').read_text()
source = source.replace('<div class="gt-caption"><span id="gt-direction-name">Fieldwork / 02</span><span>Concept · fictional data</span></div>', '<!-- Fieldwork Glass: extend the owner-selected brand and existing challenges. Solid score-sheet content; glass navigation. Local fictional flow study, no external actions. Brand authority: ../2026-09-13-creation-directions/fieldwork-glass-brand-kit.json -->\n<div class="gt-caption"><span id="gt-direction-name">GameTime · Fieldwork Glass</span><span>Prototype · fictional data · no real money</span></div><div class="prototype-tools"></div>')
source = source[:source.index('function render()')]
# Load the exact owner-specified brand kit; the palette is never re-invented here.
brand = json.loads((HERE.parent / '2026-09-13-creation-directions/fieldwork-glass-brand-kit.json').read_text())['brand_kit']
palette = {(c['role'],c['appearance']):c['hex'] for c in brand['colors']}
roles = {'--gt-paper':'canvas','--gt-ink':'text-primary','--gt-muted':'text-secondary','--gt-line':'divider','--gt-surface':'surface','--gt-soft':'selection','--gt-action':'action','--gt-action-ink':'action-text','--gt-pop':'accent','--ft-progress':'chart-primary','--ft-secondary-bar':'chart-secondary'}
tokens = ';'.join(f'{token}:light-dark({palette[(role,"light")]},{palette[(role,"dark")]})' for token,role in roles.items())
for token,role in {'--ft-forest':'club-board','--ft-on-forest':'club-board-text','--ft-citrus':'club-board-accent'}.items():
    tokens += f';{token}:{palette[(role,"both")]}'
source = source.replace('</style>', '#gt-fieldwork-glass{'+tokens+'}\n</style>')
source = source.replace('<div class="prototype-tools"></div>', '<div class="prototype-tools"></div><div class="scenario-tools" hidden><label class="ft-hidden" for="result-picker">Result example</label><select id="result-picker" data-result-picker><option value="review">Result example: review open</option><option value="tie">Result example: equal best totals</option><option value="unknown">Result example: missing final data</option></select></div>')
source = re.sub(r'^#gt-fieldwork-glass \.gt-score-row\.me.*\n', '', source, flags=re.M)
source = source.replace('</style>', (HERE / 'screens.css').read_text() + '\n</style>')
art_assets = {key:'data:image/webp;base64,'+base64.b64encode((HERE / 'assets' / name).read_bytes()).decode('ascii') for key,name in {'photo':'club-morning-v1.webp','graphic':'stride-print-v1.webp','lace':'lace-up-print-v1.webp','bump':'fist-bump-print-v1.webp','run':'running-print-v1.webp'}.items()}
source += 'const fieldworkArtAssets='+json.dumps(art_assets)+';\n'
source += (HERE / 'screens.js').read_text() + '\n})();\n</script>\n'
# Keep the source study intact; apply only the diagnosed copy repairs to this build.
for repair in json.loads((HERE / 'copy-rewrites.json').read_text()):
    source = source.replace(repair['before'],repair['after'])
assert len(source.encode('utf-8')) < 1_000_000, 'Keep the embedded prototype below 1 MB.'
(HERE / 'fieldwork-app.html').write_text(source)
standalone = '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>GameTime · Fieldwork Glass</title><script src="https://unpkg.com/lucide@0.468.0/dist/umd/lucide.min.js"></script><style>body{margin:0;padding:24px 12px;background:#e7e7df}body:has(#gt-fieldwork-glass[style*="dark"]){background:#141b20}@media(max-width:450px){body{padding:8px}}</style></head><body>' + source + '</body></html>'
(HERE / 'index.html').write_text(standalone)
scripts = re.findall(r'<script>(.*?)</script>',source,re.S)
(HERE / 'check-syntax.js').write_text('\n'.join(scripts))
print('Built fieldwork-app.html and index.html')
