#!/usr/bin/env python3
from __future__ import annotations

import argparse
import logging
import subprocess
import sys
from pathlib import Path

import yaml
from check_storage_classes import identity

REPO = Path(__file__).resolve().parent.parent
MANIFEST_DIRS = ("apps", "platform/argocd")
RENDER_DIR = REPO / "out"
RENDER_SEPARATOR = "__"
PROJECT_KIND = "AppProject"
APPLICATION_KIND = "Application"
VALUES_PREFIX = "$values/"
HELM_DEFAULT_NAMESPACE = "default"
CLUSTER_WHITELIST = "clusterResourceWhitelist"
NAMESPACE_WHITELIST = "namespaceResourceWhitelist"
CLUSTER_SCOPED = frozenset(
    {
        ("", "Namespace"),
        ("", "PersistentVolume"),
        ("rbac.authorization.k8s.io", "ClusterRole"),
        ("rbac.authorization.k8s.io", "ClusterRoleBinding"),
        ("storage.k8s.io", "StorageClass"),
        ("apiextensions.k8s.io", "CustomResourceDefinition"),
        ("scheduling.k8s.io", "PriorityClass"),
        ("networking.k8s.io", "IngressClass"),
        ("admissionregistration.k8s.io", "MutatingWebhookConfiguration"),
        ("admissionregistration.k8s.io", "ValidatingWebhookConfiguration"),
        ("admissionregistration.k8s.io", "ValidatingAdmissionPolicy"),
        ("admissionregistration.k8s.io", "ValidatingAdmissionPolicyBinding"),
    }
)
EXIT_FINDINGS = 1
logger = logging.getLogger("check_project_kinds")


class RenderError(Exception):
    pass


def documents(text: str) -> list[dict]:
    return [doc for doc in yaml.safe_load_all(text) if isinstance(doc, dict)]


def repo_manifests(repo: Path) -> list[dict]:
    return [
        doc
        for directory in MANIFEST_DIRS
        for path in sorted((repo / directory).glob("*.yaml"))
        for doc in documents(path.read_text())
    ]


def group_kind(doc: dict) -> tuple[str, str]:
    api_version = doc.get("apiVersion", "")
    group = api_version.rpartition("/")[0]
    return group, doc.get("kind", "")


def whitelist_finding(project: dict, doc: dict) -> str | None:
    group, kind = group_kind(doc)
    field = CLUSTER_WHITELIST if (group, kind) in CLUSTER_SCOPED else NAMESPACE_WHITELIST
    allowed = {(entry.get("group"), entry.get("kind")) for entry in project["spec"].get(field) or []}
    if (group, kind) in allowed:
        return None
    return f"{identity(doc)}: {kind} in group '{group}' is outside {field} of project {project['metadata']['name']}"


def render_chart(application: dict, source: dict, repo: Path) -> list[dict]:
    helm = source.get("helm", {})
    namespace = application["spec"]["destination"].get("namespace", HELM_DEFAULT_NAMESPACE)
    command = [
        "helm",
        "template",
        helm.get("releaseName", application["metadata"]["name"]),
        source["chart"],
        "--repo",
        source["repoURL"],
        "--version",
        source["targetRevision"],
        "--namespace",
        namespace,
        "--skip-tests",
    ]
    for values in helm.get("valueFiles", []):
        command += ["--values", str(repo / values.removeprefix(VALUES_PREFIX))]
    result = subprocess.run(command, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        message = f"chart {source['chart']} {source['targetRevision']} did not render: {result.stderr.strip()}"
        raise RenderError(message)
    return documents(result.stdout)


def read_render(source: dict, renders: Path) -> list[dict]:
    path = source["path"]
    render = renders / f"{path.replace('/', RENDER_SEPARATOR)}.yaml"
    if not render.is_file():
        message = f"no render of {path} at {render}"
        raise RenderError(message)
    return documents(render.read_text())


def rendered_objects(application: dict, repo: Path, renders: Path) -> list[dict]:
    spec = application["spec"]
    objects = []
    for source in spec.get("sources") or [spec["source"]]:
        if "chart" in source:
            objects += render_chart(application, source, repo)
        elif "path" in source:
            objects += read_render(source, renders)
    return objects


def application_findings(project: dict, application: dict, repo: Path, renders: Path) -> list[str]:
    name = application["metadata"]["name"]
    try:
        objects = rendered_objects(application, repo, renders)
    except RenderError as error:
        return [f"{name}: {error}"]
    return [f"{name}: {finding}" for doc in objects if (finding := whitelist_finding(project, doc)) is not None]


def project_named(manifests: list[dict], name: str) -> dict | None:
    return next(
        (doc for doc in manifests if doc.get("kind") == PROJECT_KIND and doc["metadata"]["name"] == name),
        None,
    )


def project_applications(manifests: list[dict], name: str) -> list[dict]:
    return [doc for doc in manifests if doc.get("kind") == APPLICATION_KIND and doc["spec"].get("project") == name]


def findings(manifests: list[dict], project_name: str, repo: Path, renders: Path) -> list[str]:
    project = project_named(manifests, project_name)
    if project is None:
        return [f"no {PROJECT_KIND} named {project_name}"]
    applications = project_applications(manifests, project_name)
    if not applications:
        return [f"no {APPLICATION_KIND} uses project {project_name}"]
    return [
        finding for application in applications for finding in application_findings(project, application, repo, renders)
    ]


def _arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check that each Application of a project renders only kinds the AppProject allows."
    )
    parser.add_argument("projects", nargs="+")
    parser.add_argument("--renders", type=Path, default=RENDER_DIR)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    arguments = _arguments(argv)
    manifests = repo_manifests(REPO)
    result = [
        finding for project in arguments.projects for finding in findings(manifests, project, REPO, arguments.renders)
    ]
    if result:
        for finding in result:
            logger.error("FAILED  %s", finding)
        return EXIT_FINDINGS
    logger.info("ok      projects %s allow every rendered kind", ", ".join(arguments.projects))
    return 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    sys.exit(main(sys.argv[1:]))
