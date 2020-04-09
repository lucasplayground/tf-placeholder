locals {
  prefix = "acg-streaming-lab"
}
# Create Kinesis Stream
resource "aws_kinesis_stream" "this" {
  name        = local.prefix
  shard_count = 1

  tags = {
    Environment = "lab"
  }
}

#Analytics
resource "aws_kinesis_analytics_application" "this" {
  name = local.prefix
  code = <<-EOT
    CREATE OR REPLACE STREAM "DESTINATION_USER_DATA" (
        first VARCHAR(16),
        last VARCHAR(16),
        age integer,
        gender VARCHAR(16),
        latitude float,
        longitude float
    );
    CREATE OR REPLACE PUMP "STREAM_PUMP" AS INSERT INTO "DESTINATION_USER_DATA"

    SELECT STREAM "first", "last", "age", "gender", "latitude", "longitude"
    FROM "SOURCE_SQL_STREAM_001"
    WHERE "age" >= 21;
  EOT

  lifecycle {
    ignore_changes = [inputs, outputs]
  }
}

# Firehose
resource "aws_kinesis_firehose_delivery_stream" "this" {
  name        = local.prefix
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn        = aws_iam_role.firehose.arn
    bucket_arn      = aws_s3_bucket.this.arn
    buffer_size     = 1
    buffer_interval = 60

    processing_configuration {
      enabled = "true"

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.this.arn}:$LATEST"
        }
        parameters {
          parameter_name  = "BufferSizeInMBs"
          parameter_value = "1"
        }
      }
    }
  }
}

# Destination s3 bucket
resource "aws_s3_bucket" "this" {
  bucket_prefix = local.prefix
  acl           = "private"
  force_destroy = true
}

# Lambda
resource "aws_lambda_function" "this" {
  filename         = "firehose_processing.zip"
  function_name    = join("-", [local.prefix, "processor"])
  role             = aws_iam_role.lambda.arn
  handler          = join(".", ["firehose_processing", "handler"])
  runtime          = "python3.7"
  timeout          = 60
  source_code_hash = filebase64sha256("firehose_processing.zip")
}

# Lambda Source Code
data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/firehose_processing.py"
  output_path = "${path.module}/firehose_processing.zip"
}

# IAM
resource "aws_iam_role" "firehose" {
  name = join("-", [local.prefix, "firehose"])

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
resource "aws_iam_role_policy" "firehose" {
  name   = join("-", [local.prefix, "firehose"])
  role   = aws_iam_role.firehose.id
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "${aws_s3_bucket.this.arn}/*",
                "${aws_s3_bucket.this.arn}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "kinesisanalytics:*"
            ],
            "Resource": [
                "${aws_kinesis_analytics_application.this.arn}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "lambda:*"
            ],
            "Resource": [
                "${aws_lambda_function.this.arn}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "*"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role" "lambda" {
  name = join("-", [local.prefix, "lambda"])

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
resource "aws_iam_role_policy" "lambda" {
  name   = join("-", [local.prefix, "lambda"])
  role   = aws_iam_role.lambda.id
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "firehose:*"
            ],
            "Resource": [
                "${aws_kinesis_firehose_delivery_stream.this.arn}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "${aws_s3_bucket.this.arn}/*",
                "${aws_s3_bucket.this.arn}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:*"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role" "this" {
  name = local.prefix

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "kinesisanalytics.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "this" {
  name   = local.prefix
  role   = aws_iam_role.this.id
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:*"
            ],
            "Resource": [
                "${aws_kinesis_stream.this.arn}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "firehose:*"
            ],
            "Resource": [
                "${aws_kinesis_firehose_delivery_stream.this.arn}"
            ]
        }
    ]
}
EOF
}
