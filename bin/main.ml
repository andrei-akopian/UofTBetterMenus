(** Dream Web Server for UofT Dining Menu System *)

open Lwt.Infix
open Menu_lib

let get_current_meal_slug () : string =
  let tm = Unix.localtime (Unix.time ()) in
  let h = tm.Unix.tm_hour in
  if h < 11 then "breakfast"
  else if h < 16 then "lunch"
  else "dinner"

let safe_hall_or_default (hall_slug : string) : Types.hall_info =
  match Types.find_hall_by_slug hall_slug with
  | Some h -> h
  | None ->
    (match Types.dining_halls with
     | h :: _ -> h
     | [] -> { slug = "new-college"; name = "New College Dining Hall"; short_name = "New College"; address = "" })

let port =
  match Sys.getenv_opt "PORT" with
  | Some s -> (match int_of_string_opt s with Some p -> p | None -> 8080)
  | None -> 8080

let () =
  (* Initialize photo bindings on startup *)
  Photos.init_photos_from_file ();

  (* Hydrate dish frequency tracker from on-disk cached menus *)
  Frequency.hydrate_from_cache ~cache_menus_dir:Api_client.cache_menus_dir;

  Dream.run ~interface:"0.0.0.0" ~port
  @@ Dream.logger
  @@ Dream.router [
    (* Static assets (CSS, photos, etc.) *)
    Dream.get "/static/**" (Dream.static "static");

    (* Blank path: returns minimalist landing page with dining hall selection buttons *)
    Dream.get "/" (fun _request ->
      let today = Date_utils.get_today_str () in
      Dream.html (Views.render_landing_page ~today)
    );

    (* Food Item Frequency Tracker *)
    Dream.get "/frequency" (fun _request ->
      let entries = Frequency.get_top_frequent ~limit:50 () in
      let total = Frequency.total_dishes_tracked () in
      Dream.html (Views.render_frequency_page ~entries ~total)
    );

    Dream.get "/analytics" (fun request ->
      Dream.redirect request "/frequency"
    );

    (* Short URL: /hall -> redirects to /hall/today/meal *)
    Dream.get "/:hall" (fun request ->
      let hall = Dream.param request "hall" in
      let today = Date_utils.get_today_str () in
      let meal = get_current_meal_slug () in
      Dream.redirect request (Printf.sprintf "/%s/%s/%s" hall today meal)
    );

    (* URL: /hall/date -> infers current meal *)
    Dream.get "/:hall/:date" (fun request ->
      let hall = Dream.param request "hall" in
      let date = Dream.param request "date" in
      let meal = get_current_meal_slug () in
      Dream.redirect request (Printf.sprintf "/%s/%s/%s" hall date meal)
    );

    (* Primary view: /hall/date/meal *)
    Dream.get "/:hall/:date/:meal" (fun request ->
      let hall_slug = Dream.param request "hall" in
      let date_str = Dream.param request "date" in
      let meal_slug = Dream.param request "meal" in
      let active_hall = safe_hall_or_default hall_slug in
      let next_date = Date_utils.shift_date date_str 1 in
      Api_client.fetch_meal_menu ~hall_slug ~date_str ~meal_slug >>= fun menu ->
      Api_client.is_date_available ~hall_slug ~date_str:next_date >>= fun next_day_available ->
      Dream.html (Views.render_main_menu ~menu ~active_hall ~next_day_available ())
    );
  ]
