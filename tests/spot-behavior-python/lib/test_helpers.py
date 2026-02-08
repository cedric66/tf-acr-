"""kubectl/az CLI wrappers and node/pod manipulation helpers."""

import json
import subprocess
import time
from typing import Any, Dict, List, Optional


class KubeCommand:
    """Execute kubectl commands and parse JSON output."""

    def __init__(self, namespace: str = "robot-shop"):
        self.namespace = namespace

    def run(self, args: List[str], timeout: int = 30) -> subprocess.CompletedProcess:
        cmd = ["kubectl"] + args
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

    def run_json(self, args: List[str], timeout: int = 30) -> Any:
        result = self.run(args + ["-o", "json"], timeout=timeout)
        if result.returncode != 0:
            return None
        return json.loads(result.stdout)

    def get_pods(self, label: str = "", field_selector: str = "") -> List[Dict]:
        args = ["get", "pods", "-n", self.namespace]
        if label:
            args += ["-l", label]
        if field_selector:
            args += ["--field-selector", field_selector]
        data = self.run_json(args)
        return data.get("items", []) if data else []

    def get_nodes(self, label: str = "") -> List[Dict]:
        args = ["get", "nodes"]
        if label:
            args += ["-l", label]
        data = self.run_json(args)
        return data.get("items", []) if data else []

    def get_node(self, name: str) -> Optional[Dict]:
        data = self.run_json(["get", "node", name])
        return data

    def get_pdbs(self) -> List[Dict]:
        data = self.run_json(["get", "pdb", "-n", self.namespace])
        return data.get("items", []) if data else []

    def get_configmap(self, name: str, namespace: str = "kube-system") -> Optional[Dict]:
        data = self.run_json(["get", "configmap", name, "-n", namespace])
        return data

    def cluster_info(self) -> bool:
        result = self.run(["cluster-info"], timeout=10)
        return result.returncode == 0


class NodeHelper:
    """Node inspection and manipulation."""

    def __init__(self, kube: KubeCommand):
        self.kube = kube

    def get_pool_name(self, node: Dict) -> str:
        return node.get("metadata", {}).get("labels", {}).get("agentpool", "")

    def get_zone(self, node: Dict) -> str:
        return node.get("metadata", {}).get("labels", {}).get(
            "topology.kubernetes.io/zone", "")

    def is_spot(self, node: Dict) -> bool:
        return node.get("metadata", {}).get("labels", {}).get(
            "kubernetes.azure.com/scalesetpriority") == "spot"

    def is_ready(self, node: Dict) -> bool:
        for cond in node.get("status", {}).get("conditions", []):
            if cond.get("type") == "Ready":
                return cond.get("status") == "True"
        return False

    def get_spot_nodes(self) -> List[Dict]:
        return self.kube.get_nodes("kubernetes.azure.com/scalesetpriority=spot")

    def get_pool_nodes(self, pool_name: str) -> List[Dict]:
        return self.kube.get_nodes(f"agentpool={pool_name}")

    def count_ready_in_pool(self, pool_name: str) -> int:
        nodes = self.get_pool_nodes(pool_name)
        return sum(1 for n in nodes if self.is_ready(n))

    def drain(self, node_name: str, timeout: int = 60) -> bool:
        result = self.kube.run([
            "drain", node_name,
            "--ignore-daemonsets",
            "--delete-emptydir-data",
            f"--grace-period={timeout}",
            f"--timeout={timeout}s",
            "--force"
        ], timeout=timeout + 30)
        return result.returncode == 0

    def cordon(self, node_name: str) -> bool:
        result = self.kube.run(["cordon", node_name])
        return result.returncode == 0

    def uncordon(self, node_name: str) -> bool:
        result = self.kube.run(["uncordon", node_name])
        return result.returncode == 0


class PodHelper:
    """Pod inspection and service mapping."""

    def __init__(self, kube: KubeCommand, node_helper: NodeHelper):
        self.kube = kube
        self.nodes = node_helper

    def get_service_pods(self, service: str) -> List[Dict]:
        pods = self.kube.get_pods(label=f"app={service}")
        if not pods:
            pods = self.kube.get_pods(label=f"service={service}")
        return pods

    def get_pod_node(self, pod: Dict) -> str:
        return pod.get("spec", {}).get("nodeName", "")

    def is_running(self, pod: Dict) -> bool:
        return pod.get("status", {}).get("phase") == "Running"

    def count_running_for_service(self, service: str) -> int:
        pods = self.get_service_pods(service)
        return sum(1 for p in pods if self.is_running(p))

    def get_pods_on_spot(self, service: str) -> List[Dict]:
        pods = self.get_service_pods(service)
        result = []
        for pod in pods:
            node_name = self.get_pod_node(pod)
            if not node_name:
                continue
            node = self.kube.get_node(node_name)
            if node and self.nodes.is_spot(node):
                result.append(pod)
        return result

    def get_pods_on_standard(self, service: str) -> List[Dict]:
        pods = self.get_service_pods(service)
        result = []
        for pod in pods:
            node_name = self.get_pod_node(pod)
            if not node_name:
                continue
            node = self.kube.get_node(node_name)
            if node and not self.nodes.is_spot(node):
                pool = self.nodes.get_pool_name(node)
                if pool not in ("system",):
                    result.append(pod)
        return result

    def get_pod_zones(self, service: str) -> List[str]:
        pods = self.get_service_pods(service)
        zones = set()
        for pod in pods:
            node_name = self.get_pod_node(pod)
            if node_name:
                node = self.kube.get_node(node_name)
                if node:
                    zone = self.nodes.get_zone(node)
                    if zone:
                        zones.add(zone)
        return sorted(zones)

    def wait_for_ready(self, label: str, timeout: int = 120) -> bool:
        deadline = time.time() + timeout
        while time.time() < deadline:
            pods = self.kube.get_pods(label=label)
            not_ready = sum(1 for p in pods if not self.is_running(p))
            if not_ready == 0 and pods:
                return True
            time.sleep(5)
        return False


class VMSSHelper:
    """Azure VMSS inspection via az CLI."""

    def __init__(self, resource_group: str, cluster_name: str, location: str):
        """Initialize VMSSHelper.

        Args:
            resource_group: AKS resource group name
            cluster_name: AKS cluster name
            location: Azure region (REQUIRED - must match cluster location)
        """
        self.mc_rg = f"MC_{resource_group}_{cluster_name}_{location}"

    def run_az(self, args: List[str], timeout: int = 30) -> Any:
        cmd = ["az"] + args + ["-o", "json"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        if result.returncode != 0:
            return None
        return json.loads(result.stdout)

    def get_vmss_for_pool(self, pool_name: str) -> List[Dict]:
        data = self.run_az([
            "vmss", "list", "-g", self.mc_rg,
            "--query", f"[?tags.\"aks-managed-poolName\"=='{pool_name}']"
        ])
        return data if data else []

    def get_vmss_instances(self, vmss_name: str) -> List[Dict]:
        data = self.run_az([
            "vmss", "list-instances", "-n", vmss_name, "-g", self.mc_rg
        ])
        return data if data else []

    def get_vmss_instance_zones(self, vmss_name: str) -> List[str]:
        instances = self.get_vmss_instances(vmss_name)
        zones = set()
        for inst in instances:
            zone = inst.get("zones", [None])
            if zone and zone[0]:
                zones.add(zone[0])
        return sorted(zones)

    def get_spot_config(self, vmss_name: str) -> Optional[Dict]:
        data = self.run_az(["vmss", "show", "-n", vmss_name, "-g", self.mc_rg])
        if not data:
            return None
        return {
            "priority": data.get("virtualMachineProfile", {}).get("priority"),
            "eviction_policy": data.get("virtualMachineProfile", {}).get("evictionPolicy"),
            "max_price": data.get("virtualMachineProfile", {}).get("billingProfile", {}).get("maxPrice"),
        }
