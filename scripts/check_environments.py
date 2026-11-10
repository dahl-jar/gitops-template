#!/usr/bin/env python3
from __future__ import annotations

import json
import logging
import re
import sys
from collections.abc import Mapping
from functools import cache
from pathlib import Path
from typing import cast

import yaml
from jsonschema import Draft202012Validator
from service_config import CONFIG_FILE, KUSTOMIZATION_FILE

SCHEMA_PATH = Path(__file__).resolve().parent.parent / "environments" / "schema.json"
DUPLICATE_KEYS = ("service", "repo")
ECR_IMAGE_PATTERN = re.compile(r"^[0-9]+\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/(.+)$")
MAX_ECR_REPOSITORIES = 1

logger = logging.getLogger("check_environments")


class EnvironmentFileError(Exception):
    pass


@cache
def schema_validator() -> Draft202012Validator:
    schema = json.loads(SCHEMA_PATH.read_text())
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def load(path: Path) -> dict[str, object]:
    try:
        config = yaml.safe_load(path.read_text())
    except OSError as error:
        raise EnvironmentFileError(f"cannot read file: {error.strerror}") from error
    except yaml.YAMLError as error:
        raise EnvironmentFileError(f"cannot parse YAML: {error}") from error
    if not isinstance(config, dict):
        raise EnvironmentFileError("top level must be a mapping")
    return config


def ecr_repositories(environments: dict[str, dict[str, object]]) -> list[str]:
    images = (environment.get("image") for environment in environments.values())
    matches = (
        ECR_IMAGE_PATTERN.match(image) for image in images if isinstance(image, str)
    )
    return sorted({match.group(1) for match in matches if match})


def file_errors(name: str, environment: dict[str, object], root: Path) -> list[str]:
    overlay = environment.get("overlay")
    required = [
        ("versions", environment.get("versions"), KUSTOMIZATION_FILE),
        ("overlay", overlay, KUSTOMIZATION_FILE),
    ]
    if "config" in environment:
        required.append(("config", overlay, CONFIG_FILE))
    return [
        f"$.environments.{name}.{field}: {folder}/{file} does not exist"
        for field, folder, file in required
        if isinstance(folder, str) and not (root / folder / file).is_file()
    ]


def validate(config: dict[str, object], root: Path) -> list[str]:
    errors = sorted(
        f"{error.json_path}: {error.message}"
        for error in schema_validator().iter_errors(config)
    )
    if errors:
        return errors
    environments = cast("dict[str, dict[str, object]]", config["environments"])
    for name, environment in environments.items():
        errors += file_errors(name, environment, root)
    repositories = ecr_repositories(environments)
    if len(repositories) > MAX_ECR_REPOSITORIES:
        errors.append(
            f"$.environments: images name {len(repositories)} ECR repositories "
            f"({', '.join(repositories)}), expected at most {MAX_ECR_REPOSITORIES}"
        )
    return errors


def check_file(path: Path) -> tuple[dict[str, object] | None, list[str]]:
    try:
        config = load(path)
    except EnvironmentFileError as error:
        return None, [str(error)]
    errors = validate(config, path.resolve().parent.parent)
    if errors:
        return None, errors
    service = config["service"]
    if service != path.stem:
        return config, [
            f"$.service: '{service}' does not match the file name '{path.name}'"
        ]
    return config, []


def duplicate_errors(configs: Mapping[str, dict[str, object]]) -> dict[str, list[str]]:
    errors: dict[str, list[str]] = {}
    for key in DUPLICATE_KEYS:
        groups: dict[str, list[str]] = {}
        for arg, config in configs.items():
            groups.setdefault(str(config[key]), []).append(arg)
        for value, args in groups.items():
            for arg in args:
                others = [other for other in args if other != arg]
                if others:
                    errors.setdefault(arg, []).append(
                        f"$.{key}: '{value}' is also in {', '.join(others)}"
                    )
    return errors


def main(argv: list[str]) -> int:
    if not argv:
        logger.error("FAILED  no environment files given")
        return 1
    errors: dict[str, list[str]] = {}
    configs: dict[str, dict[str, object]] = {}
    for arg in argv:
        config, errors[arg] = check_file(Path(arg))
        if config is not None:
            configs[arg] = config
    for arg, duplicates in duplicate_errors(configs).items():
        errors[arg].extend(duplicates)
    for arg, messages in errors.items():
        for error in messages:
            logger.error("FAILED  %s: %s", arg, error)
        if not messages:
            logger.info("ok      %s", arg)
    return 1 if any(errors.values()) else 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    sys.exit(main(sys.argv[1:]))
