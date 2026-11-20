"""Read-only lint of the wiki. Usage: python wiki/lint.py [wiki-folder]

Checks broken relative links, pages missing from index.md, the context.md budget, oversized logs,
pages without frontmatter and em or en dashes. Exits with 1 when something needs fixing.
"""
import re
import sys
from pathlib import Path

CONTEXT_MAX = 6000
LOG_MAX = 20000
SKIP_DIRS = {"raw", "archive"}
SPECIAL = {"index", "log", "context"}
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
CODE = re.compile(r"`[^`]*`")


def pages(root):
    return sorted(p for p in root.rglob("*.md") if not SKIP_DIRS & set(p.relative_to(root).parts[:-1]))


def stem(p):
    return p.name.removesuffix(".md").removesuffix(".example")


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).parent).resolve()
    found = {k: [] for k in ("broken links", "missing from index", "context over budget", "large logs",
                             "pages without frontmatter", "em or en dashes")}
    all_pages = pages(root)
    index = root / "index.md"
    if not index.exists():
        index = root / "index.example.md"
    index_text = index.read_text(encoding="utf-8") if index.exists() else ""

    for p in all_pages:
        rel = p.relative_to(root).as_posix()
        text = p.read_text(encoding="utf-8")
        in_fence = False
        for n, line in enumerate(text.splitlines(), 1):
            if line.strip().startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for target in LINK.findall(CODE.sub("", line)):
                if re.match(r"^(https?:|mailto:|#)", target):
                    continue
                path = p.parent / target.split("#")[0]
                template = path.with_name(path.name.removesuffix(".md") + ".example.md")
                if not path.exists() and not template.exists():
                    found["broken links"].append(f"{rel}:{n} -> {target}")
        dashes = len(re.findall("[–—]", text))
        if dashes:
            found["em or en dashes"].append(f"{rel} ({dashes})")
        if stem(p) == "context" and len(text) > CONTEXT_MAX:
            found["context over budget"].append(f"{rel}: {len(text)} chars, max {CONTEXT_MAX}")
        if stem(p) == "log" and len(text) > LOG_MAX:
            found["large logs"].append(f"{rel}: {len(text)} chars, Grep it instead of reading it")
        if stem(p) not in SPECIAL:
            if not text.startswith("---"):
                found["pages without frontmatter"].append(rel)
            if p.name not in index_text:
                found["missing from index"].append(rel)

    problems = sum(len(v) for v in found.values())
    print(f"wiki lint | {root} | {len(all_pages)} pages | {problems} findings")
    for title, items in found.items():
        if items:
            print(f"\n{title} ({len(items)})")
            for item in items[:20]:
                print(f"  {item}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
