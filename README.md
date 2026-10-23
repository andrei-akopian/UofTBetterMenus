# Unofficial UofT Dining Halls Menus

University of Toronto Dining Halls menu website. Information sourced from [Menu Nutritional Information](https://fso.ueat.utoronto.ca/FSO/ServiceMenuReport/Today) and repackaged with a nicer UI.

Frontend implemented with server-side rendering; backend in OCaml and Dream. Built using Gemini-3.8-Flash.

## Development

### Local Development
```bash
eval $(opam env --switch=default)
dune build
dune exec bin/main.exe
```
The server runs on `http://localhost:8080`.

### Docker Build
```bash
docker build -t uoft-dining-menu .
docker run -p 8080:8080 -v menu_cache:/app/cache uoft-dining-menu
```

Or using Docker Compose:
```bash
docker compose up -d
```

## TODO

- [ ] Setup header with about and link to github repo.
- [ ] procure all the photos of different food.