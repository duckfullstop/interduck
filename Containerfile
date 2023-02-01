FROM alpine:3.17 AS build

# We add git to the build stage, because Hugo needs it with --enableGitInfo
RUN apk add --no-cache hugo git

# The source files are copied to /site
COPY . /site
WORKDIR /site

# And then we just run Hugo
RUN /hugo --minify --enableGitInfo

FROM nginxinc/nginx-unprivileged
COPY --from=build /site/public /usr/share/nginx/html
