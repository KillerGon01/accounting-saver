# syntax=docker/dockerfile:1

#######################################################################
# 1) Build: compila la app web con el mismo Flutter que el CI
#    (.github/workflows/ci.yml, FLUTTER_VERSION) y que el entorno local.
#
# Ninguna imagen de Docker (oficial ni de comunidad) tenía todavía esta
# versión al escribir esto (10/10/2026): ghcr.io/cirruslabs/flutter llega
# como mucho a 3.44.0, instrumentisto/flutter a 3.41.6. En vez de fijar una
# versión distinta a la del CI, se instala el SDK a mano desde el archivo
# oficial de Google, con su sha256 real (releases_linux.json, no inventado)
# fijado abajo.
#
# Base: debian:bookworm-20261005-slim, una instantánea fechada (no la
# etiqueta "slim" sin fecha, que cambia sola con cada actualización de
# Debian), verificada tirando de ella de verdad el 10/10/2026
# (sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587).
#######################################################################
FROM debian:bookworm-20261005-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587 AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git xz-utils \
    && rm -rf /var/lib/apt/lists/*

# sha256 real de flutter_linux_3.47.6-stable.tar.xz, tomado de
# https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json
# (la fuente que publica Google, no un valor inventado aquí). Si se cambia
# FLUTTER_VERSION sin actualizar FLUTTER_SHA256, `sha256sum -c` hace que el
# build falle en vez de instalar un SDK sin comprobar.
ARG FLUTTER_VERSION=3.47.6
ARG FLUTTER_SHA256=f1631b9c2c8b3529323db412b0d1beacf4a748f8783b0d7cf599a8fd5f461675

RUN curl -fsSLo /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && tar -xf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory /opt/flutter

ENV PATH="/opt/flutter/bin:${PATH}"

RUN flutter config --no-analytics --no-cli-animations \
    && flutter precache --web

WORKDIR /app

# Argumentos de build de la IA: vacíos por defecto, nunca un valor real en
# este archivo ni en el repositorio (ver README.md, "Ejecución con
# Docker"). Con ENABLE_AI vacío, `bool.fromEnvironment` compila a false,
# igual que al ejecutar la app sin ningún --dart-define.
ARG ENABLE_AI=""
ARG RECAPTCHA_SITE_KEY=""

# pubspec.* antes del resto del código: si no cambian, Docker reutiliza la
# capa de `flutter pub get` entre builds.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release \
      --dart-define=ENABLE_AI="${ENABLE_AI}" \
      --dart-define=RECAPTCHA_SITE_KEY="${RECAPTCHA_SITE_KEY}"

#######################################################################
# 2) Servir: nginx sin privilegios (usuario no root, puerto 8080 — no
# privilegiado), verificado tirando de la imagen de verdad el 10/10/2026
# (sha256:15c994d10d6d78658721c3bcafff14cb281fba2a4bdf9d5ba92c416a472516e3).
#######################################################################
FROM nginxinc/nginx-unprivileged:1.30.5-alpine@sha256:15c994d10d6d78658721c3bcafff14cb281fba2a4bdf9d5ba92c416a472516e3

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 8080
