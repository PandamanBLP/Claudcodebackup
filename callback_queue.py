"""
Build a callback queue from the latest Jobber Quotes_Report CSV in Downloads.

Picks up the newest Quotes_Report_*.csv automatically, filters to live quotes
(Awaiting response / Changes requested), tiers by viewed-state and age, and
writes the queue to Downloads/callback-queue.csv.

PII goes to Downloads (not synced to GitHub). This script lives in the
ClaudeCode folder and contains no customer data.
"""

from __future__ import annotations

import csv
import glob
import sys
from datetime import date, datetime
from pathlib import Path

DOWNLOADS = Path.home() / "Downloads"
INPUT_GLOB = str(DOWNLOADS / "Quotes_Report_*.csv")
OUTPUT_CSV = DOWNLOADS / "callback-queue.csv"

LIVE_STATUSES = {"Awaiting response", "Changes requested"}
DATE_FMT = "%b %d, %Y"  # "Apr 25, 2026"


def newest_export() -> Path:
    matches = glob.glob(INPUT_GLOB)
    if not matches:
        sys.exit(f"No Quotes_Report_*.csv found in {DOWNLOADS}")
    return Path(max(matches, key=lambda p: Path(p).stat().st_mtime))


def parse_date(s: str) -> date | None:
    if not s or s == "-":
        return None
    try:
        return datetime.strptime(s, DATE_FMT).date()
    except ValueError:
        return None


def tier(viewed: bool, days_since_sent: int | None) -> str:
    if days_since_sent is None:
        return "Z-unknown"
    if not viewed:
        if days_since_sent <= 7:
            return "A-hot-unviewed"
        if days_since_sent <= 30:
            return "B-warm-unviewed"
        return "C-cold-unviewed"
    if days_since_sent <= 14:
        return "D-viewed-silent"
    return "E-viewed-stale"


def build_rows(src: Path, today: date) -> list[dict]:
    out = []
    with src.open(encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            if r["Status"] not in LIVE_STATUSES:
                continue
            sent_date = parse_date(r["Sent date"])
            days = (today - sent_date).days if sent_date else None
            viewed = r["Viewed in client hub"] not in ("", "-")
            out.append(
                {
                    "Tier": tier(viewed, days),
                    "Quote #": r["Quote #"],
                    "Client name": r["Client name"],
                    "Phone": r["Client phone"],
                    "Email": r["Client email"],
                    "Title": r["Title"],
                    "Total": r["Total ($)"],
                    "Sent date": r["Sent date"],
                    "Days since sent": days if days is not None else "",
                    "Status": r["Status"],
                    "Viewed": "yes" if viewed else "no",
                    "Lead source": r["Lead source"],
                    "Salesperson": r["Salesperson"],
                }
            )
    out.sort(key=lambda r: (r["Tier"], r["Days since sent"] if r["Days since sent"] != "" else 9999))
    return out


def write_queue(rows: list[dict], dst: Path) -> None:
    with dst.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else [])
        if rows:
            w.writeheader()
            w.writerows(rows)


def summarize(rows: list[dict], src: Path, src_age_hours: float) -> str:
    from collections import Counter
    tiers = Counter(r["Tier"] for r in rows)
    lines = [
        f"Source: {src.name}  (age: {src_age_hours:.1f}h)",
        f"Total live quotes: {len(rows)}",
        "",
        "Tier breakdown:",
    ]
    labels = {
        "A-hot-unviewed": "A  Hot - unviewed, <=7d (re-text now)",
        "B-warm-unviewed": "B  Warm - unviewed, 8-30d (re-send)",
        "C-cold-unviewed": "C  Cold - unviewed, 30+d (long-shot)",
        "D-viewed-silent": "D  Viewed, silent <=14d (any questions?)",
        "E-viewed-stale": "E  Viewed, silent 15+d (final check)",
        "Z-unknown": "Z  Unknown sent date",
    }
    for key, label in labels.items():
        if tiers.get(key):
            lines.append(f"  {label}: {tiers[key]}")
    if src_age_hours > 36:
        lines.append("")
        lines.append("WARNING: export is >36h old — re-run the Jobber report for fresh data.")
    return "\n".join(lines)


def main() -> None:
    src = newest_export()
    src_age_hours = (datetime.now().timestamp() - src.stat().st_mtime) / 3600
    today = date.today()
    rows = build_rows(src, today)
    write_queue(rows, OUTPUT_CSV)
    print(summarize(rows, src, src_age_hours))
    print(f"\nWrote {len(rows)} rows to {OUTPUT_CSV}")


if __name__ == "__main__":
    main()
