# syntax=docker/dockerfile:1.7-labs

FROM node as builder

WORKDIR /sources/Viewers

COPY package.json yarn.lock preinstall.js lerna.json ./
COPY --parents ./addOns/package.json ./addOns/*/*/package.json ./extensions/*/package.json ./modes/*/package.json ./platform/*/package.json ./

RUN yarn install --frozen-lockfile --verbose

ENV QUICK_BUILD=true
# ENV GENERATE_SOURCEMAP=false
# ENV REACT_APP_CONFIG=config/default.js
RUN yarn install
COPY --link --exclude=yarn.lock --exclude=package.json --exclude=Dockerfile . .

RUN QUICK_BUILD=true PUBLIC_URL=/ohif/ yarn run build

# Stage 3: Bundle the built application into a Docker container
# which runs Nginx using Alpine Linux
FROM nginx as final
COPY .docker/ohif/ohif-static.conf /etc/nginx/enabled-sites/
ADD .docker/ohif/ohif-nginx-http.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /sources/Viewers/platform/app/dist /usr/share/nginx/html/
COPY .docker/ohif/default-app-config.js /usr/share/nginx/html/app-config.js
