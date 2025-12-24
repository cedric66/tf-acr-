ARG BUILD_IMAGE=cgr.dev/chainguard/go:latest
ARG RUN_IMAGE=cgr.dev/chainguard/static:latest

FROM ${BUILD_IMAGE} as build

WORKDIR /work
COPY main.go .
RUN go build -o app main.go

FROM ${RUN_IMAGE}
COPY --from=build /work/app /app
EXPOSE 8080
CMD ["/app"]
