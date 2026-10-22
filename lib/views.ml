(** HTML View templates for UofT Dining Menu System *)

let escape_html (s : string) : string =
  let buf = Buffer.create (String.length s) in
  String.iter (function
    | '&' -> Buffer.add_string buf "&amp;"
    | '<' -> Buffer.add_string buf "&lt;"
    | '>' -> Buffer.add_string buf "&gt;"
    | '"' -> Buffer.add_string buf "&quot;"
    | '\'' -> Buffer.add_string buf "&#39;"
    | c -> Buffer.add_char buf c
  ) s;
  Buffer.contents buf

let parse_date_components = Date_utils.parse_date_components
let shift_date = Date_utils.shift_date
let get_today_str = Date_utils.get_today_str
let clean_date = Date_utils.clean_date
let format_date_display = Date_utils.format_date_display

(** Global HTML Page Shell *)
let html_shell ~(title : string) ~(content : string) : string =
  Printf.sprintf {|<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
  <title>%s</title>
  <link rel="stylesheet" href="/static/style.css">
</head>
<body>
  <div id="page-container">
    %s
  </div>
</body>
</html>|} (escape_html title) content

(** Landing page for blank path "/" *)
let render_landing_page ~(today : string) : string =
  let halls_html =
    List.map (fun (h : Types.hall_info) ->
      let link_url = Printf.sprintf "/%s/%s" h.slug today in
      Printf.sprintf {|
        <a href="%s" class="hall-card-button">
          <div>
            <div class="hall-card-name">%s</div>
            <div class="hall-card-address">%s</div>
          </div>
          <div class="hall-card-arrow">›</div>
        </a>
      |} link_url (escape_html h.name) (escape_html h.address)
    ) Types.dining_halls
    |> String.concat "\n"
  in
  let content = Printf.sprintf {|
    <div class="landing-container">
      <div class="landing-hero">
        <h1 class="landing-title">UofT Dining</h1>
        <p class="landing-subtitle">Select your dining hall to view today's fresh menu</p>
      </div>

      <div class="landing-halls-grid">
        %s
      </div>
    </div>
  |} halls_html in
  html_shell ~title:"Select Dining Hall | UofT Menu" ~content

(** Render 1-click Dining Halls Toggle List with all 5 halls *)
let render_halls_nav ~(active_slug : string) ~(date_str : string) ~(meal_slug : string) : string =
  let tabs =
    List.map (fun (h : Types.hall_info) ->
      let is_active = String.equal h.slug active_slug in
      let active_cls = if is_active then "active" else "" in
      let url = Printf.sprintf "/%s/%s/%s" h.slug date_str meal_slug in
      Printf.sprintf {|<a href="%s" class="hall-tab %s">%s</a>|}
        url active_cls (escape_html h.short_name)
    ) Types.dining_halls
  in
  Printf.sprintf {|<nav class="halls-switcher" role="navigation" aria-label="Dining halls">%s</nav>|}
    (String.concat "" tabs)

(** Render Day Switcher with 1-click Forward and Back buttons & accurate Today/Tomorrow indicators.
    Hides buttons if date is outside archive bounds. *)
let render_day_switcher ~(hall_slug : string) ~(date_str : string) ~(meal_slug : string) ?(prev_day_available = true) ?(next_day_available = true) () : string =
  let prev_date = shift_date date_str (-1) in
  let next_date = shift_date date_str 1 in
  let (rel_badge_opt, day_name, day_short, month_name, day_num, year_str) = format_date_display date_str in
  let today = get_today_str () in
  let is_today = clean_date date_str = clean_date today in
  let prev_url = Printf.sprintf "/%s/%s/%s" hall_slug prev_date meal_slug in
  let next_url = Printf.sprintf "/%s/%s/%s" hall_slug next_date meal_slug in
  let today_url = Printf.sprintf "/%s/%s/%s" hall_slug today meal_slug in
  let badge_html =
    match rel_badge_opt with
    | Some "Today" -> {|<span class="badge badge-today">Today</span>|}
    | Some "Tomorrow" -> {|<span class="badge badge-tomorrow">Tomorrow</span>|}
    | Some "Yesterday" -> {|<span class="badge badge-neutral">Yesterday</span>|}
    | Some other -> Printf.sprintf {|<span class="badge badge-neutral">%s</span>|} (escape_html other)
    | None -> ""
  in
  let jump_today_row =
    if not is_today then
      Printf.sprintf {|
        <div class="jump-today-row">
          <a href="%s" class="jump-today-btn">
            ↩ Return to Today
          </a>
        </div>
      |} today_url
    else ""
  in
  let prev_btn_html =
    if prev_day_available then
      Printf.sprintf {|
        <a href="%s" class="day-btn day-btn-prev" aria-label="Previous day">
          <span class="day-btn-arrow" aria-hidden="true">‹</span>
          <span class="day-btn-label">
            <span class="day-btn-text-full">Prev Day</span>
            <span class="day-btn-text-short">Prev</span>
          </span>
        </a>
      |} prev_url
    else
      {|<span class="day-btn-placeholder" aria-hidden="true"></span>|}
  in
  let next_btn_html =
    if next_day_available then
      Printf.sprintf {|
        <a href="%s" class="day-btn day-btn-next" aria-label="Next day">
          <span class="day-btn-label">
            <span class="day-btn-text-full">Next Day</span>
            <span class="day-btn-text-short">Next</span>
          </span>
          <span class="day-btn-arrow" aria-hidden="true">›</span>
        </a>
      |} next_url
    else
      {|<span class="day-btn-placeholder" aria-hidden="true"></span>|}
  in
  Printf.sprintf {|
    <div class="day-switcher-wrapper">
      <div class="day-switcher">
        %s
        <div class="day-indicator">
          <span class="day-main-title">
            <span class="day-name-full">%s</span><span class="day-name-short">%s</span>, %s %d, %s
          </span>
          %s
        </div>
        %s
      </div>
      %s
    </div>
  |} prev_btn_html (escape_html day_name) (escape_html day_short) (escape_html month_name) day_num (escape_html year_str) badge_html next_btn_html jump_today_row

(** Render Meal Switcher with 1-click Breakfast, Lunch, Dinner buttons *)
let render_meal_switcher ~(hall_slug : string) ~(date_str : string) ~(active_meal : string) : string =
  let meals = [ ("breakfast", "Breakfast"); ("lunch", "Lunch"); ("dinner", "Dinner") ] in
  let tabs =
    List.map (fun (slug, label) ->
      let is_active = String.equal slug active_meal in
      let active_cls = if is_active then "active" else "" in
      let url = Printf.sprintf "/%s/%s/%s" hall_slug date_str slug in
      Printf.sprintf {|<a href="%s" class="meal-tab %s">%s</a>|}
        url active_cls label
    ) meals
  in
  Printf.sprintf {|<div class="meal-switcher">%s</div>|} (String.concat "" tabs)

(** Render Photo Slot with bound file / dummy SVG (upload functionality removed) *)
let render_photo_slot (d : Types.dish) : string =
  let photo_url =
    match d.image_url with
    | Some u when u <> "" -> u
    | _ -> Photos.resolve_dish_photo d.name
  in
  Printf.sprintf {|
    <div class="dish-photo-slot">
      <img src="%s" alt="%s" class="dish-thumb" loading="lazy">
    </div>
  |} (escape_html photo_url) (escape_html d.name)

(** Render Allergens and Dietary Tags with explicit estimation note *)
let render_allergens_in_place (d : Types.dish) : string =
  let allergen_badges =
    if d.allergens <> [] then
      [ Printf.sprintf {|<span class="badge badge-allergen" title="Estimated from recipe description — always verify with staff for allergies">⚠️ Est. Contains: %s</span>|} (escape_html (String.concat ", " d.allergens)) ]
    else
      [ {|<span class="badge badge-safe">✓ No common allergens flagged</span>|} ]
  in
  let tag_badges =
    List.map (fun t ->
      let lower = String.lowercase_ascii t in
      let cls =
        if String.contains lower 'v' then "badge-veg"
        else if String.contains lower 'h' then "badge-halal"
        else "badge-neutral"
      in
      let icon =
        if String.starts_with ~prefix:"veg" lower then "🌱"
        else if String.starts_with ~prefix:"hal" lower then "حلال"
        else "🏷️"
      in
      Printf.sprintf {|<span class="badge %s">%s %s</span>|} cls icon (escape_html t)
    ) d.tags
  in
  let all_badges = allergen_badges @ tag_badges in
  Printf.sprintf {|<div class="dish-allergens-row">%s</div>|} (String.concat "" all_badges)

(** Render Collapsible Nutrition and Ingredients Details (Backgrounded) *)
let render_collapsible_nutrition (d : Types.dish) : string =
  match d.nutrition with
  | None -> ""
  | Some n ->
    Printf.sprintf {|
      <details class="dish-details-wrapper">
        <summary class="dish-details-toggle">
          <span>▾ Full Nutrition</span>
        </summary>
        <div class="dish-expanded-details">
          <div class="nutrition-grid">
            <div class="nutrition-cell">
              <div class="nutrition-cell-label">Calories</div>
              <div class="nutrition-cell-val">%s</div>
            </div>
            <div class="nutrition-cell">
              <div class="nutrition-cell-label">Fat</div>
              <div class="nutrition-cell-val">%sg</div>
            </div>
            <div class="nutrition-cell">
              <div class="nutrition-cell-label">Carbs</div>
              <div class="nutrition-cell-val">%sg</div>
            </div>
            <div class="nutrition-cell">
              <div class="nutrition-cell-label">Protein</div>
              <div class="nutrition-cell-val">%sg</div>
            </div>
            <div class="nutrition-cell">
              <div class="nutrition-cell-label">Sodium</div>
              <div class="nutrition-cell-val">%smg</div>
            </div>
            <div class="nutrition-cell">
              <div class="nutrition-cell-label">Sugar</div>
              <div class="nutrition-cell-val">%sg</div>
            </div>
            <div class="nutrition-cell">
              <div class="nutrition-cell-label">Fibre</div>
              <div class="nutrition-cell-val">%sg</div>
            </div>
            <div class="nutrition-cell">
              <div class="nutrition-cell-label">Sat Fat</div>
              <div class="nutrition-cell-val">%sg</div>
            </div>
          </div>
          <div class="buffet-note">Buffet style dining · Nutritional values per standard portion</div>
        </div>
      </details>
    |}
    (escape_html n.calories)
    (escape_html n.fat)
    (escape_html n.carbs)
    (escape_html n.protein)
    (escape_html n.sodium)
    (escape_html n.sugar)
    (escape_html n.fibre)
    (escape_html n.sat_fat)

(** Check if a dish is a zero-cal / build-your-own header item *)
let is_zero_cal_or_byo (d : Types.dish) : bool =
  let lower = String.lowercase_ascii d.name in
  Types.contains_sub lower "create your own" ||
  Types.contains_sub lower "build your own" ||
  Types.contains_sub lower "byo" ||
  Types.contains_sub lower "custom" ||
  (match d.nutrition with
   | Some n -> n.calories = "0" || n.calories = "0.0" || n.calories = "-" || n.calories = ""
   | None -> true)

(** Render a single Dish Card *)
let render_dish_card (d : Types.dish) : string =
  let allergens_html =
    if is_zero_cal_or_byo d then ""
    else render_allergens_in_place d
  in
  Printf.sprintf {|
    <div class="dish-card">
      <div class="dish-card-body">
        %s
        <div class="dish-info">
          <div class="dish-header-row">
            <h3 class="dish-name">%s</h3>
          </div>
          %s
          %s
        </div>
      </div>
    </div>
  |} (render_photo_slot d) (escape_html d.name) allergens_html (render_collapsible_nutrition d)

(** Check if a station is a composite Build-Your-Own station (Pan Station or Foodie Finds) *)
let is_composite_station (sg : Types.station_group) : (Types.dish * Types.dish list) option =
  let lower = String.lowercase_ascii sg.name in
  if (Types.contains_sub lower "pan" || Types.contains_sub lower "foodie" || Types.contains_sub lower "find" || Types.contains_sub lower "wok")
     && List.length sg.dishes > 1 then
    let first = List.hd sg.dishes in
    if is_zero_cal_or_byo first then
      Some (first, List.tl sg.dishes)
    else None
  else None

(** Check if a station is a Salad Stand section *)
let is_salad_station (sg : Types.station_group) : bool =
  let lower = String.lowercase_ascii sg.name in
  Types.contains_sub lower "salad" && not (Types.contains_sub lower "fruit")

(** Check if a station is a Deli Bar / Sandwich section *)
let is_deli_station (sg : Types.station_group) : bool =
  let lower = String.lowercase_ascii sg.name in
  Types.contains_sub lower "deli"

(** Render a 1-line tall table row for an ingredient / salad item with click-to-expand nutrition *)
let render_ingredient_table_row (d : Types.dish) : string =
  let allergen_badges =
    if d.allergens <> [] then
      String.concat " " (List.map (fun a ->
        Printf.sprintf {|<span class="badge badge-allergen">⚠️ %s</span>|} (escape_html a)
      ) d.allergens)
    else
      {|<span class="badge badge-safe">✓ None</span>|}
  in
  let tag_badges =
    if d.tags <> [] then
      " " ^ String.concat " " (List.map (fun t ->
        let lower = String.lowercase_ascii t in
        let cls = if String.contains lower 'v' then "badge-veg" else "badge-halal" in
        let icon = if String.starts_with ~prefix:"veg" lower then "🌱" else "حلال" in
        Printf.sprintf {|<span class="badge %s">%s %s</span>|} cls icon (escape_html t)
      ) d.tags)
    else ""
  in
  let nutrition_details_html =
    match d.nutrition with
    | None ->
      Printf.sprintf {|
        <div class="ingredient-expanded-nutrition">
          <div class="buffet-note" style="padding: 4px 0;">No detailed nutritional breakdown published for this buffet item.</div>
        </div>
      |}
    | Some n ->
      Printf.sprintf {|
        <div class="ingredient-expanded-nutrition">
          <div class="nutrition-grid">
            <div class="nutrition-cell"><div class="nutrition-cell-label">Calories</div><div class="nutrition-cell-val">%s</div></div>
            <div class="nutrition-cell"><div class="nutrition-cell-label">Fat</div><div class="nutrition-cell-val">%sg</div></div>
            <div class="nutrition-cell"><div class="nutrition-cell-label">Carbs</div><div class="nutrition-cell-val">%sg</div></div>
            <div class="nutrition-cell"><div class="nutrition-cell-label">Protein</div><div class="nutrition-cell-val">%sg</div></div>
            <div class="nutrition-cell"><div class="nutrition-cell-label">Sodium</div><div class="nutrition-cell-val">%smg</div></div>
            <div class="nutrition-cell"><div class="nutrition-cell-label">Sugar</div><div class="nutrition-cell-val">%sg</div></div>
            <div class="nutrition-cell"><div class="nutrition-cell-label">Fibre</div><div class="nutrition-cell-val">%sg</div></div>
            <div class="nutrition-cell"><div class="nutrition-cell-label">Sat Fat</div><div class="nutrition-cell-val">%sg</div></div>
          </div>
          <div class="buffet-note">Buffet portion · Click row again to collapse</div>
        </div>
      |}
      (escape_html n.calories) (escape_html n.fat) (escape_html n.carbs) (escape_html n.protein)
      (escape_html n.sodium) (escape_html n.sugar) (escape_html n.fibre) (escape_html n.sat_fat)
  in
  Printf.sprintf {|
    <details class="ingredient-table-row">
      <summary class="ingredient-row-summary">
        <span class="ing-col-name">%s</span>
        <span class="ing-col-allergens">%s%s</span>
        <span class="ing-col-arrow">▾</span>
      </summary>
      %s
    </details>
  |} (escape_html d.name) allergen_badges tag_badges nutrition_details_html

(** Render a table of 1-line tall ingredients / items *)
let render_ingredient_table (dishes : Types.dish list) : string =
  let rows_html = List.map render_ingredient_table_row dishes |> String.concat "\n" in
  Printf.sprintf {|
    <div class="ingredient-table-container">
      <div class="ingredient-table-header">
        <span class="ing-col-name">Ingredient / Option</span>
        <span class="ing-col-allergens">Allergens & Dietary</span>
        <span class="ing-col-arrow"></span>
      </div>
      <div class="ingredient-table-body">
        %s
      </div>
    </div>
  |} rows_html

(** Render Composite Dish Section (Pan Station & Foodie Finds) with 1 Lead Image & 1-line Table of Ingredients *)
let render_composite_station (sg : Types.station_group) (lead_dish : Types.dish) (ingredients : Types.dish list) : string =
  let photo_url =
    match lead_dish.image_url with
    | Some u when u <> "" -> u
    | _ -> Photos.resolve_dish_photo lead_dish.name
  in
  let table_html = render_ingredient_table ingredients in
  Printf.sprintf {|
    <section class="station-section composite-section">
      <div class="station-header">
        <span>%s</span>
        <span class="station-count">%d ingredients</span>
      </div>

      <div class="composite-lead-card">
        <div class="composite-lead-body">
          <div class="dish-photo-slot composite-photo-slot">
            <img src="%s" alt="%s" class="dish-thumb" loading="lazy">
          </div>
          <div class="composite-lead-info">
            <span class="composite-badge">Custom Bowl / Dish</span>
            <h3 class="composite-lead-title">%s</h3>
            <p class="composite-lead-subtitle">Single dish with customizable ingredients. Tap any ingredient row below to view full nutrition:</p>
          </div>
        </div>
      </div>

      %s
    </section>
  |} (escape_html sg.name) (List.length ingredients)
    (escape_html photo_url) (escape_html lead_dish.name)
    (escape_html lead_dish.name)
    table_html

(** Render Salad Stand Section with a Single Picture Spot & 1-line Table of Salad Items *)
let render_salad_station (sg : Types.station_group) : string =
  let salad_photo_url = "/static/photos/salad.svg" in
  let table_html = render_ingredient_table sg.dishes in
  Printf.sprintf {|
    <section class="station-section salad-section">
      <div class="station-header">
        <span>%s</span>
        <span class="station-count">%d items</span>
      </div>

      <div class="composite-lead-card salad-lead-card">
        <div class="composite-lead-body">
          <div class="dish-photo-slot composite-photo-slot">
            <img src="%s" alt="Salad Stand" class="dish-thumb" loading="lazy">
          </div>
          <div class="composite-lead-info">
            <span class="composite-badge">Fresh Salad Stand</span>
            <h3 class="composite-lead-title">Salad Bar & Dressings</h3>
            <p class="composite-lead-subtitle">Full selection of fresh greens, vegetables, seeds, cheeses, and dressings. Tap any row to view full nutrition:</p>
          </div>
        </div>
      </div>

      %s
    </section>
  |} (escape_html sg.name) (List.length sg.dishes)
    salad_photo_url
    table_html

(** Render Deli Bar Section with a Single Picture Spot & 1-line Table of Deli Items *)
let render_deli_station (sg : Types.station_group) : string =
  let deli_photo_url = "/static/photos/egg_salad.svg" in
  let table_html = render_ingredient_table sg.dishes in
  Printf.sprintf {|
    <section class="station-section deli-section">
      <div class="station-header">
        <span>%s</span>
        <span class="station-count">%d items</span>
      </div>

      <div class="composite-lead-card deli-lead-card">
        <div class="composite-lead-body">
          <div class="dish-photo-slot composite-photo-slot">
            <img src="%s" alt="Deli Bar" class="dish-thumb" loading="lazy">
          </div>
          <div class="composite-lead-info">
            <span class="composite-badge">Fresh Deli Counter</span>
            <h3 class="composite-lead-title">Deli Bar & Sandwiches</h3>
            <p class="composite-lead-subtitle">Full selection of deli meats, sandwich fillings, cheeses, toppings, and condiments. Tap any row to view full nutrition:</p>
          </div>
        </div>
      </div>

      %s
    </section>
  |} (escape_html sg.name) (List.length sg.dishes)
    deli_photo_url
    table_html

(** Render complete Main Menu Page for a hall, date, and meal *)
let render_main_menu ~(menu : Types.meal_menu) ~(active_hall : Types.hall_info) ?(prev_day_available = true) ?(next_day_available = true) () : string =
  let header_html = Printf.sprintf {|
    <header class="app-header">
      %s
      %s
      %s
    </header>
  |}
    (render_halls_nav ~active_slug:menu.hall_slug ~date_str:menu.date_str ~meal_slug:menu.meal_slug)
    (render_day_switcher ~hall_slug:menu.hall_slug ~date_str:menu.date_str ~meal_slug:menu.meal_slug ~prev_day_available ~next_day_available ())
    (render_meal_switcher ~hall_slug:menu.hall_slug ~date_str:menu.date_str ~active_meal:menu.meal_slug)
  in
  let disclaimer_html = {|
    <div class="disclaimer-banner allergen-warning-banner">
      <span class="disclaimer-icon">⚠️</span>
      <div class="disclaimer-text">
        <strong>Allergen &amp; Dietary Notice:</strong> Allergen tags on dish cards are <em>estimated from food names</em> and do not account for cross-contact, prep changes, or hidden allergens (e.g. sulphites, trace nuts, sesame).
        Always verify with dining hall staff if you have severe allergies. Review the
        <a href="https://fso.ueat.utoronto.ca/FSO/ServiceMenuReport" target="_blank" rel="noopener noreferrer">official UofT menu labels</a>.
      </div>
    </div>
  |} in
  let is_summer =
    let (_, m, _) = Date_utils.parse_date_components menu.date_str in
    m >= 5 && m <= 8
  in
  let stations_html =
    if menu.stations = [] then
      if is_summer then
        Printf.sprintf {|
          <div class="empty-notice summer-notice" style="margin-top: 24px;">
            <div style="font-size: 2.2rem; margin-bottom: 8px;">☀️</div>
            <h3 style="font-size: 1.15rem; font-weight: 700;">Summer Term — Dining Hall Inactive</h3>
            <p style="margin-top: 6px; font-size: 0.85rem; max-width: 440px; margin-left: auto; margin-right: auto; line-height: 1.45;">
              %s pauses regular residence dining plan operations during the summer term (May to August).
            </p>
            <p style="margin-top: 14px;">
              <a href="/%s/%s" class="jump-today-btn" style="display:inline-flex; padding: 6px 14px;">View Today's Active Menu</a>
            </p>
          </div>
        |} (escape_html active_hall.name) menu.hall_slug (get_today_str ())
      else if not (Date_utils.is_date_in_allowed_range menu.date_str) then
        Printf.sprintf {|
          <div class="empty-notice" style="margin-top: 24px;">
            <div style="font-size: 2.2rem; margin-bottom: 8px;">📅</div>
            <h3 style="font-size: 1.15rem; font-weight: 700;">Date Outside Archive Bounds</h3>
            <p style="margin-top: 6px; font-size: 0.85rem; max-width: 440px; margin-left: auto; margin-right: auto; line-height: 1.45;">
              To protect university services, online menu lookups are limited to the past 14 days and upcoming 14 days.
            </p>
            <p style="margin-top: 14px;">
              <a href="/%s/%s" class="jump-today-btn" style="display:inline-flex; padding: 6px 14px;">View Today's Active Menu</a>
            </p>
          </div>
        |} menu.hall_slug (get_today_str ())
      else
        Printf.sprintf {|
          <div class="empty-notice" style="margin-top: 24px;">
            <h3>No Menu Scheduled</h3>
            <p style="margin-top: 6px; font-size: 0.85rem;">No published meal items found for %s on this date.</p>
            <p style="margin-top: 12px;">
              <a href="/%s/%s" class="jump-today-btn" style="display:inline-flex; padding: 6px 14px;">View Today's Menu</a>
            </p>
          </div>
        |} (escape_html menu.meal_name) menu.hall_slug (get_today_str ())
    else
      List.map (fun (sg : Types.station_group) ->
        if is_salad_station sg then
          render_salad_station sg
        else if is_deli_station sg then
          render_deli_station sg
        else
          match is_composite_station sg with
          | Some (lead_dish, ingredients) ->
            render_composite_station sg lead_dish ingredients
          | None ->
            let dishes_cards = List.map render_dish_card sg.dishes |> String.concat "\n" in
            Printf.sprintf {|
              <section class="station-section">
                <div class="station-header">
                  <span>%s</span>
                  <span class="station-count">%d items</span>
                </div>
                <div class="dishes-grid">
                  %s
                </div>
              </section>
            |} (escape_html sg.name) (List.length sg.dishes) dishes_cards
      ) menu.stations
      |> String.concat "\n"
  in
  let body_content = Printf.sprintf {|
    %s
    <main class="main-content">
      %s
      %s
    </main>
  |} header_html disclaimer_html stations_html in
  let title = Printf.sprintf "%s %s Menu | %s" active_hall.short_name menu.meal_name menu.date_str in
  html_shell ~title ~content:body_content

(** Render custom 404 / 503 fallback and error pages *)
let render_error_page
    ~(title : string)
    ~(icon : string)
    ~(heading : string)
    ~(message : string)
    ?(primary_link = ("/", "Browse All Dining Halls"))
    ?(secondary_link : (string * string) option = None)
    () : string =
  let sec_html =
    match secondary_link with
    | Some (url, label) ->
      Printf.sprintf {|<a href="%s" class="btn-secondary">%s</a>|} url (escape_html label)
    | None -> ""
  in
  let content = Printf.sprintf {|
    <div class="error-page-container">
      <div class="error-page-icon">%s</div>
      <h1 class="error-page-title">%s</h1>
      <p class="error-page-message">%s</p>
      <div class="error-page-actions">
        <a href="%s" class="btn-primary">%s</a>
        %s
        <a href="https://fso.ueat.utoronto.ca/FSO/ServiceMenuReport" target="_blank" rel="noopener noreferrer" class="error-page-fso-link">
          Visit Official UofT Food Services Portal ↗
        </a>
      </div>
    </div>
  |} icon (escape_html heading) (escape_html message) (fst primary_link) (escape_html (snd primary_link)) sec_html in
  html_shell ~title ~content
