# syntax=docker/dockerfile:1.7-labs

############################
# Stage 1: Build
############################
FROM node:20.18.1-slim AS builder

WORKDIR /sources/Viewers

# 1) Copia manifests primero para cache
COPY package.json yarn.lock preinstall.js lerna.json ./
COPY --parents \
  ./addOns/package.json \
  ./addOns/*/*/package.json \
  ./extensions/*/package.json \
  ./modes/*/package.json \
  ./platform/*/package.json \
  ./

# 2) Instala deps (1 sola vez)
RUN --mount=type=cache,target=/usr/local/share/.cache/yarn,sharing=locked \
    corepack enable && \
    yarn install --frozen-lockfile --verbose

# 3) Copia el resto del repo
COPY --link . .

# 4) Build con PUBLIC_URL (para tu proxy actual: "/")
ARG PUBLIC_URL=/
ENV QUICK_BUILD=true
ENV PUBLIC_URL=${PUBLIC_URL}
RUN yarn run build


############################
# Stage 2: Runtime (nginx)
############################
FROM nginx:1.27-alpine AS final

# Config nginx del OHIF (tal cual tu Dockerfile)
# Nota: nginx oficial no usa "enabled-sites" por defecto, pero no molesta tenerlo.
RUN mkdir -p /etc/nginx/enabled-sites
COPY .docker/ohif/ohif-static.conf /etc/nginx/enabled-sites/ohif-static.conf
COPY .docker/ohif/ohif-nginx-http.conf /etc/nginx/conf.d/default.conf

# Archivos estáticos del build
COPY --from=builder /sources/Viewers/platform/app/dist/ /usr/share/nginx/html/

# app-config por defecto (lo puedes pisar con volumen)
COPY .docker/ohif/default-app-config.js /usr/share/nginx/html/app-config.js

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
