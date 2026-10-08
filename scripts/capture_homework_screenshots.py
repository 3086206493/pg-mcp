"""汤豪 · 作业截图采集（DataLens 四库场景）。

Usage:
  python scripts/capture_homework_screenshots.py
"""

from __future__ import annotations

import asyncio
import html
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "screenshots"
OUT.mkdir(exist_ok=True)
BASE_URL = "http://127.0.0.1:8080"


def run_pytest_summary() -> str:
    cmd = [sys.executable, "-m", "pytest", "tests/unit", "tests/integration/test_homework_features.py", "-q", "--tb=no"]
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return (proc.stdout or "") + (proc.stderr or "")


def run_demo_homework() -> str:
    proc = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "demo_homework.py")],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    return (proc.stdout or "") + (proc.stderr or "")


def terminal_html(title: str, body_text: str) -> str:
    escaped = html.escape(body_text)
    return f"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8"/>
<title>{html.escape(title)}</title>
<style>
  body {{ margin:0; background:#0b0f14; font-family:Consolas,monospace; }}
  .bar {{ background:#d97706; color:#1a1208; padding:12px 16px; font-family:"IBM Plex Sans",sans-serif; font-size:14px; font-weight:700; }}
  pre {{ color:#fcd34d; padding:16px; margin:0; white-space:pre-wrap; font-size:13px; line-height:1.45; background:#12100e; }}
</style></head><body>
<div class="bar">{html.escape(title)}</div>
<pre>{escaped}</pre>
</body></html>"""


async def wait_result(page, timeout_ms: int = 180_000) -> None:
    await page.wait_for_function(
        """() => {
          const b = document.getElementById('resultBadge');
          if (!b) return false;
          const t = (b.textContent || '').trim();
          return t !== 'STANDBY' && t !== 'RUNNING' && (b.classList.contains('ok') || b.classList.contains('bad'));
        }""",
        timeout=timeout_ms,
    )
    await page.wait_for_timeout(800)


async def apply_preset_and_run(page, preset_id: str, preset_value: str) -> None:
    await page.select_option(f"#{preset_id}", preset_value)
    await page.wait_for_timeout(400)
    await page.click("#runBtn")
    await wait_result(page)


async def main() -> None:
    try:
        from playwright.async_api import async_playwright
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "playwright", "-q"])
        subprocess.check_call([sys.executable, "-m", "playwright", "install", "chromium"])
        from playwright.async_api import async_playwright

    shots = [
        ("01_web_multi_db_health.png", "OpsQuery · 四库健康检查"),
        ("02_security_ops_query_success.png", "security_ops 告警查询"),
        ("03_saas_crm_query_success.png", "saas_crm_large 组织统计"),
        ("04_audit_logs_rejected.png", "audit_logs 审计表拦截"),
        ("05_hospital_care_query_success.png", "hospital_care 患者统计"),
    ]

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await (await browser.new_context(viewport={"width": 1440, "height": 900}, locale="zh-CN")).new_page()

        print("[1/5] health...")
        await page.goto(BASE_URL, wait_until="networkidle", timeout=60_000)
        await page.wait_for_timeout(1500)
        await page.screenshot(path=str(OUT / shots[0][0]), full_page=True)

        print("[2/5] security_ops...")
        await apply_preset_and_run(page, "presetSecOps", "ops_alerts")
        await page.screenshot(path=str(OUT / shots[1][0]), full_page=True)

        print("[3/5] saas_crm...")
        await apply_preset_and_run(page, "presetCrm", "crm_orgs")
        await page.screenshot(path=str(OUT / shots[2][0]), full_page=True)

        print("[4/5] audit_logs block...")
        await apply_preset_and_run(page, "presetSec", "sec_audit")
        await page.screenshot(path=str(OUT / shots[3][0]), full_page=True)

        print("[5/5] hospital_care...")
        await apply_preset_and_run(page, "presetHosp", "hosp_patients")
        await page.screenshot(path=str(OUT / shots[4][0]), full_page=True)

        print("[bonus] terminal pages...")
        for name, title, text in [
            ("06_pytest_all_passed.png", "汤豪 · 单元测试通过", run_pytest_summary()),
            ("07_demo_homework_security.png", "汤豪 · 规则链安全演示", run_demo_homework()),
        ]:
            html_path = OUT / name.replace(".png", ".html")
            html_path.write_text(terminal_html(title, text), encoding="utf-8")
            tp = await browser.new_page()
            await tp.goto(html_path.as_uri())
            await tp.wait_for_timeout(300)
            await tp.screenshot(path=str(OUT / name), full_page=True)
            await tp.close()

        await browser.close()

    print("\nScreenshots:", OUT)
    for fn, desc in shots:
        print(f"  - {fn}  ({desc})")


if __name__ == "__main__":
    asyncio.run(main())
