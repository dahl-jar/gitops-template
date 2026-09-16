#!/usr/bin/env python3
"""Fail when a claim in the rendered manifests could land on a Delete volume.

Every PersistentVolumeClaim and StatefulSet volumeClaimTemplate must name a
class in ALLOWED. A claim with no class falls back to the cluster default,
which on k3s deletes the volume with the claim, so it is rejected too.

Usage: check-storage-classes.py out/*.yaml
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

import yaml

ALLOWED = {"local-path-retain", "local-static"}

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("check-storage-classes")


def claims(document: dict) -> list[tuple[str, str | None]]:
    """Return (identity, storageClassName) for every claim the document declares."""
    kind = document.get("kind")
    meta = document.get("metadata", {})
    identity = f"{meta.get('namespace', '')}/{kind}/{meta.get('name', '')}"
    if kind == "PersistentVolumeClaim":
        return [(identity, document.get("spec", {}).get("storageClassName"))]
    if kind == "StatefulSet":
        templates = document.get("spec", {}).get("volumeClaimTemplates") or []
        return [
            (identity, template.get("spec", {}).get("storageClassName"))
            for template in templates
        ]
    return []


def main(paths: list[str]) -> int:
    """Check every rendered file; return 1 when any claim is on a Delete class."""
    failed = 0
    for path in paths:
        for document in yaml.safe_load_all(Path(path).read_text()):
            if not isinstance(document, dict):
                continue
            for identity, storage_class in claims(document):
                if storage_class in ALLOWED:
                    logger.info("ok      %s (%s)", identity, storage_class)
                else:
                    logger.error(
                        "FAILED  %s uses class %r; allowed: %s",
                        identity,
                        storage_class,
                        ", ".join(sorted(ALLOWED)),
                    )
                    failed = 1
    return failed


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
