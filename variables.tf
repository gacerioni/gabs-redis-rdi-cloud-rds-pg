variable "region" {
  type        = string
  description = "AWS region, e.g. us-east-1"
}

variable "vpc_id" {
  type        = string
  description = "Existing VPC ID"
}

variable "db_subnet_ids" {
  type        = list(string)
  description = "DB subnet group subnets (min 2 in different AZs)"
}

variable "nlb_subnet_ids" {
  type        = list(string)
  description = "Subnets to place the NLB (should reach DB)"
}

variable "db_username" {
  type        = string
  default     = "postgres"
  description = "RDS master username"
}

variable "db_password" {
  type        = string
  default     = "Secret_42"
  sensitive   = true
  description = "RDS master password"
}

variable "db_name" {
  type        = string
  default     = "rdi_tag_team_demo"
  description = "Initial database name"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t4g.micro"
  description = "RDS instance class"
}

variable "db_allocated_storage" {
  type        = number
  default     = 20
  description = "RDS allocated storage (GB)"
}

# Enforce 17.4 as requested
variable "engine_version" {
  type        = string
  default     = "17.4"
  description = "PostgreSQL engine version"
}

# --- RDI specifics (split) ---
variable "rdi_account_id" {
  type        = string
  description = "RDI AWS account id (e.g., 120569626564)"
}

variable "rdi_endpoint_service_principal_arn" {
  type        = string
  description = "Principal ARN allowed on Endpoint Service (e.g., arn:aws:iam::120569626564:role/redis-data-pipeline)"
}

variable "rdi_secret_access_principal_arn" {
  type        = string
  description = "Principal ARN allowed to Get/Describe secret (e.g., arn:aws:iam::120569626564:role/redis-data-pipeline-secrets-role)"
}

variable "extra_allowed_cidrs_to_db" {
  type        = list(string)
  default     = []
  description = "Optional extra CIDRs to allow to DB:5432"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Optional tags"
}

variable "name_suffix" {
  type        = string
  default     = ""
  description = "Custom suffix for resource names, e.g. 'sa-01' or 'gabs'"
}
variable "add_random_suffix" {
  type        = bool
  default     = true
  description = "Append a random 6-char suffix for uniqueness"
}
variable "random_suffix_length" {
  type        = number
  default     = 6
  description = "Length of random suffix if enabled"
}