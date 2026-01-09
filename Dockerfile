# syntax=docker/dockerfile:1.7-labs

############################
# Stage 1: Build (static)
############################
FROM node:20.18.1-slim AS builder

# Dependencias nativas mínimas para builds (node-gyp, etc.)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      python3 \
      ca-certificates \
      git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

# Versiones fijas
RUN npm install -g bun@1.2.23 lerna@7.4.2

# Variables de build
ARG PUBLIC_URL=/
ENV PUBLIC_URL=${PUBLIC_URL}

# OHIF suele soportar APP_CONFIG; lo dejamos disponible
ARG APP_CONFIG=config/default.js
ENV APP_CONFIG=${APP_CONFIG}

# 1) Copia solo manifests/locks primero para maximizar caché
COPY package.json yarn.lock preinstall.js lerna.json ./

# Monorepo manifests (BuildKit --parents)
COPY --parents \
  ./addOns/package.json \
  ./addOns/*/*/package.json \
  ./extensions/*/package.json \
  ./modes/*/package.json \
  ./platform/*/package.json \
  ./

# 2) Instala deps con caché de Bun
#    (si tu repo usa yarn.lock, bun lo puede respetar; --frozen-lockfile exige consistencia)
RUN --mount=type=cache,target=/root/.bun \
    bun install --frozen-lockfile

# OPCIÓN A (recomendada): Ajv debe estar en package.json (NO hacer bun add aquí)
# Si aún no puedes modificar package.json, deja la opción B:

# OPCIÓN B (temporal): forzar Ajv, pero esto puede tocar lockfile en algunos casos
# RUN --mount=type=cache,target=/root/.bun \
#     bun add ajv@8.12.0

# 3) Copia el resto del repo (código)
COPY --link . .

# Build
ENV QUICK_BUILD=true
RUN bun run show:config
RUN bun run build

# Precompress (si lo necesitas)
RUN chmod u+x .docker/compressDist.sh && ./.docker/compressDist.sh


############################
# Stage 2: Runtime (nginx)
############################
FROM nginxinc/nginx-unprivileged:1.27-alpine AS final

# Puerto interno típico del unprivileged (proxy apunta a este)
ARG PORT=8080
ENV PORT=${PORT}

ARG PUBLIC_URL=/
ENV PUBLIC_URL=${PUBLIC_URL}

# Si usas config propia de nginx dentro de la imagen (según tu .docker/Viewer-v3.x)
# eliminamos default de nginx
RUN rm -f /etc/nginx/conf.d/default.conf

# Copiamos scripts/config del viewer (tu entrypoint)
USER nginx
COPY --chown=nginx:nginx .docker/Viewer-v3.x /usr/src
RUN chmod 755 /usr/src/entrypoint.sh

# Copiamos el build del viewer
COPY --from=builder --chown=nginx:nginx \
  /usr/src/app/platform/app/dist \
  /usr/share/nginx/html${PUBLIC_URL}

# Microscopy (dependencia a nivel root)
COPY --from=builder --chown=nginx:nginx \
  /usr/src/app/platform/app/dist/dicom-microscopy-viewer \
  /usr/share/nginx/html/dicom-microscopy-viewer

# (Opcional pero recomendado) “Hornear” tu app-config.js dentro de la imagen
# para NO depender de volume mounts ni permisos:
# COPY --chown=nginx:nginx app-config.js /usr/share/nginx/html/app-config.js

# Permisos mínimos (evita 777). Ajusta si tu entrypoint necesita escribir algo:
USER root
RUN chown -R nginx:nginx /usr/share/nginx/html \
    && chmod -R u=rwX,g=rX,o=rX /usr/share/nginx/html
USER nginx

ENTRYPOINT ["/usr/src/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
