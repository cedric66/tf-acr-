---
name: Terraform Automation & Best Practices
description: Best practices for Terraform project structure, configuration via tfvars, and testing with Kind.
---

# Terraform Automation & Best Practices

This skill outlines the mandatory project structure and workflows for reliable, scalable Terraform infrastructure.

## 1. Project Organization (Mandatory)

All Terraform projects must adhere to a strict modular structure to ensure reusability and environment isolation.

### Directory Structure

```text
project-root/
├── modules/                 # Reusable logic (Stateless)
│   ├── networking/          #   - main.tf (Resources)
│   ├── aks-cluster/         #   - variables.tf (Inputs)
│   └── database/            #   - outputs.tf (Outputs)
│
└── environments/            # Deployable instances (Stateful)
    ├── dev/                 # Development environment
    │   ├── provider.tf      #   - REQUIRED: Provider & backend config
    │   ├── main.tf          #   - Calls ../../modules
    │   ├── variables.tf     #   - Defines environment inputs
    │   ├── terraform.tfvars #   - Values (git-ignored if sensitive)
    │   └── outputs.tf       #   - Environment outputs
    │
    └── prod/                # Production environment
        ├── provider.tf      #   - REQUIRED: Provider & backend config
        ├── main.tf
        ├── variables.tf
        ├── terraform.tfvars
        └── outputs.tf
```

### Configuration Rules

1.  **Provider Configuration**:
    *   **ALWAYS** create a `provider.tf` file in each environment directory.
    *   `provider.tf` must contain the `terraform` block, `required_providers`, and `provider` configuration.
    *   **NEVER** put provider configuration in `main.tf`.

2.  **Modules vs. Environments**:
    *   **Modules** contain logic and resources. They **must not** contain provider configurations or backend settings.
    *   **Environments** contain state and values. They simple instantiate modules.

2.  **No Hardcoded Values**:
    *   **NEVER** hardcode values like identifiers, names, or SKU counts in `.tf` files.
    *   **ALWAYS** define a variable in `variables.tf`.
    *   **ALWAYS** set the value in `terraform.tfvars` (or `*.auto.tfvars`).

3.  **Variable Definitions**:
    *   All configurable items (node counts, version strings, machine types) must be variables.
    *   Use `terraform.tfvars.example` to document required variables for users.

4.  **Tags Strategy**:
    *   **NEVER** hardcode tags in `main.tf` or `locals`.
    *   **ALWAYS** define a generic `tags` variable (map) with an empty default `{}`.
    *   Tags should be completely optional and controlled strictly via `terraform.tfvars`.

5.  **AKS IP Planning** (Azure-specific):
    *   Calculate IP requirements: `(max_nodes × max_pods) + surge_IPs + system_overhead`.
    *   Use `maxUnavailable` in standard pools to avoid surge IP consumption.
    *   Reduce `maxSurge` percentage in spot pools (spot cannot use `maxUnavailable`).
    *   Example: Standard pools use `max_unavailable = "1"`, spot pools use `max_surge = "10%"`.

6.  **Spot Pool Resilience** (Azure-specific):
    *   **ALWAYS** configure each spot pool with **1 zone + 1 SKU family**.
    *   **NEVER** give multiple zones to a single spot pool (VMSS pins to one zone).
    *   Use multiple VM families (D, E, F-series) across pools for SKU diversity.
    *   Standard pools provide fallback when all spot pools are exhausted.

---

## 2. Terraform Workflow with tfvars

When running Terraform, explicit configuration files ensure reproducibility.

### Steps

1.  **Initialize**:
    ```bash
    terraform init
    ```

2.  **Validate**:
    ```bash
    terraform validate
    ```

3.  **Plan**:
    Always target the specific environment variable file.
    ```bash
    terraform plan -var-file="terraform.tfvars" -out=tfplan
    ```

4.  **Apply**:
    ```bash
    terraform apply tfplan
    ```

---

## 3. Simulate EKS Spot Instances with Kind

You can simulate the ephemeral nature of EKS spot instances locally using a Kind cluster, taints, and tolerations.

### Prerequisites

-   Docker
-   Kind: `go install sigs.k8s.io/kind@latest`
-   kubectl

### Steps

1.  **Create a Kind Cluster**:
    Create a multi-node cluster configuration file `kind-config.yaml`:
    ```yaml
    # kind-config.yaml
    kind: Cluster
    apiVersion: kind.x-k8s.io/v1alpha4
    nodes:
    - role: control-plane
    - role: worker
    - role: worker
      labels:
        lifecycle: spot
    ```
    Create the cluster:
    ```bash
    kind create cluster --config kind-config.yaml --name spot-sim
    ```

2.  **Taint a Node to Simulate Spot**:
    Get the name of the "spot" labeled node:
    ```bash
    SPOT_NODE=$(kubectl get nodes -l lifecycle=spot -o jsonpath='{.items[0].metadata.name}')
    ```
    Apply a taint to it:
    ```bash
    kubectl taint nodes $SPOT_NODE lifecycle=spot:NoSchedule
    ```

3.  **Deploy a Tolerating Workload**:
    Create a deployment that tolerates the `spot` taint.
    ```yaml
    # spot-deployment.yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: spot-tolerant-app
    spec:
      replicas: 2
      selector:
        matchLabels:
          app: spot-tolerant
      template:
        metadata:
          labels:
            app: spot-tolerant
        spec:
          nodeSelector:
            lifecycle: spot
          tolerations:
          - key: "lifecycle"
            operator: "Equal"
            value: "spot"
            effect: "NoSchedule"
          containers:
          - name: nginx
            image: nginx:alpine
    ```
    Apply:
    ```bash
    kubectl apply -f spot-deployment.yaml
    ```

4.  **Simulate Node Termination**:
    To simulate a spot instance being reclaimed, drain or delete the node:
    ```bash
    # Drain the node gracefully
    kubectl drain $SPOT_NODE --ignore-daemonsets --delete-emptydir-data
    
    # Or simulate immediate failure by deleting the docker container
    # docker stop spot-sim-worker2
    ```

5.  **Cleanup**:
    ```bash
    kind delete cluster --name spot-sim
    ```

### Advanced: Amazon EC2 Metadata Mock (AEMM)

For more realistic simulation of the 2-minute interruption notice, deploy the [Amazon EC2 Metadata Mock (AEMM)](https://github.com/aws/amazon-ec2-metadata-mock) into your Kind cluster.
