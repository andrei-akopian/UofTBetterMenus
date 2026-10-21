(** API Client with Persistent On-Disk Caching for UofT Dining Menu System *)

open Lwt.Infix

let base_url = "https://fso.ueat.utoronto.ca/FSO/ServiceMenuReport"

let cache_root = "cache"
let cache_dates_dir = Filename.concat cache_root "dates"
let cache_menus_dir = Filename.concat cache_root "menus"
let cache_labels_dir = Filename.concat cache_root "labels"

(** Ensure on-disk cache directories exist *)
let ensure_cache_dirs () : unit =
  let make_dir d =
    if not (Sys.file_exists d) then
      try Unix.mkdir d 0o755 with _ -> ()
  in
  make_dir cache_root;
  make_dir cache_dates_dir;
  make_dir cache_menus_dir;
  make_dir cache_labels_dir

let () = ensure_cache_dirs ()

(** In-memory caches for fast sub-millisecond retrieval *)
let menu_memory_cache : (string, Types.meal_menu) Hashtbl.t = Hashtbl.create 100
let label_memory_cache : (string, Types.dish_label) Hashtbl.t = Hashtbl.create 500
let date_units_memory_cache : (string, (string * (string * string) list) list) Hashtbl.t = Hashtbl.create 30

(** Low-level HTTP GET using curl *)
let http_get (url : string) : string Lwt.t =
  let cmd = ("", [| "curl"; "-s"; "-L"; "--max-time"; "8"; url |]) in
  Lwt_process.pread cmd

(** Low-level HTTP POST using curl *)
let http_post (url : string) (form_data : string) : string Lwt.t =
  let cmd = ("", [| "curl"; "-s"; "-L"; "--max-time"; "8"; "-X"; "POST"; "-d"; form_data; url |]) in
  Lwt_process.pread cmd

(** Disk Cache Path Helpers *)
let disk_menu_path ~(hall_slug : string) ~(date_str : string) ~(meal_slug : string) : string =
  let clean_date = String.concat "" (String.split_on_char '-' date_str) in
  Filename.concat cache_menus_dir (Printf.sprintf "%s_%s_%s.json" clean_date hall_slug meal_slug)

let disk_date_path (date_str : string) : string =
  let clean_date = String.concat "" (String.split_on_char '-' date_str) in
  Filename.concat cache_dates_dir (Printf.sprintf "%s.json" clean_date)

let disk_label_path ~(menu_id : string) ~(line_id : string) : string =
  Filename.concat cache_labels_dir (Printf.sprintf "%s_%s.json" menu_id line_id)

(** Fetch date hierarchy with persistent disk caching *)
let fetch_date_hierarchy (date_str_raw : string) : (string * (string * string) list) list Lwt.t =
  let clean_date = String.concat "" (String.split_on_char '-' date_str_raw) in
  match Hashtbl.find_opt date_units_memory_cache clean_date with
  | Some h -> Lwt.return h
  | None ->
    let disk_file = disk_date_path clean_date in
    if Sys.file_exists disk_file then (
      try
        let json = Yojson.Safe.from_file disk_file in
        let h = Devexpress.hierarchy_of_yojson json in
        Hashtbl.replace date_units_memory_cache clean_date h;
        Lwt.return h
      with _ -> Lwt.return []
    ) else (
      let url = Printf.sprintf "%s/GetDate?dt=%s" base_url clean_date in
      http_get url >>= fun html ->
      match Devexpress.extract_items_info_from_html html with
      | Some b64 ->
        let tokens = Devexpress.tokenize_items_info b64 in
        let hierarchy = Devexpress.parse_location_hierarchy tokens in
        Hashtbl.replace date_units_memory_cache clean_date hierarchy;
        (try
          let j = Devexpress.hierarchy_to_yojson hierarchy in
          Yojson.Safe.to_file disk_file j
        with _ -> ());
        Lwt.return hierarchy
      | None ->
        Lwt.return []
    )

let clean_badge_text (s : string) : string =
  let trimmed = String.trim s in
  if String.ends_with ~suffix:">" trimmed then
    String.trim (String.sub trimmed 0 (String.length trimmed - 1))
  else trimmed

(** Parse GetLabel HTML into Types.dish_label *)
let parse_label_html (html : string) : Types.dish_label =
  let soup = Soup.parse html in
  let tr_nodes = Soup.select "table.nutLabel tr" soup |> Soup.to_list in
  let ingredients = ref "" in
  let allergens = ref [] in
  let may_contain = ref [] in
  let tags = ref [] in
  List.iter (fun tr ->
    let text = Soup.trimmed_texts tr |> String.concat " " in
    if String.starts_with ~prefix:"Ingredients:" text then
      ingredients := clean_badge_text (String.sub text 12 (String.length text - 12))
    else if String.starts_with ~prefix:"Allergens:" text then
      let raw_allergens = clean_badge_text (String.sub text 10 (String.length text - 10)) in
      let splitted = String.split_on_char ',' raw_allergens |> List.map clean_badge_text in
      allergens := List.filter (fun s -> s <> "" && s <> "None" && s <> "none") splitted
    else if String.starts_with ~prefix:"May Contain:" text then
      let raw_mc = clean_badge_text (String.sub text 12 (String.length text - 12)) in
      let splitted = String.split_on_char ',' raw_mc |> List.map clean_badge_text in
      may_contain := List.filter (fun s -> s <> "" && s <> "None" && s <> "none") splitted
    else if String.starts_with ~prefix:"Tags:" text then
      let raw_tags = clean_badge_text (String.sub text 5 (String.length text - 5)) in
      let splitted = String.split_on_char ',' raw_tags |> List.map clean_badge_text in
      tags := List.filter (fun s -> s <> "" && s <> "None" && s <> "none") splitted
  ) tr_nodes;
  {
    Types.ingredients = !ingredients;
    allergens = !allergens;
    may_contain = !may_contain;
    tags = !tags;
  }

(** Fetch dish label with persistent disk caching *)
let fetch_dish_label ~(menu_id : string) ~(line_id : string) : Types.dish_label Lwt.t =
  let mem_key = Printf.sprintf "%s:%s" menu_id line_id in
  match Hashtbl.find_opt label_memory_cache mem_key with
  | Some lbl -> Lwt.return lbl
  | None ->
    let disk_file = disk_label_path ~menu_id ~line_id in
    if Sys.file_exists disk_file then (
      try
        let json = Yojson.Safe.from_file disk_file in
        match Types.dish_label_of_yojson json with
        | Some lbl ->
          Hashtbl.replace label_memory_cache mem_key lbl;
          Lwt.return lbl
        | None -> Lwt.return { Types.ingredients = ""; allergens = []; may_contain = []; tags = [] }
      with _ -> Lwt.return { Types.ingredients = ""; allergens = []; may_contain = []; tags = [] }
    ) else (
      let url = Printf.sprintf "%s/GetLabel/%s/%s" base_url menu_id line_id in
      http_post url "allergens=&tags=&maycontain=" >>= fun html ->
      let label = parse_label_html html in
      Hashtbl.replace label_memory_cache mem_key label;
      (try
        let j = Types.dish_label_to_yojson label in
        Yojson.Safe.to_file disk_file j
      with _ -> ());
      Lwt.return label
    )

(** Parse GetReport HTML string into station_group list sorted by station priority *)
let parse_report_html (html : string) : Types.station_group list =
  let soup = Soup.parse html in
  let tr_nodes = Soup.select "table tr" soup |> Soup.to_list in
  let groups = ref [] in
  let current_station = ref "Featured Items" in
  let current_dishes = ref [] in
  let flush_station () =
    if !current_dishes <> [] then (
      groups := { Types.name = !current_station; dishes = List.rev !current_dishes } :: !groups;
      current_dishes := []
    )
  in
  List.iter (fun tr ->
    match Soup.select_one "td.courseHeader" tr with
    | Some header_td ->
      flush_station ();
      current_station := String.trim (Soup.trimmed_texts header_td |> String.concat " ")
    | None ->
      (match Soup.select_one "td.description" tr with
      | Some desc_td ->
        let dish_name = String.trim (Soup.trimmed_texts desc_td |> String.concat " ") in
        let onclick = Soup.attribute "onclick" desc_td |> Option.value ~default:"" in
        let pattern = Re.Perl.compile_pat "MenuItemClick\\(this,\\s*'([^']*)',\\s*'([^']*)',\\s*'([^']*)'\\)" in
        let menu_id, line_id =
          match Re.exec_opt pattern onclick with
          | Some g -> (Re.Group.get g 2, Re.Group.get g 3)
          | None -> ("", "")
        in
        let portion =
          match Soup.select_one "td.uom" tr with
          | Some u -> String.trim (Soup.trimmed_texts u |> String.concat " ")
          | None -> ""
        in
        let nut_cells = Soup.select "td[class*='nutCell']" tr |> Soup.to_list in
        let nut_values = List.map (fun td -> String.trim (Soup.trimmed_texts td |> String.concat " ")) nut_cells in
        let get_val idx =
          if idx < List.length nut_values then List.nth nut_values idx else "-"
        in
        let nut_info =
          if List.length nut_values >= 5 then
            Some {
              Types.serving = portion;
              calories = get_val 0;
              fat = get_val 1;
              sat_fat = get_val 2;
              cholesterol = get_val 3;
              sodium = get_val 4;
              carbs = get_val 5;
              fibre = get_val 6;
              sugar = get_val 7;
              protein = get_val 8;
              vit_c = get_val 9;
              calcium = get_val 10;
              iron = get_val 11;
            }
          else None
        in
        if dish_name <> "" then (
          let inferred_al, inferred_tg = Dietary.infer_allergens_and_tags dish_name in
          let img = Photos.resolve_dish_photo dish_name in
          let dish = {
            Types.name = dish_name;
            menu_id;
            line_id;
            portion;
            station = !current_station;
            nutrition = nut_info;
            allergens = inferred_al;
            tags = inferred_tg;
            image_url = Some img;
          } in
          current_dishes := dish :: !current_dishes
        )
      | None -> ())
  ) tr_nodes;
  flush_station ();
  let raw_groups = List.rev !groups in
  (* Sort station groups by priority: Entrees/Pan first, Grill/Deli/Salad/Dessert bottom *)
  List.sort (fun (a : Types.station_group) (b : Types.station_group) ->
    compare (Types.station_priority a.name) (Types.station_priority b.name)
  ) raw_groups

(** Find Menu UUID for a given hall and meal on a date *)
let find_menu_uuid ~(date_str : string) ~(hall_slug : string) ~(meal_slug : string) : (string * string) option Lwt.t =
  fetch_date_hierarchy date_str >>= fun hierarchy ->
  let target_hall_opt = Types.find_hall_by_slug hall_slug in
  let hall_name =
    match target_hall_opt with
    | Some h -> h.name
    | None -> hall_slug
  in
  let target_meal_name = Types.meal_name_of_slug meal_slug in
  let matched_entry =
    List.find_opt (fun (loc_name, _) ->
      let l1 = String.lowercase_ascii loc_name in
      let l2 = String.lowercase_ascii hall_name in
      let l3 = String.lowercase_ascii hall_slug in
      String.equal l1 l2 ||
      (match target_hall_opt with
       | Some h -> String.equal (String.lowercase_ascii h.short_name) l1 || String.starts_with ~prefix:(String.lowercase_ascii h.short_name) l1
       | None -> false) ||
      String.starts_with ~prefix:l3 l1
    ) hierarchy
  in
  match matched_entry with
  | None -> Lwt.return None
  | Some (_, meals) ->
    let meal_match =
      List.find_opt (fun (m_name, _) ->
        String.equal (String.lowercase_ascii m_name) (String.lowercase_ascii target_meal_name) ||
        Types.meal_slug_of_name m_name = meal_slug
      ) meals
    in
    match meal_match with
    | Some (m_name, uuid) -> Lwt.return (Some (m_name, uuid))
    | None ->
      (match meals with
       | (m_name, uuid) :: _ -> Lwt.return (Some (m_name, uuid))
       | [] -> Lwt.return None)

(** Check if a dining hall has published meals/menu for a given date *)
let is_date_available ~(hall_slug : string) ~(date_str : string) : bool Lwt.t =
  let clean_date = String.concat "" (String.split_on_char '-' date_str) in
  if String.length clean_date <> 8 then Lwt.return false
  else
    fetch_date_hierarchy date_str >>= fun hierarchy ->
    if hierarchy = [] then Lwt.return false
    else
      let target_hall_opt = Types.find_hall_by_slug hall_slug in
      let hall_name =
        match target_hall_opt with
        | Some h -> h.name
        | None -> hall_slug
      in
      let has_hall =
        List.exists (fun (loc_name, meals) ->
          let l1 = String.lowercase_ascii loc_name in
          let l2 = String.lowercase_ascii hall_name in
          let l3 = String.lowercase_ascii hall_slug in
          (String.equal l1 l2 ||
           (match target_hall_opt with
            | Some h ->
              String.equal (String.lowercase_ascii h.short_name) l1 ||
              String.starts_with ~prefix:(String.lowercase_ascii h.short_name) l1
            | None -> false) ||
           String.starts_with ~prefix:l3 l1)
          && meals <> []
        ) hierarchy
      in
      Lwt.return has_hall

(** Fetch full meal menu with PERSISTENT DISK CACHING.
    If cached on disk, loads in < 1ms with NO network requests.
    Only scrapes when a new day/meal is not on disk!
*)
let fetch_meal_menu ~(hall_slug : string) ~(date_str : string) ~(meal_slug : string) : Types.meal_menu Lwt.t =
  let mem_key = Printf.sprintf "%s:%s:%s" date_str hall_slug meal_slug in
  match Hashtbl.find_opt menu_memory_cache mem_key with
  | Some m -> Lwt.return m
  | None ->
    let disk_file = disk_menu_path ~hall_slug ~date_str ~meal_slug in
    if Sys.file_exists disk_file then (
      try
        let json = Yojson.Safe.from_file disk_file in
        match Types.meal_menu_of_yojson json with
        | Some m ->
          (* Re-sort stations in case priority function updated *)
          let sorted_stations =
            List.sort (fun (a : Types.station_group) (b : Types.station_group) ->
              compare (Types.station_priority a.name) (Types.station_priority b.name)
            ) m.stations
          in
          let menu = { m with stations = sorted_stations } in
          Hashtbl.replace menu_memory_cache mem_key menu;
          List.iter (fun (sg : Types.station_group) ->
            Frequency.record_dishes ~hall:hall_slug ~date:date_str sg.dishes
          ) sorted_stations;
          Lwt.return menu
        | None -> Lwt.fail (Failure "Failed to parse cached menu")
      with _ ->
        (* If corrupted, scrape again *)
        find_menu_uuid ~date_str ~hall_slug ~meal_slug >>= function
        | None ->
          let empty_menu = {
            Types.hall_slug; date_str; meal_slug;
            meal_name = Types.meal_name_of_slug meal_slug;
            menu_id = ""; stations = [];
          } in
          Lwt.return empty_menu
        | Some (actual_meal_name, menu_uuid) ->
          let url = Printf.sprintf "%s/GetReport/%s" base_url menu_uuid in
          http_post url "allergens=&tags=&maycontain=" >>= fun html ->
          let stations = parse_report_html html in
          let result = {
            Types.hall_slug; date_str; meal_slug;
            meal_name = actual_meal_name; menu_id = menu_uuid;
            stations;
          } in
          Hashtbl.replace menu_memory_cache mem_key result;
          List.iter (fun (sg : Types.station_group) ->
            Frequency.record_dishes ~hall:hall_slug ~date:date_str sg.dishes
          ) stations;
          (try Yojson.Safe.to_file disk_file (Types.meal_menu_to_yojson result) with _ -> ());
          Lwt.return result
    ) else (
      (* Not on disk: scrape once and persist *)
      find_menu_uuid ~date_str ~hall_slug ~meal_slug >>= function
      | None ->
        let empty_menu = {
          Types.hall_slug; date_str; meal_slug;
          meal_name = Types.meal_name_of_slug meal_slug;
          menu_id = ""; stations = [];
        } in
        Lwt.return empty_menu
      | Some (actual_meal_name, menu_uuid) ->
        let url = Printf.sprintf "%s/GetReport/%s" base_url menu_uuid in
        http_post url "allergens=&tags=&maycontain=" >>= fun html ->
        let stations = parse_report_html html in
        List.iter (fun (sg : Types.station_group) ->
          Frequency.record_dishes ~hall:hall_slug ~date:date_str sg.dishes
        ) stations;
        let result = {
          Types.hall_slug; date_str; meal_slug;
          meal_name = actual_meal_name; menu_id = menu_uuid;
          stations;
        } in
        Hashtbl.replace menu_memory_cache mem_key result;
        (try Yojson.Safe.to_file disk_file (Types.meal_menu_to_yojson result) with _ -> ());
        Lwt.return result
    )
