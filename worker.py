import json
import os
import time
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1"))
bedrock_runtime = boto3.client("bedrock-runtime", region_name=os.environ.get("AWS_REGION", "us-east-1"))

TABLE_NAME = os.environ.get("TABLE_NAME", "genai-inference-jobs")
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    records = event.get("Records", [])
    print(f"Received batch of {len(records)} SQS message(s).")

    for record in records:
        body_raw = record.get("body", "{}")
        
        try:
            payload = json.loads(body_raw)
        except Exception as parse_err:
            print(f"Malformed JSON payload: {body_raw}. Error: {str(parse_err)}")
            continue

        job_id = payload.get("job_id")
        prompt = payload.get("prompt")
        model_id = payload.get("model_id", "amazon.nova-micro-v1:0")
        max_tokens = int(payload.get("max_tokens", 512))
        temperature = float(payload.get("temperature", 0.3))

        if not job_id or not prompt:
            print(f"Skipping record missing job_id or prompt: {payload}")
            continue

        # 1. Update State to PROCESSING in DynamoDB
        current_time = int(time.time())
        try:
            table.update_item(
                Key={"job_id": job_id},
                UpdateExpression="SET #s = :status, updated_at = :u",
                ExpressionAttributeNames={"#s": "status"},
                ExpressionAttributeValues={":status": "PROCESSING", ":u": current_time}
            )
        except Exception as e:
            print(f"Failed setting status to PROCESSING for job {job_id}: {str(e)}")

        # 2. Invoke Bedrock Model via Converse API
        try:
            start_time = time.time()
            response = bedrock_runtime.converse(
                modelId=model_id,
                messages=[{"role": "user", "content": [{"text": prompt}]}],
                inferenceConfig={"maxTokens": max_tokens, "temperature": temperature}
            )
            duration_ms = int((time.time() - start_time) * 1000)

            generated_text = response["output"]["message"]["content"][0]["text"]
            token_usage = response.get("usage", {})
            completed_time = int(time.time())

            # 3. Update State to COMPLETED with Aliased Reserved Keywords (#r for result)
            table.update_item(
                Key={"job_id": job_id},
                UpdateExpression=(
                    "SET #s = :status, #r = :res, updated_at = :u, "
                    "completed_at = :c, execution_duration_ms = :dur, "
                    "input_tokens = :in_tok, output_tokens = :out_tok, total_tokens = :tot_tok"
                ),
                ExpressionAttributeNames={
                    "#s": "status",
                    "#r": "result"
                },
                ExpressionAttributeValues={
                    ":status": "COMPLETED",
                    ":res": generated_text,
                    ":u": completed_time,
                    ":c": completed_time,
                    ":dur": duration_ms,
                    ":in_tok": token_usage.get("inputTokens", 0),
                    ":out_tok": token_usage.get("outputTokens", 0),
                    ":tot_tok": token_usage.get("totalTokens", 0)
                }
            )
            print(f"Successfully processed job {job_id} in {duration_ms}ms.")

        except ClientError as bedrock_err:
            error_msg = bedrock_err.response["Error"]["Message"]
            print(f"Bedrock invocation failed for job {job_id}: {error_msg}")
            
            table.update_item(
                Key={"job_id": job_id},
                UpdateExpression="SET #s = :status, error_message = :err, updated_at = :u",
                ExpressionAttributeNames={"#s": "status"},
                ExpressionAttributeValues={
                    ":status": "FAILED",
                    ":err": f"Bedrock Error: {error_msg}",
                    ":u": int(time.time())
                }
            )
            raise bedrock_err

        except Exception as general_err:
            print(f"Unhandled error for job {job_id}: {str(general_err)}")
            table.update_item(
                Key={"job_id": job_id},
                UpdateExpression="SET #s = :status, error_message = :err, updated_at = :u",
                ExpressionAttributeNames={"#s": "status"},
                ExpressionAttributeValues={
                    ":status": "FAILED",
                    ":err": f"Internal Worker Error: {str(general_err)}",
                    ":u": int(time.time())
                }
            )
            raise general_err

    return {"statusCode": 200, "body": "Batch processing completed."}