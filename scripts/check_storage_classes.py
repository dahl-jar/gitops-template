#!/usr/bin/env python3
from __future__ import annotations

import logging
import sys
from pathlib import Path

import yaml

# change this: the storage classes a claim may use
ALLOWED = {"local-path-retain"}

logger = logging.getLogger("check_storage_classes")


def claims(document: dict) -> list[tuple[str, str | None]]:
    kind = document.get("kind")
    if kind == "PersistentVolumeClaim":
        return [(document["metadata"]["name"], document.get("spec", {}).get("storageClassName"))]
    if kind == "StatefulSet":
        templates = document.get("spec", {}).get("volumeClaimTemplates") or []
        return [
            (template["metadata"]["name"], template.get("spec", {}).get("storageClassName"))
            for template in templates
        ]
    return []


def identity(document: dict) -> str:
    meta = document.get("metadata", {})
    return f"{meta.get('namespace', '')}/{document.get('kind')}/{meta.get('name', '')}"


def main(paths: list[str]) -> int:
    failed = 0
    for path in paths:
        for document in yaml.safe_load_all(Path(path).read_text()):
            if not isinstance(document, dict):
                continue
            owner = identity(document)
            for _, storage_class in claims(document):
                if storage_class in ALLOWED:
                    logger.info("ok      %s (%s)", owner, storage_class)
                else:
                    logger.error(
                        "FAILED  %s uses class %r, allowed: %s",
                        owner,
                        storage_class,
                        ", ".join(sorted(ALLOWED)),
                    )
                    failed = 1
    return failed


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    sys.exit(main(sys.argv[1:]))
