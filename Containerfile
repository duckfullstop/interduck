FROM floryn90/hugo:0.142.0-ext-alpine-ci AS build

# Get dart-sass
RUN apk add --no-cache dart-sass

# The source files are copied to /src
COPY . /src
WORKDIR /src

# And then we just run Hugo
RUN hugo --minify --enableGitInfo -e ${HUGO_ENV}

FROM nginx:alpine-slim
COPY --from=build /src/public /usr/share/nginx/html
