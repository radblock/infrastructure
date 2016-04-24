#  ██████╗  █████╗ ██████╗ ██████╗ ██╗      ██████╗  ██████╗██╗  ██╗
#  ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝
#  ██████╔╝███████║██║  ██║██████╔╝██║     ██║   ██║██║     █████╔╝
#  ██╔══██╗██╔══██║██║  ██║██╔══██╗██║     ██║   ██║██║     ██╔═██╗
#  ██║  ██║██║  ██║██████╔╝██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗
#  ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
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

# use amazon web services

provider "aws" {
  alias = "prod"
  region = "us-east-1"
  access_key = "${var.prod_access_key}"
  secret_key = "${var.prod_secret_key}"
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
#   random.radblock.xyz
#
#   a function for returning a random gif from the gif bucket
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# make a role that can get a list of all the gifs in the bucket

resource "aws_iam_role" "iam_for_random_giffer" {
    name = "iam_for_uploader"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Stmt1458531615000",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${var.gifs.s3_bucket}"
      ]
    }
  ]
}
EOF
}

# make a lambda function, using that role, for choosing one at random
# https://github.com/radblock/show-a-gif

resource "aws_lambda_function" "random_giffer" {
    filename = "random_giffer.zip"
    function_name = "random_gif"
    role = "${aws_iam_role.iam_for_random_giffer.arn}"
    handler = "exports.handler"
    source_code_hash = "${base64sha256(file("random_giffer.zip"))}"
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

# create a role for the gif uploader that can upload gifs to the gif bucket

resource "aws_iam_role" "iam_for_uploader" {
    name = "iam_for_uploader"
    assume_role_policy = <<EOF
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

# create a function to sign s3 upload requests using that role
# https://github.com/radblock/gimme

resource "aws_lambda_function" "uploader" {
    filename = "uploader.zip"
    function_name = "upload_gif"
    role = "${aws_iam_role.iam_for_uploader.arn}"
    handler = "exports.handler"
    source_code_hash = "${base64sha256(file("uploader.zip"))}"
}
