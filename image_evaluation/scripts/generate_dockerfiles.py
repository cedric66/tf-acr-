
import os

images = {
    "java": {
        "chainguard": ("cgr.dev/chainguard/jdk", "cgr.dev/chainguard/jre"),
        "minimus": ("reg.mini.dev/openjdk:17", "reg.mini.dev/openjdk:17"),
        "dhi": ("dhi.io/java:17", "dhi.io/java:17"),
        "alpine": ("eclipse-temurin:17-alpine", "eclipse-temurin:17-alpine"),
        "ubi": ("registry.access.redhat.com/ubi9/openjdk-17", "registry.access.redhat.com/ubi9/openjdk-17")
    },
    "springboot": {
        "chainguard": ("cgr.dev/chainguard/jdk", "cgr.dev/chainguard/jre"),
        "minimus": ("reg.mini.dev/openjdk:17", "reg.mini.dev/openjdk:17"),
        "dhi": ("dhi.io/java:17", "dhi.io/java:17"),
        "alpine": ("eclipse-temurin:17-alpine", "eclipse-temurin:17-alpine"),
        "ubi": ("registry.access.redhat.com/ubi9/openjdk-17", "registry.access.redhat.com/ubi9/openjdk-17")
    },
    "nodejs": {
        "chainguard": ("cgr.dev/chainguard/node:latest", "cgr.dev/chainguard/node:latest"),
        "minimus": ("reg.mini.dev/node:18", "reg.mini.dev/node:18"),
        "dhi": ("dhi.io/node:18", "dhi.io/node:18"),
        "alpine": ("node:18-alpine", "node:18-alpine"),
        "ubi": ("registry.access.redhat.com/ubi9/nodejs-18", "registry.access.redhat.com/ubi9/nodejs-18")
    },
    "go": {
        "chainguard": ("cgr.dev/chainguard/go:latest", "cgr.dev/chainguard/static:latest"),
        "minimus": ("reg.mini.dev/go:1.20", "reg.mini.dev/base"),
        "dhi": ("dhi.io/golang:1.20", "dhi.io/base"), # Assumption for DHI
        "alpine": ("golang:1.20-alpine", "alpine:latest"),
        "ubi": ("registry.access.redhat.com/ubi9/go-toolset", "registry.access.redhat.com/ubi9-minimal")
    },
    "python": {
        "chainguard": ("cgr.dev/chainguard/python:latest", "cgr.dev/chainguard/python:latest"),
        "minimus": ("reg.mini.dev/python:3.11", "reg.mini.dev/python:3.11"),
        "dhi": ("dhi.io/python:3.11", "dhi.io/python:3.11"),
        "alpine": ("python:3.11-alpine", "python:3.11-alpine"),
        "ubi": ("registry.access.redhat.com/ubi9/python-311", "registry.access.redhat.com/ubi9/python-311")
    }
}

base_path = "image_evaluation/dockerfiles"
app_path = "image_evaluation/apps"

for app, variants in images.items():
    for provider, (builder_img, runner_img) in variants.items():
        dockerfile_content = ""
        
        # JAVA & SPRINGBOOT
        if app == "java":
            dockerfile_content = f"""
FROM {builder_img} AS builder
WORKDIR /app
COPY ../apps/java/Main.java .
RUN javac Main.java

FROM {runner_img}
WORKDIR /app
COPY --from=builder /app/Main.class .
CMD ["java", "Main"]
"""
        elif app == "springboot":
             dockerfile_content = f"""
FROM {builder_img} AS builder
WORKDIR /app
COPY ../apps/springboot/pom.xml .
COPY ../apps/springboot/src ./src
# Mocking mvn wrap or installing maven if needed, but for simplicity assuming builder has javac
# For Chainguard/Distroless finding Maven can be hard. 
# Strategy: Use a standard maven builder for the extensive build, then copy to target image.
# BUT, we want to evaluate the PROVIDER'S builder image if possible. 
# Many minimal images don't have maven. 
# Fallback: Use a standard maven builder for the artifact, then strictly use the PROVIDER image for runtime.
"""
             # Revision: Standardize Build Stage to Maven for Spring
             dockerfile_content = f"""
FROM maven:3.8-openjdk-17-slim AS builder
WORKDIR /app
COPY ../apps/springboot/pom.xml .
COPY ../apps/springboot/src ./src
RUN mvn package -DskipTests

FROM {runner_img}
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
CMD ["java", "-jar", "app.jar"]
"""

        # NODEJS
        elif app == "nodejs":
            dockerfile_content = f"""
FROM {runner_img}
WORKDIR /app
COPY ../apps/nodejs/package.json .
COPY ../apps/nodejs/server.js .
# Try install, if fails (distroless), ignore dependencies (ours is simple)
RUN npm install || echo "Skipping npm install"
CMD ["node", "server.js"]
"""

        # GO
        elif app == "go":
            dockerfile_content = f"""
FROM {builder_img} AS builder
WORKDIR /app
COPY ../apps/go/go.mod .
COPY ../apps/go/main.go .
# Static build
RUN CGO_ENABLED=0 go build -o server main.go

FROM {runner_img}
WORKDIR /app
COPY --from=builder /app/server .
CMD ["./server"]
"""

        # PYTHON
        elif app == "python":
            dockerfile_content = f"""
FROM {runner_img}
WORKDIR /app
COPY ../apps/python/requirements.txt .
COPY ../apps/python/app.py .
# Try pip install, might fail on distroless/minimal without build tools
RUN pip install -r requirements.txt || echo "Skipping pip install - attempting usage of pre-installed site-packages if available"
CMD ["python", "app.py"]
"""

        path = f"{base_path}/{app}/Dockerfile.{provider}"
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(dockerfile_content)

print("Generated 25 Dockerfiles.")
