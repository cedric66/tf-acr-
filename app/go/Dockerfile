FROM cgr.dev/chainguard/go:latest as build

WORKDIR /work
COPY main.go .
RUN go build -o app main.go

FROM cgr.dev/chainguard/static:latest
COPY --from=build /work/app /app
CMD ["/app"]
