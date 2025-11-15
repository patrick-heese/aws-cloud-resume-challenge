# src/count_function/count_lambda.py
import os
import json
import boto3


def _get_table():
    """Create the DynamoDB Table handle at call time so Moto can mock it."""
    table_name = os.environ.get("TABLE_NAME")
    if not table_name:
        raise RuntimeError("TABLE_NAME environment variable is required")
    ddb = boto3.resource("dynamodb")
    return ddb.Table(table_name)


def handler(event, context):
    site_id = os.environ.get("SITE_ID", "default")
    table = _get_table()

    resp = table.update_item(
        Key={"pk": site_id},
        UpdateExpression="ADD #c :inc",
        ExpressionAttributeNames={"#c": "count"},
        ExpressionAttributeValues={":inc": 1},
        ReturnValues="UPDATED_NEW",
    )

    count = int(resp["Attributes"]["count"])
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"count": count}),
    }
