from __future__ import annotations

import functools
import hashlib
import json
import logging
import os
from collections.abc import Mapping
from dataclasses import dataclass
from typing import TYPE_CHECKING, cast

import boto3

if TYPE_CHECKING:
    from collections.abc import Sequence

    from botocore.client import BaseClient

APPROVED = "approved"
PENDING = "pending"
DEPLOY = "deploy"
TERRAFORM = "terraform"
KINDS = (DEPLOY, TERRAFORM)
NO_APP = ""
KEY = "request_id"
KEY_PATH = ("dynamodb", "Keys", KEY, "S")
UNKNOWN_EVENT_ID = "unknown"
QUEUE_URL_VARIABLE = "QUEUE_URL"
APPROVALS_TABLE_VARIABLE = "APPROVALS_TABLE"
DECISIONS_TABLE_VARIABLE = "DECISIONS_TABLE"
UNHASHED = frozenset({"content_hash", "status", "status_at", "status_detail"})

logger = logging.getLogger("approval_forwarder")
logger.setLevel(logging.INFO)

Item = Mapping[str, Mapping[str, object]]
Plain = dict[str, str | int]


class ApprovalRecordError(Exception):
    pass


@dataclass(frozen=True)
class ApprovalMessage:
    app: str
    kind: str
    request_id: str

    def body(self) -> str:
        return json.dumps({"app": self.app, "kind": self.kind, "request_id": self.request_id}, sort_keys=True)


def record_request_id(record: Mapping[str, object]) -> str:
    value: object = record
    for step in KEY_PATH:
        value = value.get(step) if isinstance(value, Mapping) else None
    if isinstance(value, str):
        return value
    event_id = record.get("eventID", UNKNOWN_EVENT_ID)
    msg = f"record {event_id} has no request_id key"
    raise ApprovalRecordError(msg)


def plain_value(attribute: Mapping[str, object], name: str, owner: str) -> str | int:
    text = attribute.get("S")
    if isinstance(text, str):
        return text
    number = attribute.get("N")
    if isinstance(number, str):
        try:
            return int(number)
        except ValueError:
            msg = f"{owner} has attribute {name} with number {number}, expected an integer"
            raise ApprovalRecordError(msg) from None
    kind = next(iter(attribute), "none")
    msg = f"{owner} has attribute {name} of type {kind}, expected S or N"
    raise ApprovalRecordError(msg)


def plain_item(item: Item, owner: str) -> Plain:
    return {name: plain_value(attribute, name, owner) for name, attribute in item.items()}


def content_hash(request: Mapping[str, str | int]) -> str:
    hashed = {name: value for name, value in request.items() if name not in UNHASHED}
    text = json.dumps(hashed, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(text.encode()).hexdigest()


def string_attribute(item: Plain, name: str, owner: str) -> str:
    value = item.get(name)
    if isinstance(value, str):
        return value
    msg = f"{owner} has no string attribute {name}"
    raise ApprovalRecordError(msg)


def number_attribute(item: Plain, name: str, owner: str) -> int:
    value = item.get(name)
    if isinstance(value, int):
        return value
    msg = f"{owner} has no number attribute {name}"
    raise ApprovalRecordError(msg)


def approved_decision(request_id: str, decision: Item | None) -> Plain:
    if decision is None:
        msg = f"request {request_id} has no decision item"
        raise ApprovalRecordError(msg)
    owner = f"decision {request_id}"
    plain = plain_item(decision, owner)
    verdict = string_attribute(plain, "decision", owner)
    if verdict != APPROVED:
        msg = f"{owner} has decision {verdict}, expected approved"
        raise ApprovalRecordError(msg)
    return plain


def check_window(request_id: str, decision: Plain, request: Plain) -> None:
    decided_at = number_attribute(decision, "decided_at", f"decision {request_id}")
    approve_before = number_attribute(request, "approve_before", f"request {request_id}")
    if decided_at >= approve_before:
        msg = f"request {request_id} expired at {approve_before}, and its decision was made at {decided_at}"
        raise ApprovalRecordError(msg)


def check_hash(request_id: str, decision: Plain, request: Plain) -> None:
    owner = f"request {request_id}"
    computed = content_hash(request)
    stored = string_attribute(request, "content_hash", owner)
    if computed != stored:
        msg = f"{owner} has content hash {computed}, and its stored content_hash is {stored}"
        raise ApprovalRecordError(msg)
    approved = string_attribute(decision, "content_hash", f"decision {request_id}")
    if computed != approved:
        msg = f"{owner} has content hash {computed}, and its decision approved {approved}"
        raise ApprovalRecordError(msg)


def approval_message(request_id: str, decision: Item | None, request: Item | None) -> ApprovalMessage | None:
    plain_decision = approved_decision(request_id, decision)
    owner = f"request {request_id}"
    if request is None:
        msg = f"{owner} has no item in the approvals table"
        raise ApprovalRecordError(msg)
    plain_request = plain_item(request, owner)
    status = string_attribute(plain_request, "status", owner)
    if status != PENDING:
        logger.info("approval skipped request_id=%s status=%s", request_id, status)
        return None
    check_window(request_id, plain_decision, plain_request)
    kind = string_attribute(plain_request, "kind", owner)
    if kind not in KINDS:
        msg = f"{owner} has kind {kind}, expected deploy or terraform"
        raise ApprovalRecordError(msg)
    check_hash(request_id, plain_decision, plain_request)
    app = string_attribute(plain_request, "app", owner) if kind == DEPLOY else NO_APP
    return ApprovalMessage(app=app, kind=kind, request_id=request_id)


@functools.cache
def dynamodb_client() -> BaseClient:
    return boto3.client("dynamodb")


@functools.cache
def sqs_client() -> BaseClient:
    return boto3.client("sqs")


def stored_item(table_variable: str, request_id: str) -> Item | None:
    response = dynamodb_client().get_item(
        TableName=os.environ[table_variable],
        Key={KEY: {"S": request_id}},
        ConsistentRead=True,
    )
    return cast("Item | None", response.get("Item"))


def checked_message(record: Mapping[str, object]) -> ApprovalMessage | None:
    request_id = record_request_id(record)
    logger.info("approval received request_id=%s", request_id)
    try:
        return approval_message(
            request_id,
            stored_item(DECISIONS_TABLE_VARIABLE, request_id),
            stored_item(APPROVALS_TABLE_VARIABLE, request_id),
        )
    except ApprovalRecordError as error:
        logger.error("approval refused request_id=%s reason=%s", request_id, error)
        raise


def handler(event: Mapping[str, object], _context: object) -> None:
    records = cast("Sequence[Mapping[str, object]]", event["Records"])
    messages = [checked_message(record) for record in records]
    for message in messages:
        if message is None:
            continue
        sqs_client().send_message(QueueUrl=os.environ[QUEUE_URL_VARIABLE], MessageBody=message.body())
        logger.info("approval forwarded kind=%s request_id=%s", message.kind, message.request_id)
