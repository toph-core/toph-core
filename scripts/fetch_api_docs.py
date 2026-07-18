#!/usr/bin/env python3
"""Fetch MaryAI Swagger and generate Markdown API docs.

Usage (from repo root):
    python3 scripts/fetch_api_docs.py

Optional:
    python3 scripts/fetch_api_docs.py --url https://api.maryai.uz/swagger/doc.json
    python3 scripts/fetch_api_docs.py --out api-docs
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from collections import defaultdict
from pathlib import Path

DEFAULT_URL = "https://api.maryai.uz/swagger/doc.json"
DEFAULT_OUT = "api-docs"


def fetch_swagger(url: str, timeout: int = 60) -> dict:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "mary-ai-pos-api-docs/1.0",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
    return json.loads(raw.decode("utf-8"))


def _ref_name(ref: str | None) -> str:
    if not ref:
        return ""
    # "#/definitions/Foo" -> "Foo"
    return ref.rsplit("/", 1)[-1]


def _schema_label(schema: dict | None) -> str:
    if not schema:
        return ""
    if "$ref" in schema:
        return _ref_name(schema["$ref"])
    t = schema.get("type", "object")
    if t == "array":
        items = schema.get("items") or {}
        inner = _schema_label(items) or items.get("type", "object")
        return f"array<{inner}>"
    return t


def _slug(name: str) -> str:
    s = name.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-") or "untagged"


def _param_row(p: dict) -> str:
    name = p.get("name", "")
    loc = p.get("in", "")
    required = "yes" if p.get("required") else "no"
    typ = p.get("type") or _schema_label(p.get("schema")) or ""
    desc = (p.get("description") or "").replace("\n", " ").strip()
    return f"| `{name}` | {loc} | {typ} | {required} | {desc} |"


def render_operation(method: str, path: str, op: dict) -> str:
    lines: list[str] = []
    summary = op.get("summary") or op.get("operationId") or f"{method.upper()} {path}"
    lines.append(f"### `{method.upper()}` `{path}`")
    lines.append("")
    lines.append(f"**{summary}**")
    lines.append("")
    desc = (op.get("description") or "").strip()
    if desc:
        lines.append(desc)
        lines.append("")

    if op.get("security"):
        lines.append("_Auth: Bearer required_")
        lines.append("")

    params = op.get("parameters") or []
    if params:
        lines.append("| Name | In | Type | Required | Description |")
        lines.append("|---|---|---|---|---|")
        for p in params:
            lines.append(_param_row(p))
        lines.append("")

    body = next((p for p in params if p.get("in") == "body"), None)
    if body and body.get("schema"):
        lines.append(f"**Body schema:** `{_schema_label(body['schema'])}`")
        lines.append("")

    responses = op.get("responses") or {}
    if responses:
        lines.append("**Responses**")
        lines.append("")
        for code, resp in sorted(responses.items(), key=lambda x: str(x[0])):
            if not isinstance(resp, dict):
                continue
            rdesc = resp.get("description") or ""
            schema = _schema_label(resp.get("schema"))
            extra = f" → `{schema}`" if schema else ""
            lines.append(f"- `{code}` — {rdesc}{extra}")
        lines.append("")

    lines.append("---")
    lines.append("")
    return "\n".join(lines)


def build_docs(spec: dict, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    tags_dir = out_dir / "tags"
    tags_dir.mkdir(exist_ok=True)

    # Save raw swagger
    swagger_path = out_dir / "swagger.json"
    swagger_path.write_text(
        json.dumps(spec, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    info = spec.get("info") or {}
    host = spec.get("host") or ""
    base = spec.get("basePath") or ""
    schemes = spec.get("schemes") or ["https"]
    base_url = f"{schemes[0]}://{host}{base}" if host else base or "(see swagger)"

    by_tag: dict[str, list[tuple[str, str, dict]]] = defaultdict(list)
    for path, methods in sorted((spec.get("paths") or {}).items()):
        if not isinstance(methods, dict):
            continue
        for method, op in methods.items():
            if method.startswith("x-") or not isinstance(op, dict):
                continue
            tags = op.get("tags") or ["untagged"]
            for tag in tags:
                by_tag[tag].append((method, path, op))

    # Per-tag markdown files
    index_rows: list[tuple[str, int, str]] = []
    for tag in sorted(by_tag.keys(), key=str.lower):
        ops = by_tag[tag]
        slug = _slug(tag)
        file_name = f"{slug}.md"
        body_lines = [
            f"# {tag}",
            "",
            f"{len(ops)} endpoint(s)",
            "",
            f"[← Back to index](../README.md)",
            "",
        ]
        for method, path, op in sorted(ops, key=lambda x: (x[1], x[0])):
            body_lines.append(render_operation(method, path, op))
        (tags_dir / file_name).write_text("\n".join(body_lines) + "\n", encoding="utf-8")
        index_rows.append((tag, len(ops), file_name))

    # Definitions index (short)
    defs = spec.get("definitions") or {}
    def_lines = [
        "# Definitions",
        "",
        f"{len(defs)} model(s) from swagger `definitions`.",
        "",
        "| Name | Type | Description |",
        "|---|---|---|",
    ]
    for name in sorted(defs.keys()):
        d = defs[name] if isinstance(defs[name], dict) else {}
        typ = d.get("type", "object")
        desc = (d.get("description") or "").replace("\n", " ").strip()
        def_lines.append(f"| `{name}` | {typ} | {desc} |")
    (out_dir / "definitions.md").write_text("\n".join(def_lines) + "\n", encoding="utf-8")

    # README index
    readme = [
        f"# {info.get('title') or 'API Docs'}",
        "",
        info.get("description") or "",
        "",
        f"- **Version:** `{info.get('version', '')}`",
        f"- **Base URL:** `{base_url}`",
        f"- **Swagger:** `{DEFAULT_URL}`",
        f"- **Endpoints:** {sum(n for _, n, _ in index_rows)}",
        f"- **Tags:** {len(index_rows)}",
        f"- **Definitions:** [{len(defs)} models](definitions.md)",
        f"- **Raw spec:** [swagger.json](swagger.json)",
        "",
        "## Tags",
        "",
        "| Tag | Endpoints | Doc |",
        "|---|---:|---|",
    ]
    for tag, count, file_name in index_rows:
        readme.append(f"| {tag} | {count} | [open](tags/{file_name}) |")
    readme.extend(
        [
            "",
            "## Regenerate",
            "",
            "```bash",
            "python3 scripts/fetch_api_docs.py",
            "```",
            "",
        ]
    )
    (out_dir / "README.md").write_text("\n".join(readme) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch MaryAI swagger → api-docs/")
    parser.add_argument("--url", default=DEFAULT_URL, help="Swagger JSON URL")
    parser.add_argument(
        "--out",
        default=DEFAULT_OUT,
        help="Output directory (relative to repo root or absolute)",
    )
    parser.add_argument(
        "--from-file",
        default=None,
        help="Use a local swagger JSON file instead of fetching",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    out_dir = Path(args.out)
    if not out_dir.is_absolute():
        out_dir = repo_root / out_dir

    try:
        if args.from_file:
            src = Path(args.from_file)
            print(f"Loading {src} …")
            spec = json.loads(src.read_text(encoding="utf-8"))
        else:
            print(f"Fetching {args.url} …")
            spec = fetch_swagger(args.url)
    except urllib.error.HTTPError as e:
        print(f"HTTP error: {e.code} {e.reason}", file=sys.stderr)
        return 1
    except urllib.error.URLError as e:
        print(f"Network error: {e.reason}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"Invalid JSON: {e}", file=sys.stderr)
        return 1

    paths = len(spec.get("paths") or {})
    print(f"Loaded swagger {spec.get('swagger') or spec.get('openapi')} — {paths} paths")
    build_docs(spec, out_dir)
    print(f"Wrote docs → {out_dir}")
    print(f"  - {out_dir / 'README.md'}")
    print(f"  - {out_dir / 'swagger.json'}")
    print(f"  - {out_dir / 'tags'}/ ({len(list((out_dir / 'tags').glob('*.md')))} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
