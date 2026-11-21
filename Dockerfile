# Fallback build for platforms whose Build Context is the repository root.
# The canonical file is server/Dockerfile (Build Context: server).
# Keep both in sync.
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/*.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/server .

FROM alpine:3.21
RUN apk --no-cache add ca-certificates && addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=build /out/server /app/server
COPY server/schema.sql /app/schema.sql
COPY server/web /app/web
# RelaxDev's build context silently drops the two files above ~20 MB, so fetch
# them from the same repository when they are missing. The Go build stage
# already proves outbound HTTPS works.
RUN cd /app/web && \
    for f in index.wasm index.pck; do \
        if [ ! -f "$f" ]; then \
            ( wget -q -T 60 -t 3 -O "$f.part" "https://raw.githubusercontent.com/Darones/three-skies-server/main/server/web/$f" || \
              wget -q -T 60 -t 3 -O "$f.part" "https://ghproxy.net/https://raw.githubusercontent.com/Darones/three-skies-server/main/server/web/$f" ) && \
            mv "$f.part" "$f" || exit 1; \
        fi; \
    done
RUN cd /app/web && for f in index.wasm index.js index.html index.pck; do \
        [ -f "$f" ] && gzip -9 -c "$f" > "$f.gz"; \
    done; true
ENV PORT=8080
ENV WEB_DIR=/app/web
USER app
EXPOSE 8080
ENTRYPOINT ["/app/server"]
