ARG BUILD_IMAGE=golang:1.21-alpine
ARG RUN_IMAGE=gcr.io/distroless/static:nonroot

FROM ${BUILD_IMAGE} as build

WORKDIR /work
COPY main.go .
RUN go build -o app main.go

FROM ${RUN_IMAGE}
COPY --from=build /work/app /app
EXPOSE 8080
CMD ["/app"]
