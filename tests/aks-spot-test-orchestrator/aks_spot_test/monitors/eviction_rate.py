"""Spot eviction rate monitoring."""

import threading
import time
from datetime import datetime
from typing import List, Dict
from ..utils import run_kubectl


class EvictionMonitor:
    """Background monitor for spot eviction events."""

    def __init__(self, poll_interval: int = 30):
        self.poll_interval = poll_interval
        self.running = False
        self.thread = None
        self.eviction_events: List[Dict] = []
        self.start_time = None

    def start(self):
        """Start monitoring eviction events in background thread."""
        self.running = True
        self.start_time = datetime.now()
        self.thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self.thread.start()

    def stop(self) -> tuple[List[Dict], float]:
        """Stop monitoring and return events + rate."""
        self.running = False
        if self.thread:
            self.thread.join(timeout=5)

        # Calculate eviction rate
        duration_hours = (datetime.now() - self.start_time).total_seconds() / 3600
        rate = len(self.eviction_events) / duration_hours if duration_hours > 0 else 0.0

        return self.eviction_events, rate

    def _monitor_loop(self):
        """Background loop to poll for eviction events."""
        seen_events = set()

        while self.running:
            events = run_kubectl(["get", "events", "--all-namespaces"], output_json=True)
            if events:
                for event in events.get("items", []):
                    reason = event.get("reason", "")
                    message = event.get("message", "")
                    uid = event.get("metadata", {}).get("uid", "")

                    # Look for spot eviction events
                    if ("evict" in reason.lower() or "evict" in message.lower()) and uid not in seen_events:
                        involved_obj = event.get("involvedObject", {})
                        if involved_obj.get("kind") == "Node":
                            self.eviction_events.append({
                                "timestamp": event.get("metadata", {}).get("creationTimestamp", ""),
                                "node": involved_obj.get("name", ""),
                                "reason": reason,
                                "message": message
                            })
                            seen_events.add(uid)

            time.sleep(self.poll_interval)
