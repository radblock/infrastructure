#  ██████╗  █████╗ ██████╗ ██████╗ ██╗      ██████╗  ██████╗██╗  ██╗
#  ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝
#  ██████╔╝███████║██║  ██║██████╔╝██║     ██║   ██║██║     █████╔╝
#  ██╔══██╗██╔══██║██║  ██║██╔══██╗██║     ██║   ██║██║     ██╔═██╗
#  ██║  ██║██║  ██║██████╔╝██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗
#  ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
#  This is a [terraform](https://github.com/hashicorp/terraform)
#  configuration for deploying RADBLOCK.
#
#  It will set up S3 buckets, Lambda functions, DNS, and whatnot.
#
#     Instructions:
#
#     0. Sign up for Amazon Web Services
#     1. Set the variables over in terraform.tfvars
#     2. Install terraform
#     3. Run `terraform apply`
#
#  See http://github.com/radblock for more info
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# use amazon web services

provider "aws" {
  alias = "prod"
  region = "us-east-1"
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
}

resource "aws_route53_zone" "primary" {
   name = "radblock.xyz"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
#   users.radblock.xyz
#
#   whenever a user uploads a gif, we put their id in this bucket
#   when it expries, they're allowed to upload another
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# make a bucket

resource "aws_s3_bucket" "users" {
  provider = "aws.prod"
  bucket = "${var.users_s3_bucket}"
  acl = "private"
  lifecycle_rule {
    prefix = ""
    enabled = true
    expiration {
      days = 7
    }
  }
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
#   gifs.radblock.xyz
#
#   a bucket for holding gifs, a function for showing a random gif
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# make a bucket

resource "aws_s3_bucket" "gifs" {
  provider = "aws.prod"
  bucket = "${var.gifs_s3_bucket}"
  acl = "public-read"
  // allow the uploader on the website to upload to this bucket
  cors_rule {
    allowed_origins = [ "https://${var.website_s3_bucket}" ]
    allowed_methods = [ "PUT", "GET" ]
    allowed_headers = [ "*" ]
  }
  lifecycle_rule {
    prefix = ""
    enabled = true
    expiration {
      days = 7
    }
  }
  website {
    index_document = "index.html"
  }
}

# point gifs.radblock.xyz to the bucket

resource "aws_route53_record" "gifs" {
  zone_id = "${aws_route53_zone.primary.zone_id}"
  name = "${var.gifs_s3_bucket}"
  type = "A"

  alias {
    name = "${aws_s3_bucket.gifs.website_domain}"
    zone_id = "${aws_s3_bucket.gifs.hosted_zone_id}"
    evaluate_target_health = true
  }
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
#   list.radblock.xyz
#
#   a bucket with a list of all the files in the gifs bucket
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# make a bucket

resource "aws_s3_bucket" "list" {
  provider = "aws.prod"
  bucket = "${var.list_s3_bucket}"
  acl = "public-read"
  website {
    index_document = "list.json"
  }
}

# point list.radblock.xyz to that bucket

resource "aws_route53_record" "list" {
  zone_id = "${aws_route53_zone.primary.zone_id}"
  name = "${var.list_s3_bucket}"
  type = "A"

  alias {
    name = "${aws_s3_bucket.list.website_domain}"
    zone_id = "${aws_s3_bucket.list.hosted_zone_id}"
    evaluate_target_health = true
  }
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
#   radblock.xyz
#
#   this is the main website with marketing + the gif uploader
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# make a bucket

resource "aws_s3_bucket" "website" {
  provider = "aws.prod"
  bucket = "${var.website_s3_bucket}"
  acl = "public-read"
  website {
    index_document = "index.html"
    error_document = "error.html"
  }
}

# point radblock.xyz to that bucket

resource "aws_route53_record" "website" {
  zone_id = "${aws_route53_zone.primary.zone_id}"
  name = "${var.website_s3_bucket}"
  type = "A"

  alias {
    name = "${aws_s3_bucket.website.website_domain}"
    zone_id = "${aws_s3_bucket.website.hosted_zone_id}"
    evaluate_target_health = true
  }
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
#   uploader
#
#   this is the gif uploader's backend function
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# create a policy for the gif uploader that can upload gifs to the gif bucket

resource "aws_iam_role_policy" "uploader_lambda_policy" {
  name = "uploader_lambda_policy"
  role = "${aws_iam_role.uploader_lambda_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Stmt1458531615000",
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts",
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:PutObjectVersionAcl"
      ],
      "Resource": [
        "arn:aws:s3:::${var.gifs_s3_bucket}",
        "arn:aws:s3:::${var.gifs_s3_bucket}/*"
      ]
    }
  ]
}
EOF
}

# attach it to a role

resource "aws_iam_role" "uploader_lambda_role" {
  name = "uploader_lambda_role"
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

# create a function to sign s3 upload requests using that role
# https://github.com/radblock/gimme

resource "aws_lambda_function" "uploader" {
  filename = "repos/uploader.zip"
  function_name = "upload_gif"
  role = "${aws_iam_role.uploader_lambda_role.arn}"
  handler = "main.handler"
  source_code_hash = "${base64sha256(file("repos/uploader.zip"))}"
  provisioner "local-exec" {
    command = "zip -r repos/uploader.zip repos/uploader"
  }
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
#   list-s3-bucket
#
#   this lambda function is called whenever "gifs.radblock.xyz" changes
#   (when a gif expires or is uploaded).
#
#   It makes a list of all the gifs in that bucket, and saves it into
#   the "list.radblock.xyz" bucket.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# create a policy that can read from the gifs bucket
# and write to the list bucket

resource "aws_iam_role_policy" "accountant_lambda_policy" {
  name = "accountant_lambda_policy"
  role = "${aws_iam_role.accountant_lambda_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Stmt1458531615000",
      "Effect": "Allow",
      "Action": [
        "*"
      ],
      "Resource": [
        "arn:aws:s3:::${var.gifs_s3_bucket}",
        "arn:aws:s3:::${var.list_s3_bucket}/*"
      ]
    }
  ]
}
EOF
}

# attach it to a role

resource "aws_iam_role" "accountant_lambda_role" {
  name = "accountant_lambda_role"
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

# create a function to make a list of gifs and put it in a bucket
# https://github.com/radblock/list-s3-bucket

resource "aws_lambda_function" "accountant" {
  filename = "repos/list-s3-bucket.zip"
  function_name = "accountant"
  role = "${aws_iam_role.accountant_lambda_role.arn}"
  handler = "main.handler"
  source_code_hash = "${base64sha256(file("repos/list-s3-bucket.zip"))}"
  provisioner "local-exec" {
    command = "zip -r repos/accountant.zip repos/list-s3-bucket"
  }
}

# make the s3 bucket notify the lambda function of its changes

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = "${aws_s3_bucket.gifs.id}"
  lambda_function {
    lambda_function_arn = "${aws_lambda_function.accountant.arn}"
    events = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
    filter_prefix = ""
  }
}

# allow the lambda function to be called by the notification

resource "aws_lambda_permission" "allow_bucket" {
    statement_id = "AllowExecutionFromS3Bucket"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.accountant.arn}"
    principal = "s3.amazonaws.com"
    source_arn = "${aws_s3_bucket.gifs.arn}"
}

