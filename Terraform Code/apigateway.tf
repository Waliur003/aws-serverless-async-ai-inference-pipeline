//Declare REST API Gateway resource named "genai_async_api"
resource "aws_api_gateway_rest_api" "genai_async_api" {
  name        = "genai-async-api"
  description = "Asynchronous AI Inference API backed by SQS and Bedrock"

  #Set endpoint configuration to REGIONAL
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "genai-async-api"
    Environment = var.environment
    Project     = "AsyncAIInferencePipeline"
  }
}


//Declare API Gateway Resource "/jobs"
resource "aws_api_gateway_resource" "jobs_resource" {
  rest_api_id = aws_api_gateway_rest_api.genai_async_api.id
  parent_id   = aws_api_gateway_rest_api.genai_async_api.root_resource_id
  path_part   = "jobs"
}


//Declare API Gateway Method POST for "/jobs"
resource "aws_api_gateway_method" "jobs_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.genai_async_api.id
  resource_id   = aws_api_gateway_resource.jobs_resource.id
  http_method   = "POST"
  authorization = "NONE"
}


//Declare API Gateway Lambda Proxy Integration for POST "/jobs"
resource "aws_api_gateway_integration" "jobs_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.genai_async_api.id
  resource_id             = aws_api_gateway_resource.jobs_resource.id
  http_method             = aws_api_gateway_method.jobs_post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_producer.invoke_arn
}


//Declare API Gateway Child Resource "/jobs/{job_id}"
resource "aws_api_gateway_resource" "job_id_resource" {
  rest_api_id = aws_api_gateway_rest_api.genai_async_api.id
  parent_id   = aws_api_gateway_resource.jobs_resource.id
  path_part   = "{job_id}"
}


//Declare API Gateway Method GET for "/jobs/{job_id}"
resource "aws_api_gateway_method" "job_id_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.genai_async_api.id
  resource_id   = aws_api_gateway_resource.job_id_resource.id
  http_method   = "GET"
  authorization = "NONE"
}


//Declare API Gateway Lambda Proxy Integration for GET "/jobs/{job_id}"
resource "aws_api_gateway_integration" "job_id_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.genai_async_api.id
  resource_id             = aws_api_gateway_resource.job_id_resource.id
  http_method             = aws_api_gateway_method.job_id_get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_producer.invoke_arn
}


//Declare API Gateway Deployment resource
resource "aws_api_gateway_deployment" "genai_async_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.jobs_post_integration,
    aws_api_gateway_integration.job_id_get_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.genai_async_api.id
  description = "Deployment for genai-async-api"

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.jobs_resource.id,
      aws_api_gateway_method.jobs_post_method.id,
      aws_api_gateway_integration.jobs_post_integration.id,
      aws_api_gateway_resource.job_id_resource.id,
      aws_api_gateway_method.job_id_get_method.id,
      aws_api_gateway_integration.job_id_get_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}


//Declare API Gateway Stage resource for the deployment
resource "aws_api_gateway_stage" "genai_async_api_stage" {
  rest_api_id   = aws_api_gateway_rest_api.genai_async_api.id
  deployment_id = aws_api_gateway_deployment.genai_async_api_deployment.id
  stage_name    = var.environment
  description   = "Stage for genai-async-api"

  tags = {
    Environment = var.environment
    Project     = "AsyncAIInferencePipeline"
  }
}


//Declare Lambda permission resource to allow API Gateway to invoke the producer Lambda function
resource "aws_lambda_permission" "allow_apigateway_invoke_producer" {
  statement_id  = "AllowAPIGatewayInvokeProducer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.genai_async_api.execution_arn}/*/*"
}