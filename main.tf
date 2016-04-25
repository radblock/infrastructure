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

resource "null_resource" "clone" {
  provisioner "local-exec" {
    command = "./provision.sh"
  }
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
  force_destroy = true
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
  force_destroy = true
  bucket = "${var.gifs_s3_bucket}"
  acl = "public-read"
  // allow the signatory on the website to upload to this bucket
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
  provider = "aws.prod"
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
#   radblock.xyz
#
#   this is the main website with marketing + the gif signatory
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# make a bucket

resource "null_resource" "deploy_website" {
  depends_on = ["null_resource.clone"]

  provisioner "local-exec" {
    command = "cd repos/website ; npm run deploy"
  }
}

resource "aws_s3_bucket" "website" {
  provider = "aws.prod"
  force_destroy = true
  bucket = "${var.website_s3_bucket}"
  acl = "public-read"
  website {
    index_document = "index.html.gz"
    error_document = "error.html.gz"
  }
}

# point radblock.xyz to that bucket

resource "aws_route53_record" "website" {
  provider = "aws.prod"
  zone_id = "${aws_route53_zone.primary.zone_id}"
  name = "${var.website_s3_bucket}"
  type = "A"

  alias {
    name = "${aws_s3_bucket.website.website_domain}"
    zone_id = "${aws_s3_bucket.website.hosted_zone_id}"
    evaluate_target_health = true
  }
}

# the website needs to know about the signatory

resource "template_file" "website_deps" {
  depends_on = ["null_resource.clone"]
  template = "${file("repos/website/deps.tpl")}"
  vars {
    signatory = "${aws_api_gateway_resource.signatory.path}"
    region = "us-east-1"
    bucket = "${aws_s3_bucket.website.bucket}"
  }
  provisioner "local-exec" {
    command = "echo '${template_file.website_deps.rendered}' > repos/website/deps.json"
  }
}

 # build the website

resource "null_resource" "build_website" {
  depends_on = ["template_file.website_deps", "aws_s3_bucket.website"]
  provisioner "local-exec" {
    command = "cd repos/website ; npm run deploy"
  }
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
#   signatory
#
#   this is the gif signatory's backend function
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# create a policy for the gif signatory that can upload gifs to the gif bucket

resource "aws_iam_role_policy" "signatory_lambda_policy" {
  provider = "aws.prod"
  name = "signatory_lambda_policy"
  role = "${aws_iam_role.signatory_lambda_role.id}"
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

resource "aws_iam_role" "signatory_lambda_role" {
  provider = "aws.prod"
  name = "signatory_lambda_role"
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

resource "aws_lambda_function" "signatory" {
  depends_on = ["template_file.signatory_deps"]
  provider = "aws.prod"
  filename = "repos/signatory.zip"
  function_name = "upload_gif"
  role = "${aws_iam_role.signatory_lambda_role.arn}"
  handler = "main.handler"
  source_code_hash = "${base64sha256(file("repos/signatory.zip"))}"
}

# the website needs to know about the signatory

resource "template_file" "signatory_deps" {
  depends_on = ["null_resource.clone"]
  template = "${file("repos/signatory/deps.tpl")}"
  vars {
    bucket = "${aws_s3_bucket.gifs.bucket}"
  }
  provisioner "local-exec" {
    command = "echo '${template_file.website_deps.rendered}' > repos/website/deps.json"
  }
}

# build the signatory

resource "null_resource" "build_signatory" {
  depends_on = ["template_file.signatory_deps"]
  provisioner "local-exec" {
    command = "cd repos/gimme ; npm run deploy ; zip -r ../signatory.zip ."
  }
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# api gateway crap to make the signatory function visible
# amazon says they're gonna change this so we need less crap here

resource "aws_api_gateway_rest_api" "signatory" {
  name = "signatory_api"
}

resource "aws_api_gateway_resource" "signatory" {
  rest_api_id = "${aws_api_gateway_rest_api.signatory.id}"
  parent_id = "${aws_api_gateway_rest_api.signatory.root_resource_id}"
  path_part = "signatory"
}

resource "aws_api_gateway_deployment" "signatory" {
  depends_on = ["aws_api_gateway_integration.signatory"]
  stage_name = "prod"
  rest_api_id = "${aws_api_gateway_rest_api.signatory.id}"
}

# the POST method triggers the lambda function

resource "aws_api_gateway_method" "signatory" {
  rest_api_id = "${aws_api_gateway_rest_api.signatory.id}"
  resource_id = "${aws_api_gateway_resource.signatory.id}"
  http_method = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "signatory" {
  rest_api_id = "${aws_api_gateway_rest_api.signatory.id}"
  resource_id = "${aws_api_gateway_resource.signatory.id}"
  http_method = "${aws_api_gateway_method.signatory.http_method}"
  type = "AWS"
  integration_http_method = "${aws_api_gateway_method.signatory.http_method}"
  uri = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${aws_lambda_function.signatory.arn}/invocations"
}

# the OPTIONS method is necessary for CORS
# http://docs.aws.amazon.com/apigateway/latest/developerguide/how-to-cors.html

resource "aws_api_gateway_method" "signatory_options" {
  rest_api_id = "${aws_api_gateway_rest_api.signatory.id}"
  resource_id = "${aws_api_gateway_resource.signatory.id}"
  http_method = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "signatory_options" {
  rest_api_id = "${aws_api_gateway_rest_api.signatory.id}"
  resource_id = "${aws_api_gateway_resource.signatory.id}"
  http_method = "${aws_api_gateway_method.signatory_options.http_method}"
  type = "MOCK"
  integration_http_method = "${aws_api_gateway_method.signatory_options.http_method}"
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

resource "aws_iam_role_policy" "list_s3_bucket_lambda_policy" {
  provider = "aws.prod"
  name = "list_s3_bucket_lambda_policy"
  role = "${aws_iam_role.list_s3_bucket_lambda_role.id}"
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

resource "aws_iam_role" "list_s3_bucket_lambda_role" {
  provider = "aws.prod"
  name = "list_s3_bucket_lambda_role"
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

resource "aws_lambda_function" "list_s3_bucket" {
  depends_on = ["null_resource.build_list_s3_bucket"]
  provider = "aws.prod"
  filename = "repos/list-s3-bucket.zip"
  function_name = "list_s3_bucket"
  role = "${aws_iam_role.list_s3_bucket_lambda_role.arn}"
  handler = "main.handler"
  source_code_hash = "${base64sha256(file("repos/list-s3-bucket.zip"))}"
  provisioner "local-exec" {
    command = "zip -r repos/list_s3_bucket.zip repos/list-s3-bucket"
  }
}

# # make the s3 bucket notify the lambda function of its changes
# # terraform claims to support this but I keep getting an error like they don't
#
# resource "aws_s3_bucket_notification" "bucket_notification" {
#   bucket = "${aws_s3_bucket.gifs.id}"
#   lambda_function {
#     lambda_function_arn = "${aws_lambda_function.list_s3_bucket.arn}"
#     events = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
#     filter_prefix = ""
#   }
# }

# allow the lambda function to be called by the notification

resource "aws_lambda_permission" "allow_bucket" {
  provider = "aws.prod"
  statement_id = "AllowExecutionFromS3Bucket"
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.list_s3_bucket.arn}"
  principal = "s3.amazonaws.com"
  source_arn = "${aws_s3_bucket.gifs.arn}"
}

# the list_s3_bucket needs to know about the gifs bucket and the list bucket

resource "template_file" "list_s3_bucket_deps" {
  depends_on = ["null_resource.clone"]
  template = "${file("repos/list-s3-bucket/deps.tpl")}"
  vars {
    gifs_bucket = "${aws_s3_bucket.gifs.bucket}"
    list_bucket = "${aws_s3_bucket.list.bucket}"
  }
  provisioner "local-exec" {
    command = "echo '${template_file.website_deps.rendered}' > repos/list-s3-bucket/deps.json"
  }
}

 # build the list_s3_bucket

resource "null_resource" "build_list_s3_bucket" {
  depends_on = ["template_file.list_s3_bucket_deps", "aws_s3_bucket.website"]
  provisioner "local-exec" {
    command = "cd repos/list-s3-bucket ; npm run deploy ; zip -r ../list_s3_bucket.zip ."
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
  force_destroy = true
  bucket = "${var.list_s3_bucket}"
  acl = "public-read"
  website {
    index_document = "list.json"
  }
}

# point list.radblock.xyz to that bucket

resource "aws_route53_record" "list" {
  provider = "aws.prod"
  zone_id = "${aws_route53_zone.primary.zone_id}"
  name = "${var.list_s3_bucket}"
  type = "A"

  alias {
    name = "${aws_s3_bucket.list.website_domain}"
    zone_id = "${aws_s3_bucket.list.hosted_zone_id}"
    evaluate_target_health = true
  }
}

