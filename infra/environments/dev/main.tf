# ═══════════════════════════════════════════════════════════════
# DEV ENVIRONMENT
# Wires all modules together for the dev environment
# We build this incrementally — adding modules as we write them
# ═══════════════════════════════════════════════════════════════

# ─── VPC ─────────────────────────────────────────────────────
module "vpc" {
  source      = "../../modules/vpc"
  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  region      = var.region
}

# ─── ECR ─────────────────────────────────────────────────────
module "ecr" {
  source      = "../../modules/ecr"
  project     = var.project
  environment = var.environment
}



