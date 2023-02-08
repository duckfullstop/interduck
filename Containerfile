FROM floryn90/hugo:0.110.0-ext AS build

# The source files are copied to /src
COPY . /src
WORKDIR /src

# And then we just run Hugo
ARG HUGO_ENV=production
RUN hugo --minify --enableGitInfo -e ${HUGO_ENV}

FROM nginx:alpine-slim
COPY --from=build /src/public /usr/share/nginx/html
