// Declare policy document for the lambda producer function
data "aws_iam_policy_document" "lambda_producer_policy" {
  statement {
    sid    = "DynamoDBReadWriteAccess"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
    ]

    resources = [
      "arn:aws:dynamodb:us-east-1:*:table/genai-inference-jobs",
    ]
  }

  statement {
    sid    = "SQSSendMessageAccess"
    effect = "Allow"

    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
    ]

    resources = [
      "arn:aws:sqs:us-east-1:*:genai-inference-queue",
    ]
  }

  statement {
    sid    = "CloudWatchLogging"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:*:*:log-group:/aws/lambda/*",
    ]
  }
}


//Attach the policy document to "ProducerLambdaPolicy"
resource "aws_iam_policy" "lambda_producer_policy" {
  name        = "ProducerLambdaPolicy"
  description = "IAM policy for the lambda producer function"
  policy      = data.aws_iam_policy_document.lambda_producer_policy.json
}


//Declare IAM role for the lambda producer function named LambdaAsyncProducerRole with inline policy attached to it
resource "aws_iam_role" "lambda_producer_role" {
  name = "LambdaAsyncProducerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}


//Attach the policy to the IAM role "LambdaAsyncProducerRole"
resource "aws_iam_role_policy_attachment" "lambda_producer_policy_attachment" {
  role       = aws_iam_role.lambda_producer_role.name
  policy_arn = aws_iam_policy.lambda_producer_policy.arn
}



//--------------------------------------Now for the Lambda Worker Function-----------------------------------------------------------------------



// Declare policy document for the lambda worker function
data "aws_iam_policy_document" "lambda_worker_policy" {
  statement {
    sid    = "DynamoDBUpdateAccess"
    effect = "Allow"

    actions = [
      "dynamodb:UpdateItem",
      "dynamodb:PutItem",
    ]

    resources = [
      "arn:aws:dynamodb:us-east-1:*:table/genai-inference-jobs",
    ]
  }

  statement {
    sid    = "SQSConsumeBatchAccess"
    effect = "Allow"

    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]

    resources = [
      "arn:aws:sqs:us-east-1:*:genai-inference-queue",
    ]
  }

  statement {
    sid    = "BedrockInvokeModelAccess"
    effect = "Allow"

    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]

    resources = [
      "arn:aws:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:*:*:inference-profile/*",
    ]
  }

  statement {
    sid    = "CloudWatchLogging"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:*:*:log-group:/aws/lambda/*",
    ]
  }
}


//Attach the policy document to "WorkerLambdaPolicy"
resource "aws_iam_policy" "lambda_worker_policy" {
  name        = "WorkerLambdaPolicy"
  description = "IAM policy for the lambda worker function"
  policy      = data.aws_iam_policy_document.lambda_worker_policy.json
}


//Declare IAM role for the lambda worker function named LambdaAsyncWorkerRole with inline policy attached to it
resource "aws_iam_role" "lambda_worker_role" {
  name = "LambdaAsyncWorkerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}


//Attach the policy to the IAM role "LambdaAsyncWorkerRole"
resource "aws_iam_role_policy_attachment" "lambda_worker_policy_attachment" {
  role       = aws_iam_role.lambda_worker_role.name
  policy_arn = aws_iam_policy.lambda_worker_policy.arn
}