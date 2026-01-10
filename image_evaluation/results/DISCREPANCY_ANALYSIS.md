
# Discrepancy Analysis: VEX & Scanner Variance

We conducted a deep-dive analysis on the `dhi.io/python` image to understand why vulnerability counts differ across tools (Docker Scout vs. Trivy vs. Grype).

## Experiment Setup
1. **Fetch VEX**: `docker scout vex get registry://dhi.io/python:latest -o vex.json`
2. **Generate SBOM**: `syft dhi.io/python:latest -o cyclonedx-json > sbom.json`
3. **Scan with VEX**: `grype sbom:sbom.json --vex vex.json` (Explicit application)
4. **Scan w/o VEX**: Standard `grype DHI_IMAGE` and `trivy DHI_IMAGE`

## Findings Table

| Tool | Configuration | Critical | High | Medium | Low | Total | Conclusion |
|------|---------------|----------|------|--------|-----|-------|------------|
| **Docker Scout** | Default (Has VEX) | 0 | 0 | 1 | 19 | 20 | ✅ Baseline (Filters applied) |
| **Grype** | **With VEX (Explicit)** | **0** | **0** | **0** | **0** | **0** | ✅ **Cleanest Result** |
| **Grype** | Without VEX | 0 | 14 | 14 | 8 | 36 | ❌ False Positives found |
| **Trivy** | Default (Repo VEX) | 0 | 0 | 7 | 41 | 48 | ⚠️ Most conservative/noisy |

### Key Takeaways
1. **VEX is Critical**: Without applying the VEX file (`vex.json`), scanners report ~14 High and ~30+ Low/Medium vulnerabilities that are actually false positives or fixed.
2. **Tool Variance**: 
   - **Trivy** picks up more "Low" severity issues (41) related to unpatched but non-critical upstream Debian packages.
   - **Grype** with explicit VEX is the only tool that reports a completely "Clean" (0 vulnerability) state, validating the effectiveness of the DHI VEX data.
3. **Recommendation**: For DHI images, **always** rely on `docker scout` or explicit VEX application in your CI/CD pipeline to avoid blocking builds on false positives.
