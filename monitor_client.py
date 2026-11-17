import json
import os
from urllib.error import URLError, TimeoutError, OSError
from urllib.request import Request, urlopen

MONITOR_URL = os.environ.get("MONITOR_URL", "")
APP_VERSION = os.environ.get("APP_VERSION", "blue")


def notify(operation, priority="none"):
    if not MONITOR_URL:
        return

    payload = json.dumps(
        {
            "operation": operation,
            "resource": "task",
            "version": APP_VERSION,
            "priority": priority or "none"
        }
    ).encode("utf-8")

    request = Request(
        MONITOR_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST"
    )

    try:
        urlopen(request, timeout=1)
    except (URLError, TimeoutError, OSError):
        pass
