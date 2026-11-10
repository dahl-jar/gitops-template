from __future__ import annotations

import argparse
import base64
import json
import logging
import subprocess
import sys
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

import boto3
import yaml
from botocore.client import BaseClient
from botocore.exceptions import BotoCoreError, ClientError
from service_config import (
    AWS_REGION,
    CONFIG_FILE,
    KUSTOMIZATION_FILE,
    PRODUCTION_HOST_PATTERN,
    SECURE_STRING_TYPE,
    STRING_TYPE,
    Config,
    ConfigError,
    SecretSpec,
    load_config,
    overlay_dir,
    secret_sources,
)

ENV_FILE = "variables.env"
SECRETS_FOLDER = "sealedsecrets"
# change this: the public certificate of the Sealed Secrets controller
DEFAULT_CERT = "infra/certs/sealed-secrets.crt"
VERSIONS_ANNOTATION = "gitops.example.com/parameter-versions"
SYNC_WAVE_ANNOTATION = "argocd.argoproj.io/sync-wave"
SECRET_SYNC_WAVE = "-1"
YAML_LINE_WIDTH = 4096
KUSTOMIZATION_HEADER = "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n\nresources:\n"
LINE_BREAKS = ("\n", "\r")
VERSIONS_PATH = ("spec", "template", "metadata", "annotations", VERSIONS_ANNOTATION)
logger = logging.getLogger("render_config")


class SealError(Exception):
    pass


@dataclass(frozen=True)
class Parameter:
    name: str
    value: str
    type: str
    version: int


def ssm_client() -> BaseClient:
    return boto3.client("ssm", region_name=AWS_REGION)


def load_parameters(ssm: BaseClient, paths: Sequence[str]) -> dict[str, Parameter]:
    parameters: dict[str, Parameter] = {}
    for path in paths:
        request: dict[str, object] = {"Path": path, "WithDecryption": True, "Recursive": False}
        while True:
            answer = ssm.get_parameters_by_path(**request)
            for entry in answer["Parameters"]:
                key = entry["Name"].rsplit("/", 1)[-1]
                parameters[key] = Parameter(entry["Name"], entry["Value"], entry["Type"], entry["Version"])
            if "NextToken" not in answer:
                break
            request["NextToken"] = answer["NextToken"]
    return parameters


def _present(keys: Sequence[str], params: Mapping[str, Parameter]) -> list[str]:
    return [key for key in keys if key in params]


def _type_errors(label: str, keys: Sequence[str], params: Mapping[str, Parameter], expected: str) -> list[str]:
    return [
        f"{label} {key} has type {params[key].type}, expected {expected}"
        for key in keys
        if params[key].type != expected
    ]


def _line_break_errors(keys: Sequence[str], params: Mapping[str, Parameter]) -> list[str]:
    return [
        f"value of {key} has a line break"
        for key in keys
        if any(line_break in params[key].value for line_break in LINE_BREAKS)
    ]


def _production_host_errors(keys: Sequence[str], params: Mapping[str, Parameter]) -> list[str]:
    return [
        f"value of {key} names a production host"
        for key in keys
        if PRODUCTION_HOST_PATTERN.search(params[key].value)
    ]


def parameter_errors(config: Config, params: Mapping[str, Parameter]) -> list[str]:
    sources = secret_sources(config)
    joined_paths = ", ".join(config.paths)
    errors = [
        f"missing parameter {key} in {joined_paths}"
        for key in (*config.config_keys, *sources)
        if key not in params
    ]
    config_found = _present(config.config_keys, params)
    sources_found = _present(sources, params)
    errors += _type_errors("configKeys entry", config_found, params, STRING_TYPE)
    errors += _type_errors("secret source", sources_found, params, SECURE_STRING_TYPE)
    errors += _line_break_errors(config_found, params)
    errors += _production_host_errors([*config_found, *sources_found], params)
    return errors


def render_env(config: Config, params: Mapping[str, Parameter]) -> str:
    errors = parameter_errors(config, params)
    if errors:
        raise ConfigError("\n".join(errors))
    return "".join(f"{key}={params[key].value}\n" for key in sorted(config.config_keys))


def version_pairs(spec: SecretSpec, params: Mapping[str, Parameter]) -> dict[str, str]:
    return {
        secret_key: f"{params[source].name}:{params[source].version}"
        for secret_key, source in spec.keys.items()
    }


def annotation_value(namespace: str, secret_type: str, versions: Mapping[str, str]) -> str:
    return ",".join(
        [
            f"@namespace={namespace}",
            f"@type={secret_type}",
            *(f"{key}={versions[key]}" for key in sorted(versions)),
        ]
    )


def sealed_secret(
    name: str,
    namespace: str,
    values: Mapping[str, str],
    versions: Mapping[str, str],
    cert: Path,
    secret_type: str,
) -> str:
    secret = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {
            "name": name,
            "namespace": namespace,
            "annotations": {VERSIONS_ANNOTATION: annotation_value(namespace, secret_type, versions)},
        },
        "type": secret_type,
        "data": {key: base64.b64encode(value.encode()).decode() for key, value in values.items()},
    }
    command = ["kubeseal", "--cert", str(cert), "--format", "yaml", "--scope", "strict"]
    try:
        sealed = subprocess.run(command, input=json.dumps(secret), capture_output=True, text=True, check=True)
    except FileNotFoundError as error:
        message = "kubeseal is not on PATH"
        raise SealError(message) from error
    except subprocess.CalledProcessError as error:
        message = f"kubeseal failed for Secret {name} with exit code {error.returncode}"
        raise SealError(message) from None
    document = yaml.safe_load(sealed.stdout)
    document["metadata"].setdefault("annotations", {})[SYNC_WAVE_ANNOTATION] = SECRET_SYNC_WAVE
    return "---\n" + yaml.safe_dump(document, sort_keys=False, width=YAML_LINE_WIDTH)


def current_versions(path: Path) -> str | None:
    if not path.exists():
        return None
    node = yaml.safe_load(path.read_text())
    for field in VERSIONS_PATH:
        if not isinstance(node, dict) or field not in node:
            return None
        node = node[field]
    return str(node)


def sealed_documents(
    config: Config, params: Mapping[str, Parameter], folder: Path, cert: Path
) -> dict[str, str]:
    documents: dict[str, str] = {}
    for spec in sorted(config.secrets, key=lambda secret: secret.name):
        versions = version_pairs(spec, params)
        if current_versions(folder / f"{spec.name}.yaml") == annotation_value(config.namespace, spec.type, versions):
            logger.info("kept %s, parameter versions unchanged", spec.name)
            continue
        values = {secret_key: params[source].value for secret_key, source in spec.keys.items()}
        documents[spec.name] = sealed_secret(spec.name, config.namespace, values, versions, cert, spec.type)
    return documents


def kustomization_text(config: Config) -> str:
    names = sorted(spec.name for spec in config.secrets)
    return KUSTOMIZATION_HEADER + "".join(f"- {name}.yaml\n" for name in names)


def stale_files(config: Config, folder: Path) -> list[Path]:
    kept = {KUSTOMIZATION_FILE, *(f"{spec.name}.yaml" for spec in config.secrets)}
    return sorted(path for path in folder.glob("*.yaml") if path.name not in kept)


def write_secrets(
    folder: Path, documents: Mapping[str, str], kustomization: str, stale: Sequence[Path]
) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    for name, document in documents.items():
        (folder / f"{name}.yaml").write_text(document)
    (folder / KUSTOMIZATION_FILE).write_text(kustomization)
    for path in stale:
        path.unlink()


def _arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render a service's config and SealedSecrets from Parameter Store.")
    parser.add_argument("service")
    parser.add_argument("environment")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--cert", default=DEFAULT_CERT)
    parser.add_argument("--overlay")
    return parser.parse_args(argv)


def _render(repo_root: Path, service: str, environment: str, cert: Path, overlay_path: str | None) -> None:
    overlay = repo_root / overlay_path if overlay_path else overlay_dir(repo_root, service, environment)
    config_path = overlay / CONFIG_FILE
    config = load_config(config_path)
    if (config.service, config.environment) != (service, environment):
        message = f"{config_path} is for {config.service} {config.environment}, expected {service} {environment}"
        raise ConfigError(message)
    if not cert.exists():
        message = f"{cert} does not exist"
        raise ConfigError(message)
    params = load_parameters(ssm_client(), config.paths)
    env_text = render_env(config, params)
    folder = overlay / SECRETS_FOLDER
    documents = sealed_documents(config, params, folder, cert)
    kustomization = kustomization_text(config)
    stale = stale_files(config, folder)
    env_path = overlay / ENV_FILE
    env_path.write_text(env_text)
    logger.info("wrote %s", env_path.relative_to(repo_root))
    write_secrets(folder, documents, kustomization, stale)
    for name in documents:
        logger.info("resealed %s", name)
    for path in stale:
        logger.info("removed %s", path.relative_to(repo_root))
    logger.info("wrote %s", (folder / KUSTOMIZATION_FILE).relative_to(repo_root))


def main(argv: list[str]) -> int:
    arguments = _arguments(argv)
    repo_root = Path(arguments.repo_root)
    cert = Path(arguments.cert)
    if not cert.is_absolute():
        cert = repo_root / cert
    try:
        _render(repo_root, arguments.service, arguments.environment, cert, arguments.overlay)
    except (ConfigError, SealError) as error:
        for line in str(error).split("\n"):
            logger.error("%s", line)
        return 1
    except ClientError as error:
        logger.error("AWS error %s on %s", error.response["Error"]["Code"], error.operation_name)
        return 1
    except BotoCoreError as error:
        logger.error("AWS client error %s", type(error).__name__)
        return 1
    return 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    sys.exit(main(sys.argv[1:]))
