(** Date and time utility functions for UofT Dining Menu System *)

let parse_date_components (s : string) : int * int * int =
  let clean = String.concat "" (String.split_on_char '-' s) in
  if String.length clean = 8 then
    try
      let y = int_of_string (String.sub clean 0 4) in
      let m = int_of_string (String.sub clean 4 2) in
      let d = int_of_string (String.sub clean 6 2) in
      (y, m, d)
    with _ ->
      let tm = Unix.localtime (Unix.time ()) in
      (tm.Unix.tm_year + 1900, tm.Unix.tm_mon + 1, tm.Unix.tm_mday)
  else
    let tm = Unix.localtime (Unix.time ()) in
    (tm.Unix.tm_year + 1900, tm.Unix.tm_mon + 1, tm.Unix.tm_mday)

let shift_date (s : string) (days : int) : string =
  let (y, m, d) = parse_date_components s in
  let tm = {
    Unix.tm_sec = 0; tm_min = 0; tm_hour = 12;
    tm_mday = d + days;
    tm_mon = m - 1;
    tm_year = y - 1900;
    tm_wday = 0; tm_yday = 0; tm_isdst = false;
  } in
  let (time_sec, _) = Unix.mktime tm in
  let new_tm = Unix.localtime time_sec in
  Printf.sprintf "%04d-%02d-%02d" (new_tm.tm_year + 1900) (new_tm.tm_mon + 1) new_tm.tm_mday

let get_today_str () : string =
  let tm = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02d" (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday

let clean_date (s : string) : string =
  String.concat "" (String.split_on_char '-' s)

(** Date bounds to protect upstream servers from arbitrary scraping or bot attacks *)
let max_past_days = 14
let max_future_days = 14

let days_from_today (date_str : string) : int =
  let (y, m, d) = parse_date_components date_str in
  let tm = {
    Unix.tm_sec = 0; tm_min = 0; tm_hour = 12;
    tm_mday = d;
    tm_mon = m - 1;
    tm_year = y - 1900;
    tm_wday = 0; tm_yday = 0; tm_isdst = false;
  } in
  let (target_sec, _) = Unix.mktime tm in
  let (today_y, today_m, today_d) = parse_date_components (get_today_str ()) in
  let today_tm = {
    Unix.tm_sec = 0; tm_min = 0; tm_hour = 12;
    tm_mday = today_d;
    tm_mon = today_m - 1;
    tm_year = today_y - 1900;
    tm_wday = 0; tm_yday = 0; tm_isdst = false;
  } in
  let (today_sec, _) = Unix.mktime today_tm in
  int_of_float (Float.round ((target_sec -. today_sec) /. 86400.0))

let is_date_in_allowed_range (date_str : string) : bool =
  let diff = days_from_today date_str in
  diff >= -max_past_days && diff <= max_future_days

let is_past_limit_reached (date_str : string) : bool =
  let diff = days_from_today date_str in
  diff <= -max_past_days

let is_future_limit_reached (date_str : string) : bool =
  let diff = days_from_today date_str in
  diff >= max_future_days

(** Get accurate relative day badge (Today, Tomorrow, Yesterday, or None) and formatted date components *)
let format_date_display (date_str : string) : string option * string * string * string * int * string =
  let (y, m, d) = parse_date_components date_str in
  let tm = {
    Unix.tm_sec = 0; tm_min = 0; tm_hour = 12;
    tm_mday = d;
    tm_mon = m - 1;
    tm_year = y - 1900;
    tm_wday = 0; tm_yday = 0; tm_isdst = false;
  } in
  let (time_sec, _) = Unix.mktime tm in
  let final_tm = Unix.localtime time_sec in
  let day_name =
    match final_tm.tm_wday with
    | 0 -> "Sunday" | 1 -> "Monday" | 2 -> "Tuesday" | 3 -> "Wednesday"
    | 4 -> "Thursday" | 5 -> "Friday" | 6 -> "Saturday" | _ -> ""
  in
  let day_name_short =
    match final_tm.tm_wday with
    | 0 -> "Sun" | 1 -> "Mon" | 2 -> "Tue" | 3 -> "Wed"
    | 4 -> "Thu" | 5 -> "Fri" | 6 -> "Sat" | _ -> ""
  in
  let month_name =
    match final_tm.tm_mon with
    | 0 -> "Jan" | 1 -> "Feb" | 2 -> "Mar" | 3 -> "Apr"
    | 4 -> "May" | 5 -> "Jun" | 6 -> "Jul" | 7 -> "Aug"
    | 8 -> "Sep" | 9 -> "Oct" | 10 -> "Nov" | 11 -> "Dec" | _ -> ""
  in
  let today_str = get_today_str () in
  let tomorrow_str = shift_date today_str 1 in
  let yesterday_str = shift_date today_str (-1) in
  let c_target = clean_date date_str in
  let rel_badge =
    if c_target = clean_date today_str then Some "Today"
    else if c_target = clean_date tomorrow_str then Some "Tomorrow"
    else if c_target = clean_date yesterday_str then Some "Yesterday"
    else None
  in
  let year_str = Printf.sprintf "%d" (final_tm.tm_year + 1900) in
  (rel_badge, day_name, day_name_short, month_name, final_tm.tm_mday, year_str)
