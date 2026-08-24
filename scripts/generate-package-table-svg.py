#!/usr/bin/env python3
"""Generate the package matrix displayed in README.md."""

from __future__ import annotations

import base64
import html
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "assets" / "package-table.svg"


def scalar(lines: list[str], key: str) -> str:
    prefix = f"{key}:"
    for line in lines:
        if line.startswith(prefix):
            value = line[len(prefix) :].strip()
            return value.strip('"\'')
    return ""


def has_top_level_section(lines: list[str], section: str) -> bool:
    return any(line == f"{section}:" for line in lines)


def yes_no(lines: list[str], key: str) -> str:
    value = scalar(lines, key).lower()
    if value in {"yes", "true", "1"}:
        return "yes"
    if value in {"no", "false", "0"}:
        return "no"
    raise ValueError(f"{key} must be yes or no")


def app_template(lines: list[str]) -> Path | None:
    in_app_dist = False
    for line in lines:
        if line == "app_dist:":
            in_app_dist = True
            continue
        if in_app_dist and line and not line.startswith(" "):
            break
        if in_app_dist and line.strip().startswith("template:"):
            return ROOT / line.split(":", 1)[1].strip().strip('"\'')
    return None


def artifact_type(lines: list[str]) -> str:
    in_artifact = False
    for line in lines:
        if line == "artifact:":
            in_artifact = True
            continue
        if in_artifact and line and not line.startswith(" "):
            break
        if in_artifact and line.strip().startswith("type:"):
            return line.split(":", 1)[1].strip().strip('"\'')
    return "app_dist"


def icon_data(package_dir: Path, lines: list[str]) -> str:
    template = app_template(lines)
    if template and template.is_dir():
        icons = sorted(template.rglob("icon.png"))
        if icons:
            encoded = base64.b64encode(icons[0].read_bytes()).decode("ascii")
            return f"data:image/png;base64,{encoded}"
    return ""


def package_rows() -> list[dict[str, str]]:
    tracked = subprocess.check_output(
        ["git", "ls-files", "packages"], cwd=ROOT, text=True
    ).splitlines()
    manifests = sorted(
        ROOT / path
        for path in tracked
        if path.endswith("/package.yml")
    )

    rows = []
    for manifest in manifests:
        lines = manifest.read_text(encoding="utf-8").splitlines()
        package_id = manifest.parent.name
        rows.append(
            {
                "id": html.escape(scalar(lines, "id") or package_id),
                "name": html.escape(scalar(lines, "name") or package_id),
                "kind": {"tool_bundle": "tool bundle", "port": "port"}.get(
                    artifact_type(lines), "app dist"
                ),
                "native": "yes" if has_top_level_section(lines, "host") else "—",
                "modified": yes_no(lines, "modified_source"),
                "icon": icon_data(manifest.parent, lines),
            }
        )
    return rows


def render(rows: list[dict[str, str]]) -> str:
    row_height = 70
    # Reserve space for the title, subtitle, table, and card padding.
    height = 170 + row_height * len(rows)
    rendered_rows = []
    for row in rows:
        icon = (
            f'<img class="icon" src="{row["icon"]}" alt="" />'
            if row["icon"]
            else '<span class="icon empty">—</span>'
        )
        rendered_rows.append(
            f"""<div class="row">
  <div class="identity">{icon}<div><strong>{row["id"]}</strong><span>{row["name"]}</span></div></div>
  <div class="kind">{row["kind"]}</div>
  <div class="native">{row["native"]}</div>
  <div class="modified">{row["modified"]}</div>
</div>"""
        )

    body = "\n".join(rendered_rows)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xhtml="http://www.w3.org/1999/xhtml" width="1100" height="{height}" viewBox="0 0 1100 {height}" role="img" aria-labelledby="title description">
  <title id="title">mm-buildbot package matrix</title>
  <desc id="description">Tracked mm-buildbot packages, native host support, and modified source status</desc>
  <foreignObject width="100%" height="100%">
    <xhtml:div xmlns="http://www.w3.org/1999/xhtml">
      <style>
        * {{ box-sizing: border-box; }}
        .card {{ font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #dbeafe; background: transparent; padding: 22px; width: 1100px; height: {height}px; }}
        h1 {{ font-size: 26px; margin: 0 0 4px; color: #f8fafc; }}
        .subtitle {{ color: #94a3b8; font-size: 14px; margin-bottom: 18px; }}
        .table {{ overflow: hidden; }}
        .row {{ display: grid; grid-template-columns: 1fr 140px 95px 120px; align-items: center; min-height: {row_height}px; }}
        .header {{ min-height: 38px; color: #93c5fd; font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: .08em; }}
        .header > div, .row > div {{ padding: 9px 14px; }}
        .identity {{ display: flex; align-items: center; gap: 12px; min-width: 0; }}
        .identity strong {{ display: block; color: #f8fafc; font-size: 15px; }}
        .identity span:not(.icon) {{ display: block; color: #94a3b8; font-size: 12px; margin-top: 3px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }}
        .icon {{ width: 42px; height: 42px; object-fit: contain; flex: 0 0 42px; border-radius: 8px; }}
        .empty {{ display: flex; align-items: center; justify-content: center; color: #64748b; font-size: 18px; }}
        .kind {{ color: #cbd5e1; font-size: 13px; }}
        .native {{ color: #86efac; font-weight: 700; font-size: 13px; }}
        .modified {{ color: #fcd34d; font-weight: 700; font-size: 13px; }}
        .native:empty {{ color: #64748b; }}
      </style>
      <div class="card">
        <h1>mm-buildbot packages</h1>
        <div class="subtitle">Tracked package recipes · native host support · source modification status</div>
        <div class="table">
          <div class="row header"><div>Package</div><div>Artifact</div><div>Native run</div><div>Modified source</div></div>
          {body}
        </div>
      </div>
    </xhtml:div>
  </foreignObject>
</svg>
'''


def main() -> None:
    rows = package_rows()
    if not rows:
        raise SystemExit("No tracked package manifests found")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(render(rows), encoding="utf-8")
    print(f"Generated {OUTPUT} for {len(rows)} packages")


if __name__ == "__main__":
    main()
