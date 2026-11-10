#!/usr/bin/env python3
from __future__ import annotations

import logging
import sys
from pathlib import Path

import yaml

CONFIGMAP_PATH = Path(__file__).resolve().parent.parent / "platform" / "cloudflared" / "configmap.yaml"
CONFIG_KEY = "config.yaml"
LAN_SUFFIX = ".home.arpa"
PRIVATE_SERVICE = "jenkins"
CATCH_ALL = {"service": "http_status:404"}
EXIT_FINDINGS = 1
logger = logging.getLogger("check_tunnel_routes")


def rule_label(index: int, rule: dict) -> str:
    return rule.get("hostname") or f"#{index + 1}"


def lan_findings(text: str) -> list[str]:
    return [
        f"{CONFIG_KEY} line {number} names a {LAN_SUFFIX} host"
        for number, line in enumerate(text.splitlines(), start=1)
        if LAN_SUFFIX in line.lower()
    ]


def jenkins_findings(rules: list[dict]) -> list[str]:
    return [
        f"rule for {rule_label(index, rule)}: service {rule.get('service', '')} names {PRIVATE_SERVICE}"
        for index, rule in enumerate(rules)
        if PRIVATE_SERVICE in rule.get("service", "").lower()
    ]


def catch_all_findings(rules: list[dict]) -> list[str]:
    if not rules:
        return [f"ingress has no rules, expected a last rule {CATCH_ALL!r}"]
    if rules[-1] != CATCH_ALL:
        return [f"last rule is {rules[-1]!r}, expected {CATCH_ALL!r}"]
    return []


def findings(config: dict) -> list[str]:
    text = config["data"][CONFIG_KEY]
    rules = yaml.safe_load(text).get("ingress") or []
    return lan_findings(text) + jenkins_findings(rules) + catch_all_findings(rules)


def main(argv: list[str]) -> int:
    path = Path(argv[0]) if argv else CONFIGMAP_PATH
    result = findings(yaml.safe_load(path.read_text()))
    if result:
        for finding in result:
            logger.error("FAILED  %s: %s", path, finding)
        return EXIT_FINDINGS
    logger.info("ok      %s", path)
    return 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    sys.exit(main(sys.argv[1:]))
