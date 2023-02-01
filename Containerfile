FROM --platform=$BUILDPLATFORM alpine:3.17 as build
RUN apk add --no-cache hugo
WORKDIR /src
COPY . .
RUN --mount=type=cache,target=/tmp/hugo_cache \
    hugo

FROM nginxinc/nginx-unprivileged
COPY --from=build /src/public /usr/share/nginx/html
