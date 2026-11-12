"""The banned-claims check for the copy gate (tests/policy-copy.sh).

Prints one line per banned word found in the VISIBLE text of a published page,
"<page>: <word>: <the words around it>", and nothing when the site is clean.
The list is tests/banned-claims.json, a copy of the app's
src/test-utils/copy/banned-claims.json (dwasi-app); its allowed_phrases are
denials and are removed before the search. tests/banned-claims-allowed.tsv holds
this site's own exceptions, by page and exact text.

Usage: python3 tests/banned_claims.py <site root> [page ...]
"""

from __future__ import annotations

import html
import json
import re
import sys
from pathlib import Path


def visible(markup: str) -> str:
    """The text a visitor reads: no scripts, styles, comments or tags."""
    markup = re.sub(r"<script[\s\S]*?</script>|<style[\s\S]*?</style>|<!--[\s\S]*?-->", " ", markup)
    return " ".join(html.unescape(re.sub(r"<[^>]+>", " ", markup)).split())


def allowed_by_page(path: Path) -> dict[str, list[str]]:
    pages: dict[str, list[str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        page, _, text = line.partition("\t")
        if text:
            pages.setdefault(page, []).append(" ".join(text.split()))
    return pages


def main(argv: list[str]) -> int:
    root = Path(argv[1])
    tests = root / "tests"
    claims = json.loads((tests / "banned-claims.json").read_text(encoding="utf-8"))
    site_allowed = allowed_by_page(tests / "banned-claims-allowed.tsv")
    pages = argv[2:] or sorted(
        p.relative_to(root).as_posix()
        for p in root.rglob("*.html")
        if not {".git", ".wrangler", "tests"} & set(p.relative_to(root).parts)
    )
    found = 0
    for page in pages:
        text = visible((root / page).read_text(encoding="utf-8"))
        for phrase in [*claims["allowed_phrases"], *site_allowed.get(page, [])]:
            text = re.sub(re.escape(phrase), " ", text, flags=re.IGNORECASE)
        for term in claims["banned"]:
            pattern = r"(?<![A-Za-z])" + re.escape(term) + r"(?![A-Za-z])"
            for hit in re.finditer(pattern, text, flags=re.IGNORECASE):
                around = text[max(0, hit.start() - 40) : hit.end() + 40]
                print(f"{page}: {term}: ...{around}...")
                found += 1
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
