FROM golang:1.24.3 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG GIT_COMMIT=dev
RUN CGO_ENABLED=0 go build -ldflags "-X github.com/mathiazom/innbo/backend/internal/httpapi.Version=${GIT_COMMIT}" -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12
COPY --from=build /out/server /server
ENTRYPOINT ["/server"]
