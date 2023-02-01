FROM alpine:3.17 AS build

# We add git to the build stage, because Hugo needs it with --enableGitInfo
RUN apk add --no-cache go git

# The Hugo version
ARG VERSION=0.110.0

RUN go install -tags extended github.com/gohugoio/hugo@v${VERSION}
RUN hugo version

# The source files are copied to /site
COPY . /site
WORKDIR /site

# And then we just run Hugo
RUN /hugo --minify --enableGitInfo

FROM nginxinc/nginx-unprivileged
COPY --from=build /site/public /usr/share/nginx/html
