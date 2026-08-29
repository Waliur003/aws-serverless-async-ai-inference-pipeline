//Declare the Lambda function for the producer
resource "aws_lambda_function" "lambda_producer" {
  filename         = "src/producer.zip"
  function_name    = "genai-async-job-producer"
  role             = aws_iam_role.lambda_producer_role.arn
  handler          = "producer.lambda_handler"
  runtime          = "python3.12"
  architectures     = ["arm64"]

  #File system path to the Lambda function code
  source_code_hash = filebase64sha256("src/producer.zip")

  #Timeout and memory size for the Lambda function
  timeout          = var.lambda_producer_timeout
  memory_size      = var.lambda_producer_memory_size

  #Environment variables for the Lambda function
  environment {
    variables = {
      QUEUE_NAME           = aws_sqs_queue.genai_inference_queue.name
      TABLE_NAME           = aws_dynamodb_table.genai_inference_jobs.name
    }
  } 
}