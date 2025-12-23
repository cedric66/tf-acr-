# Use Chainguard JDK for build
FROM cgr.dev/chainguard/jdk:latest as build

WORKDIR /app
COPY pom.xml .
COPY src src

# Build the application
# Using mvnw if available would be better, but assuming maven is present or we use the jdk image which typically has it?
# Actually chainguard/jdk is just the JDK.
# Let's use a maven image for build or install maven.
# Easier: Use maven wrapper or just simple maven command if available.
# Chainguard jdk image might not have maven.
# Let's use cgr.dev/chainguard/maven if it exists, or standard maven.
# Safe bet: standard maven image for build stage, then chainguard jre for run.

FROM maven:3.9-eclipse-temurin-17 as builder
WORKDIR /app
COPY pom.xml .
COPY src src
RUN mvn clean package -DskipTests

# Runtime stage using Chainguard JRE
FROM cgr.dev/chainguard/jre:latest

WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar

CMD ["java", "-jar", "app.jar"]
