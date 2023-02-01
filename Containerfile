FROM klakegg/hugo:0.107.0-ext AS build

# The source files are copied to /src
COPY . /src
WORKDIR /src

# And then we just run Hugo
RUN hugo --minify --enableGitInfo

FROM nginx:latest
COPY --from=build /src/public /usr/share/nginx/html
