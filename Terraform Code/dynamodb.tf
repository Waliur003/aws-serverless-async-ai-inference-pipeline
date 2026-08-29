//Declare DynamoDB table 
resource "aws_dynamodb_table" "genai_inference_jobs" {
    name           = var.dynamodb_table_name
    
    #billing mode to use on-demand capacity mode
    billing_mode   = "PAY_PER_REQUEST"
    hash_key       = "job_id"
    
    attribute {
        name = "job_id"
        type = "S"
    }
    
    tags = {
        Name        = var.dynamodb_table_name
        Environment = var.environment
    }

}
