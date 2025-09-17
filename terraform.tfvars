region         = "us-east-1"
vpc_id         = "vpc-0ae08c2573e50aa42"

# Suffix to append to names (e.g. -dev, -prod, -sa-01)
name_suffix       = "gabs-13"

# RDS requires a DB subnet group with subnets in at least 2 AZs
db_subnet_ids  = ["subnet-095e39127aa2e17ce", "subnet-0c417f0775bbfad70"]

# NLB in subnets that can reach the DB (you gave two; fine)
nlb_subnet_ids = ["subnet-095e39127aa2e17ce", "subnet-0c417f0775bbfad70"]

# --- RDI specifics (split by purpose) ---
# Account root used in KMS key policy
rdi_account_id                      = "366717664304"
# Endpoint Service allowed principal
rdi_endpoint_service_principal_arn  = "arn:aws:iam::366717664304:role/redis-data-pipeline"
# Secret policy allowed principal (aws:PrincipalArn condition)
rdi_secret_access_principal_arn     = "arn:aws:iam::366717664304:role/redis-data-pipeline-secrets-role"

# Optional: open DB to additional CIDRs on 5432 (avoid unless truly needed)
extra_allowed_cidrs_to_db = []

# Force engine version as requested
engine_version = "17.4"

# Optional overrides:
# db_username       = "postgres"
# db_password       = "Secret_42"
# db_name           = "rdi_tag_team_demo"
# db_instance_class = "db.t4g.micro"