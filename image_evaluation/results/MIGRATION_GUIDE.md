# Migration Guide: Alpine/UBI/Debian → Chainguard/Minimus/DHI

## Overview

This guide provides step-by-step instructions for migrating containerized applications from traditional Linux distributions (Alpine, UBI, Debian) to hardened, distroless alternatives (Chainguard, Minimus, DHI).

---

## 1. Migration Tools

### Chainguard: `dfc` (Dockerfile Converter)

**Installation:**
```bash
# Using Homebrew
brew install chainguard-dev/tap/dfc

# Or download from GitHub
# https://github.com/chainguard-dev/dfc
```

**Usage:**
```bash
# Convert a Dockerfile
dfc path/to/Dockerfile

# Save converted output
dfc path/to/Dockerfile > Dockerfile.chainguard
```

### Minimus: Manual Migration with `-dev` Images

Minimus doesn't provide an automated tool but uses a two-phase approach:
1. Use `-dev` variant for build stage (includes shell + package manager)
2. Use production variant for runtime (distroless)

### DHI: Docker AI Assistant

Docker provides an AI assistant for migration:
1. Visit [Docker Hub](https://hub.docker.com)
2. Use the migration wizard
3. Follow interactive guidance

---

## 2. Migration Patterns by Language

### Node.js

**Original (Alpine):**
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["node", "server.js"]
```

**Migrated (Chainguard):**
```dockerfile
FROM cgr.dev/chainguard/node:latest-dev
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["node", "server.js"]
```

**Migrated (Minimus):**
```dockerfile
FROM reg.mini.dev/node:18-dev AS builder
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .

FROM reg.mini.dev/node:18
WORKDIR /app
COPY --from=builder /app .
CMD ["node", "server.js"]
```

**Migrated (DHI):**
```dockerfile
FROM dhi.io/node:25-debian13-sfw-ent-dev
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["node", "server.js"]
```

---

### Spring Boot / Java

**Original (Alpine):**
```dockerfile
FROM maven:3.8-openjdk-17-slim AS builder
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn package -DskipTests

FROM openjdk:17-alpine
COPY --from=builder /app/target/*.jar app.jar
CMD ["java", "-jar", "app.jar"]
```

**Migrated (Chainguard):**
```dockerfile
FROM cgr.dev/chainguard/maven:latest-dev AS builder
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn package -DskipTests

FROM cgr.dev/chainguard/jre:latest
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
CMD ["java", "-jar", "app.jar"]
```

**Migrated (DHI):**
```dockerfile
FROM maven:3.8-openjdk-17-slim AS builder
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn package -DskipTests

FROM dhi.io/amazoncorretto:8-alpine3.22-dev
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
CMD ["java", "-jar", "app.jar"]
```

---

### Python

**Original (Alpine):**
```dockerfile
FROM python:3.11-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "app.py"]
```

**Migrated (Chainguard):**
```dockerfile
FROM cgr.dev/chainguard/python:latest-dev
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "app.py"]
```

**Migrated (DHI):**
```dockerfile
FROM dhi.io/python:3-debian13-sfw-ent-dev
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "app.py"]
```

---

### Go

**Original (Alpine):**
```dockerfile
FROM golang:1.20-alpine AS builder
WORKDIR /app
COPY go.mod .
COPY main.go .
RUN CGO_ENABLED=0 go build -o server main.go

FROM alpine:latest
COPY --from=builder /app/server .
CMD ["./server"]
```

**Migrated (Chainguard):**
```dockerfile
FROM cgr.dev/chainguard/go:latest-dev AS builder
WORKDIR /app
COPY go.mod .
COPY main.go .
RUN CGO_ENABLED=0 go build -o server main.go

FROM cgr.dev/chainguard/static:latest
COPY --from=builder /app/server .
CMD ["./server"]
```

**Migrated (DHI):**
```dockerfile
FROM dhi.io/golang:1-debian13-sfw-ent-dev AS builder
WORKDIR /app
COPY go.mod .
COPY main.go .
RUN CGO_ENABLED=0 go build -o server main.go

FROM dhi.io/golang:1-debian13-sfw-ent-dev
COPY --from=builder /app/server .
CMD ["./server"]
```

---

## 3. Key Considerations

### LibC Compatibility

| Base | LibC | Migration Notes |
|------|------|-----------------|
| Alpine | musl | May have compat issues with glibc binaries |
| Chainguard | glibc | Full glibc compat, smooth migration |
| Minimus | glibc | Full glibc compat |
| DHI | glibc/musl | Depends on variant |
| UBI | glibc | RHEL glibc |

**Recommendation:** Moving FROM Alpine (musl) TO Chainguard/DHI (glibc) is generally safe. Reverse may break pre-compiled binaries.

### musl → glibc Break Scenario (Documented Test)

**Scenario**: Build binary on Alpine (musl), run on Chainguard (glibc)

```bash
# Build dynamically linked binary on Alpine (musl)
docker run --rm golang:1.20-alpine sh -c "go build -o hello main.go"
# Output: ELF 64-bit, interpreter /lib/ld-musl-x86_64.so.1

# Try to run on glibc-based Chainguard - WILL FAIL
docker run --rm cgr.dev/chainguard/wolfi-base /app/hello
# Error: /lib/ld-musl-x86_64.so.1: No such file or directory
```

**Why it breaks**: The musl dynamic linker (`ld-musl`) doesn't exist on glibc systems.

**Solutions**:
1. **Static linking**: `CGO_ENABLED=0 go build`
2. **Build on target**: Use Chainguard/DHI build images
3. **Multi-stage**: Build and run on same base family

### Package Manager Differences

| Distro | Package Manager | Available in Prod? | Available in -dev? |
|--------|-----------------|-------------------|-------------------|
| Alpine | apk | ✅ Yes | ✅ Yes |
| Chainguard | apk (Wolfi) | ❌ No | ✅ Yes |
| Minimus | apk | ❌ No | ✅ Yes |
| DHI | apt/apk | ⚠️ Depends | ✅ Yes |
| UBI | microdnf/yum | ✅ Yes | ✅ Yes |

### Shell Access

| Provider | Production Image | -dev Image |
|----------|------------------|------------|
| Chainguard | ❌ No shell | ✅ /bin/sh |
| Minimus | ❌ No shell | ✅ /bin/sh |
| DHI | ✅ /bin/sh | ✅ /bin/sh |
| Alpine | ✅ /bin/sh | ✅ /bin/sh |
| UBI | ✅ /bin/bash | ✅ /bin/bash |

---

## 4. Common Package Mappings (Extended)

| Alpine | Chainguard (Wolfi) | DHI (Debian) | UBI (RHEL) |
|--------|-------------------|--------------|------------|
| curl | curl | curl | curl |
| git | git | git | git-core |
| openssl | openssl | openssl | openssl |
| ca-certificates | ca-certificates-bundle | ca-certificates | ca-certificates |
| bash | bash | bash | bash |
| jq | jq | jq | jq |
| wget | wget | wget | wget |
| tar | tar | tar | tar |
| gzip | gzip | gzip | gzip |
| make | make | make | make |
| gcc | gcc | gcc | gcc |
| g++ | gcc-c++ | g++ | gcc-c++ |
| python3 | python-3 | python3 | python3 |
| nodejs | nodejs | nodejs | nodejs |
| npm | nodejs | npm | npm |
| openjdk | openjdk | default-jdk | java-17-openjdk |

---

## 5. Testing Checklist by Language and Vendor

### Java / Spring Boot

| Test | Chainguard | Minimus | DHI | Alpine | UBI |
|------|------------|---------|-----|--------|-----|
| **App starts correctly** | ✅ `java -jar app.jar` | ✅ | ✅ | ✅ | ✅ |
| **Dependencies installed** | ✅ Maven/Gradle in -dev | ✅ | ✅ | ✅ | ✅ |
| **Networking (curl)** | ⚠️ Add curl in -dev | ⚠️ | ✅ | ✅ | ✅ |
| **Non-root user** | ✅ Default | ✅ | ✅ | ⚠️ Manual | ✅ |
| **Health checks** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Vuln scan improved** | ✅ 0 CVEs | ✅ 0 CVEs | ✅ 0 CVEs | ⚠️ 28 High | ❌ 37 High |
| **Image size** | 301 MB | 370 MB | **199 MB** | 317 MB | 389 MB |
| **SBOM generated** | ✅ | ✅ | ✅ | ✅ | ✅ |

### Node.js

| Test | Chainguard | Minimus | DHI | Alpine | UBI |
|------|------------|---------|-----|--------|-----|
| **App starts correctly** | ✅ `node server.js` | ❌ Build failed | ✅ | ✅ | ✅ |
| **Dependencies installed** | ✅ npm in -dev | - | ✅ | ✅ | ✅ |
| **Networking (curl)** | ⚠️ Add curl | - | ✅ | ✅ | ✅ |
| **Non-root user** | ✅ Default | - | ✅ | ⚠️ Manual | ✅ |
| **Health checks** | ✅ | - | ✅ | ✅ | ✅ |
| **Vuln scan improved** | ✅ 0 CVEs | - | ⚠️ 50 High | ⚠️ 9 High | ❌ 833 High |
| **Image size** | **155 MB** | - | 497 MB | 128 MB | 572 MB |
| **SBOM generated** | ✅ | - | ✅ | ✅ | ✅ |

### Python

| Test | Chainguard | Minimus | DHI | Alpine | UBI |
|------|------------|---------|-----|--------|-----|
| **App starts correctly** | ✅ (migrated) | ❌ | ✅ | ✅ | ✅ |
| **Dependencies installed** | ✅ pip in -dev | - | ✅ | ✅ | ✅ |
| **Networking (curl)** | ⚠️ Add curl | - | ✅ | ✅ | ✅ |
| **Non-root user** | ✅ Default | - | ✅ | ⚠️ Manual | ✅ |
| **Health checks** | ✅ | - | ✅ | ✅ | ✅ |
| **Vuln scan improved** | ✅ 0 CVEs | - | ⚠️ 14 High | ⚠️ 0 High | ❌ 743 High |
| **Image size** | 1860 MB (-dev) | - | 241 MB | **67 MB** | 1034 MB |
| **SBOM generated** | ✅ | - | ✅ | ✅ | ✅ |

### Go

| Test | Chainguard | Minimus | DHI | Alpine | UBI |
|------|------------|---------|-----|--------|-----|
| **App starts correctly** | ✅ Static binary | ❌ | ❌ | ✅ | ✅ |
| **Dependencies installed** | ✅ go in -dev | - | - | ✅ | ✅ |
| **Networking (curl)** | ❌ Static only | - | - | ✅ | ✅ |
| **Non-root user** | ✅ Default | - | - | ⚠️ Manual | ✅ |
| **Health checks** | ✅ | - | - | ✅ | ✅ |
| **Vuln scan improved** | ✅ 0 CVEs | - | - | ⚠️ 12 High | ⚠️ 14 High |
| **Image size** | **9.66 MB** | - | - | 14 MB | 108 MB |
| **SBOM generated** | ✅ | - | - | ✅ | ⚠️ |

---

## 6. SBOM-Based Package Mapping

When migrating, use SBOM analysis to identify required packages:

```bash
# Generate SBOM for source image
docker sbom source-image:tag --format spdx-json > source_sbom.json

# Extract package names
jq '.packages[].name' source_sbom.json | sort | uniq

# Compare with target image
docker sbom target-image:tag --format spdx-json > target_sbom.json
jq '.packages[].name' target_sbom.json | sort | uniq

# Find missing packages
comm -23 <(jq -r '.packages[].name' source_sbom.json | sort | uniq) \
         <(jq -r '.packages[].name' target_sbom.json | sort | uniq)
```

---

## 7. Rollback Plan

Always maintain the original Dockerfile:

```bash
# Keep both versions
Dockerfile.alpine    # Original
Dockerfile.chainguard # Migrated

# Quick rollback
docker build -t myapp:rollback -f Dockerfile.alpine .
```

---

## 8. Resources

- [Chainguard DFC Tool](https://github.com/chainguard-dev/dfc)
- [Chainguard Images Catalog](https://images.chainguard.dev)
- [Minimus Documentation](https://minimus.io/docs)
- [Docker Hardened Images](https://docs.docker.com/hardened-images/)
- [Wolfi OS Package Search](https://packages.wolfi.dev)
