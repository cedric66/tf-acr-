"""Test configuration matching terraform/modules/aks-spot-optimized/variables.tf defaults."""

import os
from dataclasses import dataclass, field
from typing import Dict, List


@dataclass
class TestConfig:
    """Cluster and workload configuration for spot behavior tests."""

    # Cluster identity
    cluster_name: str = field(default_factory=lambda: os.environ.get("CLUSTER_NAME", "aks-spot-prod"))
    resource_group: str = field(default_factory=lambda: os.environ.get("RESOURCE_GROUP", "rg-aks-spot"))
    namespace: str = field(default_factory=lambda: os.environ.get("NAMESPACE", "robot-shop"))

    # Node pool names
    system_pool: str = "system"
    standard_pool: str = "stdworkload"
    spot_pools: List[str] = field(default_factory=lambda: [
        "spotgeneral1", "spotmemory1", "spotgeneral2", "spotcompute", "spotmemory2"
    ])

    # VM SKU mapping
    pool_vm_size: Dict[str, str] = field(default_factory=lambda: {
        "system": "Standard_D4s_v5",
        "stdworkload": "Standard_D4s_v5",
        "spotgeneral1": "Standard_D4s_v5",
        "spotmemory1": "Standard_E4s_v5",
        "spotgeneral2": "Standard_D8s_v5",
        "spotcompute": "Standard_F8s_v2",
        "spotmemory2": "Standard_E8s_v5",
    })

    # Zone mapping
    pool_zones: Dict[str, List[str]] = field(default_factory=lambda: {
        "system": ["1", "2", "3"],
        "stdworkload": ["1", "2"],
        "spotgeneral1": ["1"],
        "spotmemory1": ["2"],
        "spotgeneral2": ["2"],
        "spotcompute": ["3"],
        "spotmemory2": ["3"],
    })

    # Priority expander weights (lower = higher priority)
    pool_priority: Dict[str, int] = field(default_factory=lambda: {
        "spotmemory1": 5, "spotmemory2": 5,
        "spotgeneral1": 10, "spotgeneral2": 10, "spotcompute": 10,
        "stdworkload": 20, "system": 30,
    })

    # Robot-Shop services
    stateless_services: List[str] = field(default_factory=lambda: [
        "web", "cart", "catalogue", "user", "payment", "shipping", "ratings", "dispatch"
    ])
    stateful_services: List[str] = field(default_factory=lambda: [
        "mongodb", "mysql", "redis", "rabbitmq"
    ])
    pdb_services: List[str] = field(default_factory=lambda: [
        "web", "cart", "catalogue", "mongodb", "mysql", "redis", "rabbitmq"
    ])

    # Timeouts (seconds)
    termination_grace_period: int = 35
    prestop_sleep: int = 25
    autoscaler_scan_interval: int = 20
    ghost_node_cleanup: int = 180
    descheduler_interval: int = 300
    pod_ready_timeout: int = 120
    node_ready_timeout: int = 300
    drain_timeout: int = 60

    # Results directory
    results_dir: str = field(default_factory=lambda: os.environ.get(
        "RESULTS_DIR",
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")
    ))

    @property
    def all_services(self) -> List[str]:
        return self.stateless_services + self.stateful_services

    @property
    def all_pools(self) -> List[str]:
        return [self.system_pool, self.standard_pool] + self.spot_pools
