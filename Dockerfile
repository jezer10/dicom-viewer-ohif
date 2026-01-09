# syntax=docker/dockerfile:1.7-labs

############################
# Stage 1: Build (OHIF static)
############################
FROM node:20.18.1-slim AS builder

# Dependencias nativas (algunos paquetes pueden requerir node-gyp)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential python3 git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /sources/Viewers

# Para builds más rápidos en OHIF
ENV QUICK_BUILD=true

# PUBLIC_URL debe coincidir con cómo lo sirves detrás del proxy.
# Para tu entorno actual (proxy sirve OHIF en "/"), déjalo en "/".
ARG PUBLIC_URL=/
ENV PUBLIC_URL=${PUBLIC_URL}

# 1) Copiamos manifests para maximizar cache
COPY package.json yarn.lock preinstall.js lerna.json ./
COPY --parents \
  ./addOns/package.json \
  ./addOns/*/*/package.json \
  ./extensions/*/package.json \
  ./modes/*/package.json \
  ./platform/*/package.json \
  ./

# 2) Install determinístico
RUN corepack enable && yarn install --frozen-lockfile --verbose

# 3) Copiamos el resto del repo
COPY --link . .

# 4) Build
RUN yarn run build


############################
# Stage 2: Runtime (nginx)
############################
FROM nginx:1.27-alpine AS final

# Si tu config de nginx incluye enabled-sites, lo creamos
RUN mkdir -p /etc/nginx/enabled-sites

# Configs nginx del OHIF (las mismas rutas que tu Dockerfile)
COPY .docker/ohif/ohif-static.conf /etc/nginx/enabled-sites/ohif-static.conf
COPY .docker/ohif/ohif-nginx-http.conf /etc/nginx/conf.d/default.conf

# Build output
COPY --from=builder /sources/Viewers/platform/app/dist/ /usr/share/nginx/html/

# TU app-config (obligatorio según tu requerimiento)
COPY app-config.js /usr/share/nginx/html/app-config.js

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
