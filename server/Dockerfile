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
# Pre-compress the big text assets so players download ~10 MB of wasm instead
# of 39 MB. Runtime gzip of a 39 MB file per request would burn the CPU.
RUN cd /app/web && for f in index.wasm index.js index.html index.pck; do \
        [ -f "$f" ] && gzip -9 -c "$f" > "$f.gz"; \
    done; true
ENV PORT=8080
ENV WEB_DIR=/app/web
USER app
EXPOSE 8080
ENTRYPOINT ["/app/server"]
