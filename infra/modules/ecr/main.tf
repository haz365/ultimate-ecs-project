# ═══════════════════════════════════════════════════════════════
# ECR MODULE
# Creates three Docker image repositories:
#   - api       (Python FastAPI)
#   - worker    (Python SQS consumer)
#   - dashboard (Python analytics)
#
# Each service has its own repo so images are versioned
# and deployed independently
# ═══════════════════════════════════════════════════════════════

locals {
  # The three services we're building
  services = ["api", "worker", "dashboard"]
}

# ─── ECR Repositories ────────────────────────────────────────
# One repository per service
# for_each creates one resource per item in the set
resource "aws_ecr_repository" "services" {
  for_each = toset(local.services)

  name = "${var.project}-${var.environment}-${each.key}"

  # IMMUTABLE = once an image tag is pushed it can never be
  # overwritten. Guarantees reproducibility in staging + prod.
  # In dev we use MUTABLE for convenience
  image_tag_mutability = var.environment == "prod" ? "IMMUTABLE" : "MUTABLE"

  # Scan every image on push for known CVEs (free)
  image_scanning_configuration {
    scan_on_push = true
  }

  # Allow deletion even if images exist
  # Important so terraform destroy works cleanly
  force_delete = true

  tags = {
    Name    = "${var.project}-${var.environment}-${each.key}"
    Service = each.key
  }
}

# ─── Lifecycle Policies ───────────────────────────────────────
# Auto-delete old images to save storage costs
# ECR charges $0.10/GB — keeps costs near zero
resource "aws_ecr_lifecycle_policy" "services" {
  for_each = toset(local.services)

  repository = aws_ecr_repository.services[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}