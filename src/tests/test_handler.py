import os
import json
import boto3
from moto import mock_aws

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # .../src

from count_function.count_lambda import handler  # noqa: E402

# Test-time configuration (overridable via env)
TABLE_NAME = os.getenv("TEST_TABLE_NAME", "test-crc-visitors")
SITE_ID    = os.getenv("TEST_SITE_ID", "patrick-site")
REGION     = os.getenv("AWS_DEFAULT_REGION", "us-east-1")

@mock_aws
def test_counter_creates_and_increments_item():
    # Env vars expected by the Lambda
    os.environ["AWS_DEFAULT_REGION"] = REGION
    os.environ["TABLE_NAME"] = TABLE_NAME
    os.environ["SITE_ID"]    = SITE_ID

    # Create mock DynamoDB table
    ddb = boto3.client("dynamodb", region_name=REGION)
    ddb.create_table(
        TableName=TABLE_NAME,
        BillingMode="PAY_PER_REQUEST",
        AttributeDefinitions=[{"AttributeName": "pk", "AttributeType": "S"}],
        KeySchema=[{"AttributeName": "pk", "KeyType": "HASH"}],
    )

    # 1st call: creates item with count = 1
    resp1 = handler({}, {})
    body1 = json.loads(resp1["body"])
    assert resp1["statusCode"] == 200
    assert isinstance(body1["count"], int)
    assert body1["count"] == 1

    # 2nd call: increments to 2
    resp2 = handler({}, {})
    body2 = json.loads(resp2["body"])
    assert resp2["statusCode"] == 200
    assert body2["count"] == 2

    # Verify table contents directly
    item = ddb.get_item(
        TableName=TABLE_NAME,
        Key={"pk": {"S": SITE_ID}}
    )["Item"]
    assert int(item["count"]["N"]) == 2

@mock_aws
def test_counter_respects_site_id_partition():
    os.environ["AWS_DEFAULT_REGION"] = REGION
    os.environ["TABLE_NAME"] = TABLE_NAME
    os.environ["SITE_ID"]    = "another-site"

    ddb = boto3.client("dynamodb", region_name=REGION)
    ddb.create_table(
        TableName=TABLE_NAME,
        BillingMode="PAY_PER_REQUEST",
        AttributeDefinitions=[{"AttributeName": "pk", "AttributeType": "S"}],
        KeySchema=[{"AttributeName": "pk", "KeyType": "HASH"}],
    )

    handler({}, {})
    resp = handler({}, {})
    body = json.loads(resp["body"])
    assert body["count"] == 2
