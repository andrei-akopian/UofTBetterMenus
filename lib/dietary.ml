(** Allergen and dietary tag inference for UofT Dining Menu System *)

let contains_sub (s : string) (sub : string) : bool =
  Types.contains_sub s sub

(** Infer likely allergens & dietary tags from dish name *)
let infer_allergens_and_tags (dish_name : string) : string list * string list =
  let lower = String.lowercase_ascii dish_name in
  let allergens = ref [] in
  let tags = ref [] in
  let add_al a = if not (List.mem a !allergens) then allergens := a :: !allergens in
  let add_tg t = if not (List.mem t !tags) then tags := t :: !tags in

  if contains_sub lower "egg" || contains_sub lower "omelet" || contains_sub lower "mayo" then add_al "Egg";
  if contains_sub lower "milk" || contains_sub lower "cheese" || contains_sub lower "butter" || contains_sub lower "cream" || contains_sub lower "feta" || contains_sub lower "cheddar" || contains_sub lower "parmesan" || contains_sub lower "pudding" || contains_sub lower "ice cream" then add_al "Dairy";
  if contains_sub lower "fish" || contains_sub lower "tuna" || contains_sub lower "salmon" || contains_sub lower "cod" then add_al "Fish";
  if contains_sub lower "shrimp" || contains_sub lower "surimi" || contains_sub lower "crab" then add_al "Shellfish";
  if contains_sub lower "peanut" || contains_sub lower "almond" || contains_sub lower "walnut" || contains_sub lower "pecan" then add_al "Tree Nuts";
  if contains_sub lower "tofu" || contains_sub lower "soy" || contains_sub lower "edamame" then add_al "Soy";
  if contains_sub lower "wheat" || contains_sub lower "gluten" || contains_sub lower "pizza" || contains_sub lower "pasta" || contains_sub lower "bread" || contains_sub lower "cookie" || contains_sub lower "cake" || contains_sub lower "brownie" || contains_sub lower "cracker" || contains_sub lower "burger" then add_al "Gluten";
  if contains_sub lower "pork" || contains_sub lower "ham" || contains_sub lower "bacon" || contains_sub lower "salami" || contains_sub lower "pepperoni" || contains_sub lower "bologna" then add_al "Pork";

  if contains_sub lower "vegan" then (add_tg "Vegan"; add_tg "Vegetarian")
  else if contains_sub lower "veggie" || contains_sub lower "vegetarian" || contains_sub lower "salad" || contains_sub lower "tofu" || contains_sub lower "cheese" || contains_sub lower "fruit" then add_tg "Vegetarian";
  if contains_sub lower "halal" || contains_sub lower "chicken" || contains_sub lower "beef" || contains_sub lower "stir fry" || contains_sub lower "tofu" then add_tg "Halal";

  (List.rev !allergens, List.rev !tags)
