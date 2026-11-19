# UltiRace game server (GAME_PLAN §7.1). Build from the repo root:
#   docker build -f deploy/Dockerfile -t ultirace-server:latest .
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /out/server ./cmd/server

FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/server /server
USER nonroot:nonroot
EXPOSE 8090
ENV ADDR=0.0.0.0:8090 DATA_DIR=/data
ENTRYPOINT ["/server"]
