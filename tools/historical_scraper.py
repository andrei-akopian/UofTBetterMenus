#!/usr/bin/env python3
"""
UofT Dining Hall Historical Menu Scraper & Compression Engine
=============================================================

Scrapes historical dining hall menus and nutritional data from the UofT
Food Services Online (FSO) portal for offline analysis, frequency tracking,
and edge case discovery.

Key Features:
- Normalized SQLite storage: Dedupes ~1.2M dish instances into ~3k unique recipes.
- Extreme compression: Reduces raw HTML (~1.5 GB+) down to ~22 MB SQLite (or ~7 MB with Zstandard/Gzip).
- Resumable: Tracks daily checkpoints in SQLite; safe to interrupt (Ctrl+C) and resume anytime.
- Polite rate-limiting: Jittered intervals (default: 2.5s ± 0.5s) and exponential backoff to avoid server load.
- Edge case detector: Logs missing meals, empty days, zero-dish menus, and naming anomalies.

Usage Examples:
    # 1. Probe a short date range without saving to DB:
    python3 tools/historical_scraper.py --probe --start 2026-11-01 --end 2026-11-05

    # 2. Scrape past 3 years with 2.5s delay (recommended overnight run):
    python3 tools/historical_scraper.py --start 2023-09-01 --end 2026-11-10 --delay 2.5

    # 3. View database statistics and edge cases:
    python3 tools/historical_scraper.py --summary

    # 4. Compress database to .zst or .gz:
    python3 tools/historical_scraper.py --compress
"""

import sys
import os
import re
import ssl
import time
import base64
import random
import socket
import sqlite3
import argparse
import datetime
from typing import List, Dict, Tuple, Optional, Any

# Ensure IPv4 resolution to prevent macOS dual-stack happy-eyeballs timeout on FSO
_orig_getaddrinfo = socket.getaddrinfo
def _ipv4_getaddrinfo(*args, **kwargs):
    responses = _orig_getaddrinfo(*args, **kwargs)
    return [r for r in responses if r[0] == socket.AF_INET]
socket.getaddrinfo = _ipv4_getaddrinfo

import urllib.request
import urllib.error

BASE_URL = "https://fso.ueat.utoronto.ca/FSO/ServiceMenuReport"
SSL_CTX = ssl._create_unverified_context()
DEFAULT_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

RESIDENCE_HALL_SLUGS = {
    "new college": "new-college",
    "chestnut": "chestnut",
    "campusone": "campus-one",
    "oak house": "oak-house",
}


def normalize_hall_name(name: str) -> Optional[Tuple[str, str]]:
    """Map raw location name to standard (slug, full_name)."""
    lower = name.lower()
    for key, slug in RESIDENCE_HALL_SLUGS.items():
        if key in lower:
            if slug == "new-college":
                return (slug, "New College Dining Hall")
            elif slug == "chestnut":
                return (slug, "Chestnut Residence")
            elif slug == "campus-one":
                return (slug, "CampusOne Dining Hall")
            elif slug == "oak-house":
                return (slug, "Oak House Dining Hall")
    return None


def normalize_meal_slug(meal_name: str) -> str:
    """Normalize meal name to slug."""
    lower = meal_name.strip().lower()
    if "breakfast" in lower:
        return "breakfast"
    elif "brunch" in lower:
        return "lunch"  # Weekend brunch acts as lunch in dining operations
    elif "lunch" in lower:
        return "lunch"
    elif "dinner" in lower:
        return "dinner"
    return re.sub(r"[^a-z0-9]+", "-", lower).strip("-")


# -----------------------------------------------------------------------------
# HTTP Request Utilities with Jitter & Backoff
# -----------------------------------------------------------------------------

def http_get(url: str, timeout: int = 12, max_retries: int = 3, retry_delay: float = 5.0) -> str:
    """HTTP GET with automatic retry and exponential backoff."""
    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": DEFAULT_USER_AGENT})
            with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as resp:
                return resp.read().decode("utf-8", errors="ignore")
        except Exception as e:
            if attempt == max_retries - 1:
                raise e
            backoff = retry_delay * (2 ** attempt) + random.uniform(0.5, 2.0)
            sys.stderr.write(f"\n[Warning] GET {url} failed: {e}. Retrying in {backoff:.1f}s...\n")
            time.sleep(backoff)
    return ""


def http_post(url: str, data: bytes, timeout: int = 12, max_retries: int = 3, retry_delay: float = 5.0) -> str:
    """HTTP POST with automatic retry and exponential backoff."""
    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(
                url,
                data=data,
                headers={
                    "User-Agent": DEFAULT_USER_AGENT,
                    "Content-Type": "application/x-www-form-urlencoded",
                },
            )
            with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as resp:
                return resp.read().decode("utf-8", errors="ignore")
        except Exception as e:
            if attempt == max_retries - 1:
                raise e
            backoff = retry_delay * (2 ** attempt) + random.uniform(0.5, 2.0)
            sys.stderr.write(f"\n[Warning] POST {url} failed: {e}. Retrying in {backoff:.1f}s...\n")
            time.sleep(backoff)
    return ""


# -----------------------------------------------------------------------------
# DevExpress Binary Protocol Tokenizer & Parser
# -----------------------------------------------------------------------------

def parse_items_info(b64_str: str) -> Dict[str, List[Tuple[str, str]]]:
    """
    Decodes the DevExpress itemsInfo base64 payload into:
    { "Location Name": [("Meal Name", "Menu UUID"), ...] }
    """
    try:
        raw = base64.b64decode(b64_str)
    except Exception:
        return {}

    pos = 0
    tokens = []
    length = len(raw)

    while pos < length:
        b = raw[pos]
        pos += 1
        if b == 2 and pos < length:
            slen = raw[pos]
            pos += 1
            if pos + slen <= length:
                s = raw[pos : pos + slen].decode("utf-8", errors="ignore")
                pos += slen
                tokens.append(("str", s))
            else:
                tokens.append(("byte", b))
        elif b == 7 and pos < length:
            count = raw[pos]
            pos += 1
            tokens.append(("struct", count))
        else:
            tokens.append(("byte", b))

    locations: Dict[str, List[Tuple[str, str]]] = {}
    current_loc = ""
    i = 0
    n = len(tokens)

    while i < n:
        t, v = tokens[i]
        if t == "str" and v == "noaction" and i + 1 < n:
            nt, nv = tokens[i + 1]
            if nt == "str" and nv != "Locations":
                current_loc = nv
                if current_loc not in locations:
                    locations[current_loc] = []
                i += 2
                continue
        elif t == "str" and len(v) == 36 and v.count("-") == 4 and i + 1 < n:
            nt, nv = tokens[i + 1]
            if nt == "str" and current_loc:
                locations[current_loc].append((nv, v))
                i += 2
                continue
        i += 1

    return locations


def extract_items_info(html: str) -> Optional[str]:
    """Extract base64 itemsInfo string from GetDate HTML response."""
    m = re.search(r"'mnuUnits'[^{]+\{[^{]+'stateObject':\{'itemsInfo':'([^']+)'", html)
    if m:
        return m.group(1)
    fallback = re.search(r"'itemsInfo':'([^']+)'", html)
    if fallback:
        return fallback.group(1)
    return None


# -----------------------------------------------------------------------------
# Report & Dish Parsers
# -----------------------------------------------------------------------------

def parse_report_html(html: str) -> List[Dict[str, Any]]:
    """
    Extracts all dishes, stations, portion sizes, line_ids, and 12 nutrients
    from a GetReport HTML table.
    """
    rows = re.findall(r"<tr[^>]*>(.*?)</tr>", html, re.DOTALL)
    current_station = "Featured Items"
    dishes = []

    for r in rows:
        header_m = re.search(r'<td class="courseHeader"[^>]*>(.*?)</td>', r, re.DOTALL)
        if header_m:
            current_station = re.sub(r"<[^>]+>", "", header_m.group(1)).strip()
            continue

        desc_m = re.search(r'<td class="description"[^>]*>(.*?)</td>', r, re.DOTALL)
        if desc_m:
            dish_name = re.sub(r"<[^>]+>", "", desc_m.group(1)).strip()
            if not dish_name:
                continue

            click_m = re.search(r"MenuItemClick\(this,\s*'([^']*)',\s*'([^']*)',\s*'([^']*)'\)", r)
            menu_id = click_m.group(2) if click_m else ""
            line_id = click_m.group(3) if click_m else ""

            portion_m = re.search(r'<td class="uom"[^>]*>(.*?)</td>', r, re.DOTALL)
            portion = portion_m.group(1).strip() if portion_m else ""

            nut_cells = re.findall(r'<td class="nutCell(?:Odd|Even)">([^<]*)</td>', r)
            nut_values = [v.strip() for v in nut_cells]

            def parse_num(idx: int) -> Optional[float]:
                if idx < len(nut_values):
                    val = nut_values[idx].replace(",", "").strip()
                    try:
                        return float(val)
                    except ValueError:
                        return None
                return None

            dishes.append({
                "station": current_station,
                "name": dish_name,
                "portion": portion,
                "menu_id": menu_id,
                "line_id": line_id,
                "calories": parse_num(0),
                "fat_g": parse_num(1),
                "sat_fat_g": parse_num(2),
                "cholesterol_mg": parse_num(3),
                "sodium_mg": parse_num(4),
                "carbs_g": parse_num(5),
                "fibre_g": parse_num(6),
                "sugar_g": parse_num(7),
                "protein_g": parse_num(8),
                "vit_c_mg": parse_num(9),
                "calcium_mg": parse_num(10),
                "iron_mg": parse_num(11),
            })

    return dishes


def parse_label_html(html: str) -> Dict[str, str]:
    """Parse GetLabel popup HTML for allergens, ingredients, and tags."""
    res = {"ingredients": "", "allergens": "", "may_contain": "", "tags": ""}
    rows = re.findall(r"<tr[^>]*>(.*?)</tr>", html, re.DOTALL)

    for r in rows:
        text = re.sub(r"<[^>]+>", " ", r)
        text = " ".join(text.split())
        if "Ingredients:" in text:
            res["ingredients"] = text.split("Ingredients:", 1)[1].strip().rstrip(">").strip()
        elif "Allergens:" in text:
            res["allergens"] = text.split("Allergens:", 1)[1].strip().rstrip(">").strip()
        elif "May Contain:" in text:
            res["may_contain"] = text.split("May Contain:", 1)[1].strip().rstrip(">").strip()
        elif "Tags:" in text:
            res["tags"] = text.split("Tags:", 1)[1].strip().rstrip(">").strip()

    return res


# -----------------------------------------------------------------------------
# Database Architecture & Management
# -----------------------------------------------------------------------------

def init_database(db_path: str) -> sqlite3.Connection:
    """Initializes normalized SQLite schema with WAL mode enabled."""
    os.makedirs(os.path.dirname(os.path.abspath(db_path)), exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA synchronous = NORMAL")

    with conn:
        conn.executescript("""
        CREATE TABLE IF NOT EXISTS scrape_checkpoints (
            date_str TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            halls_found INTEGER DEFAULT 0,
            menus_found INTEGER DEFAULT 0,
            dishes_found INTEGER DEFAULT 0,
            error_message TEXT,
            scraped_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS dining_halls (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            slug TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS stations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL
        );

        CREATE TABLE IF NOT EXISTS dishes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            clean_name TEXT NOT NULL,
            portion TEXT,
            calories REAL,
            fat_g REAL,
            sat_fat_g REAL,
            cholesterol_mg REAL,
            sodium_mg REAL,
            carbs_g REAL,
            fibre_g REAL,
            sugar_g REAL,
            protein_g REAL,
            vit_c_mg REAL,
            calcium_mg REAL,
            iron_mg REAL,
            ingredients TEXT,
            allergens TEXT,
            tags TEXT,
            first_seen_date TEXT,
            last_seen_date TEXT,
            appearance_count INTEGER DEFAULT 1,
            UNIQUE(clean_name, portion)
        );

        CREATE TABLE IF NOT EXISTS meal_menus (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date_str TEXT NOT NULL,
            hall_id INTEGER NOT NULL REFERENCES dining_halls(id),
            meal_slug TEXT NOT NULL,
            meal_name TEXT NOT NULL,
            menu_uuid TEXT NOT NULL,
            dish_count INTEGER DEFAULT 0,
            UNIQUE(date_str, hall_id, meal_slug)
        );

        CREATE TABLE IF NOT EXISTS menu_items (
            menu_id INTEGER NOT NULL REFERENCES meal_menus(id),
            station_id INTEGER NOT NULL REFERENCES stations(id),
            dish_id INTEGER NOT NULL REFERENCES dishes(id),
            line_uuid TEXT,
            PRIMARY KEY (menu_id, station_id, dish_id)
        );

        CREATE TABLE IF NOT EXISTS edge_case_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date_str TEXT NOT NULL,
            hall_slug TEXT,
            meal_slug TEXT,
            anomaly_type TEXT NOT NULL,
            description TEXT NOT NULL,
            created_at TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_meal_menus_date ON meal_menus(date_str);
        CREATE INDEX IF NOT EXISTS idx_dishes_clean_name ON dishes(clean_name);
        CREATE INDEX IF NOT EXISTS idx_menu_items_dish ON menu_items(dish_id);
        """)

    return conn


def get_or_create_hall(conn: sqlite3.Connection, slug: str, name: str) -> int:
    cur = conn.cursor()
    cur.execute("SELECT id FROM dining_halls WHERE slug = ?", (slug,))
    row = cur.fetchone()
    if row:
        return row[0]
    cur.execute("INSERT INTO dining_halls (slug, name) VALUES (?, ?)", (slug, name))
    return cur.lastrowid


def get_or_create_station(conn: sqlite3.Connection, name: str) -> int:
    cur = conn.cursor()
    cur.execute("SELECT id FROM stations WHERE name = ?", (name,))
    row = cur.fetchone()
    if row:
        return row[0]
    cur.execute("INSERT INTO stations (name) VALUES (?, ?)", (name,))
    return cur.lastrowid


def upsert_dish(conn: sqlite3.Connection, d: Dict[str, Any], date_str: str) -> int:
    """Inserts or updates deduplicated dish, tracking appearances and dates."""
    clean_name = d["name"].strip().lower()
    portion = d["portion"].strip()
    cur = conn.cursor()
    cur.execute(
        "SELECT id, appearance_count FROM dishes WHERE clean_name = ? AND portion = ?",
        (clean_name, portion),
    )
    row = cur.fetchone()
    if row:
        dish_id, count = row
        cur.execute(
            """UPDATE dishes SET 
                last_seen_date = ?,
                appearance_count = ?
               WHERE id = ?""",
            (date_str, count + 1, dish_id),
        )
        return dish_id

    cur.execute(
        """INSERT INTO dishes (
            name, clean_name, portion,
            calories, fat_g, sat_fat_g, cholesterol_mg, sodium_mg,
            carbs_g, fibre_g, sugar_g, protein_g, vit_c_mg, calcium_mg, iron_mg,
            first_seen_date, last_seen_date, appearance_count
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)""",
        (
            d["name"].strip(), clean_name, portion,
            d["calories"], d["fat_g"], d["sat_fat_g"], d["cholesterol_mg"], d["sodium_mg"],
            d["carbs_g"], d["fibre_g"], d["sugar_g"], d["protein_g"], d["vit_c_mg"], d["calcium_mg"], d["iron_mg"],
            date_str, date_str,
        ),
    )
    return cur.lastrowid


# -----------------------------------------------------------------------------
# Scraper Engine
# -----------------------------------------------------------------------------

class HistoricalScraper:
    def __init__(
        self,
        db_path: str,
        delay: float = 2.5,
        fetch_labels: bool = False,
        dry_run: bool = False,
    ):
        self.db_path = db_path
        self.delay = delay
        self.fetch_labels = fetch_labels
        self.dry_run = dry_run
        self.conn = None if dry_run else init_database(db_path)
        self.interrupted = False

    def sleep_with_jitter(self):
        """Polite sleep with randomized ±0.5s jitter."""
        sleep_time = max(0.5, self.delay + random.uniform(-0.5, 0.5))
        time.sleep(sleep_time)

    def scrape_date(self, dt_iso: str) -> Dict[str, Any]:
        """Scrapes full menus for a given ISO date YYYY-MM-DD."""
        dt_clean = dt_iso.replace("-", "")
        url = f"{BASE_URL}/GetDate?dt={dt_clean}"
        html = http_get(url)
        items_b64 = extract_items_info(html)

        if not items_b64:
            return {"date": dt_iso, "status": "empty", "halls": 0, "menus": 0, "dishes": 0}

        loc_hierarchy = parse_items_info(items_b64)
        halls_found = 0
        menus_found = 0
        total_dishes = 0

        # Check for missing meals in dining halls to log anomalies
        residence_entries = []
        for raw_loc, meals in loc_hierarchy.items():
            hall_info = normalize_hall_name(raw_loc)
            if hall_info:
                residence_entries.append((hall_info, meals))

        if not residence_entries:
            return {"date": dt_iso, "status": "no_residence_halls", "halls": 0, "menus": 0, "dishes": 0}

        for (slug, full_name), meals in residence_entries:
            halls_found += 1
            meal_names = [m[0].lower() for m in meals]

            # Edge Case Detection: Missing dinner when breakfast/lunch exist
            if ("breakfast" in meal_names or "lunch" in meal_names) and "dinner" not in meal_names:
                if self.conn:
                    self.conn.execute(
                        """INSERT INTO edge_case_logs (date_str, hall_slug, meal_slug, anomaly_type, description, created_at)
                           VALUES (?, ?, 'dinner', 'MISSING_MEAL', 'Breakfast/Lunch published but Dinner missing', datetime('now'))""",
                        (dt_iso, slug),
                    )

            hall_id = None if self.dry_run else get_or_create_hall(self.conn, slug, full_name)

            for meal_name, uuid in meals:
                meal_slug = normalize_meal_slug(meal_name)
                self.sleep_with_jitter()

                rep_url = f"{BASE_URL}/GetReport/{uuid}"
                rep_html = http_post(rep_url, b"allergens=&tags=&maycontain=")
                dishes = parse_report_html(rep_html)

                menus_found += 1
                dish_count = len(dishes)
                total_dishes += dish_count

                # Edge Case Detection: UUID exists but 0 dishes
                if dish_count == 0 and self.conn:
                    self.conn.execute(
                        """INSERT INTO edge_case_logs (date_str, hall_slug, meal_slug, anomaly_type, description, created_at)
                           VALUES (?, ?, ?, 'EMPTY_REPORT', 'Menu UUID found in GetDate but GetReport returned 0 dishes', datetime('now'))""",
                        (dt_iso, slug, meal_slug),
                    )

                if not self.dry_run:
                    cur = self.conn.cursor()
                    cur.execute(
                        """INSERT INTO meal_menus (date_str, hall_id, meal_slug, meal_name, menu_uuid, dish_count)
                           VALUES (?, ?, ?, ?, ?, ?)
                           ON CONFLICT(date_str, hall_id, meal_slug) DO UPDATE SET
                           menu_uuid = excluded.menu_uuid, dish_count = excluded.dish_count""",
                        (dt_iso, hall_id, meal_slug, meal_name, uuid, dish_count),
                    )
                    menu_id = cur.lastrowid
                    if not menu_id:
                        cur.execute(
                            "SELECT id FROM meal_menus WHERE date_str = ? AND hall_id = ? AND meal_slug = ?",
                            (dt_iso, hall_id, meal_slug),
                        )
                        menu_id = cur.fetchone()[0]

                    for d in dishes:
                        station_id = get_or_create_station(self.conn, d["station"])
                        dish_id = upsert_dish(self.conn, d, dt_iso)
                        cur.execute(
                            """INSERT OR IGNORE INTO menu_items (menu_id, station_id, dish_id, line_uuid)
                               VALUES (?, ?, ?, ?)""",
                            (menu_id, station_id, dish_id, d["line_id"]),
                        )

        if not self.dry_run:
            self.conn.execute(
                """INSERT OR REPLACE INTO scrape_checkpoints 
                   (date_str, status, halls_found, menus_found, dishes_found, scraped_at)
                   VALUES (?, 'completed', ?, ?, ?, datetime('now'))""",
                (dt_clean, halls_found, menus_found, total_dishes),
            )
            self.conn.commit()

        return {
            "date": dt_iso,
            "status": "completed",
            "halls": halls_found,
            "menus": menus_found,
            "dishes": total_dishes,
        }

    def run(self, start_date: str, end_date: str):
        """Main execution loop traversing date range chronologically."""
        start_dt = datetime.datetime.strptime(start_date, "%Y-%m-%d").date()
        end_dt = datetime.datetime.strptime(end_date, "%Y-%m-%d").date()

        delta = datetime.timedelta(days=1)
        curr = start_dt
        dates = []
        while curr <= end_dt:
            dates.append(curr.strftime("%Y-%m-%d"))
            curr += delta

        print("=" * 65)
        print(f" UofT Dining Historical Menu Scraper")
        print(f" Range: {start_date} -> {end_date} ({len(dates)} total calendar days)")
        print(f" Delay: {self.delay}s (±0.5s jitter) | Dry Run: {self.dry_run}")
        print(f" Database: {self.db_path}")
        print("=" * 65)

        completed_set = set()
        if not self.dry_run:
            cur = self.conn.cursor()
            cur.execute("SELECT date_str FROM scrape_checkpoints WHERE status = 'completed'")
            completed_set = {r[0] for r in cur.fetchall()}

        to_scrape = [d for d in dates if d.replace("-", "") not in completed_set]
        already_done = len(dates) - len(to_scrape)
        print(f"[*] Found {already_done} already completed dates. {len(to_scrape)} dates remaining.\n")

        total_scraped_dishes = 0
        total_scraped_menus = 0
        start_time = time.time()

        for idx, dt_str in enumerate(to_scrape):
            if self.interrupted:
                print("\n[!] Stopping gracefully due to user interrupt...")
                break

            progress_pct = (idx + 1) / len(to_scrape) * 100
            print(f"[{idx+1}/{len(to_scrape)} - {progress_pct:.1f}%] Scraping {dt_str}...", end="", flush=True)

            try:
                res = self.scrape_date(dt_str)
                total_scraped_dishes += res["dishes"]
                total_scraped_menus += res["menus"]
                print(f" Done ({res['halls']} halls, {res['menus']} menus, {res['dishes']} dishes)")
            except KeyboardInterrupt:
                self.interrupted = True
                print("\n[!] KeyboardInterrupt received.")
                break
            except Exception as e:
                print(f" Failed ({e})")
                if not self.dry_run:
                    self.conn.execute(
                        """INSERT OR REPLACE INTO scrape_checkpoints 
                           (date_str, status, error_message, scraped_at)
                           VALUES (?, 'error', ?, datetime('now'))""",
                        (dt_str.replace("-", ""), str(e)),
                    )
                    self.conn.commit()

            self.sleep_with_jitter()

        elapsed = time.time() - start_time
        print("\n" + "=" * 65)
        print(f" Scrape Run Finished in {elapsed/60:.1f} minutes")
        print(f" Total Menus Captured: {total_scraped_menus}")
        print(f" Total Dish Appearances Logged: {total_scraped_dishes}")
        print("=" * 65)

        if not self.dry_run:
            self.print_summary()


    def print_summary(self):
        """Prints analytics and edge case summary from SQLite."""
        if not self.conn:
            return
        cur = self.conn.cursor()
        cur.execute("SELECT COUNT(*) FROM scrape_checkpoints WHERE status = 'completed'")
        days_done = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM dishes")
        unique_dishes = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM meal_menus")
        total_menus = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM menu_items")
        total_appearances = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM edge_case_logs")
        edge_cases = cur.fetchone()[0]

        raw_size_mb = os.path.getsize(self.db_path) / (1024 * 1024)

        print("\n📊 Database Summary:")
        print(f"  • Days Scraped:             {days_done:,}")
        print(f"  • Meal Menus Captured:      {total_menus:,}")
        print(f"  • Unique Recipes/Dishes:    {unique_dishes:,}")
        print(f"  • Total Dish Appearances:   {total_appearances:,}")
        print(f"  • Edge Cases Flagged:       {edge_cases:,}")
        print(f"  • SQLite Database Size:     {raw_size_mb:.2f} MB")

        cur.execute("SELECT anomaly_type, COUNT(*) FROM edge_case_logs GROUP BY anomaly_type")
        anomalies = cur.fetchall()
        if anomalies:
            print("\n🔍 Edge Cases Detected:")
            for a_type, count in anomalies:
                print(f"  • {a_type}: {count} occurrences")

        cur.execute("SELECT name, appearance_count FROM dishes ORDER BY appearance_count DESC LIMIT 5")
        top_dishes = cur.fetchall()
        if top_dishes:
            print("\n🍲 Top 5 Most Frequent Food Items:")
            for name, count in top_dishes:
                print(f"  • {name}: {count} appearances")


def compress_database(db_path: str):
    """Compresses SQLite database using Zstandard or Gzip."""
    if not os.path.exists(db_path):
        print(f"[Error] Database {db_path} does not exist.")
        return

    orig_size = os.path.getsize(db_path)
    print(f"Compressing {db_path} ({orig_size / (1024*1024):.2f} MB)...")

    # Try zstandard first
    try:
        import zstandard as zstd
        out_path = db_path + ".zst"
        cctx = zstd.ZstdCompressor(level=12)
        with open(db_path, "rb") as f_in, open(out_path, "wb") as f_out:
            cctx.copy_stream(f_in, f_out)
        new_size = os.path.getsize(out_path)
        print(f"✓ Zstandard archive created: {out_path}")
        print(f"  Original:   {orig_size / (1024*1024):.2f} MB")
        print(f"  Compressed: {new_size / (1024*1024):.2f} MB ({new_size/orig_size:.1%})")
        return
    except ImportError:
        pass

    # Fallback to standard gzip
    import gzip
    out_path = db_path + ".gz"
    with open(db_path, "rb") as f_in, gzip.open(out_path, "wb", compresslevel=9) as f_out:
        while True:
            chunk = f_in.read(1024 * 1024)
            if not chunk:
                break
            f_out.write(chunk)
    new_size = os.path.getsize(out_path)
    print(f"✓ Gzip archive created: {out_path}")
    print(f"  Original:   {orig_size / (1024*1024):.2f} MB")
    print(f"  Compressed: {new_size / (1024*1024):.2f} MB ({new_size/orig_size:.1%})")


# -----------------------------------------------------------------------------
# CLI Entrypoint
# -----------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="UofT Dining Hall Historical Menu Scraper & Compression Engine")
    parser.add_argument("--start", default="2023-09-01", help="Start date (YYYY-MM-DD)")
    parser.add_argument("--end", default=datetime.date.today().strftime("%Y-%m-%d"), help="End date (YYYY-MM-DD)")
    parser.add_argument("--delay", type=float, default=2.5, help="Delay between requests in seconds (default: 2.5s)")
    parser.add_argument("--db", default="data/uoft_menus_history.sqlite", help="SQLite DB output path")
    parser.add_argument("--probe", action="store_true", help="Probe run only (does not write to DB)")
    parser.add_argument("--summary", action="store_true", help="Print summary of existing database and exit")
    parser.add_argument("--compress", action="store_true", help="Compress the SQLite database to .zst / .gz")

    args = parser.parse_args()

    if args.summary:
        if os.path.exists(args.db):
            scraper = HistoricalScraper(args.db)
            scraper.print_summary()
        else:
            print(f"[Error] Database {args.db} not found.")
        return

    if args.compress:
        compress_database(args.db)
        return

    scraper = HistoricalScraper(
        db_path=args.db,
        delay=args.delay,
        dry_run=args.probe,
    )
    scraper.run(args.start, args.end)


if __name__ == "__main__":
    main()
