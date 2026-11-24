FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/server .

FROM alpine:3.21
RUN apk --no-cache add ca-certificates && addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=build /out/server /app/server
COPY schema.sql /app/schema.sql
COPY web /app/web
COPY web-vk /app/web-vk
COPY web-ok /app/web-ok
# Pre-compress the small assets that are present in the build context. The two
# large files are fetched at runtime when the context drops them.
RUN cd /app/web && for f in index.wasm index.js index.html; do \
        [ -f "$f" ] && gzip -9 -c "$f" > "$f.gz"; \
    done; true
# RelaxDev's build context silently drops files above ~20 MB, so the server
# downloads and caches index.wasm/index.pck from the published build on first
# start. This keeps the image build reliable and players still download from
# this host at full speed.
ENV WEB_ORIGIN=https://raw.githubusercontent.com/Darones/three-skies-server/main/server/web,https://ghproxy.net/https://raw.githubusercontent.com/Darones/three-skies-server/main/server/web
ENV WEB_VK_ORIGIN=https://raw.githubusercontent.com/Darones/three-skies-server/main/server/web-vk,https://ghproxy.net/https://raw.githubusercontent.com/Darones/three-skies-server/main/server/web-vk
ENV WEB_OK_ORIGIN=https://raw.githubusercontent.com/Darones/three-skies-server/main/server/web-ok,https://ghproxy.net/https://raw.githubusercontent.com/Darones/three-skies-server/main/server/web-ok
ENV PORT=8080
ENV WEB_DIR=/app/web
ENV WEB_VK_DIR=/app/web-vk
ENV WEB_OK_DIR=/app/web-ok
RUN chown -R app:app /app/web /app/web-vk /app/web-ok
USER app
EXPOSE 8080
ENTRYPOINT ["/app/server"]
