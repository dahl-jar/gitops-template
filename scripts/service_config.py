from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

import yaml

# change this: the AWS region of Parameter Store
AWS_REGION = "eu-west-1"
CONFIG_FILE = "config.yaml"
KUSTOMIZATION_FILE = "kustomization.yaml"
STRING_TYPE = "String"
SECURE_STRING_TYPE = "SecureString"
OPAQUE_TYPE = "Opaque"
# change this: a pattern that matches the production hosts
PRODUCTION_HOST_PATTERN = re.compile(r"\.example(?![\w-])|(?:^|[/.,])example\.com")
REQUIRED_FIELDS = ("service", "environment", "namespace", "paths", "configKeys", "secrets")


class ConfigError(Exception):
    pass


@dataclass(frozen=True)
class SecretSpec:
    name: str
    type: str
    keys: Mapping[str, str]


@dataclass(frozen=True)
class Config:
    service: str
    environment: str
    namespace: str
    paths: tuple[str, ...]
    config_keys: tuple[str, ...]
    secrets: tuple[SecretSpec, ...]


def overlay_dir(repo_root: Path, service: str, environment: str) -> Path:
    return repo_root / "deploy" / f"{service}-{environment}"


def _secret_keys(path: Path, name: str, entries: Sequence[object]) -> dict[str, str]:
    keys: dict[str, str] = {}
    for entry in entries:
        if isinstance(entry, str):
            keys[entry] = entry
        elif isinstance(entry, dict) and len(entry) == 1:
            keys.update(entry)
        else:
            message = f"{path}: secret {name} has an entry that is neither a name nor one SECRET_KEY: SOURCE pair"
            raise ConfigError(message)
    return keys


def load_config(path: Path) -> Config:
    if not path.exists():
        message = f"{path} does not exist"
        raise ConfigError(message)
    try:
        document = yaml.safe_load(path.read_bytes())
    except yaml.YAMLError as error:
        problem = getattr(error, "problem", None) or str(error).splitlines()[0]
        message = f"{path} is not valid YAML: {problem}"
        raise ConfigError(message) from error
    fields = document if isinstance(document, dict) else {}
    for field in REQUIRED_FIELDS:
        if field not in fields:
            message = f"{path} has no {field}"
            raise ConfigError(message)
    secrets = tuple(
        SecretSpec(name, body.get("type", OPAQUE_TYPE), _secret_keys(path, name, body["keys"]))
        for name, body in fields["secrets"].items()
    )
    return Config(
        service=fields["service"],
        environment=fields["environment"],
        namespace=fields["namespace"],
        paths=tuple(fields["paths"]),
        config_keys=tuple(fields["configKeys"]),
        secrets=secrets,
    )


def secret_sources(config: Config) -> tuple[str, ...]:
    return tuple(sorted({source for spec in config.secrets for source in spec.keys.values()}))
