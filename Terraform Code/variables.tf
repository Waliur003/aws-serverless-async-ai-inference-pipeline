//Declare AWS region variable
variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}


//Declare environment variable for AWS deployment
variable "environment" {
  description = "The deployment environment (e.g., dev, prod)"
  type        = string
  default     = "dev"
}


//Declare DynamoDB table name variable
variable "dynamodb_table_name" {
  description = "The name of the DynamoDB table for job state tracking"
  type        = string
  default     = "genai-inference-jobs"
}


//Declare SQS main queue name variable
variable "sqs_queue_name" {
  description = "The name of the main SQS queue for inference jobs"
  type        = string
  default     = "genai-inference-queue"
}


//Declare SQS Dead-Letter Queue (DLQ) name variable
variable "sqs_dlq_queue_name" {
  description = "The name of the SQS Dead-Letter Queue"
  type        = string
  default     = "genai-inference-dlq"
}


//Declare SQS visibility timeout variable in seconds
variable "sqs_visibility_timeout" {
  description = "The visibility timeout for the SQS queue in seconds"
  type        = number
  default     = 180
}


//Declare memory size for the Lambda producer function in MB
variable "lambda_producer_memory_size" {
  description = "The memory size for the producer Lambda function in MB"
  type        = number
  default     = 256
}


//Declare timeout for the Lambda producer function in seconds
variable "lambda_producer_timeout" {
  description = "The timeout for the producer Lambda function in seconds"
  type        = number
  default     = 10
}


//Declare memory size for the Lambda worker function in MB
variable "lambda_worker_memory_size" {
  description = "The memory size for the worker Lambda function in MB"
  type        = number
  default     = 512
}


//Declare timeout for the Lambda worker function in seconds
variable "lambda_worker_timeout" {
  description = "The timeout for the worker Lambda function in seconds"
  type        = number
  default     = 120
}


//Declare CloudWatch log retention variable in days
variable "log_retention_in_days" {
  description = "The number of days to retain CloudWatch logs"
  type        = number
  default     = 14
}


//Declare Bedrock foundation model ID variable
variable "bedrock_model_id" {
  description = "The foundation model ID for Bedrock inference"
  type        = string
  default     = "amazon.nova-micro-v1:0"
}