FROM ghcr.io/hugomods/hugo:dart-sass-go-git-0.142.0 AS build

ARG HUGO_ENV=production
ENV HUGO_ENV=${HUGO_ENV}

# The source files are copied to /src
COPY . /src
WORKDIR /src

# And then we just run Hugo
RUN hugo --minify --enableGitInfo

FROM nginx:alpine-slim
COPY --from=build /src/public /usr/share/nginx/html
