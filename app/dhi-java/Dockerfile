ARG BUILD_IMAGE=maven:3.9-eclipse-temurin-17
ARG RUN_IMAGE=gcr.io/distroless/java17-debian12:nonroot

# Build stage
FROM ${BUILD_IMAGE} as builder

WORKDIR /app
COPY pom.xml .
COPY src src

# Build the application skipping tests to speed up the process
RUN mvn clean package -DskipTests

# Runtime stage
FROM ${RUN_IMAGE}

WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar

EXPOSE 8080
CMD ["app.jar"]
