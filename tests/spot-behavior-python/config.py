"""Test configuration matching terraform/modules/aks-spot-optimized/variables.tf defaults.

CONFIGURATION:
    1. Copy .env.example to .env
    2. Edit .env with your cluster details
    3. Load before running: export $(cat .env | xargs)
    4. See README.md for detailed setup instructions

ALL configuration values use environment variables with fallback defaults.
Customize via .env file for your specific cluster.
"""

import os
from dataclasses import dataclass, field
from typing import Dict, List


@dataclass
class TestConfig:
    """Cluster and workload configuration for spot behavior tests.

    All values are loaded from environment variables with sensible defaults.
    Customize via .env file (copy from .env.example).
    """

    # ── Cluster identity (customize via .env file) ───────────────────
    cluster_name: str = field(
        default_factory=lambda: os.environ.get("CLUSTER_NAME", "aks-spot-prod")
    )
    resource_group: str = field(
        default_factory=lambda: os.environ.get("RESOURCE_GROUP", "rg-aks-spot")
    )
    namespace: str = field(
        default_factory=lambda: os.environ.get("NAMESPACE", "robot-shop")
    )
    location: str = field(
        default_factory=lambda: os.environ.get("LOCATION", "australiaeast")
    )

    # ── Node pool names (customize via .env file) ────────────────────
    system_pool: str = field(
        default_factory=lambda: os.environ.get("SYSTEM_POOL", "system")
    )
    standard_pool: str = field(
        default_factory=lambda: os.environ.get("STANDARD_POOL", "stdworkload")
    )
    spot_pools: List[str] = field(
        default_factory=lambda: os.environ.get(
            "SPOT_POOLS",
            "spotgeneral1,spotmemory1,spotgeneral2,spotcompute,spotmemory2"
        ).split(",")
    )

    # ── VM SKU mapping (customize via .env file) ─────────────────────
    # Override via: POOL_VM_SIZE_system="Standard_D2s_v5" etc.
    pool_vm_size: Dict[str, str] = field(default_factory=lambda: {
        "system": os.environ.get("POOL_VM_SIZE_system", "Standard_D4s_v5"),
        "stdworkload": os.environ.get("POOL_VM_SIZE_stdworkload", "Standard_D4s_v5"),
        "spotgeneral1": os.environ.get("POOL_VM_SIZE_spotgeneral1", "Standard_D4s_v5"),
        "spotmemory1": os.environ.get("POOL_VM_SIZE_spotmemory1", "Standard_E4s_v5"),
        "spotgeneral2": os.environ.get("POOL_VM_SIZE_spotgeneral2", "Standard_D8s_v5"),
        "spotcompute": os.environ.get("POOL_VM_SIZE_spotcompute", "Standard_F8s_v2"),
        "spotmemory2": os.environ.get("POOL_VM_SIZE_spotmemory2", "Standard_E8s_v5"),
    })

    # ── Zone mapping (customize via .env file) ───────────────────────
    # Override via: POOL_ZONES_system="1,2,3" etc.
    pool_zones: Dict[str, List[str]] = field(default_factory=lambda: {
        "system": os.environ.get("POOL_ZONES_system", "1,2,3").split(","),
        "stdworkload": os.environ.get("POOL_ZONES_stdworkload", "1,2").split(","),
        "spotgeneral1": os.environ.get("POOL_ZONES_spotgeneral1", "1").split(","),
        "spotmemory1": os.environ.get("POOL_ZONES_spotmemory1", "2").split(","),
        "spotgeneral2": os.environ.get("POOL_ZONES_spotgeneral2", "2").split(","),
        "spotcompute": os.environ.get("POOL_ZONES_spotcompute", "3").split(","),
        "spotmemory2": os.environ.get("POOL_ZONES_spotmemory2", "3").split(","),
    })

    # ── Priority expander weights (customize via .env file) ──────────
    # Lower = higher priority. Override via: POOL_PRIORITY_system="30" etc.
    pool_priority: Dict[str, int] = field(default_factory=lambda: {
        "spotmemory1": int(os.environ.get("POOL_PRIORITY_spotmemory1", "5")),
        "spotmemory2": int(os.environ.get("POOL_PRIORITY_spotmemory2", "5")),
        "spotgeneral1": int(os.environ.get("POOL_PRIORITY_spotgeneral1", "10")),
        "spotgeneral2": int(os.environ.get("POOL_PRIORITY_spotgeneral2", "10")),
        "spotcompute": int(os.environ.get("POOL_PRIORITY_spotcompute", "10")),
        "stdworkload": int(os.environ.get("POOL_PRIORITY_stdworkload", "20")),
        "system": int(os.environ.get("POOL_PRIORITY_system", "30")),
    })

    # ── Robot-Shop services (customize via .env file) ────────────────
    # Override via: STATELESS_SERVICES="web,cart,catalogue" etc.
    stateless_services: List[str] = field(
        default_factory=lambda: os.environ.get(
            "STATELESS_SERVICES",
            "web,cart,catalogue,user,payment,shipping,ratings,dispatch"
        ).split(",")
    )
    stateful_services: List[str] = field(
        default_factory=lambda: os.environ.get(
            "STATEFUL_SERVICES",
            "mongodb,mysql,redis,rabbitmq"
        ).split(",")
    )
    pdb_services: List[str] = field(
        default_factory=lambda: os.environ.get(
            "PDB_SERVICES",
            "web,cart,catalogue,mongodb,mysql,redis,rabbitmq"
        ).split(",")
    )

    # ── Timeouts (seconds) (customize via .env file) ─────────────────
    termination_grace_period: int = field(
        default_factory=lambda: int(os.environ.get("TERMINATION_GRACE_PERIOD", "35"))
    )
    prestop_sleep: int = field(
        default_factory=lambda: int(os.environ.get("PRESTOP_SLEEP", "25"))
    )
    autoscaler_scan_interval: int = field(
        default_factory=lambda: int(os.environ.get("AUTOSCALER_SCAN_INTERVAL", "20"))
    )
    ghost_node_cleanup: int = field(
        default_factory=lambda: int(os.environ.get("GHOST_NODE_CLEANUP", "180"))
    )
    descheduler_interval: int = field(
        default_factory=lambda: int(os.environ.get("DESCHEDULER_INTERVAL", "300"))
    )
    pod_ready_timeout: int = field(
        default_factory=lambda: int(os.environ.get("POD_READY_TIMEOUT", "120"))
    )
    node_ready_timeout: int = field(
        default_factory=lambda: int(os.environ.get("NODE_READY_TIMEOUT", "300"))
    )
    drain_timeout: int = field(
        default_factory=lambda: int(os.environ.get("DRAIN_TIMEOUT", "60"))
    )

    # ── Results directory (customize via .env file) ──────────────────
    results_dir: str = field(default_factory=lambda: os.environ.get(
        "RESULTS_DIR",
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")
    ))

    @property
    def all_services(self) -> List[str]:
        """Return combined list of stateless and stateful services."""
        return self.stateless_services + self.stateful_services

    @property
    def all_pools(self) -> List[str]:
        """Return combined list of all node pools."""
        return [self.system_pool, self.standard_pool] + self.spot_pools
