(** Dish photo registry and keyword-based visual illustration fallback *)

let contains_sub (s : string) (sub : string) : bool =
  let sub_len = String.length sub in
  let s_len = String.length s in
  if sub_len = 0 then true
  else if sub_len > s_len then false
  else
    let found = ref false in
    let i = ref 0 in
    while !i <= s_len - sub_len && not !found do
      if String.sub s !i sub_len = sub then found := true;
      incr i
    done;
    !found

let photo_registry : (string, string) Hashtbl.t = Hashtbl.create 200

let init_photos_from_file () : unit =
  let file_path = "static/photos/photos.json" in
  if Sys.file_exists file_path then (
    try
      let json = Yojson.Safe.from_file file_path in
      match json with
      | `Assoc pairs ->
        List.iter (function
          | (name, `String fname) ->
            let full_url =
              if String.starts_with ~prefix:"/" fname then fname
              else Printf.sprintf "/static/photos/%s" fname
            in
            Hashtbl.replace photo_registry (String.trim (String.lowercase_ascii name)) full_url
          | _ -> ()
        ) pairs
      | _ -> ()
    with _ -> ()
  )

let resolve_dish_photo (name : string) : string =
  let norm = String.trim (String.lowercase_ascii name) in
  match Hashtbl.find_opt photo_registry norm with
  | Some url -> url
  | None ->
    (* Keyword based visual illustration fallback *)
    if contains_sub norm "burger" then "/static/photos/burger.svg"
    else if contains_sub norm "pizza" then "/static/photos/pizza.svg"
    else if contains_sub norm "soup" || contains_sub norm "broth" then "/static/photos/soup.svg"
    else if contains_sub norm "stir" || contains_sub norm "fry" || contains_sub norm "noodle" || contains_sub norm "curry" || contains_sub norm "rice" then "/static/photos/stir_fry.svg"
    else if contains_sub norm "salad" || contains_sub norm "greens" then "/static/photos/salad.svg"
    else if contains_sub norm "cookie" then "/static/photos/cookie.svg"
    else if contains_sub norm "cake" || contains_sub norm "pudding" || contains_sub norm "crumble" || contains_sub norm "pie" || contains_sub norm "brownie" || contains_sub norm "cheesecake" || contains_sub norm "jello" || contains_sub norm "ice cream" then "/static/photos/cake.svg"
    else if contains_sub norm "egg" || contains_sub norm "sandwich" || contains_sub norm "deli" then "/static/photos/egg_salad.svg"
    else if contains_sub norm "chicken" || contains_sub norm "pork" || contains_sub norm "beef" || contains_sub norm "tofu" || contains_sub norm "turkey" || contains_sub norm "entree" || contains_sub norm "roast" then "/static/photos/entree.svg"
    else "/static/photos/default.svg"
