#!/usr/bin/env python3
"""Regressions for scripts/build-legal-site.py."""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('legal_site', ROOT / 'scripts/build-legal-site.py')
legal_site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(legal_site)

PUBLISHABLE_PRIVACY = """# GameTime privacy policy

GameTime is operated by Example Person in Example State.

- Write to **help@example.com**.
"""
PUBLISHABLE_TERMS = """# GameTime beta terms

1. Stakes are simulated.
   No money moves.
"""


def run(*argv):
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()) as err:
        status = legal_site.main(list(argv))
    return status, err.getvalue()


class LegalSiteTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='gametime-legal-site-test-')
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        (self.root / 'docs').mkdir()
        self.write(PUBLISHABLE_PRIVACY, PUBLISHABLE_TERMS)

    def write(self, privacy, terms):
        (self.root / 'docs/PRIVACY_POLICY.md').write_text(privacy, encoding='utf-8')
        (self.root / 'docs/BETA_TERMS.md').write_text(terms, encoding='utf-8')

    def site(self, name):
        return (self.root / legal_site.OUTPUT / name).read_text(encoding='utf-8')

    def test_committed_site_is_final_and_matches_its_sources(self):
        status, err = run('--root', str(ROOT), '--final', '--check')
        self.assertEqual(status, 0, err)

    def test_draft_build_is_bannered_and_unindexed(self):
        self.assertEqual(run('--root', str(self.root))[0], 0)
        for name in ('index.html', 'privacy.html', 'beta-terms.html'):
            self.assertIn('Draft — not published.', self.site(name))
            self.assertIn('content="noindex"', self.site(name))
        self.assertTrue((self.root / legal_site.OUTPUT / '.nojekyll').is_file())

    def test_final_refuses_placeholders_and_draft_notes(self):
        self.write(PUBLISHABLE_PRIVACY.replace('Example Person', '[LEGAL ENTITY]'),
                   '# Beta terms — unpublished implementation draft\n')
        status, err = run('--root', str(self.root), '--final')
        self.assertEqual(status, 1)
        self.assertIn('PRIVACY_POLICY.md:3: unfilled placeholder "[LEGAL ENTITY]"', err)
        self.assertIn('BETA_TERMS.md:1: draft note "unpublished"', err)
        self.assertFalse((self.root / legal_site.OUTPUT).exists())

    def test_final_build_drops_the_banner(self):
        self.assertEqual(run('--root', str(self.root), '--final')[0], 0)
        privacy = self.site('privacy.html')
        self.assertNotIn('Draft — not published.', privacy)
        self.assertNotIn('noindex', privacy)
        self.assertIn('<li>Write to <strong>help@example.com</strong>.</li>', privacy)
        self.assertIn('<ol><li>Stakes are simulated. No money moves.</li></ol>', self.site('beta-terms.html'))

    def test_check_reports_a_stale_site(self):
        run('--root', str(self.root))
        self.write(PUBLISHABLE_PRIVACY + '\nA new sentence.\n', PUBLISHABLE_TERMS)
        status, err = run('--root', str(self.root), '--check')
        self.assertEqual(status, 1)
        self.assertIn('privacy.html', err)

    def test_inline_rendering(self):
        self.assertEqual(legal_site.inline('Write to [SUPPORT EMAIL].'),
                         'Write to <mark>[SUPPORT EMAIL]</mark>.')
        # Repository links become plain text; web links stay links.
        self.assertEqual(legal_site.inline('See [the plan](PLAN.md).'), 'See the plan.')
        self.assertEqual(legal_site.inline('[Apple](https://apple.com/a?b=1&c=2)'),
                         '<a href="https://apple.com/a?b=1&amp;c=2">Apple</a>')
        self.assertEqual(legal_site.inline('<script> & `a<b`'),
                         '&lt;script&gt; &amp; <code>a&lt;b</code>')


if __name__ == '__main__':
    unittest.main()
