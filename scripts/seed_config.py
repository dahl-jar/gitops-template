from __future__ import annotations

import argparse
import getpass
import logging
import re
import secrets
import string
import sys
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from botocore.client import BaseClient
from botocore.exceptions import BotoCoreError, ClientError
from render_config import ssm_client
from service_config import (
    CONFIG_FILE,
    PRODUCTION_HOST_PATTERN,
    SECURE_STRING_TYPE,
    STRING_TYPE,
    ConfigError,
    load_config,
    overlay_dir,
    secret_sources,
)

SHARED_ENVIRONMENT = "shared"
MANAGED_KEY = "alias/aws/ssm"
GENERATED_ALPHABET = string.ascii_letters + string.digits
GENERATED_LENGTH = 32
ALREADY_EXISTS = "ParameterAlreadyExists"
# change this: the name of the dev host
ENVIRONMENT_HOST_PATTERN = re.compile(PRODUCTION_HOST_PATTERN.pattern + r"|example-dev")
COMMENT_PREFIX = "#"
GENERATE_OPTION = "--generate"
ROTATE_OPTION = "--rotate"
ONLY_OPTION = "--only"
logger = logging.getLogger("seed_config")


@dataclass(frozen=True)
class SeedKeys:
    path: str
    config_keys: tuple[str, ...]
    secret_keys: tuple[str, ...]

    @property
    def known(self) -> set[str]:
        return {*self.config_keys, *self.secret_keys}


def seed_keys(repo_root: Path, service: str, environment: str) -> SeedKeys:
    # change this: the Parameter Store path of a service
    path = f"/gitops/{service}/{environment}"
    if environment == SHARED_ENVIRONMENT:
        configs = [load_config(file) for file in sorted(repo_root.glob(f"deploy/*/{CONFIG_FILE}"))]
        matching = [config for config in configs if config.service == service and path in config.paths]
        if not matching:
            message = f"no {CONFIG_FILE} for {service} under deploy/"
            raise ConfigError(message)
        config_keys = sorted({key for config in matching for key in config.config_keys})
        return SeedKeys(path, tuple(config_keys), ())
    config_path = overlay_dir(repo_root, service, environment) / CONFIG_FILE
    config = load_config(config_path)
    if path not in config.paths:
        message = f"{path} is not in the paths of {config_path}"
        raise ConfigError(message)
    return SeedKeys(path, config.config_keys, secret_sources(config))


def read_env_file(path: Path) -> dict[str, str]:
    if not path.exists():
        message = f"{path} does not exist"
        raise ConfigError(message)
    values: dict[str, str] = {}
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip() or line.startswith(COMMENT_PREFIX):
            continue
        key, separator, value = line.partition("=")
        if not separator:
            message = f"{path} line {number} has no ="
            raise ConfigError(message)
        values[key] = value
    return values


def generate_secret() -> str:
    return "".join(secrets.choice(GENERATED_ALPHABET) for _ in range(GENERATED_LENGTH))


def _option_problems(keys: SeedKeys, only: Sequence[str], option: str, option_keys: Sequence[str], label: str) -> list[str]:
    problems = []
    for key in option_keys:
        if key in keys.config_keys:
            problems.append(f"{option} {key} is not a secret key of {label}")
        if only and key in keys.known and key not in only:
            problems.append(f"{option} {key} is not selected by {ONLY_OPTION}")
    return problems


def check_requested(keys: SeedKeys, only: Sequence[str], options: Mapping[str, Sequence[str]], label: str) -> None:
    requested = [*only, *(key for option_keys in options.values() for key in option_keys)]
    problems = [f"{key} is not a key of {label}" for key in dict.fromkeys(requested) if key not in keys.known]
    for option, option_keys in options.items():
        problems += _option_problems(keys, only, option, option_keys, label)
    if problems:
        raise ConfigError("\n".join(problems))


def shared_value_error(key: str, value: str) -> str | None:
    if ENVIRONMENT_HOST_PATTERN.search(value):
        return f"{key} names an environment-specific host, seed it under dev or prod"
    return None


def _arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Put a service's config and secrets into Parameter Store.")
    parser.add_argument("service")
    parser.add_argument("environment")
    parser.add_argument("--from-env", metavar="PATH")
    parser.add_argument(GENERATE_OPTION, nargs="+", default=[], metavar="KEY")
    parser.add_argument(ROTATE_OPTION, nargs="+", default=[], metavar="KEY")
    parser.add_argument(ONLY_OPTION, nargs="+", default=[], metavar="KEY")
    return parser.parse_args(argv)


def _selected(keys: Sequence[str], only: Sequence[str]) -> list[str]:
    return sorted(key for key in keys if not only or key in only)


def _file_values(from_env: str | None, keys: SeedKeys) -> dict[str, str]:
    if from_env is None:
        return {}
    values = read_env_file(Path(from_env))
    for key in values:
        if key not in keys.config_keys:
            logger.info("%s in %s is not a configKeys entry, skipped", key, from_env)
    return values


def _check_shared(values: Mapping[str, str]) -> None:
    errors = [error for key, value in values.items() if (error := shared_value_error(key, value))]
    if errors:
        raise ConfigError("\n".join(errors))


def _store(ssm: BaseClient, path: str, key: str, value: str, parameter_type: str, *, overwrite: bool) -> bool:
    request: dict[str, object] = {"Name": f"{path}/{key}", "Value": value, "Type": parameter_type, "Overwrite": overwrite}
    if parameter_type == SECURE_STRING_TYPE:
        request["KeyId"] = MANAGED_KEY
    try:
        version = ssm.put_parameter(**request)["Version"]
    except ClientError as error:
        code = error.response["Error"]["Code"]
        if code == ALREADY_EXISTS and not overwrite:
            logger.info("%s exists, kept the current value", key)
            return True
        logger.error("AWS error %s on %s for %s", code, error.operation_name, key)
        return False
    except BotoCoreError as error:
        logger.error("AWS client error %s for %s", type(error).__name__, key)
        return False
    logger.info("%s version %d", key, version)
    return True


def _config_value(key: str, file_values: Mapping[str, str], shared: bool) -> str:
    if key in file_values:
        return file_values[key]
    value = input(f"{key} (String, empty skips): ")
    error = shared_value_error(key, value) if shared else None
    if error:
        raise ConfigError(error)
    return value


def _put_config_keys(
    ssm: BaseClient, path: str, selected: Sequence[str], file_values: Mapping[str, str], *, shared: bool
) -> bool:
    for key in selected:
        value = _config_value(key, file_values, shared)
        if not value:
            logger.info("%s skipped, empty value", key)
        elif not _store(ssm, path, key, value, STRING_TYPE, overwrite=True):
            return False
    return True


def _put_secret_keys(
    ssm: BaseClient, path: str, selected: Sequence[str], generate: Sequence[str], rotate: Sequence[str]
) -> bool:
    for key in selected:
        rotated = key in rotate
        generated = rotated or key in generate
        value = generate_secret() if generated else getpass.getpass(f"{key} (SecureString, empty skips): ")
        if not value:
            logger.info("%s skipped, empty value", key)
        elif not _store(ssm, path, key, value, SECURE_STRING_TYPE, overwrite=rotated or not generated):
            return False
    return True


def _seed(arguments: argparse.Namespace) -> int:
    label = f"{arguments.service} {arguments.environment}"
    shared = arguments.environment == SHARED_ENVIRONMENT
    keys = seed_keys(Path(), arguments.service, arguments.environment)
    check_requested(keys, arguments.only, {GENERATE_OPTION: arguments.generate, ROTATE_OPTION: arguments.rotate}, label)
    file_values = _file_values(arguments.from_env, keys)
    config_keys = _selected(keys.config_keys, arguments.only)
    if shared:
        _check_shared({key: file_values[key] for key in config_keys if key in file_values})
    ssm = ssm_client()
    secret_keys = _selected(keys.secret_keys, arguments.only)
    stored = _put_config_keys(ssm, keys.path, config_keys, file_values, shared=shared) and _put_secret_keys(
        ssm, keys.path, secret_keys, arguments.generate, arguments.rotate
    )
    return 0 if stored else 1


def main(argv: list[str]) -> int:
    arguments = _arguments(argv)
    try:
        return _seed(arguments)
    except ConfigError as error:
        for line in str(error).split("\n"):
            logger.error("%s", line)
        return 1


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    sys.exit(main(sys.argv[1:]))
