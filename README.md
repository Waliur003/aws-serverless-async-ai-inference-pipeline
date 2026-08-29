# AI Cloud Engineering Project 3: Reliable Asynchronous AI Inference Pipeline with Bedrock, SQS, DynamoDB & DLQ

---

## Overview

I have architected and deployed an enterprise-grade, asynchronous AI inference pipeline on AWS designed to handle bursty, long-running foundation model workloads without blocking client connections. By decoupling client request ingestion from compute-intensive LLM inference, this architecture eliminates HTTP timeout risks, provides graceful traffic buffering, ensures fault isolation, and implements automated dead-letter queue (DLQ) redrive mechanisms.

When clients submit prompts via **Amazon API Gateway**, an ingestion **Producer Lambda** validates the payload, generates an immutable tracking identifier (`job_id`), records the initial `QUEUED` state in **Amazon DynamoDB**, and enqueues the job into **Amazon SQS**—returning an immediate HTTP `202 Accepted` response in sub-100ms. A background **Worker Lambda** consumes the message batch, orchestrates inference via **Amazon Bedrock** (**Amazon Nova Micro** via the Bedrock Converse API), and updates DynamoDB with the completed response payload, execution duration, and token usage telemetry for client polling.

---

## The Problem

Executing Generative AI inference synchronously in web applications creates severe reliability, latency, and cost bottlenecks.

### Client Connection Timeouts & HTTP 504 Gateway Errors

Synchronous LLM inference can take anywhere from 2 to 30+ seconds depending on context length and model generation load. Standard API Gateways and load balancers terminate connections after 29 seconds, resulting in dropped requests and poor user experiences.

### Throttling & Downstream Service Overwhelm

Spikes in user traffic sent directly to foundation model endpoints can trigger AWS Bedrock account-level TPS/RPM rate limits (`ThrottlingException`), resulting in unrecoverable message drops without a retry buffer.

### Cascading Failures & Lack of Poison-Pill Handling

In a synchronous architecture, transient model failures crash upstream user sessions. Without automated retries and dead-letter queues, malformed inputs or runtime exceptions cause total data loss with no debugging audit trail.

---

## The Solution

### Decoupled Producer-Consumer Architecture

Implemented an asynchronous ingestion pattern where API Gateway routes requests to a lightweight Producer Lambda that immediately returns an HTTP `202 Accepted` response alongside a unique `job_id`, freeing the client from waiting on inference execution.

### Traffic Buffering & Concurrency Regulation via SQS

Leveraged **Amazon SQS Standard Queues** as a managed elastic buffer. The queue absorbs sudden traffic surges and feeds messages to the Worker Lambda based on controlled batch sizes (`BatchSize = 5`), preventing downstream Bedrock API throttling.

### Multi-Stage State Tracking in DynamoDB

Engineered an end-to-end state machine stored in **Amazon DynamoDB** (`genai-inference-jobs`) tracking the full lifecycle of every inference job:

```text
QUEUED → PROCESSING → COMPLETED / FAILED
```

### Resilient Redrive Policy & Dead-Letter Queue Isolation

Configured a 180-second Visibility Timeout on the main queue and a Dead-Letter Queue (`genai-inference-dlq`) with `maxReceiveCount = 3`. Poison messages or unhandled inference exceptions automatically transition to the DLQ after 3 failed processing attempts for administrative inspection.

---

## Tech Stack

| Layer | Technology |
|---|---|
| **API Ingress & Polling** | Amazon API Gateway REST API (`genai-async-api` / `9gseie9u5i`) |
| **Ingestion Compute** | AWS Lambda (`genai-async-job-producer` – Python 3.12 / Graviton `arm64`) |
| **Inference Compute** | AWS Lambda (`genai-inference-worker` – Python 3.12 / Graviton `arm64`) |
| **Message Queue & Buffer** | Amazon SQS (`genai-inference-queue` – Visibility: 180s) |
| **Dead-Letter Queue** | Amazon SQS (`genai-inference-dlq` – Retention: 14 Days) |
| **Foundation Model** | Amazon Nova Micro (`amazon.nova-micro-v1:0` via Bedrock Converse API) |
| **State & Metadata Store** | Amazon DynamoDB (`genai-inference-jobs` – On-Demand / Pay-Per-Request) |
| **Security & Access Control** | AWS IAM (`LambdaAsyncProducerRole`, `LambdaAsyncWorkerRole`) |
| **Observability & Alarms** | Amazon CloudWatch Logs & SQS Queue Depth Alarms |
| **Infrastructure as Code** | HashiCorp Terraform |

---

## Architecture Diagram



---

## Project Procedure

### 1. DynamoDB State Store Provisioning

* Created DynamoDB table **`genai-inference-jobs`** with partition key **`job_id`** as a String.
* Enabled **On-Demand (Pay-per-request)** capacity mode to eliminate cold provisioning and eliminate idle hourly costs.

---

### 2. SQS Queue & Dead-Letter Queue Provisioning

* Provisioned Dead-Letter Queue: **`genai-inference-dlq`** with a 14-day retention cycle.
* Provisioned Main Ingestion Queue: **`genai-inference-queue`** with:
  * **Visibility Timeout:** `180 seconds`
  * **Redrive Policy:** Enabled targeting `genai-inference-dlq` with `maxReceiveCount = 3`

---

### 3. Least-Privilege IAM Execution Roles

### `LambdaAsyncProducerRole`

Grants permission for:

* `dynamodb:PutItem`
* `dynamodb:GetItem`
* `sqs:SendMessage`
* `sqs:GetQueueUrl`

Access is scoped to:

* DynamoDB table `genai-inference-jobs`
* SQS queue `genai-inference-queue`

### `LambdaAsyncWorkerRole`

Grants permission for:

* `sqs:ReceiveMessage`
* `sqs:DeleteMessage`
* `sqs:GetQueueAttributes`
* `dynamodb:UpdateItem`
* `bedrock:InvokeModel`

Access is scoped to the processing queue, DynamoDB job table, and foundation model ARNs.

---

### 4. Job Producer Lambda Implementation

* Created function **`genai-async-job-producer`** on Python 3.12 (`arm64`), scaled to 256 MB RAM, 10s Timeout.
* Implemented dynamic endpoint routing.
* Generated unique IDs using the `job-<hex>` pattern.
* Persisted initial `QUEUED` state to DynamoDB.
* Published request payloads to SQS.
* Returned fast HTTP `202 Accepted` serialization.
* Implemented status retrieval handler for `GET /jobs/{job_id}` returning current execution state.

---

### 5. Worker Lambda & SQS Event Source Mapping

* Created function **`genai-inference-worker`** on Python 3.12 (`arm64`), configured with **512 MB RAM** and a **120-second timeout**.
* Attached an **SQS Event Source Mapping Trigger** consuming from `genai-inference-queue` with a batch size of 5.
* Orchestrated:
  * Bedrock Converse API execution
  * Runtime timing calculations
  * Token usage parsing
  * Atomic updates to DynamoDB

---

### 6. API Gateway REST Exposure & Deployment

* Built REST API **`genai-async-api`** (`9gseie9u5i`) in `us-east-1`.
* Configured route `/jobs` (`POST`) and route `/jobs/{job_id}` (`GET`) with Lambda Proxy Integration targeting `genai-async-job-producer`.
* Deployed stage `dev`, producing live public endpoints.

---

## Infrastructure as Code (IaC) Architecture

The entire asynchronous inference architecture can be deployed and reproduced via modular HashiCorp Terraform configuration files:

```text
terraform-aws-async-bedrock/
├── main.tf                    # AWS provider (us-east-1), version constraints, and project tags
├── variables.tf               # Environment variables, queue names, memory, timeouts
├── terraform.tfvars           # Concrete parameter values
├── dynamodb.tf                # State tracking table (genai-inference-jobs) with PAY_PER_REQUEST
├── sqs.tf                     # Main queue, DLQ, and RedrivePolicy configuration
├── iam.tf                     # Scoped IAM execution roles for Producer and Worker Lambdas
├── lambda_producer.tf         # Producer packaging, env vars, and API Gateway permissions
├── lambda_worker.tf           # Worker packaging, 120s timeout, and SQS Event Source Mapping
├── apigateway.tf              # REST API, /jobs (POST), /jobs/{job_id} (GET), and dev stage
├── cloudwatch.tf              # Log groups with 14-day retention and DLQ depth Alarm
├── outputs.tf                 # Exported API URLs, Queue ARNs, and DynamoDB Table Name
└── src/
    ├── producer.py            # Python 3.12 Producer handler
    └── worker.py              # Python 3.12 Worker handler
```

---

## Detailed File-by-File Technical Breakdown

### `dynamodb.tf`

Declares `aws_dynamodb_table.jobs` with:

```hcl
hash_key     = "job_id"
billing_mode = "PAY_PER_REQUEST"
```

### `sqs.tf`

Sets up the DLQ (`genai-inference-dlq`) and main queue (`genai-inference-queue`) with visibility timeout set to `180s` and `redrive_policy` pointing to the DLQ.

### `iam.tf`

Declares two isolated IAM execution roles:

* `LambdaAsyncProducerRole`
* `LambdaAsyncWorkerRole`

Both enforce strict least privilege.

### `lambda_producer.tf` & `lambda_worker.tf`

Packages source archives using `archive_file`, provisions Lambda functions on AWS Graviton (`arm64`), and binds the SQS event source mapping.

### `apigateway.tf`

Configures the REST API hierarchy:

* `/jobs` `POST`
* `/jobs/{job_id}` `GET`

It also defines Lambda proxy integrations and active deployment stages.

### `cloudwatch.tf`

Creates dedicated `/aws/lambda/*` log groups with 14-day retention and provisions a CloudWatch metric alarm on DLQ message accumulation.

### `outputs.tf`

Exports invocation URLs (`api_endpoint_url`), resource ARNs, and queue URLs for automated testing.

---

## Technical Difficulties Faced & Engineering Resolutions

### Challenge 1: Boto3 SQS Hostname Mismatch in `us-east-1`

#### Root Cause Analysis

During initial POST job execution, the Producer Lambda threw the following error:

```text
AWS service Error: The address [https://sqs.us-east-1.amazonaws.com/...] is not valid for this endpoint.
```

In `us-east-1`, the default Boto3 client configuration can route requests through legacy regional endpoints (`https://queue.amazonaws.com`), conflicting with newly generated SQS queue URLs.

#### Architectural Resolution

Explicitly bound the Boto3 SQS client to the regional endpoint:

```python
sqs = boto3.client(
    "sqs",
    region_name="us-east-1",
    endpoint_url="https://sqs.us-east-1.amazonaws.com"
)
```

Additionally implemented dynamic queue URL resolution:

```python
sqs.get_queue_url(QueueName="genai-inference-queue")
```

Appended `sqs:GetQueueUrl` to the Producer IAM execution policy.

---

### Challenge 2: DynamoDB Reserved Keyword Collision on `result` Attribute

#### Root Cause Analysis

When the Worker Lambda completed foundation model inference, updating DynamoDB failed with the following error:

```text
Invalid UpdateExpression: Attribute name is a reserved keyword; reserved keyword: result
```

DynamoDB reserves words like `result`, `status`, `year`, and `data` in expression syntax.

#### Architectural Resolution

Refactored the `update_item` expression to use expression attribute name aliases (`#r` and `#s`):

```python
table.update_item(
    Key={"job_id": job_id},
    UpdateExpression="SET #s = :status, #r = :res, updated_at = :u, completed_at = :c, execution_duration_ms = :dur, input_tokens = :in_tok, output_tokens = :out_tok, total_tokens = :tot_tok",
    ExpressionAttributeNames={
        "#s": "status",
        "#r": "result"
    },
    ExpressionAttributeValues={
        ":status": "COMPLETED",
        ":res": generated_text
    }
)
```

---

### Challenge 3: In-Flight Message Visibility Race Conditions

#### Root Cause Analysis

Default SQS visibility timeouts of 30 seconds can be exceeded if foundation model inference encounters cold starts or heavy token output generation, causing SQS to assume the worker failed and re-deliver the message to another worker instance concurrently.

#### Architectural Resolution

Configured a safe execution margin where the SQS visibility timeout was scaled to **180 seconds**, which is 1.5x greater than the Worker Lambda timeout limit of **120 seconds**, guaranteeing strict single-consumer processing.

---

## Verification and Results

### Sub-100ms Ingestion Latency

Validated that `POST /jobs` returns an HTTP `202 Accepted` response with a unique `job_id` in under 100 milliseconds, decoupling the client from the LLM execution lifecycle.

### Asynchronous Worker Execution

The Worker Lambda consumed the queued message from SQS, executed inference against **Amazon Nova Micro** in **671 ms**, and persisted all generated content and token metrics directly into DynamoDB.

### Live Terminal Verification

#### 1. Submit Asynchronous Inference Request

```bash
curl -X POST https://9gseie9u5i.execute-api.us-east-1.amazonaws.com/dev/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Explain the architectural advantages of asynchronous decoupled systems in cloud computing in three concise bullet points.",
    "temperature": 0.2,
    "max_tokens": 200
  }'
```

#### Immediate Ingestion Response: HTTP 202

```json
{
  "job_id": "job-8db49a2c",
  "status": "QUEUED",
  "created_at": 1788033839,
  "message": "Inference request enqueued successfully. Poll GET /jobs/{job_id} for status."
}
```

#### 2. Poll Status & Retrieve Completed Output

```bash
curl -X GET https://9gseie9u5i.execute-api.us-east-1.amazonaws.com/dev/jobs/job-93a021f5
```

#### Final Output Payload: HTTP 200

```json
{
  "job_id": "job-93a021f5",
  "status": "COMPLETED",
  "prompt": "Explain the architectural advantages of asynchronous decoupled systems in cloud computing in three concise bullet points.",
  "model_id": "amazon.nova-micro-v1:0",
  "created_at": 1788033716,
  "updated_at": 1788033717,
  "completed_at": 1788033717,
  "execution_duration_ms": 671,
  "input_tokens": 18,
  "output_tokens": 95,
  "total_tokens": 113,
  "result": "- **Scalability**: Asynchronous decoupled systems allow components to scale independently based on demand, optimizing resource allocation and minimizing downtime during peak loads.\n\n- **Fault Tolerance**: By decoupling components, failures in one part of the system do not necessarily cascade to others, enhancing overall system resilience and reliability.\n\n- **Improved Performance**: Asynchronous processing enables tasks to be handled in the background without blocking other operations, leading to faster response times and more efficient use of computational resources."
}
```

---

## Verification Screenshots

### 1. End-to-End Live Terminal Execution & Polling Verification

Displays the live terminal executing `POST /jobs` returning HTTP `202 Accepted` with `job-8db49a2c` and `GET /jobs/job-93a021f5` returning HTTP `200 OK` with status `COMPLETED`, inference execution duration (`671ms`), token counts (`18` input / `95` output), and synthesized model output.

<img width="1913" height="365" alt="Screenshot 1" src="https://github.com/user-attachments/assets/475a6373-b609-4c86-a79a-0caef220f703" />


### 2. DynamoDB Job State Store & Telemetry Items

Shows the scanned records in DynamoDB table `genai-inference-jobs`, verifying state lifecycle tracking (`QUEUED` → `COMPLETED`), persisted execution durations, prompt records, and token metrics.

<img width="1699" height="774" alt="Screenshot 2" src="https://github.com/user-attachments/assets/d246a2dd-0932-4060-9bd9-55764967afe5" />


### 3. Amazon SQS Main Processing Queue & Dead-Letter Queue

Displays both active SQS queues in the AWS Console: `genai-inference-queue` with redrive policy enabled and `genai-inference-dlq` with 14-day retention, confirming 0 message buildup and normal message processing.

<img width="1549" height="398" alt="Screenshot 3" src="https://github.com/user-attachments/assets/e432f1a9-68f8-4018-aeb6-ccf38297a7d5" />


### 4. CloudWatch Logs & Lambda Worker Execution Metrics

Captures the CloudWatch monitoring dashboard for `genai-inference-worker`, highlighting sub-second billed execution durations ranging from 685ms to 775ms, 512 MB memory allocation, and zero execution failures.

<img width="1607" height="876" alt="Screenshot 4" src="https://github.com/user-attachments/assets/7cb3802a-a673-482c-ae8e-769d69580054" />


---

## Future Improvements

### WebSocket Subscriptions with AWS API Gateway WebSocket API

Push completion events in real time to connected web frontends over WebSockets rather than requiring client-side HTTP polling.

### Idempotency Keys via SQS Deduplication

Transition to SQS FIFO with `MessageDeduplicationId` hashed from the prompt and user ID to prevent duplicate LLM invocations during retries.

### Automated DLQ Redrive Step Function

Implement an AWS Step Functions workflow to inspect poison messages in `genai-inference-dlq`, alert on-call engineers via SNS, and automate reprocessing.

---

## Notes

This project shifts from basic generative API invocation to production reliability engineering. By buffering requests through SQS and persisting state in DynamoDB, the system handles unpredictable traffic spikes, long inference durations, and service outages without dropping requests or blocking client threads.

---

## Bottom Line

The Asynchronous AI Inference Pipeline demonstrates how to operate Generative AI workloads with enterprise-grade reliability. Combining API Gateway, Amazon SQS buffering, AWS Lambda workers, and DynamoDB state persistence ensures that client applications remain fast, resilient, and protected against timeouts and downstream outages.
