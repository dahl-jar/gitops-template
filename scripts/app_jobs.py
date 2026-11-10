#!/usr/bin/env python3
from __future__ import annotations

import json
import logging
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import cast

import yaml

DEV_PARAMETERS = ("BRANCH", "SHA", "VERSION")
VERSION_PARAMETERS = ("VERSION",)
CI_PARAMETERS = ("REPO", "REF", "SHA")
CI_FLAGS = ("TRUSTED",)
CLUSTER_TARGET = "cluster"
PAGES_TARGET = "cloudflare-pages"
PRODUCTION_CALLS = {
    CLUSTER_TARGET: "deployImage(service: '{service}', environment: 'production')",
    PAGES_TARGET: "deployPages(service: '{service}')",
}
ENVIRONMENT_GLOB = "*.yaml"
EXIT_FAILED = 1
EXIT_USAGE = 2

logger = logging.getLogger("app_jobs")


class AppJobsError(Exception):
    pass


@dataclass(frozen=True)
class AppJob:
    name: str
    parameters: tuple[str, ...]
    call: str
    flags: tuple[str, ...] = ()


def ci_jobs(service: str) -> list[AppJob]:
    return [AppJob(f"{service}-ci", CI_PARAMETERS, f"testCommit(service: '{service}')", CI_FLAGS)]


def dev_jobs(service: str, target: object) -> list[AppJob]:
    if target != CLUSTER_TARGET:
        raise AppJobsError(f"{service}: dev target {target} has no Jenkins job")
    return [
        AppJob(
            f"{service}-dev",
            DEV_PARAMETERS,
            f"deployImage(service: '{service}', environment: 'dev')",
        )
    ]


def production_jobs(service: str, target: object) -> list[AppJob]:
    call = PRODUCTION_CALLS.get(str(target))
    if call is None:
        raise AppJobsError(f"{service}: production target {target} has no Jenkins job")
    return [AppJob(f"{service}-production", VERSION_PARAMETERS, call.format(service=service))]


def jobs_for(config: dict[str, object]) -> list[AppJob]:
    service = str(config["service"])
    environments = cast("dict[str, dict[str, object]]", config["environments"])
    return (
        ci_jobs(service)
        + dev_jobs(service, environments["dev"]["target"])
        + production_jobs(service, environments["production"]["target"])
    )


def app_jobs(folder: Path) -> list[AppJob]:
    jobs = [
        job
        for path in folder.glob(ENVIRONMENT_GLOB)
        for job in jobs_for(yaml.safe_load(path.read_text()))
    ]
    return sorted(jobs, key=lambda job: job.name)


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        logger.error("usage: app_jobs.py <environments folder>")
        return EXIT_USAGE
    try:
        jobs = app_jobs(Path(argv[0]))
    except AppJobsError as error:
        logger.error("FAILED  %s", error)
        return EXIT_FAILED
    sys.stdout.write(json.dumps([asdict(job) for job in jobs]) + "\n")
    return 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    sys.exit(main(sys.argv[1:]))
