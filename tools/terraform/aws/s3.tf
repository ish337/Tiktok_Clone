// Media storage for videos and avatars.
// The bucket name is also set in compose.server.yaml (AWS__S3__BucketName / AWS__S3__CdnBaseUrl) - keep them in sync.
locals {
  media_bucket = "much-more-demo-media-a41fd8"
}

resource "aws_s3_bucket" "media" {
  bucket = local.media_bucket
  // Media is useless without the DB, which is destroyed with the agent anyway
  force_destroy = true
}

// ACLs stay blocked; only the bucket policy below may grant public read
resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

// The site loads processed videos, thumbnails and avatars straight from the bucket
resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadMedia"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource = [
        "${aws_s3_bucket.media.arn}/uploads/processed/*",
        "${aws_s3_bucket.media.arn}/avatars/*",
      ]
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.media]
}

// Browser uploads go straight to S3 with a presigned PUT, and HLS playback fetches playlists via XHR
resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  cors_rule {
    allowed_origins = ["https://${var.duckdns_subdomain}.duckdns.org"]
    allowed_methods = ["GET", "HEAD", "PUT"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

// Key for the api and video_processor containers (AWS_S3_ACCESS_KEY / AWS_S3_SECRET_KEY in .env_server)
resource "aws_iam_user" "media" {
  name = "${var.duckdns_subdomain}-media"
}

resource "aws_iam_user_policy" "media" {
  name = "media-bucket-access"
  user = aws_iam_user.media.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
        ]
        Resource = "${aws_s3_bucket.media.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:ListBucketMultipartUploads"]
        Resource = aws_s3_bucket.media.arn
      },
    ]
  })
}

resource "aws_iam_access_key" "media" {
  user = aws_iam_user.media.name
}


//  Outputs
output "media_bucket_url" {
  value       = "https://${aws_s3_bucket.media.bucket_regional_domain_name}"
  description = "Public base URL of the media bucket (AWS__S3__CdnBaseUrl)"
}

output "media_env_server_lines" {
  value       = <<-EOT
    AWS_S3_ACCESS_KEY=${aws_iam_access_key.media.id}
    AWS_S3_SECRET_KEY=${aws_iam_access_key.media.secret}
  EOT
  description = "AWS_S3_* lines for .env_server"
  sensitive   = true
}
