(** Food Item Frequency Tracker for analytics *)

type occurrence_entry = {
  name : string;
  mutable count : int;
  mutable halls : string list;
  mutable dates : string list;
}

let table : (string, occurrence_entry) Hashtbl.t = Hashtbl.create 500

let record_dish ~(name : string) ~(hall : string) ~(date : string) : unit =
  let key = String.trim (String.lowercase_ascii name) in
  if String.length key = 0 then ()
  else
    match Hashtbl.find_opt table key with
    | Some entry ->
      entry.count <- entry.count + 1;
      if not (List.mem hall entry.halls) then entry.halls <- hall :: entry.halls;
      if not (List.mem date entry.dates) then entry.dates <- date :: entry.dates
    | None ->
      Hashtbl.add table key {
        name = String.trim name;
        count = 1;
        halls = [ hall ];
        dates = [ date ];
      }

let record_dishes ~(hall : string) ~(date : string) (dishes : Types.dish list) : unit =
  List.iter (fun (d : Types.dish) -> record_dish ~name:d.name ~hall ~date) dishes

let get_top_frequent ~(limit : int) () : occurrence_entry list =
  let entries = Hashtbl.fold (fun _ entry acc -> entry :: acc) table [] in
  let sorted = List.sort (fun a b -> compare b.count a.count) entries in
  let rec take n = function
    | [] -> []
    | x :: xs -> if n <= 0 then [] else x :: take (n - 1) xs
  in
  take limit sorted

let total_dishes_tracked () : int =
  Hashtbl.length table

(** Hydrate frequency table by scanning cached menu files on startup *)
let hydrate_from_cache ~(cache_menus_dir : string) : unit =
  if Sys.file_exists cache_menus_dir && Sys.is_directory cache_menus_dir then (
    let files = Sys.readdir cache_menus_dir in
    Array.iter (fun fname ->
      if String.ends_with ~suffix:".json" fname then (
        let full_path = Filename.concat cache_menus_dir fname in
        try
          let json = Yojson.Safe.from_file full_path in
          match Types.meal_menu_of_yojson json with
          | Some m ->
            List.iter (fun (sg : Types.station_group) ->
              record_dishes ~hall:m.hall_slug ~date:m.date_str sg.dishes
            ) m.stations
          | None -> ()
        with _ -> ()
      )
    ) files
  )
