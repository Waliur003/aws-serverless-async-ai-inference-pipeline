//Declare CloudWatch log group resource for the producer Lambda function
resource "aws_cloudwatch_log_group" "producer_lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.lambda_producer.function_name}"
  retention_in_days = var.log_retention_in_days
}


//Declare CloudWatch log group resource for the worker Lambda function
resource "aws_cloudwatch_log_group" "worker_lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.lambda_worker.function_name}"
  retention_in_days = var.log_retention_in_days
}


//Declare CloudWatch metric alarm for Dead-Letter Queue poison pill message detection
resource "aws_cloudwatch_metric_alarm" "dlq_messages_alarm" {
  alarm_name          = "DLQ-PoisonPill-MessagesDetected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alarm triggers when messages land in the Dead-Letter Queue"

  dimensions = {
    QueueName = aws_sqs_queue.genai_inference_dlq.name
  }

  tags = {
    Environment = var.environment
    Project     = "AsyncAIInferencePipeline"
  }
}