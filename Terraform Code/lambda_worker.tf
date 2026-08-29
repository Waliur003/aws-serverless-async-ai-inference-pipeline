//Declare the Lambda function for the worker
resource "aws_lambda_function" "lambda_worker" {
  filename         = "src/worker.zip"
  function_name    = "genai-inference-worker"
  role             = aws_iam_role.lambda_worker_role.arn
  handler          = "worker.lambda_handler"
  runtime          = "python3.12"
  architectures     = ["arm64"]

  #File system path to the Lambda function code
  source_code_hash = filebase64sha256("src/worker.zip")

  #Timeout and memory size for the Lambda function
  timeout          = var.lambda_worker_timeout
  memory_size      = var.lambda_worker_memory_size

  #Environment variables for the Lambda function
  environment {
    variables = {
      TABLE_NAME           = aws_dynamodb_table.genai_inference_jobs.name
    }
  } 
}


//Add the SQS trigger to the Lambda function
resource "aws_lambda_event_source_mapping" "lambda_worker_sqs_trigger" {
  event_source_arn = aws_sqs_queue.genai_inference_queue.arn
  function_name    = aws_lambda_function.lambda_worker.arn
  enabled          = true
}