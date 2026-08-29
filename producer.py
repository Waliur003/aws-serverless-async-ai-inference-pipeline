import json
import os
import time
import uuid
import boto3
from botocore.exceptions import ClientError

REGION = os.environ.get("AWS_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
sqs = boto3.client(
    "sqs",
    region_name=REGION,
    endpoint_url=f"https://sqs.{REGION}.amazonaws.com"
)

TABLE_NAME = os.environ.get("TABLE_NAME", "genai-inference-jobs")
QUEUE_NAME = os.environ.get("QUEUE_NAME", "genai-inference-queue")
table = dynamodb.Table(TABLE_NAME)

# Resolve exact Queue URL dynamically to prevent endpoint routing mismatches
try:
    QUEUE_URL = sqs.get_queue_url(QueueName=QUEUE_NAME)["QueueUrl"]
except Exception:
    QUEUE_URL = os.environ.get(
        "QUEUE_URL",
        f"https://sqs.{REGION}.amazonaws.com/418272769771/{QUEUE_NAME}"
    )

def lambda_handler(event, context):
    cors_headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type"
    }

    http_method = event.get("httpMethod")
    if http_method == "OPTIONS":
        return {"statusCode": 200, "headers": cors_headers, "body": ""}

    # 1. Status Polling: GET /jobs/{job_id}
    if http_method == "GET":
        path_params = event.get("pathParameters") or {}
        job_id = path_params.get("job_id")

        if not job_id:
            return {
                "statusCode": 400,
                "headers": cors_headers,
                "body": json.dumps({"error": "Path parameter 'job_id' is required."})
            }

        try:
            response = table.get_item(Key={"job_id": job_id})
            item = response.get("Item")
            if not item:
                return {
                    "statusCode": 404,
                    "headers": cors_headers,
                    "body": json.dumps({"error": f"Job '{job_id}' not found."})
                }

            return {
                "statusCode": 200,
                "headers": cors_headers,
                "body": json.dumps(item, default=int)
            }
        except ClientError as e:
            return {
                "statusCode": 500,
                "headers": cors_headers,
                "body": json.dumps({"error": f"DynamoDB Error: {e.response['Error']['Message']}"})
            }

    # 2. Async Enqueue: POST /jobs
    elif http_method == "POST":
        try:
            body = event.get("body")
            payload = json.loads(body) if isinstance(body, str) else (body or {})
            prompt = payload.get("prompt")

            if not prompt or not prompt.strip():
                return {
                    "statusCode": 400,
                    "headers": cors_headers,
                    "body": json.dumps({"error": "Field 'prompt' is required."})
                }

            job_id = f"job-{uuid.uuid4().hex[:8]}"
            created_at = int(time.time())
            model_id = payload.get("model_id", "amazon.nova-micro-v1:0")
            max_tokens = int(payload.get("max_tokens", 512))
            temperature = float(payload.get("temperature", 0.3))

            # Persist Initial QUEUED State in DynamoDB
            table.put_item(
                Item={
                    "job_id": job_id,
                    "status": "QUEUED",
                    "prompt": prompt,
                    "model_id": model_id,
                    "created_at": created_at,
                    "updated_at": created_at
                }
            )

            # Publish Message to SQS
            message_body = {
                "job_id": job_id,
                "prompt": prompt,
                "model_id": model_id,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "created_at": created_at
            }

            sqs.send_message(
                QueueUrl=QUEUE_URL,
                MessageBody=json.dumps(message_body)
            )

            return {
                "statusCode": 202,
                "headers": cors_headers,
                "body": json.dumps({
                    "job_id": job_id,
                    "status": "QUEUED",
                    "created_at": created_at,
                    "message": "Inference request enqueued successfully. Poll GET /jobs/{job_id} for status."
                })
            }

        except ClientError as e:
            return {
                "statusCode": 500,
                "headers": cors_headers,
                "body": json.dumps({"error": f"AWS Service Error: {e.response['Error']['Message']}"})
            }
        except Exception as e:
            return {
                "statusCode": 500,
                "headers": cors_headers,
                "body": json.dumps({"error": f"Internal Error: {str(e)}"})
            }

    return {"statusCode": 405, "headers": cors_headers, "body": json.dumps({"error": "Method Not Allowed"})}