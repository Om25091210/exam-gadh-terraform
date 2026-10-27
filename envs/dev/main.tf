locals {
  name             = "examgadh-${var.environment}"
  parameter_prefix = "/examgadh/${var.environment}"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "network" {
  source = "../../modules/network"
  name   = local.name
  azs    = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "storage" {
  source               = "../../modules/storage"
  name                 = local.name
  cors_allowed_origins = var.cors_allowed_origins
  force_destroy        = true # dev only: lets `terraform destroy` remove a non-empty bucket
}

module "database" {
  source                = "../../modules/database"
  name                  = local.name
  private_subnet_ids    = module.network.private_subnet_ids
  db_sg_id              = module.network.db_sg_id
  instance_class        = var.db_instance_class
  backup_retention_days = 7
  deletion_protection   = false
  skip_final_snapshot   = true
}

module "app_server" {
  source            = "../../modules/app_server"
  name              = local.name
  subnet_id         = module.network.public_subnet_id
  security_group_id = module.network.app_sg_id
  instance_type     = var.instance_type
  media_bucket_arn  = module.storage.media_bucket_arn
  parameter_prefix  = local.parameter_prefix
}

# The server may read the RDS-managed master secret (needed to run migrations and the API).
data "aws_iam_policy_document" "db_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [module.database.master_secret_arn]
  }
}

resource "aws_iam_role_policy" "db_secret" {
  name   = "read-db-master-secret"
  role   = module.app_server.role_name
  policy = data.aws_iam_policy_document.db_secret.json
}

module "ecr" {
  source = "../../modules/ecr"
  name   = local.name
}

module "deploy_roles" {
  source               = "../../modules/deploy_roles"
  name                 = local.name
  github_owner         = var.github_owner
  create_oidc_provider = false # created once per account in ../../bootstrap
  ecr_repository_arns  = values(module.ecr.repository_arns)
  instance_id          = module.app_server.instance_id
  parameter_prefix     = local.parameter_prefix
}

module "ops" {
  source             = "../../modules/ops"
  name               = local.name
  alert_email        = var.alert_email
  monthly_budget_usd = var.monthly_budget_usd
  instance_id        = module.app_server.instance_id
  db_identifier      = module.database.identifier
  db_arn             = module.database.arn
  enable_schedule    = var.enable_schedule
}
