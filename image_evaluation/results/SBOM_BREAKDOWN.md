# SBOM Package Breakdown Analysis

## Overview

This document provides detailed Software Bill of Materials (SBOM) analysis for container images across all providers and languages.

---

## 1. Package Count Summary

| Image | Provider | Package Count | Category |
|-------|----------|---------------|----------|
| **go-chainguard** | Chainguard | ~10 | Minimal (Static) |
| **java-dhi** | DHI | 31 | Minimal |
| **python-alpine** | Alpine | ~50 | Small |
| **nodejs-alpine** | Alpine | ~60 | Small |
| **java-chainguard** | Chainguard | 6,099 | Medium |
| **java-minimus** | Minimus | 6,965 | Medium |
| **python-dhi** | DHI | 2,957 | Medium |
| **java-chainguard-dev** | Chainguard | 8,669 | Development |
| **java-minimus-dev** | Minimus | 12,055 | Development |
| **java-ubi** | UBI | 27,815 | Enterprise |

---

## 2. Java/JDK Images - Package Details

### DHI (dhi.io/amazoncorretto:8-alpine3.22-dev)
**Total Packages:** 31

| Package | Purpose |
|---------|---------|
| alpine-baselayout-data | Base filesystem layout |
| apk-tools | Package manager |
| busybox | Core utilities |
| ca-certificates-bundle | SSL certificates |
| libcrypto3 | OpenSSL crypto |
| libssl3 | OpenSSL SSL |
| musl | C library |
| pkgconf | Package config |
| **JDK modules:** | |
| jce | Java Crypto Extension |
| jfr | Java Flight Recorder |
| jsse | Java Secure Socket |
| nashorn | JavaScript engine |
| sunec | Elliptic curve crypto |
| tools | JDK tools |

### Chainguard (cgr.dev/chainguard/jdk)
**Total Packages:** ~6,099 (includes transitive)

**Key Categories:**
- Java runtime modules
- Wolfi base packages
- CA certificates
- glibc-based utilities

### UBI (ubi8/openjdk-17)
**Total Packages:** ~27,815

**Includes (but not limited to):**
- Full RHEL userspace
- systemd libraries
- Python runtime
- Perl modules
- Documentation
- Multiple language runtimes

---

## 3. Python Images - Package Details

### Alpine (python:3.11-alpine)
**Total Packages:** ~50

| Package | Purpose |
|---------|---------|
| .python-rundeps | Python runtime |
| alpine-baselayout | Base layout |
| alpine-keys | Package signing |
| apk-tools | Package manager |
| busybox | Core utilities |
| busybox-binsh | Shell |
| ca-certificates | SSL certs |
| gdbm | Database library |
| libffi | Foreign function interface |
| musl | C library |
| ncurses-terminfo-base | Terminal info |
| readline | Line editing |
| sqlite-libs | SQLite |
| zlib | Compression |
| **App packages:** | |
| Flask | Web framework |
| Jinja2 | Templating |
| Werkzeug | WSGI toolkit |
| click | CLI toolkit |
| blinker | Signals |

### DHI (dhi.io/python:3-debian13-sfw-ent-dev)
**Total Packages:** ~2,957

**Key additions over Alpine:**
- apt (Debian package manager)
- bash (full shell)
- coreutils (GNU utilities)
- dpkg (Debian package tools)
- gcc-14-base (compiler runtime)
- grep, findutils, diffutils
- libaudit (auditing)

---

## 4. Node.js Images - Package Details

### Alpine (node:18-alpine)
**Total Packages:** ~60

| Category | Packages |
|----------|----------|
| Runtime | nodejs, npm, libuv |
| Base | alpine-baselayout, busybox, musl |
| SSL | ca-certificates, libcrypto, libssl |
| Compression | brotli, zlib |
| DNS | c-ares |

### Chainguard (cgr.dev/chainguard/node)
**Total Packages:** ~150

**Additional over Alpine:**
- glibc (instead of musl)
- Wolfi base packages
- npm with full toolchain

---

## 5. Go Images - Package Details

### Chainguard Static (cgr.dev/chainguard/static)
**Total Packages:** ~5

This is the smallest possible runtime:
- ca-certificates-bundle
- tzdata (timezones)
- Static binary (no libc dependency)

### Alpine (golang:1.20-alpine + alpine runtime)
**Total Packages:** ~30

| Package | Purpose |
|---------|---------|
| alpine-baselayout | Base layout |
| busybox | Core utilities |
| musl | C library |
| ca-certificates | SSL certs |
| libc-utils | C library utilities |

---

## 6. Migrated Images - Size Comparison

| Image | Original (Alpine) | Migrated (Chainguard) | Delta |
|-------|-------------------|----------------------|-------|
| **Go** | 14.37 MB (15.1 MB) | **10.1 MB** | -33% ✅ |
| **Node.js** | 128 MB (134 MB) | 708 MB | +429% ⚠️ |
| **Python** | 67 MB (71 MB) | 1.86 GB | +2619% ⚠️ |
| **Spring Boot** | 336 MB | 335 MB | -0.3% ✅ |

**Notes:**
- Go benefits most from Chainguard static images
- Node.js/Python -dev images are larger (include build tools)
- For production, use non-dev Chainguard images

---

## 7. Package Type Analysis

### By Package Category

| Category | Alpine | Chainguard | DHI | UBI |
|----------|--------|------------|-----|-----|
| Base OS | 10-15 | 20-30 | 30-50 | 200+ |
| Runtime | 5-10 | 10-20 | 10-20 | 50+ |
| Dev Tools | 0 (prod) | 0 (prod) | 5-10 | 100+ |
| Documentation | 0 | 0 | 0 | 5000+ |
| Locales | 0 | 0 | 0 | 1000+ |

### LibC Comparison

| LibC | Size | Compatibility | Used By |
|------|------|---------------|---------|
| musl | Small | Limited | Alpine |
| glibc | Medium | Excellent | Chainguard, Minimus, DHI, UBI |

---

## 8. Security Considerations

### Fewer Packages = Smaller Attack Surface

| Provider | Packages | High CVEs | Risk Level |
|----------|----------|-----------|------------|
| DHI | 31 | 0 | ✅ Minimal |
| Chainguard | 6,099 | 0 | ✅ Low |
| Alpine | 50 | 28 | ⚠️ Medium |
| UBI | 27,815 | 59 | ❌ High |

### Package Update Frequency

| Provider | Update Cadence | SLA |
|----------|---------------|-----|
| Chainguard | Daily | Yes |
| Minimus | Daily | Yes |
| DHI | Weekly | Yes |
| Alpine | Variable | No |
| UBI | Monthly | Yes |

---

## 9. Recommendations

### For Go Applications
Use **Chainguard static** - only 5 packages, 10MB image

### For Java Applications
Use **DHI** - 31 packages, 210MB, 0 CVEs

### For Python Applications
Use **Alpine** for production (70MB) or **DHI** for enterprise

### For Node.js Applications
Use **Chainguard** production (not -dev) or **Alpine**

---

## 10. SBOM Generation Commands

```bash
# Generate SPDX SBOM
docker sbom <image> --format spdx-json > sbom.json

# Extract package names
jq -r '.packages[].name' sbom.json | sort | uniq

# Count packages
jq '.packages | length' sbom.json

# Compare two images
comm -23 <(jq -r '.packages[].name' image1_sbom.json | sort) \
         <(jq -r '.packages[].name' image2_sbom.json | sort)
```
