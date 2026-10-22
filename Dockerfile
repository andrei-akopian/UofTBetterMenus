# syntax=docker/dockerfile:1
# ==============================================================================
# Multi-Stage Production Dockerfile for UofT Dining Menu (OCaml + Dream)
# Automatically builds for target architecture (e.g. linux/amd64 for Fly.io/cloud)
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Build the optimized native binary
# ------------------------------------------------------------------------------
FROM ocaml/opam:debian-12-ocaml-5.2 AS builder

# Set working directory
WORKDIR /home/opam/app

# Copy dependency specifications first for Docker layer caching
COPY --chown=opam:opam menu_app.opam dune-project ./

# Install opam dependencies and system build packages (depext)
RUN opam update && opam install . --deps-only -y

# Copy application source code
COPY --chown=opam:opam . .

# Build the release binary with compiler optimizations
RUN eval $(opam env) && dune build --profile release

# ------------------------------------------------------------------------------
# Stage 2: Minimal runtime image (~40 MB compressed)
# ------------------------------------------------------------------------------
FROM debian:bookworm-slim AS runner

# Install essential runtime libraries:
# - ca-certificates: required to verify TLS/HTTPS connections to ueat.utoronto.ca
# - curl: used by Api_client to perform low-level queries against upstream FSO API
# - libev4: high-performance asynchronous event loop
# - libssl3: OpenSSL runtime shared libraries
# - libgmp10: GNU Multiple Precision Arithmetic Library (Zarith)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    libev4 \
    libssl3 \
    libgmp10 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Create an unprivileged user for security
RUN groupadd -r app && useradd -r -g app app

# Copy compiled native binary directly with app user ownership (avoids duplicate layer)
COPY --chown=app:app --from=builder /home/opam/app/_build/default/bin/main.exe /app/menu_app

# Copy static assets (CSS, SVG illustrations, photos metadata)
COPY --chown=app:app --from=builder /home/opam/app/static /app/static

# Copy pre-warmed cache
COPY --chown=app:app --from=builder /home/opam/app/cache /app/cache

USER app

# Production environment defaults
ENV PORT=8080
EXPOSE 8080

# Volume mount point for persistent caching across restarts and redeployments
VOLUME ["/app/cache"]

# Start Dream native web server directly
CMD ["/app/menu_app"]
