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


# Default values for known pool names
DEFAULT_POOL_VM_SIZES = {
    "system": "Standard_D4s_v5",
    "stdworkload": "Standard_D4s_v5",
    "spotgeneral1": "Standard_D4s_v5",
    "spotmemory1": "Standard_E4s_v5",
    "spotgeneral2": "Standard_D8s_v5",
    "spotcompute": "Standard_F8s_v2",
    "spotmemory2": "Standard_E8s_v5",
}

DEFAULT_POOL_ZONES = {
    "system": ["1", "2", "3"],
    "stdworkload": ["1", "2"],
    "spotgeneral1": ["1"],
    "spotmemory1": ["2"],
    "spotgeneral2": ["2"],
    "spotcompute": ["3"],
    "spotmemory2": ["3"],
}

DEFAULT_POOL_PRIORITIES = {
    "system": 30,
    "stdworkload": 20,
    "spotgeneral1": 10,
    "spotgeneral2": 10,
    "spotcompute": 10,
    "spotmemory1": 5,
    "spotmemory2": 5,
}

DEFAULT_POOL_MIN = {
    "system": 3,
    "stdworkload": 2,
    # Spot pools default to 0 (scale-to-zero)
}

DEFAULT_POOL_MAX = {
    "system": 6,
    "stdworkload": 15,
    "spotgeneral1": 20,
    "spotmemory1": 15,
    "spotgeneral2": 15,
    "spotcompute": 10,
    "spotmemory2": 10,
}


def _build_pool_dict(pool_names: List[str], env_prefix: str,
                     defaults: Dict[str, any], generic_default: any) -> Dict[str, any]:
    """Build a dictionary dynamically from environment variables.

    Args:
        pool_names: List of pool names to build dict for
        env_prefix: Environment variable prefix (e.g., "POOL_VM_SIZE")
        defaults: Dictionary of default values for known pools
        generic_default: Fallback default for unknown pools

    Returns:
        Dictionary mapping pool names to values from env or defaults
    """
    result = {}
    for pool in pool_names:
        env_var = f"{env_prefix}_{pool}"
        pool_default = defaults.get(pool, generic_default)
        result[pool] = os.environ.get(env_var, str(pool_default) if pool_default is not None else "")
    return result


def _build_pool_dict_int(pool_names: List[str], env_prefix: str,
                         defaults: Dict[str, int], generic_default: int) -> Dict[str, int]:
    """Build an integer dictionary dynamically from environment variables."""
    result = {}
    for pool in pool_names:
        env_var = f"{env_prefix}_{pool}"
        pool_default = defaults.get(pool, generic_default)
        result[pool] = int(os.environ.get(env_var, str(pool_default)))
    return result


def _build_pool_dict_list(pool_names: List[str], env_prefix: str,
                          defaults: Dict[str, List[str]], generic_default: str) -> Dict[str, List[str]]:
    """Build a list dictionary dynamically from environment variables."""
    result = {}
    for pool in pool_names:
        env_var = f"{env_prefix}_{pool}"
        pool_default = ",".join(defaults.get(pool, [generic_default]))
        value = os.environ.get(env_var, pool_default)
        result[pool] = [item.strip() for item in value.split(",")] if value else []
    return result


@dataclass
class TestConfig:
    """Cluster and workload configuration for spot behavior tests.

    All values are loaded from environment variables with sensible defaults.
    Customize via .env file (copy from .env.example).

    Dictionaries (pool_vm_size, pool_zones, etc.) are built dynamically
    based on the actual pool names in SPOT_POOLS, supporting custom pool names.
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
        default_factory=lambda: [
            pool.strip() for pool in os.environ.get(
                "SPOT_POOLS",
                "spotgeneral1,spotmemory1,spotgeneral2,spotcompute,spotmemory2"
            ).split(",")
        ]
    )

    # ── Dynamically built dictionaries (built in __post_init__) ──────
    # These are initialized as empty and populated based on actual pool names
    pool_vm_size: Dict[str, str] = field(default_factory=dict)
    pool_zones: Dict[str, List[str]] = field(default_factory=dict)
    pool_priority: Dict[str, int] = field(default_factory=dict)
    pool_min: Dict[str, int] = field(default_factory=dict)
    pool_max: Dict[str, int] = field(default_factory=dict)

    # ── Robot-Shop services (customize via .env file) ────────────────
    # Override via: STATELESS_SERVICES="web,cart,catalogue" etc.
    stateless_services: List[str] = field(
        default_factory=lambda: [
            svc.strip() for svc in os.environ.get(
                "STATELESS_SERVICES",
                "web,cart,catalogue,user,payment,shipping,ratings,dispatch"
            ).split(",")
        ]
    )
    stateful_services: List[str] = field(
        default_factory=lambda: [
            svc.strip() for svc in os.environ.get(
                "STATEFUL_SERVICES",
                "mongodb,mysql,redis,rabbitmq"
            ).split(",")
        ]
    )
    pdb_services: List[str] = field(
        default_factory=lambda: [
            svc.strip() for svc in os.environ.get(
                "PDB_SERVICES",
                "web,cart,catalogue,mongodb,mysql,redis,rabbitmq"
            ).split(",")
        ]
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

    def __post_init__(self):
        """Build dynamic dictionaries based on actual pool names after initialization."""
        # Collect all pool names (system, standard, and spot pools)
        all_pools = [self.system_pool, self.standard_pool] + self.spot_pools

        # Build VM size mapping
        self.pool_vm_size = _build_pool_dict(
            all_pools, "POOL_VM_SIZE", DEFAULT_POOL_VM_SIZES, "Standard_D4s_v5"
        )

        # Build zone mapping
        self.pool_zones = _build_pool_dict_list(
            all_pools, "POOL_ZONES", DEFAULT_POOL_ZONES, "1"
        )

        # Build priority mapping
        self.pool_priority = _build_pool_dict_int(
            all_pools, "POOL_PRIORITY", DEFAULT_POOL_PRIORITIES, 10
        )

        # Build min node count mapping
        # System/standard have specific defaults, spot pools default to 0
        min_defaults = DEFAULT_POOL_MIN.copy()
        for pool in self.spot_pools:
            if pool not in min_defaults:
                min_defaults[pool] = 0  # Spot pools can scale to zero
        self.pool_min = _build_pool_dict_int(
            all_pools, "POOL_MIN", min_defaults, 0
        )

        # Build max node count mapping
        max_defaults = DEFAULT_POOL_MAX.copy()
        for pool in self.spot_pools:
            if pool not in max_defaults:
                max_defaults[pool] = 20  # Generic max for spot pools
        self.pool_max = _build_pool_dict_int(
            all_pools, "POOL_MAX", max_defaults, 20
        )

    @property
    def all_services(self) -> List[str]:
        """Return combined list of stateless and stateful services."""
        return self.stateless_services + self.stateful_services

    @property
    def all_pools(self) -> List[str]:
        """Return combined list of all node pools."""
        return [self.system_pool, self.standard_pool] + self.spot_pools
