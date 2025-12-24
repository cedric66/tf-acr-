# Build stage: Use standard Maven image to build the Spring Boot application
FROM maven:3.9-eclipse-temurin-17 as builder

WORKDIR /app
COPY pom.xml .
COPY src src

# Build the application skipping tests to speed up the process
RUN mvn clean package -DskipTests

# Runtime stage: Use Chainguard JRE for a secure, minimal runtime image
FROM cgr.dev/chainguard/jre:latest

WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar

CMD ["java", "-jar", "app.jar"]
