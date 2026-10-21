# UofT Dining Hall Menu — Next-Gen Web Prototype

A fast, minimalist, mobile-first dining hall menu application for University of Toronto dining halls, built with **OCaml**, **Dream**, and **HTMX**.

---

## Features

- **Reverse Engineered API Client**: Directly consumes UofT Food Services Online (FSO) endpoints without legacy DevExpress frontend bloat.
- **1-Click Mobile Navigation**:
  - **All 4 Dining Halls Exposed**: New College, Chestnut, CampusOne, and Oak House in a top segmented toggle bar. Switch dining halls in 1 tap.
  - **1-Click Day Switcher**: `< Prev Day` and `Next Day >` buttons for immediate date traversal.
  - **1-Click Meal Switcher**: Instant switching between Breakfast, Lunch, and Dinner.
- **Thoughtful Information Architecture**:
  - **Food Photo Ready**: Dedicated photo slots on dish cards with direct camera upload (`capture="environment"`) to build an in-person photo catalog.
  - **Allergens Kept Prominent**: High-visibility color-coded badges for allergens (`Egg`, `Milk`, `Wheat/Gluten`, `Soy`, `Peanuts`, etc.) and dietary tags (`Vegetarian`, `Vegan`, `Halal`).
  - **Nutritional Info Tucked Away**: Minimalist calorie badge on card, with full macro breakdown (Fat, Carbs, Protein, Sodium, etc.) and ingredient list collapsed behind a clean toggle.
- **Clean URL Architecture**:
  - `/` (Blank path): Minimalist selector with 5 dining hall cards to prevent location confusion.
  - `/<hall>/<date>`: Infers meal and serves the day's menu.
  - `/<hall>/<date>/<meal>`: Direct linkable, shareable URL updated seamlessly with HTMX (`hx-push-url="true"`).
- **Food Occurrence Frequency Tracker**:
  - `/frequency`: Log of dishes tracked across dining halls and dates, architected for future frequency analysis.

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
│   ├── views.ml            # HTML templates, HTMX views, and mobile UI components
│   └── frequency.ml        # Dish occurrence tracker for future analytics
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

Once a day's menu is scraped, subsequent visits load from disk in **< 1ms** with zero network overhead. Rescraping only occurs when a new day/meal is visited for the first time.

### 1. Build and Run
```bash
eval $(opam env --switch=default)
dune build
dune exec bin/main.exe
```

The server runs on `http://localhost:8080`.

### 2. Available Routes
- `http://localhost:8080/` — Dining hall selector (Blank path)
- `http://localhost:8080/new-college/2026-10-20/lunch` — New College Lunch
- `http://localhost:8080/chestnut/2026-10-20/dinner` — Chestnut Dinner
- `http://localhost:8080/campus-one/2026-10-20/lunch` — CampusOne Lunch
- `http://localhost:8080/oak-house/2026-10-20/lunch` — Oak House Lunch
- `http://localhost:8080/frequency` — Food Item Frequency Tracker

---

## TODO

- [ ] Verify and double check the reverse engineering. Test how stable the assumptions are.
- [ ] Create a food frequency analysis page.
- [ ] Setup header with about and link to github repo.
- [ ] double check tos to make sure scraping is permissible
- [x] add a "no responsibilities" warning
- [ ] procure all the photos of different food.
- [ ] Create detection for special / nonstandard events (like thanksgiving dinner etc.)
- [ ] Set up docker packaging for future deployment to fly.io or railway.
- [ ] Move cache to persistent storage so it survives re-deployment
- [ ] Scraper on a chron job that fetches newly published menus once a day
  - [ ] check whether menus for future days are finalized or change
- [x] Remove htmx. A fully server side implementation is entirely possible by custom editing all relevant links.
