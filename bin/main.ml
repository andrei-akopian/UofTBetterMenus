(** Dream Web Server for UofT Dining Menu System *)

open Lwt.Infix
open Menu_lib

let get_current_meal_slug () : string =
  let tm = Unix.localtime (Unix.time ()) in
  let h = tm.Unix.tm_hour in
  if h < 11 then "breakfast"
  else if h < 16 then "lunch"
  else "dinner"

let port =
  match Sys.getenv_opt "PORT" with
  | Some s -> (match int_of_string_opt s with Some p -> p | None -> 8080)
  | None -> 8080

let () =
  (* Initialize photo bindings on startup *)
  Photos.init_photos_from_file ();

  Dream.run ~interface:"0.0.0.0" ~port
  @@ Dream.logger
  @@ Dream.router [
    (* Static assets (CSS, photos, etc.) *)
    Dream.get "/static/**" (Dream.static "static");

    (* Health check endpoint for orchestrators (Fly.io, Railway, Kubernetes) *)
    Dream.get "/up" (fun _request -> Dream.respond "OK");
    Dream.head "/up" (fun _request -> Dream.empty `OK);
    Dream.head "/" (fun _request -> Dream.empty `OK);

    (* Blank path: returns minimalist landing page with dining hall selection buttons *)
    Dream.get "/" (fun _request ->
      let today = Date_utils.get_today_str () in
      Dream.html (Views.render_landing_page ~today)
    );

    (* Short URL: /hall -> redirects to /hall/today/meal with 404 validation *)
    Dream.get "/:hall" (fun request ->
      let hall = Dream.param request "hall" in
      match Types.find_hall_by_slug hall with
      | None ->
        Dream.respond ~status:`Not_Found
          (Views.render_error_page
            ~title:"Dining Hall Not Found | UofT Dining"
            ~icon:"🏛️"
            ~heading:"Dining Hall Not Found"
            ~message:(Printf.sprintf "We couldn't find a dining hall matching '%s'. UofT has 4 residential dining halls: New College, Chestnut, CampusOne, and Oak House." hall)
            ())
      | Some _ ->
        let today = Date_utils.get_today_str () in
        let meal = get_current_meal_slug () in
        Dream.redirect request (Printf.sprintf "/%s/%s/%s" hall today meal)
    );

    (* URL: /hall/date -> infers current meal with range and hall validation *)
    Dream.get "/:hall/:date" (fun request ->
      let hall = Dream.param request "hall" in
      let date = Dream.param request "date" in
      match Types.find_hall_by_slug hall with
      | None ->
        Dream.respond ~status:`Not_Found
          (Views.render_error_page
            ~title:"Dining Hall Not Found | UofT Dining"
            ~icon:"🏛️"
            ~heading:"Dining Hall Not Found"
            ~message:(Printf.sprintf "We couldn't find a dining hall matching '%s'." hall)
            ())
      | Some _ ->
        if not (Date_utils.is_date_in_allowed_range date) then
          Dream.respond ~status:`Not_Found
            (Views.render_error_page
              ~title:"Date Out of Range | UofT Dining"
              ~icon:"📅"
              ~heading:"Date Outside Archive Range"
              ~message:"Historical lookups are limited to the past 14 days and upcoming 14 days to protect university server capacity."
              ~primary_link:(Printf.sprintf "/%s/%s" hall (Date_utils.get_today_str ()), "View Today's Menu")
              ())
        else
          let meal = get_current_meal_slug () in
          Dream.redirect request (Printf.sprintf "/%s/%s/%s" hall date meal)
    );

    (* Primary view: /hall/date/meal *)
    Dream.get "/:hall/:date/:meal" (fun request ->
      let hall_slug = Dream.param request "hall" in
      let date_str = Dream.param request "date" in
      let meal_slug = Dream.param request "meal" in

      (* 1. Validate Dining Hall *)
      match Types.find_hall_by_slug hall_slug with
      | None ->
        Dream.respond ~status:`Not_Found
          (Views.render_error_page
            ~title:"Dining Hall Not Found | UofT Dining"
            ~icon:"🏛️"
            ~heading:"Dining Hall Not Found"
            ~message:(Printf.sprintf "We couldn't find a dining hall matching '%s'. Please select from New College, Chestnut, CampusOne, or Oak House." hall_slug)
            ())
      | Some active_hall ->
        (* 2. Validate Date Range *)
        if not (Date_utils.is_date_in_allowed_range date_str) then
          Dream.respond ~status:`Not_Found
            (Views.render_error_page
              ~title:"Date Out of Range | UofT Dining"
              ~icon:"📅"
              ~heading:"Date Outside Archive Range"
              ~message:"Online menu lookups are restricted to the past 14 days and next 14 days to protect university infrastructure from automated scraping."
              ~primary_link:(Printf.sprintf "/%s/%s/%s" hall_slug (Date_utils.get_today_str ()) (get_current_meal_slug ()), "View Today's Menu")
              ())
        else
          (* 3. Fetch Menu with graceful heuristic error fallback *)
          Lwt.catch
            (fun () ->
              let prev_day_available = not (Date_utils.is_past_limit_reached date_str) in
              let next_date = Date_utils.shift_date date_str 1 in
              Api_client.fetch_meal_menu ~hall_slug ~date_str ~meal_slug >>= fun menu ->
              Api_client.is_date_available ~hall_slug ~date_str:next_date >>= fun next_day_available ->
              Dream.html (Views.render_main_menu ~menu ~active_hall ~prev_day_available ~next_day_available ()))
            (fun _exn ->
              Dream.respond ~status:`Service_Unavailable
                (Views.render_error_page
                  ~title:"Menu Service Unavailable | UofT Dining"
                  ~icon:"📡"
                  ~heading:"Menu Service Temporarily Unavailable"
                  ~message:"The official UofT Food Services Online portal is temporarily unreachable or undergoing maintenance. Please try again in a few moments."
                  ~primary_link:(Printf.sprintf "/%s/%s/%s" hall_slug (Date_utils.get_today_str ()) meal_slug, "Retry Today's Menu")
                  ()))
    );
  ]
