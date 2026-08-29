//Output of the API endpoint URL for job submission (POST /jobs)
output "api_endpoint_post_jobs_url" {
  value       = "${aws_api_gateway_stage.genai_async_api_stage.invoke_url}/jobs"
  description = "The HTTP POST endpoint URL to submit asynchronous AI inference jobs"
}


//Output of the API endpoint base URL for job status polling (GET /jobs/{job_id})
output "api_endpoint_get_jobs_base_url" {
  value       = "${aws_api_gateway_stage.genai_async_api_stage.invoke_url}/jobs/"
  description = "The base HTTP GET endpoint URL to poll inference job status"
}


//Output of the main SQS queue URL
output "sqs_queue_url" {
  value       = aws_sqs_queue.genai_inference_queue.url
  description = "The URL of the main SQS inference work queue"
}


//Output of the Dead-Letter Queue (DLQ) URL
output "sqs_dlq_url" {
  value       = aws_sqs_queue.genai_inference_dlq.url
  description = "The URL of the SQS Dead-Letter Queue"
}


//Output of the DynamoDB state table name
output "dynamodb_table_name" {
  value       = aws_dynamodb_table.genai_inference_jobs.name
  description = "The name of the DynamoDB table storing job execution states"
}


//Output of the producer Lambda function ARN
output "lambda_producer_arn" {
  value       = aws_lambda_function.lambda_producer.arn
  description = "The ARN of the producer Lambda function"
}


//Output of the worker Lambda function ARN
output "lambda_worker_arn" {
  value       = aws_lambda_function.lambda_worker.arn
  description = "The ARN of the worker Lambda function"
}