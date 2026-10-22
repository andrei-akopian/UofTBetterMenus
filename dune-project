(lang dune 3.0)
(name menu_app)
(generate_opam_files true)

(package
 (name menu_app)
 (synopsis "UofT Dining Menu Web Application")
 (depends
  (ocaml (>= 5.0.0))
  (dune (>= 3.0))
  dream
  lambdasoup
  base64
  cohttp-lwt-unix
  uri
  yojson))
