---
name: Terraform Automation
description: How to dry-run Terraform code and simulate EKS spot instances with Kind.
---

# Terraform Automation Skill

This skill covers how to safely validate Terraform changes and how to simulate EKS spot instance behavior locally using Kind.

## 1. Terraform Dry Run

A "dry run" in Terraform is performed using `terraform plan`. This command previews infrastructure changes without applying them.

### Steps

1.  **Initialize**:
    ```bash
    terraform init
    ```

2.  **Validate Syntax**:
    ```bash
    terraform validate
    ```

3.  **Preview Changes**:
    ```bash
    terraform plan
    ```
    To save the plan to a file for later review or application:
    ```bash
    terraform plan -out=tfplan
    ```

4.  **Apply (Optional)**:
    If the plan looks correct, apply it:
    ```bash
    terraform apply tfplan
    ```

### Best Practices

-   **CI/CD Integration**: Automate `terraform validate` and `terraform plan` in your CI/CD pipeline.
-   **Static Analysis**: Use tools like `tflint` for linting and `tfsec` for security scanning.
-   **Input Validation**: Define validation rules for input variables in your Terraform code.

---

## 2. Simulate EKS Spot Instances with Kind

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
