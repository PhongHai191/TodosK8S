# ─────────────────────────────────────────────────────────────────────────────
# GitHub Actions OIDC Role
# ─────────────────────────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}

# Look up the existing GitHub OIDC provider (one per AWS account)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-${var.environment}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Restrict to main branch of the specific repo
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = { Name = "${var.project_name}-${var.environment}-github-actions-role" }
}

# S3 deploy access for GitHub Actions
resource "aws_iam_role_policy" "gha_s3" {
  name = "${var.project_name}-${var.environment}-gha-s3"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3DeployAccess"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/deploy/*",
          "${var.s3_bucket_arn}/ansible-tmp/*",
          "${var.s3_bucket_arn}/i-*"
        ]
      }
    ]
  })
}

# ECR push access for GitHub Actions
resource "aws_iam_role_policy" "gha_ecr" {
  name = "${var.project_name}-${var.environment}-gha-ecr"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "arn:aws:ecr:*:*:repository/${var.project_name}-*"
      }
    ]
  })
}

