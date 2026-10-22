# UofT Dining Hall Menu — Next-Gen Web Prototype

A fast, minimalist, mobile-first dining hall menu application for University of Toronto dining halls, built with **OCaml**, **Dream**, and **HTMX**.

---

## Features

- **Reverse Engineered API Client**: Directly consumes UofT Food Services Online (FSO) endpoints without legacy DevExpress frontend bloat.
- **1-Click Mobile Navigation**:
  - **All 4 Dining Halls Exposed**: New College, Chestnut, CampusOne, and Oak House in a top segmented toggle bar. Switch dining halls in 1 tap.
  - **1-Click Day Switcher**: `< Prev Day` and `Next Day >` buttons for immediate date traversal.
  - **1-Click Meal Switcher**: Instant switching between Breakfast, Lunch, and Dinner.
- **Allergens Kept Prominent**: High-visibility color-coded badges for allergens (`Egg`, `Milk`, `Wheat/Gluten`, `Soy`, `Peanuts`, etc.) and dietary tags (`Vegetarian`, `Vegan`, `Halal`).
- **Nutritional Info Tucked Away**: Minimalist calorie badge on card, with full macro breakdown (Fat, Carbs, Protein, Sodium, etc.) and ingredient list collapsed behind a clean toggle.
- **Clean URL Architecture**:
  - `/` (Blank path): Minimalist selector with 5 dining hall cards to prevent location confusion.
  - `/<hall>/<date>`: Infers meal and serves the day's menu.
  - `/<hall>/<date>/<meal>`: Direct linkable, shareable URL updated seamlessly with server-rendered navigation.

---

## Project Structure

```
.
├── API_DOCUMENTATION.md    # Reverse engineered API bindings & protocol reference
├── dune-project            # Dune project configuration
├── bin/
│   ├── dune                # Executable build configuration
│   └── main.ml             # Dream server entrypoint and route handlers
├── lib/
│   ├── dune                # Library configuration
│   ├── types.ml            # Core types (Dining halls, meals, dishes, nutrition)
│   ├── api_client.ml       # FSO API reverse engineered client & binary parser
│   └── views.ml            # HTML templates and mobile UI components
└── static/
    ├── style.css           # Mobile-first stylesheet
    ├── htmx.min.js         # HTMX library
    └── uploads/            # Directory for user-taken food photos
```

---

## Photo Binding System

Photos are stored locally in `static/photos/` and mapped via `static/photos/photos.json`:

1. **Adding Your In-Person Food Photos**:
   - Place your photo file (e.g. `pepperoni_slice.jpg`) in `static/photos/`.
   - Add the mapping to `static/photos/photos.json`:
     ```json
     {
       "pepperoni": "pepperoni_slice.jpg",
       "roasted pork with three pepper salsa": "my_pork_entree.jpg"
     }
     ```
2. **Automatic Fallbacks**:
   - If a dish name contains keywords (e.g. "burger", "pizza", "soup", "stir fry", "salad", "cookie", "cake", "entree"), the UI binds to built-in vector illustrations (`static/photos/*.svg`) automatically.
   - You can replace any SVG illustration or map dish names as you take real photos.

## On-Disk Backend Caching

Scraped menu data is persisted to disk under `cache/`:

- `cache/dates/<YYYYMMDD>.json`: Location and meal hierarchy per date.
- `cache/menus/<YYYYMMDD>_<hall>_<meal>.json`: Full dish list, stations, macro nutrients, and allergens.
- `cache/labels/<menu_id>_<line_id>.json`: Cached nutrition facts and ingredients.

Once a day's menu is scraped, subsequent visits load from disk in **&lt; 1ms** with zero network overhead. Rescraping only occurs when a new day/meal is visited for the first time.

### 1. Build and Run

#### Native (Local Development)
```bash
eval $(opam env --switch=default)
dune build
dune exec bin/main.exe
```
The server runs on `http://localhost:8080`.

#### Docker (Production Container)
```bash
docker build -t uoft-dining-menu .
docker run -p 8080:8080 -v menu_cache:/app/cache uoft-dining-menu
```

Or using Docker Compose:
```bash
docker compose up -d
```

#### Deploying to Fly.io
```bash
# 1. (Optional) Create persistent volume for cache in Toronto (yyz) region
fly volumes create menu_cache --region yyz --size 1

# 2. Deploy application
fly deploy
```

### 2. Available Routes

- `http://localhost:8080/` — Dining hall selector (Blank path)
- `http://localhost:8080/new-college/2026-10-20/lunch` — New College Lunch
- `http://localhost:8080/chestnut/2026-10-20/dinner` — Chestnut Dinner
- `http://localhost:8080/campus-one/2026-10-20/lunch` — CampusOne Lunch
- `http://localhost:8080/oak-house/2026-10-20/lunch` — Oak House Lunch

---

## Production Deployment Architecture

Unlike Python/Flask which requires external WSGI application servers (e.g. Gunicorn, uWSGI) to manage worker processes around Python's GIL, **OCaml Dream** is a compiled, asynchronous, event-driven native web server based on `Lwt` and `gluten`/`httpaf`.

- **No Gunicorn/uWSGI needed:** Dream handles HTTP/1.1 and HTTP/2 connections, non-blocking I/O, routing, and high concurrency directly within a single native binary.
- **Minimal memory footprint:** Typically ~20–30 MB RSS memory under load, making a 256MB micro VM (such as Fly.io's shared-cpu-1x) more than sufficient.
- **Non-persistent Cache:** Cached menu JSONs reside in `/app/cache` on the container's ephemeral filesystem for high performance, refreshing naturally upon container redeployments.

---

## TODO

- [x] Verify and double check the reverse engineering. Test how stable the assumptions are.
- [ ] Setup header with about and link to github repo.
- [ ] double check tos to make sure scraping is permissible
- [x] improve warning message
- [x] make top menu tighter and take up lace hight, mostly by restructuring the date selection area.
- [ ] procure all the photos of different food.
- [ ] Create detection for special / nonstandard events (like thanksgiving dinner etc.)
- [x] Set up docker packaging for future deployment to fly.io or railway.
- [x] Move cache to persistent storage so it survives re-deployment
- [ ] Scraper on a chron job that fetches newly published menus once a day
  - [x] check whether menus for future days are finalized or change (added 24h future cache refresh)
- [x] Remove htmx. A fully server side implementation is entirely possible by custom editing all relevant links.



1. Date Traversal Limits:

      • Forward Limit: Exactly +10 to +11 days into the future. Beyond day 11, residential dining halls publish 0 menus (only retail

      cafeterias like MSB, Robarts, and Sidney Smith appear). Our is\_date\_available check correctly disables "Next Day" at this

      exact boundary.

      • Backward Limit: Historical menus are archived at least -365+ days into the past (tested back to October 2025). The only

      historical gaps occur during summer term closures (July/August), where residences serve no meal plans.

  2. Completeness of Pages:

      • When a residential dining hall date is published, menus are 100% complete: 80 to 90 dishes across 7 to 9 stations per meal

      (including dedicated Special Event stations discovered on Thanksgiving).

      • All 12 macro/micronutrient columns and portion sizes (100g, Bowl, Slice) are consistently populated with numeric data.

      • Weekend schemas (Saturday/Sunday) strictly adhere to \['Breakfast', 'Lunch', 'Dinner'\] without "Brunch" variations.

  3. Two Key Vulnerabilities &amp; Open Decisions:

      • Permanent Cache on Future Dates: api\_client.ml:236 currently caches all fetched menus to disk permanently. Because dining

      services regularly update tentative menus 24–48 hours before service, visiting a future date (e.g. +7 days) will lock in

      outdated menus forever. Recommendation: Add a 12-hour TTL for future dates (date &gt; today).

      • Allergen Heuristic Accuracy: Our keyword inference in dietary.ml:7 avoids 85 sequential HTTP requests on page load, but live

      tests against GetLabel confirmed that it misses non-obvious allergens (e.g. Sulphites on the pork entree). Recommendation:

      Maintain the prominent disclaimer banner and consider asynchronous background caching of official GetLabel data. 