(** Automated Unit Tests for UofT Better Menus *)

open Menu_lib

let assert_bool msg b =
  if not b then (
    Printf.eprintf "Assertion failed: %s\n" msg;
    exit 1
  ) else
    Printf.printf "  ✓ %s\n" msg

let assert_string_contains msg str sub =
  if not (Types.contains_sub str sub) then (
    Printf.eprintf "Assertion failed: %s (expected '%s' in string of length %d)\n" msg sub (String.length str);
    exit 1
  ) else
    Printf.printf "  ✓ %s\n" msg

let assert_string_does_not_contain msg str sub =
  if Types.contains_sub str sub then (
    Printf.eprintf "Assertion failed: %s (unexpected substring '%s' found in string)\n" msg sub;
    exit 1
  ) else
    Printf.printf "  ✓ %s\n" msg

let test_date_utils () =
  Printf.printf "Testing Date_utils...\n";
  let today = Date_utils.get_today_str () in
  let tomorrow = Date_utils.shift_date today 1 in
  let yesterday = Date_utils.shift_date today (-1) in

  assert_bool "days_from_today for today is 0" (Date_utils.days_from_today today = 0);
  assert_bool "days_from_today for tomorrow is 1" (Date_utils.days_from_today tomorrow = 1);
  assert_bool "days_from_today for yesterday is -1" (Date_utils.days_from_today yesterday = -1);

  assert_bool "today is within allowed range" (Date_utils.is_date_in_allowed_range today);
  assert_bool "tomorrow is within allowed range" (Date_utils.is_date_in_allowed_range tomorrow);
  assert_bool "today is not past limit" (not (Date_utils.is_past_limit_reached today));
  assert_bool "today is not future limit" (not (Date_utils.is_future_limit_reached today));

  let future_14 = Date_utils.shift_date today 14 in
  assert_bool "+14 is future limit reached" (Date_utils.is_future_limit_reached future_14);

  let past_14 = Date_utils.shift_date today (-14) in
  assert_bool "-14 is past limit reached" (Date_utils.is_past_limit_reached past_14);

  let (badge, _, _, _, _, _) = Date_utils.format_date_display today in
  assert_bool "today rel_badge is Today" (badge = Some "Today");

  let (badge_tom, _, _, _, _, _) = Date_utils.format_date_display tomorrow in
  assert_bool "tomorrow rel_badge is Tomorrow" (badge_tom = Some "Tomorrow");

  let (badge_yest, _, _, _, _, _) = Date_utils.format_date_display yesterday in
  assert_bool "yesterday rel_badge is Yesterday" (badge_yest = Some "Yesterday")

let test_navigation_buttons () =
  Printf.printf "\nTesting Day Switcher Navigation Buttons...\n";
  let hall_slug = "new-college" in
  let today = Date_utils.get_today_str () in
  let meal_slug = "lunch" in

  (* Day switcher on today: prev_day_available = true, next_day_available = true *)
  let switcher_html = Views.render_day_switcher ~hall_slug ~date_str:today ~meal_slug ~prev_day_available:true ~next_day_available:true () in
  assert_string_contains "day-btn-prev is present" switcher_html "day-btn-prev";
  assert_string_contains "day-btn-next is present" switcher_html "day-btn-next";
  assert_string_contains "Next Day label is visible" switcher_html "Next Day";
  assert_string_contains "Prev Day label is visible" switcher_html "Prev Day";
  assert_string_does_not_contain "No placeholder when both available" switcher_html "day-btn-placeholder";

  (* When at future limit: next_day_available = false *)
  let at_limit_html = Views.render_day_switcher ~hall_slug ~date_str:today ~meal_slug ~prev_day_available:true ~next_day_available:false () in
  assert_string_contains "day-btn-prev is present when next is limited" at_limit_html "day-btn-prev";
  assert_string_contains "placeholder is present when next is limited" at_limit_html "day-btn-placeholder";
  assert_string_does_not_contain "day-btn-next is omitted when next is limited" at_limit_html "day-btn-next"

let test_today_missing_menu_parity () =
  Printf.printf "\nTesting Missing Menu Status Parity for Today...\n";
  let hall = List.hd Types.dining_halls in
  let today = Date_utils.get_today_str () in
  let empty_menu = {
    Types.hall_slug = hall.slug;
    date_str = today;
    meal_slug = "lunch";
    meal_name = "Lunch";
    menu_id = "";
    stations = [];
    available_meals = ["Breakfast"];
  } in
  let html = Views.render_main_menu ~menu:empty_menu ~active_hall:hall ~prev_day_available:true ~next_day_available:true () in

  (* Must show specialized Today heading *)
  assert_string_contains "Contains Today's Lunch Menu Not Yet Published" html "Today's Lunch Menu Not Yet Published";
  assert_string_contains "Explains dining hall delay" html "Dining halls sometimes publish schedules late";
  assert_string_contains "Mentions 10-minute re-check" html "10 minutes";
  assert_string_contains "Provides Refresh Menu action" html "Refresh Menu";

  (* Must NOT suggest View Today's Menu when on today *)
  assert_string_does_not_contain "Does NOT contain View Today's Menu link" html "View Today's Menu";
  assert_string_does_not_contain "Does NOT contain View Today's Menu link escaped" html "View Today&#39;s Menu";
  assert_string_does_not_contain "Does NOT contain View Today's Active Menu link" html "View Today's Active Menu";

  (* Must show other available meals for today if any *)
  assert_string_contains "Shows other meals posted for this date" html "Other meals posted for this date";
  assert_string_contains "Shows Breakfast option pill" html "View Breakfast";

  (* Must show alternative dining halls *)
  assert_string_contains "Shows other dining halls section" html "Check other dining halls";
  assert_string_contains "Shows Chestnut link" html "Chestnut";
  assert_string_contains "Shows CampusOne link" html "CampusOne"

let test_tomorrow_missing_menu_parity () =
  Printf.printf "\nTesting Missing Menu Status Parity for Tomorrow...\n";
  let hall = List.hd Types.dining_halls in
  let today = Date_utils.get_today_str () in
  let tomorrow = Date_utils.shift_date today 1 in
  let empty_menu = {
    Types.hall_slug = hall.slug;
    date_str = tomorrow;
    meal_slug = "dinner";
    meal_name = "Dinner";
    menu_id = "";
    stations = [];
    available_meals = [];
  } in
  let html = Views.render_main_menu ~menu:empty_menu ~active_hall:hall ~prev_day_available:true ~next_day_available:true () in

  assert_string_contains "Contains Tomorrow's Dinner Menu Not Yet Available" html "Tomorrow's Dinner Menu Not Yet Available";
  assert_string_contains "Mentions Return to Today's Menu" html "Return to Today's Menu";
  assert_string_contains "Mentions Check Again" html "Check Again"

let test_future_missing_menu_parity () =
  Printf.printf "\nTesting Missing Menu Status Parity for Future Days...\n";
  let hall = List.hd Types.dining_halls in
  let today = Date_utils.get_today_str () in
  let future_date = Date_utils.shift_date today 5 in
  let empty_menu = {
    Types.hall_slug = hall.slug;
    date_str = future_date;
    meal_slug = "lunch";
    meal_name = "Lunch";
    menu_id = "";
    stations = [];
    available_meals = [];
  } in
  let html = Views.render_main_menu ~menu:empty_menu ~active_hall:hall ~prev_day_available:true ~next_day_available:true () in

  assert_string_contains "Contains Not Yet Published for day" html "Not Yet Published";
  assert_string_contains "Contains Return to Today's Menu" html "Return to Today's Menu"

let test_past_missing_menu_parity () =
  Printf.printf "\nTesting Missing Menu Status Parity for Past Days...\n";
  let hall = List.hd Types.dining_halls in
  let today = Date_utils.get_today_str () in
  let yesterday = Date_utils.shift_date today (-1) in
  let empty_yesterday = {
    Types.hall_slug = hall.slug;
    date_str = yesterday;
    meal_slug = "lunch";
    meal_name = "Lunch";
    menu_id = "";
    stations = [];
    available_meals = [];
  } in
  let yest_html = Views.render_main_menu ~menu:empty_yesterday ~active_hall:hall ~prev_day_available:true ~next_day_available:true () in
  assert_string_contains "Contains No Archived Menu for Yesterday" yest_html "No Archived Menu for Yesterday";

  let past_date = Date_utils.shift_date today (-5) in
  let empty_past = {
    Types.hall_slug = hall.slug;
    date_str = past_date;
    meal_slug = "lunch";
    meal_name = "Lunch";
    menu_id = "";
    stations = [];
    available_meals = [];
  } in
  let past_html = Views.render_main_menu ~menu:empty_past ~active_hall:hall ~prev_day_available:true ~next_day_available:true () in
  assert_string_contains "Contains No Menu Archived for" past_html "No Menu Archived for"

let test_cooldown_logic () =
  Printf.printf "\nTesting 10-Minute Cooldown Logic...\n";
  let test_cache = Hashtbl.create 10 in
  let test_key = "20261110:new-college:lunch" in

  assert_bool "initial state has cooldown elapsed" (Api_client.has_cooldown_elapsed test_cache test_key);

  Api_client.record_fetch_attempt test_cache test_key;
  assert_bool "immediately after record, cooldown has NOT elapsed" (not (Api_client.has_cooldown_elapsed test_cache test_key));

  (* Simulate 601 seconds ago *)
  Hashtbl.replace test_cache test_key (Unix.time () -. 601.0);
  assert_bool "after > 600 seconds, cooldown has elapsed" (Api_client.has_cooldown_elapsed test_cache test_key);

  (* Simulate 300 seconds ago (5 minutes) *)
  Hashtbl.replace test_cache test_key (Unix.time () -. 300.0);
  assert_bool "at 5 minutes, cooldown has NOT elapsed" (not (Api_client.has_cooldown_elapsed test_cache test_key))

let () =
  Printf.printf "========================================\n";
  Printf.printf "Running UofT Better Menus Test Suite\n";
  Printf.printf "========================================\n\n";
  test_date_utils ();
  test_navigation_buttons ();
  test_today_missing_menu_parity ();
  test_tomorrow_missing_menu_parity ();
  test_future_missing_menu_parity ();
  test_past_missing_menu_parity ();
  test_cooldown_logic ();
  Printf.printf "\n========================================\n";
  Printf.printf "All tests passed successfully!\n";
  Printf.printf "========================================\n"
