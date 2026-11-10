#!/usr/bin/env python3
from __future__ import annotations

import logging
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

# change this: the name and e-mail Jenkins commits with
JENKINS_AUTHOR = "Jenkins <jenkins@example.com>"
NO_COMMIT = "0" * 40
ENVIRONMENTS_DIR = "environments"
ENVIRONMENT_GLOB = "*.yaml"
PIN_PATH = re.compile(r"^versions/(?:[^/]+/)+kustomization\.yaml$")
MIN_ARGUMENTS = 2
MAX_ARGUMENTS = 3
EXIT_USAGE = 2
EXIT_FAILURE = 1
PROD_BRANCH = "prod"
PROD_REF = "origin/prod"
VALUES_PATH = "platform/jenkins/values.yaml"
LISTENER_PATH = "platform/jenkins-hook/deployment.yaml"
REGULAR_FILE = "100644"
# change this: the host of the image registry
REGISTRY_HOST = "123456789012.dkr.ecr.eu-west-1.amazonaws.com"
REGISTRY = re.escape(REGISTRY_HOST)
HUNK_HEADER = re.compile(r"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@")
REMOVED = "-"
ADDED = "+"
DIFF_OPTIONS = ("-U0", "--text", "--no-color", "--no-ext-diff", "--no-textconv")
USAGE = "usage: check_jenkins_commits.py <before> <after> [branch]"
logger = logging.getLogger("check_jenkins_commits")


@dataclass(frozen=True)
class PinLine:
    line: re.Pattern[str]
    valid: re.Pattern[str]


@dataclass
class Hunk:
    old_start: int
    new_start: int
    removed: list[str] = field(default_factory=list)
    added: list[str] = field(default_factory=list)


DEFAULT_VERSION = PinLine(
    line=re.compile(r'^(?P<key>\s+defaultVersion: )"[^"]*"$'),
    valid=re.compile(r'^(?P<key>\s+defaultVersion: )"[0-9a-f]{40}"$'),
)
TOOLS_IMAGE = PinLine(
    line=re.compile(rf"^(?P<key>\s+image: ){REGISTRY}/ci-tools:\S+$"),
    valid=re.compile(
        rf"^(?P<key>\s+image: ){REGISTRY}/ci-tools:tools-v[1-9][0-9]*@sha256:[0-9a-f]{{64}}$"
    ),
)
LISTENER_IMAGE = PinLine(
    line=re.compile(rf"^(?P<key>\s+image: ){REGISTRY}/hook-listener:\S+$"),
    valid=re.compile(
        rf"^(?P<key>\s+image: ){REGISTRY}/hook-listener:listener-v[1-9][0-9]*"
        r"@sha256:[0-9a-f]{64}$"
    ),
)
RELEASE_PIN_LINES: dict[str, tuple[PinLine, ...]] = {
    VALUES_PATH: (DEFAULT_VERSION, TOOLS_IMAGE),
    LISTENER_PATH: (LISTENER_IMAGE,),
}


def services(repo: Path) -> list[str]:
    return sorted(path.stem for path in (repo / ENVIRONMENTS_DIR).glob(ENVIRONMENT_GLOB))


def allowed_paths(services: list[str]) -> tuple[re.Pattern[str], ...]:
    patterns = [PIN_PATH]
    for service in services:
        overlay = rf"^deploy/{re.escape(service)}(?:-dev)?/"
        patterns.append(re.compile(rf"{overlay}variables\.env$"))
        patterns.append(re.compile(rf"{overlay}sealedsecrets/[^/]+\.yaml$"))
    return tuple(patterns)


def git_output(repo: Path, *arguments: str) -> str:
    command = ["git", "-C", str(repo), *arguments]
    result = subprocess.run(command, capture_output=True, check=False)
    if result.returncode != 0:
        raise subprocess.CalledProcessError(
            result.returncode, command, result.stdout, result.stderr.decode(errors="replace")
        )
    return result.stdout.decode(errors="replace")


def git_lines(repo: Path, *arguments: str) -> list[str]:
    return [line for line in git_output(repo, *arguments).split("\n") if line]


def jenkins_commits(repo: Path, before: str, after: str) -> list[str]:
    entries = git_lines(
        repo, "log", "--reverse", "--format=%H%x09%an <%ae>", f"{before}..{after}"
    )
    return [
        sha
        for sha, author in (entry.split("\t", 1) for entry in entries)
        if author == JENKINS_AUTHOR
    ]


def changed_paths(repo: Path, sha: str) -> list[str]:
    return git_lines(
        repo, "diff-tree", "-r", "--root", "--cc", "--name-only", "--no-commit-id", sha
    )


def hunks(diff: list[str]) -> list[Hunk]:
    found: list[Hunk] = []
    for line in diff:
        header = HUNK_HEADER.match(line)
        if header:
            found.append(Hunk(int(header[1]), int(header[2])))
        elif found and line.startswith(REMOVED):
            found[-1].removed.append(line[1:])
        elif found and line.startswith(ADDED):
            found[-1].added.append(line[1:])
    return found


def file_hunks(repo: Path, sha: str, path: str) -> list[Hunk]:
    diff = git_output(repo, "diff", *DIFF_OPTIONS, f"{sha}^", sha, "--", path)
    return hunks(diff.split("\n"))


def is_pin_change(removed: str, added: str, pins: tuple[PinLine, ...]) -> bool:
    for pin in pins:
        line = pin.line.match(removed)
        valid = pin.valid.match(added)
        if line and valid and line["key"] == valid["key"]:
            return True
    return False


def hunk_findings(sha: str, path: str, hunk: Hunk) -> list[str]:
    if len(hunk.removed) != len(hunk.added):
        return [
            f"Jenkins commit {sha} removed {len(hunk.removed)} and added {len(hunk.added)} "
            f"lines at line {hunk.old_start} of {path}. "
            "Release pins replace each pin line in place."
        ]
    pairs = zip(hunk.removed, hunk.added, strict=True)
    return [
        f"Jenkins commit {sha} changed line {hunk.new_start + index} of {path}, "
        "which is not a valid release pin line"
        for index, (removed, added) in enumerate(pairs)
        if not is_pin_change(removed, added, RELEASE_PIN_LINES[path])
    ]


def parent_count(repo: Path, sha: str) -> int:
    return len(git_lines(repo, "rev-list", "--parents", "-n", "1", sha)[0].split()) - 1


def on_prod(repo: Path, sha: str) -> bool:
    command = ["git", "-C", str(repo), "merge-base", "--is-ancestor", sha, PROD_REF]
    return subprocess.run(command, capture_output=True, check=False).returncode == 0


def edits_regular_file(repo: Path, sha: str, path: str) -> bool:
    entries = git_lines(
        repo, "diff-tree", "-r", "--raw", "--no-renames", "--no-commit-id", sha, "--", path
    )
    return bool(entries) and all(
        entry[1:].split(" ")[:2] == [REGULAR_FILE, REGULAR_FILE] for entry in entries
    )


def has_mixed_values(repo: Path, sha: str, path: str) -> bool:
    if path != VALUES_PATH:
        return False
    values = {
        line[match.end("key"):]
        for line in git_output(repo, "show", f"{sha}:{path}").split("\n")
        if (match := TOOLS_IMAGE.line.match(line))
    }
    return len(values) > 1


def commit_finding(repo: Path, sha: str, path: str, branch: str | None) -> str | None:
    if branch != PROD_BRANCH and not on_prod(repo, sha):
        return f"Jenkins commit {sha} changed {path} outside prod. Release pins go to prod only."
    parents = parent_count(repo, sha)
    if parents == 0:
        return (
            f"Jenkins commit {sha} changed {path} in a root commit. "
            "Release pins must be single-parent commits."
        )
    if parents > 1:
        return (
            f"Jenkins commit {sha} changed {path} in a merge. "
            "Release pins must be single-parent commits."
        )
    if not edits_regular_file(repo, sha, path):
        return (
            f"Jenkins commit {sha} deleted {path} or changed its mode or type. "
            "Release pins edit a regular file in place."
        )
    return None


def release_pin_findings(repo: Path, sha: str, path: str, branch: str | None) -> list[str]:
    finding = commit_finding(repo, sha, path, branch)
    if finding:
        return [finding]
    found = [
        finding
        for hunk in file_hunks(repo, sha, path)
        for finding in hunk_findings(sha, path, hunk)
    ]
    if has_mixed_values(repo, sha, path):
        found.append(
            f"Jenkins commit {sha} left {path} with more than one ci-tools image. "
            "Release pins set every ci-tools line to the same image."
        )
    return found


def path_findings(
    repo: Path,
    sha: str,
    path: str,
    allowed: tuple[re.Pattern[str], ...],
    branch: str | None,
) -> list[str]:
    if path in RELEASE_PIN_LINES:
        return release_pin_findings(repo, sha, path, branch)
    if any(pattern.match(path) for pattern in allowed):
        return []
    return [f"Jenkins commit {sha} changed {path}, which is outside the pin and config files"]


def findings(repo: Path, commits: list[str], branch: str | None) -> list[str]:
    allowed = allowed_paths(services(repo))
    return [
        finding
        for sha in commits
        for path in changed_paths(repo, sha)
        for finding in path_findings(repo, sha, path, allowed, branch)
    ]


def main(argv: list[str]) -> int:
    if not MIN_ARGUMENTS <= len(argv) <= MAX_ARGUMENTS:
        logger.error(USAGE)
        return EXIT_USAGE
    before, after = argv[:MIN_ARGUMENTS]
    branch = argv[MIN_ARGUMENTS] if len(argv) == MAX_ARGUMENTS else None
    if before == NO_COMMIT:
        logger.info("branch created, no earlier commit to compare")
        return 0
    repo = Path.cwd()
    try:
        commits = jenkins_commits(repo, before, after)
        found = findings(repo, commits, branch)
    except subprocess.CalledProcessError as error:
        logger.error("cannot list commits %s..%s: %s", before, after, error.stderr.strip())
        return EXIT_FAILURE
    for finding in found:
        logger.error(finding)
    logger.info("checked %d Jenkins commits in %s..%s", len(commits), before, after)
    return EXIT_FAILURE if found else 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    sys.exit(main(sys.argv[1:]))
