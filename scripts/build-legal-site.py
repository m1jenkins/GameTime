#!/usr/bin/env python3
"""Render the privacy policy and beta terms as a small static site.

Writes plain HTML to docs/legal-site/ from the Markdown sources. There is no
toolchain: this script only uses the standard library, and the output is a
directory of self-contained pages any static host can serve.

    python3 scripts/build-legal-site.py            # draft preview, bannered
    python3 scripts/build-legal-site.py --check    # fail if the site is stale
    python3 scripts/build-legal-site.py --final    # refuse until publishable

A draft build marks every page "Draft — not published". --final drops the
banner and refuses while a source still carries an unfilled placeholder or an
internal draft note. The script never publishes anything; see
docs/LEGAL_PAGES_PUBLISH_RUNBOOK.md.
"""
import argparse
import filecmp
import html
from pathlib import Path
import re
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = Path('docs/legal-site')

# (source, output file, page title, index blurb)
PAGES = (
    (Path('docs/PRIVACY_POLICY.md'), 'privacy.html', 'Privacy policy',
     'What GameTime collects, why, and how to delete it.'),
    (Path('docs/BETA_PRIVACY_TERMS_DRAFT.md'), 'beta-terms.html', 'Beta terms',
     'The terms for testing the GameTime beta.'),
)

PLACEHOLDER = re.compile(r'\[(SUPPORT EMAIL|LEGAL ENTITY|JURISDICTION)\]')
# Notes written for whoever publishes, not for the person reading the page.
DRAFT_NOTE = re.compile(
    r'unpublished|draft for review|before you publish|publication blockers|not legal advice',
    re.IGNORECASE,
)

STYLE = """
:root { color-scheme: light dark; --fg: #1d1d1f; --muted: #5c5c63; --bg: #fff;
  --rule: #d9d9de; --accent: #0a6cff; --mark: #fff1a8; --banner: #fff4e0; --banner-rule: #f0b35a; }
@media (prefers-color-scheme: dark) {
  :root { --fg: #f2f2f5; --muted: #a8a8b0; --bg: #111114; --rule: #2e2e34;
    --accent: #5aa0ff; --mark: #5c4d00; --banner: #2b2112; --banner-rule: #a8752b; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg);
  font: 17px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; }
main { max-width: 42rem; margin: 0 auto; padding: 2.5rem 1.25rem 4rem; }
header.site { font-weight: 700; letter-spacing: -0.01em; margin-bottom: 2rem; }
header.site a { color: inherit; text-decoration: none; }
h1 { font-size: 2rem; line-height: 1.2; letter-spacing: -0.02em; margin: 0 0 1.25rem; }
h2 { font-size: 1.3rem; margin: 2.25rem 0 0.75rem; }
h3 { font-size: 1.1rem; margin: 1.75rem 0 0.5rem; }
p, ul, ol, blockquote { margin: 0 0 1rem; }
li { margin-bottom: 0.4rem; }
a { color: var(--accent); }
code { font: 0.9em ui-monospace, SFMono-Regular, Menlo, monospace; }
hr { border: 0; border-top: 1px solid var(--rule); margin: 2rem 0; }
blockquote { border-left: 3px solid var(--rule); padding-left: 1rem; color: var(--muted); }
mark { background: var(--mark); color: inherit; padding: 0 0.2em; border-radius: 3px; }
.banner { background: var(--banner); border: 1px solid var(--banner-rule); border-radius: 10px;
  padding: 0.85rem 1rem; margin-bottom: 2rem; font-size: 0.95rem; }
.eyebrow { color: var(--muted); font-size: 0.9rem; text-transform: uppercase;
  letter-spacing: 0.06em; margin-bottom: 0.4rem; }
ul.pages { list-style: none; padding: 0; }
ul.pages li { border-top: 1px solid var(--rule); padding: 1rem 0; margin: 0; }
ul.pages a { font-weight: 600; font-size: 1.1rem; }
ul.pages span { display: block; color: var(--muted); }
footer { color: var(--muted); font-size: 0.85rem; margin-top: 3rem;
  border-top: 1px solid var(--rule); padding-top: 1rem; }
""".strip()

BANNER = (
    '<p class="banner"><strong>Draft — not published.</strong> '
    'This page previews text that is still being reviewed. '
    'It is not in effect yet.</p>'
)


def inline(text):
    """Render the inline Markdown the sources use: code, links, bold, italic."""
    parts = re.split(r'(`[^`]+`)', text)
    rendered = []
    for part in parts:
        if part.startswith('`') and part.endswith('`') and len(part) > 1:
            rendered.append(f'<code>{html.escape(part[1:-1])}</code>')
            continue
        part = html.escape(part, quote=False)

        def link(match):
            label, target = match.group(1), match.group(2)
            # Repository-relative links mean nothing on the public site.
            if re.match(r'https?://', target):
                # Already escaped above, except for quotes.
                return f'<a href="{target.replace(chr(34), "&quot;")}">{label}</a>'
            return label

        part = re.sub(r'\[([^\]]+)\]\(([^)\s]+)\)', link, part)
        part = PLACEHOLDER.sub(lambda m: f'<mark>{m.group(0)}</mark>', part)
        part = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', part)
        part = re.sub(r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])', r'<em>\1</em>', part)
        rendered.append(part)
    return ''.join(rendered)


def render_markdown(source):
    """Render the block Markdown the sources use.

    Headings, paragraphs, blockquotes, horizontal rules, and flat ordered or
    unordered lists whose items continue on indented lines.
    """
    blocks = []
    lines = source.splitlines()
    index = 0

    def gather_list(pattern):
        nonlocal index
        items = []
        while index < len(lines):
            line = lines[index]
            match = pattern.match(line)
            if match:
                items.append(match.group(1).strip())
            elif line.startswith(' ') and line.strip() and items:
                items[-1] += ' ' + line.strip()
            else:
                break
            index += 1
        return items

    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        if not stripped:
            index += 1
            continue
        heading = re.match(r'(#{1,3})\s+(.*)', stripped)
        if heading:
            level = len(heading.group(1))
            blocks.append(f'<h{level}>{inline(heading.group(2))}</h{level}>')
            index += 1
        elif re.fullmatch(r'-{3,}', stripped):
            blocks.append('<hr>')
            index += 1
        elif stripped.startswith('>'):
            quoted = []
            while index < len(lines) and lines[index].strip().startswith('>'):
                quoted.append(re.sub(r'^\s*>\s?', '', lines[index]))
                index += 1
            blocks.append(f'<blockquote>{render_markdown(chr(10).join(quoted))}</blockquote>')
        elif re.match(r'- ', stripped):
            items = gather_list(re.compile(r'- (.*)'))
            blocks.append('<ul>' + ''.join(f'<li>{inline(i)}</li>' for i in items) + '</ul>')
        elif re.match(r'\d+\. ', stripped):
            items = gather_list(re.compile(r'\d+\. (.*)'))
            blocks.append('<ol>' + ''.join(f'<li>{inline(i)}</li>' for i in items) + '</ol>')
        else:
            paragraph = []
            while index < len(lines):
                current = lines[index].strip()
                if not current or re.match(r'(#{1,3}\s|>|- |\d+\. |-{3,}$)', current):
                    break
                paragraph.append(current)
                index += 1
            blocks.append(f'<p>{inline(" ".join(paragraph))}</p>')
    return '\n'.join(blocks)


def page(title, body, source, final):
    banner = '' if final else BANNER + '\n'
    robots = '' if final else '<meta name="robots" content="noindex">\n'
    generated = f' from {source}' if source else ''
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
{robots}<title>{html.escape(title)} — GameTime</title>
<style>
{STYLE}
</style>
</head>
<!-- Generated by scripts/build-legal-site.py{generated}. Do not edit by hand. -->
<body>
<main>
<header class="site"><a href="index.html">GameTime</a></header>
{banner}{body}
<footer><a href="index.html">GameTime legal pages</a></footer>
</main>
</body>
</html>
"""


def publication_problems(root):
    problems = []
    for source, _, _, _ in PAGES:
        for number, line in enumerate((root / source).read_text(encoding='utf-8').splitlines(), 1):
            for pattern, kind in ((PLACEHOLDER, 'unfilled placeholder'), (DRAFT_NOTE, 'draft note')):
                for match in pattern.finditer(line):
                    problems.append(f'{source}:{number}: {kind} "{match.group(0)}"')
    return problems


def build(root, output, final):
    output.mkdir(parents=True, exist_ok=True)
    links = []
    for source, filename, title, blurb in PAGES:
        body = render_markdown((root / source).read_text(encoding='utf-8'))
        body = f'<p class="eyebrow">{html.escape(title)}</p>\n{body}'
        (output / filename).write_text(page(title, body, source, final), encoding='utf-8')
        links.append(
            f'<li><a href="{filename}">{html.escape(title)}</a>'
            f'<span>{html.escape(blurb)}</span></li>'
        )
    index_body = '<h1>Legal</h1>\n<ul class="pages">\n' + '\n'.join(links) + '\n</ul>'
    (output / 'index.html').write_text(page('Legal', index_body, None, final), encoding='utf-8')
    # Serve the files as written; GitHub Pages would otherwise run Jekyll.
    (output / '.nojekyll').write_text('', encoding='utf-8')


def stale_files(expected, actual):
    names = {p.name for p in expected.iterdir()}
    if actual.is_dir():
        names |= {p.name for p in actual.iterdir()}
    return [
        name for name in sorted(names)
        if not (expected / name).is_file() or not (actual / name).is_file()
        or not filecmp.cmp(expected / name, actual / name, shallow=False)
    ]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--root', type=Path, default=ROOT, help='repository root')
    parser.add_argument('--final', action='store_true',
                        help='build without the draft banner; refuses unpublishable sources')
    parser.add_argument('--check', action='store_true',
                        help='compare a fresh build with the committed site instead of writing')
    args = parser.parse_args(argv)
    root = args.root.resolve()
    output = root / OUTPUT

    if args.final:
        problems = publication_problems(root)
        if problems:
            print('Not publishable yet. Resolve these in the sources first:', file=sys.stderr)
            for problem in problems:
                print(f'  {problem}', file=sys.stderr)
            return 1

    if args.check:
        with tempfile.TemporaryDirectory(prefix='gametime-legal-site-') as scratch:
            expected = Path(scratch)
            build(root, expected, args.final)
            stale = stale_files(expected, output)
        if stale:
            mode = ' --final' if args.final else ''
            print(f'{OUTPUT} is stale ({", ".join(stale)}). '
                  f'Run: python3 scripts/build-legal-site.py{mode}', file=sys.stderr)
            return 1
        print(f'{OUTPUT} matches its sources.')
        return 0

    build(root, output, args.final)
    print(f'Wrote {OUTPUT} ({"final" if args.final else "draft"}).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
