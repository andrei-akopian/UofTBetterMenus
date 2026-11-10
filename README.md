# Unofficial UofT Dining Halls Menus

University of Toronto Dining Halls menu website. Information sourced from [Menu Nutritional Information](https://fso.ueat.utoronto.ca/FSO/ServiceMenuReport/Today) and repackaged with a nicer UI.

Frontend implemented with server-side rendering; backend in OCaml and Dream. Built using Gemini-3.8-Flash.

## Development

### Local Development

```bash
eval $(opam env --switch=default)
dune build
dune exec bin/main.exe
```

The server runs on `http://localhost:8080`.

### Docker Build

```bash
docker build -t uoft-dining-menu .
docker run -p 8080:8080 -v menu_cache:/app/cache uoft-dining-menu
```

Or using Docker Compose:

```bash
docker compose up -d
```

## TODO

- [ ] Setup header with about and link to github repo.
- [ ] procure all the photos of different food.

## Scraper

#### 1. Dry-Run / Probe Mode (No DB Writes)
  
Test a specific date range without writing to the database:

python3 tools/historical_scraper.py --probe --start 2026-11-01 --end 2026-11-05

#### 2. Overnight Run (e.g. 3 Years)

Start the overnight scraping run (you can leave it running in a terminal or tmux session):

python3 tools/historical_scraper.py --start 2023-09-01 --end 2026-11-10 --delay 2.5 --db data/uoft_menus_history.sqlite         

(If interrupted, simply rerun the exact same command to resume from where it left off).

#### 3. Inspect Summary & Edge Cases

Check database statistics, top recurring dishes, and logged edge cases:

python3 tools/historical_scraper.py --summary --db data/uoft_menus_history.sqlite

#### 4. Compress Database

Generate the compressed .sqlite.zst or .sqlite.gz archive:

python3 tools/historical_scraper.py --compress --db data/uoft_menus_history.sqlite