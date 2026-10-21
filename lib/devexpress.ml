(** DevExpress Binary Protocol Tokenizer & Hierarchy Parser *)

type de_token =
  | DEStr of string
  | DEStruct of int
  | DEByte of int

let tokenize_items_info (b64 : string) : de_token list =
  match Base64.decode b64 with
  | Error _ -> []
  | Ok raw ->
    let len = String.length raw in
    let pos = ref 0 in
    let tokens = ref [] in
    while !pos < len do
      let b = Char.code raw.[!pos] in
      incr pos;
      if b = 2 && !pos < len then (
        let slen = Char.code raw.[!pos] in
        incr pos;
        if !pos + slen <= len then (
          let s = String.sub raw !pos slen in
          pos := !pos + slen;
          tokens := DEStr s :: !tokens
        ) else
          tokens := DEByte b :: !tokens
      ) else if b = 7 && !pos < len then (
        let count = Char.code raw.[!pos] in
        incr pos;
        tokens := DEStruct count :: !tokens
      ) else (
        tokens := DEByte b :: !tokens
      )
    done;
    List.rev !tokens

let is_uuid (s : string) : bool =
  String.length s = 36 &&
  s.[8] = '-' && s.[13] = '-' && s.[18] = '-' && s.[23] = '-'

let parse_location_hierarchy (tokens : de_token list) : (string * (string * string) list) list =
  let locations = ref [] in
  let current_loc = ref "" in
  let current_meals = ref [] in
  let flush () =
    if !current_loc <> "" && !current_meals <> [] then (
      locations := (!current_loc, List.rev !current_meals) :: !locations;
      current_meals := []
    )
  in
  let tok_array = Array.of_list tokens in
  let n = Array.length tok_array in
  let i = ref 0 in
  while !i < n do
    match tok_array.(!i) with
    | DEStr "noaction" when !i + 1 < n ->
      (match tok_array.(!i + 1) with
      | DEStr loc_candidate when loc_candidate <> "Locations" ->
        flush ();
        current_loc := loc_candidate;
        i := !i + 2
      | _ -> incr i)
    | DEStr uuid when is_uuid uuid && !i + 1 < n ->
      (match tok_array.(!i + 1) with
      | DEStr meal_name ->
        if !current_loc <> "" then
          current_meals := (meal_name, uuid) :: !current_meals;
        i := !i + 2
      | _ -> incr i)
    | _ -> incr i
  done;
  flush ();
  List.rev !locations

let extract_items_info_from_html (html : string) : string option =
  let pattern = Re.Perl.compile_pat "'mnuUnits'[^\\{]+\\{[^\\{]+'stateObject':\\{'itemsInfo':'([^']+)'" in
  match Re.exec_opt pattern html with
  | Some groups -> Some (Re.Group.get groups 1)
  | None ->
    let fallback_pattern = Re.Perl.compile_pat "'itemsInfo':'([^']+)'" in
    (match Re.exec_opt fallback_pattern html with
     | Some groups -> Some (Re.Group.get groups 1)
     | None -> None)

(** Hierarchy to/from Yojson *)
let hierarchy_to_yojson (h : (string * (string * string) list) list) : Yojson.Safe.t =
  `List (List.map (fun (loc, meals) ->
    `Assoc [
      ("location", `String loc);
      ("meals", `List (List.map (fun (m, u) -> `Assoc [("meal", `String m); ("uuid", `String u)]) meals))
    ]
  ) h)

let hierarchy_of_yojson (j : Yojson.Safe.t) : (string * (string * string) list) list =
  match j with
  | `List locs ->
    List.filter_map (function
      | `Assoc pairs ->
        let loc = match List.assoc_opt "location" pairs with Some (`String s) -> s | _ -> "" in
        let meals =
          match List.assoc_opt "meals" pairs with
          | Some (`List ml) ->
            List.filter_map (function
              | `Assoc mpairs ->
                let m = match List.assoc_opt "meal" mpairs with Some (`String s) -> s | _ -> "" in
                let u = match List.assoc_opt "uuid" mpairs with Some (`String s) -> s | _ -> "" in
                if m <> "" && u <> "" then Some (m, u) else None
              | _ -> None
            ) ml
          | _ -> []
        in
        if loc <> "" then Some (loc, meals) else None
      | _ -> None
    ) locs
  | _ -> []
