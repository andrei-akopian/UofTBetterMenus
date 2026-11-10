(** Core types for UofT Dining Menu System *)

type hall_info = {
  slug : string;
  name : string;
  short_name : string;
  address : string;
}

type nutrition_info = {
  serving : string;
  calories : string;
  fat : string;
  sat_fat : string;
  cholesterol : string;
  sodium : string;
  carbs : string;
  fibre : string;
  sugar : string;
  protein : string;
  vit_c : string;
  calcium : string;
  iron : string;
}

type dish_label = {
  ingredients : string;
  allergens : string list;
  may_contain : string list;
  tags : string list;
}

type dish = {
  name : string;
  menu_id : string;
  line_id : string;
  portion : string;
  station : string;
  nutrition : nutrition_info option;
  mutable allergens : string list;
  mutable tags : string list;
  mutable image_url : string option;
}

type station_group = {
  name : string;
  dishes : dish list;
}

type meal_menu = {
  hall_slug : string;
  date_str : string;
  meal_slug : string;
  meal_name : string;
  menu_id : string;
  stations : station_group list;
  available_meals : string list;
}

(** Pre-defined 4 Residential Dining Halls *)
let dining_halls : hall_info list = [
  { slug = "new-college"; name = "New College Dining Hall"; short_name = "New College"; address = "40 Willcocks St" };
  { slug = "chestnut"; name = "Chestnut Residence"; short_name = "Chestnut"; address = "89 Chestnut St" };
  { slug = "campus-one"; name = "CampusOne Dining Hall"; short_name = "CampusOne"; address = "253 College St" };
  { slug = "oak-house"; name = "Oak House Dining Hall"; short_name = "Oak House"; address = "Spadina & Sussex" };
]

let find_hall_by_slug (slug : string) : hall_info option =
  List.find_opt (fun (h : hall_info) -> String.lowercase_ascii h.slug = String.lowercase_ascii slug) dining_halls

let find_hall_by_name (name : string) : hall_info option =
  let lower_name = String.lowercase_ascii name in
  List.find_opt (fun (h : hall_info) ->
    let l1 = String.lowercase_ascii h.name in
    let l2 = String.lowercase_ascii h.short_name in
    String.equal l1 lower_name || String.equal l2 lower_name ||
    (String.length l2 > 3 && String.sub lower_name 0 (min (String.length lower_name) (String.length l2)) = l2)
  ) dining_halls

let meal_slug_of_name (name : string) : string =
  match String.lowercase_ascii (String.trim name) with
  | "breakfast" -> "breakfast"
  | "lunch" -> "lunch"
  | "dinner" -> "dinner"
  | other ->
    String.map (function ' ' | '/' | '_' -> '-' | c -> Char.lowercase_ascii c) other

let meal_name_of_slug (slug : string) : string =
  match String.lowercase_ascii slug with
  | "breakfast" -> "Breakfast"
  | "lunch" -> "Lunch"
  | "dinner" -> "Dinner"
  | other -> String.capitalize_ascii other

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

(** Station Priority Order
    Priority 1: Pan station, Breakfast/Lunch/Dinner entrees (daily varied mains)
    Priority 2: Soups, Foodie Finds, Pizza/Bakery specials
    Priority 3: Breakfast sides & cereals
    Priority 4 (Bottom): Grill, Deli bar, Salad bar, Desserts (daily buffet staples)
*)
let station_priority (name : string) : int =
  let lower = String.lowercase_ascii (String.trim name) in
  (* Top priority in breakfast: Breakfast Entree *)
  if contains_sub lower "breakfast entree" || contains_sub lower "breakfast entrée" then 5
  (* Top priority in lunch/dinner: Pan Station & Entrees *)
  else if contains_sub lower "pan" || contains_sub lower "wok" then 10
  else if contains_sub lower "entree" || contains_sub lower "entrée" || contains_sub lower "main" then 10
  else if contains_sub lower "find" || contains_sub lower "chef" || contains_sub lower "special" then 20
  else if contains_sub lower "pizza" || contains_sub lower "pasta" then 30
  else if contains_sub lower "soup" then 40
  (* Breakfast sides & cereals *)
  else if contains_sub lower "hot cereal" then 60
  else if contains_sub lower "cold cereal" || contains_sub lower "cereal" then 65
  else if contains_sub lower "toast" then 70
  else if contains_sub lower "pantry" then 75
  else if contains_sub lower "pastr" then 80
  (* Bottom buffet fixtures *)
  else if contains_sub lower "grill" || contains_sub lower "burger" then 70
  else if contains_sub lower "deli" || contains_sub lower "sandwich" then 82
  else if contains_sub lower "salad" then 85
  else if contains_sub lower "dessert" || contains_sub lower "sweet" || contains_sub lower "bakery" || contains_sub lower "bake" then 90
  else 55

(** Yojson Serializers & Deserializers *)

let nutrition_to_yojson (n : nutrition_info) : Yojson.Safe.t =
  `Assoc [
    ("serving", `String n.serving);
    ("calories", `String n.calories);
    ("fat", `String n.fat);
    ("sat_fat", `String n.sat_fat);
    ("cholesterol", `String n.cholesterol);
    ("sodium", `String n.sodium);
    ("carbs", `String n.carbs);
    ("fibre", `String n.fibre);
    ("sugar", `String n.sugar);
    ("protein", `String n.protein);
    ("vit_c", `String n.vit_c);
    ("calcium", `String n.calcium);
    ("iron", `String n.iron);
  ]

let nutrition_of_yojson (j : Yojson.Safe.t) : nutrition_info option =
  match j with
  | `Assoc pairs ->
    let get key =
      match List.assoc_opt key pairs with
      | Some (`String s) -> s
      | _ -> ""
    in
    Some {
      serving = get "serving";
      calories = get "calories";
      fat = get "fat";
      sat_fat = get "sat_fat";
      cholesterol = get "cholesterol";
      sodium = get "sodium";
      carbs = get "carbs";
      fibre = get "fibre";
      sugar = get "sugar";
      protein = get "protein";
      vit_c = get "vit_c";
      calcium = get "calcium";
      iron = get "iron";
    }
  | _ -> None

let dish_to_yojson (d : dish) : Yojson.Safe.t =
  `Assoc [
    ("name", `String d.name);
    ("menu_id", `String d.menu_id);
    ("line_id", `String d.line_id);
    ("portion", `String d.portion);
    ("station", `String d.station);
    ("nutrition", match d.nutrition with Some n -> nutrition_to_yojson n | None -> `Null);
    ("allergens", `List (List.map (fun a -> `String a) d.allergens));
    ("tags", `List (List.map (fun t -> `String t) d.tags));
    ("image_url", match d.image_url with Some u -> `String u | None -> `Null);
  ]

let dish_of_yojson (j : Yojson.Safe.t) : dish option =
  match j with
  | `Assoc pairs ->
    let get_str key =
      match List.assoc_opt key pairs with
      | Some (`String s) -> s
      | _ -> ""
    in
    let get_str_list key =
      match List.assoc_opt key pairs with
      | Some (`List l) ->
        List.filter_map (function `String s -> Some s | _ -> None) l
      | _ -> []
    in
    let nut =
      match List.assoc_opt "nutrition" pairs with
      | Some j_nut -> nutrition_of_yojson j_nut
      | None -> None
    in
    let img =
      match List.assoc_opt "image_url" pairs with
      | Some (`String s) when s <> "" -> Some s
      | _ -> None
    in
    Some {
      name = get_str "name";
      menu_id = get_str "menu_id";
      line_id = get_str "line_id";
      portion = get_str "portion";
      station = get_str "station";
      nutrition = nut;
      allergens = get_str_list "allergens";
      tags = get_str_list "tags";
      image_url = img;
    }
  | _ -> None

let station_group_to_yojson (sg : station_group) : Yojson.Safe.t =
  `Assoc [
    ("name", `String sg.name);
    ("dishes", `List (List.map dish_to_yojson sg.dishes));
  ]

let station_group_of_yojson (j : Yojson.Safe.t) : station_group option =
  match j with
  | `Assoc pairs ->
    let name =
      match List.assoc_opt "name" pairs with
      | Some (`String s) -> s
      | _ -> ""
    in
    let dishes =
      match List.assoc_opt "dishes" pairs with
      | Some (`List l) -> List.filter_map dish_of_yojson l
      | _ -> []
    in
    Some { name; dishes }
  | _ -> None

let meal_menu_to_yojson (m : meal_menu) : Yojson.Safe.t =
  `Assoc [
    ("hall_slug", `String m.hall_slug);
    ("date_str", `String m.date_str);
    ("meal_slug", `String m.meal_slug);
    ("meal_name", `String m.meal_name);
    ("menu_id", `String m.menu_id);
    ("stations", `List (List.map station_group_to_yojson m.stations));
    ("available_meals", `List (List.map (fun s -> `String s) m.available_meals));
  ]

let meal_menu_of_yojson (j : Yojson.Safe.t) : meal_menu option =
  match j with
  | `Assoc pairs ->
    let get_str key =
      match List.assoc_opt key pairs with
      | Some (`String s) -> s
      | _ -> ""
    in
    let stations =
      match List.assoc_opt "stations" pairs with
      | Some (`List l) -> List.filter_map station_group_of_yojson l
      | _ -> []
    in
    let available_meals =
      match List.assoc_opt "available_meals" pairs with
      | Some (`List l) ->
        List.filter_map (function `String s -> Some s | _ -> None) l
      | _ -> []
    in
    Some {
      hall_slug = get_str "hall_slug";
      date_str = get_str "date_str";
      meal_slug = get_str "meal_slug";
      meal_name = get_str "meal_name";
      menu_id = get_str "menu_id";
      stations;
      available_meals;
    }
  | _ -> None

let dish_label_to_yojson (lbl : dish_label) : Yojson.Safe.t =
  `Assoc [
    ("ingredients", `String lbl.ingredients);
    ("allergens", `List (List.map (fun a -> `String a) lbl.allergens));
    ("may_contain", `List (List.map (fun mc -> `String mc) lbl.may_contain));
    ("tags", `List (List.map (fun t -> `String t) lbl.tags));
  ]

let dish_label_of_yojson (j : Yojson.Safe.t) : dish_label option =
  match j with
  | `Assoc pairs ->
    let get_str key =
      match List.assoc_opt key pairs with
      | Some (`String s) -> s
      | _ -> ""
    in
    let get_str_list key =
      match List.assoc_opt key pairs with
      | Some (`List l) ->
        List.filter_map (function `String s -> Some s | _ -> None) l
      | _ -> []
    in
    Some {
      ingredients = get_str "ingredients";
      allergens = get_str_list "allergens";
      may_contain = get_str_list "may_contain";
      tags = get_str_list "tags";
    }
  | _ -> None
