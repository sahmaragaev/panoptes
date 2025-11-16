FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /tenant-notifier .

FROM alpine:3.23
RUN apk add --no-cache ca-certificates wget
COPY --from=build /tenant-notifier /tenant-notifier
EXPOSE 5002
ENTRYPOINT ["/tenant-notifier"]
