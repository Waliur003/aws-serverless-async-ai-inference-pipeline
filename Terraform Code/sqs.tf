//Declare DEAD Letter Queue (DLQ) for SQS
resource "aws_sqs_queue" "genai_inference_dlq" {
  name = var.sqs_dlq_queue_name

  #Message retention period for the DLQ for 14 days
  message_retention_seconds = 1209600

  tags = {
    Name        = var.sqs_dlq_queue_name
    Environment = var.environment
  }
}


//Declare SQS Queue for inference jobs
resource "aws_sqs_queue" "genai_inference_queue" {
  name = var.sqs_queue_name

  #Message retention period for the SQS queue for 4 days
  message_retention_seconds = 345600

  #Visibility timeout for the SQS queue for 30 seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.genai_inference_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = var.sqs_queue_name
    Environment = var.environment
  }
}