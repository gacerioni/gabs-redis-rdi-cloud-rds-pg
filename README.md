
# RDS PostgreSQL for RDI via AWS PrivateLink

This Terraform project provisions a **private** RDS PostgreSQL (17.4) and exposes it to **Redis Data Integration (RDI)** over **AWS PrivateLink**. It front-ends the DB with an **internal NLB**, publishes an **Endpoint Service**, and manages **Secrets Manager** + **KMS** so RDI can retrieve credentials securely.

This repo is currently used from the **AWS SA Account**, targeting the VPC **`gabs-sa-sales-vpc`**.

---

## What this Terraform does

**Core resources (provider side):**
- **RDS PostgreSQL 17.4** (private, Single-AZ) with:
  - Custom **DB Parameter Group** (`postgres17`) enabling `rds.logical_replication=1`
  - **Enhanced Monitoring disabled** for faster create
  - Security Group allowing TCP **5432** **only** from NLB subnet CIDRs (and any optional CIDRs you provide)

- **Internal Network Load Balancer (NLB)**:
  - **TCP:5432** listener → **IP Target Group**
  - Target Group attaches the **RDS private IP** (resolved at apply time from the RDS endpoint DNS)

- **VPC Endpoint Service (PrivateLink)**:
  - Backed by the NLB
  - **Allowed principal** = RDI **pipeline** role (you set via variable)
  - Share the **service name** output with RDI

- **KMS key + alias** (for Secrets Manager encryption):
  - Your account **root**: full admin
  - **RDI account root**: key **use** permissions (Decrypt/Describe/GenerateDataKey*, etc.)

- **Secrets Manager secret** with DB credentials:
  - Encrypted by the KMS key
  - Resource policy allows **RDI “secrets role”** (via `aws:PrincipalArn` condition) to `GetSecretValue`

**Naming for multi-SA safety:**
- All nameable resources support a **`name_suffix`** and optional **random suffix** to avoid collisions across runs/tenants.

**Outputs:**
- Endpoint Service **service name**
- Credentials **Secret ARN**
- Database name
- Resolved **RDS private IP** (for sanity)
- **NLB DNS name** (use this to connect from a bastion/VPCE)

---

## Why the NLB + IP Target Group?

RDS endpoint DNS can change IPs (e.g., during failover). PrivateLink **requires** a stable target on the provider side. Since **RDI cannot use RDS Proxy**, we resolve the **current** private IP at apply time and attach it to the IP target group.

> If the DB fails over and its IP changes, re-run `terraform apply` to refresh the target group attachment.

---

## Requirements

- **Terraform** ≥ 1.5 (tested with 1.7.x)
- Providers:
  - `hashicorp/aws` ~> 6.13
  - `hashicorp/external` ~> 2.3.5
  - `hashicorp/random` ~> 3.6
- AWS credentials with permissions to create RDS/NLB/VPC/Secrets/KMS/VPCE-service
- The machine running `terraform apply` must be able to **resolve the RDS private DNS** to a **private IP**:
  - Typically run from an **EC2** in the same VPC, or over VPN/Direct Connect with proper DNS forwarding.

---

## Variables you must set

- **Networking**
  - `region`
  - `vpc_id` (e.g., VPC for **`gabs-sa-sales-vpc`**)
  - `db_subnet_ids` (RDS subnet group – two subnets in different AZs)
  - `nlb_subnet_ids` (where to place the internal NLB)

- **RDI principals**
  - `rdi_account_id` (e.g., `120569626564`)
  - `rdi_endpoint_service_principal_arn` (e.g., `arn:aws:iam::120569626564:role/redis-data-pipeline`)
  - `rdi_secret_access_principal_arn` (e.g., `arn:aws:iam::120569626564:role/redis-data-pipeline-secrets-role`)

- **DB basics (defaults provided)**
  - `engine_version` (default **17.4**)
  - `db_instance_class` (default `db.t4g.micro`)
  - `db_allocated_storage` (default `20`)
  - `db_name` (default `rdi_tag_team_demo`)
  - `db_username` (default `postgres`)
  - `db_password` (default `Secret_42` – override in tfvars or environment)

- **Access tuning**
  - `extra_allowed_cidrs_to_db` (list of extra CIDRs allowed to reach the DB on 5432; optional; default `[]`)

- **Name collision safety (optional)**
  - `name_suffix` (e.g., `"gabs-13"`)
  - `add_random_suffix` (bool; default `true`)
  - `random_suffix_length` (default `6`)

---

## Example `terraform.tfvars`

> Replace IDs with your actual values for **`gabs-sa-sales-vpc`**.

```hcl
region         = "us-east-1"
vpc_id         = "vpc-0ae08c2573e50aa42"

# RDS in two private subnets (different AZs)
db_subnet_ids  = ["subnet-095e39127aa2e17ce", "subnet-0c417f0775bbfad70"]

# NLB in subnets that can reach the DB
nlb_subnet_ids = ["subnet-095e39127aa2e17ce", "subnet-0c417f0775bbfad70"]

# RDI principals
rdi_account_id                      = "120569626564"
rdi_endpoint_service_principal_arn  = "arn:aws:iam::120569626564:role/redis-data-pipeline"
rdi_secret_access_principal_arn     = "arn:aws:iam::120569626564:role/redis-data-pipeline-secrets-role"

# Optional extras
# extra_allowed_cidrs_to_db = ["10.0.0.0/16"]

# Naming
name_suffix        = "gabs-13"
add_random_suffix  = true
random_suffix_length = 6

# DB overrides (keep defaults unless you need to change)
engine_version     = "17.4"
# db_username      = "postgres"
# db_password      = "change_me"
# db_name          = "rdi_tag_team_demo"
# db_instance_class = "db.t4g.micro"
```

---

## How to run

```bash
terraform init -upgrade
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

> If you see “Inconsistent dependency lock file” after adding the `random` provider, run `terraform init -upgrade` once.

---

## Connecting to the DB for seeding/tests

- Terraform outputs **`nlb_dns_name`**.  
- From a **bastion in the same VPC** (or from the **consumer VPCE** once RDI creates it), run:

```bash
psql -h <nlb_dns_name> -p 5432 -U <db_username> -d <db_name>
```

To create the demo table + seed rows, use the provided `db_init.sql`:

```bash
psql -h <nlb_dns_name> -p 5432 -U postgres -d rdi_tag_team_demo -f ./db_init.sql
```

---

## Outputs

- `endpoint_service_name` – share this with RDI (they’ll create an Interface VPC Endpoint)
- `db_credentials_secret_arn` – credentials Secret ARN to give to RDI
- `database_name` – the DB name (default `rdi_tag_team_demo`)
- `resolved_rds_private_ip` – the IP currently registered in the NLB target group
- `nlb_dns_name` – use this to connect from a bastion/VPCE

---

## Operational notes & gotchas

- **DNS/IP resolution:** The RDS endpoint’s IP can change (failover). We resolve DNS → IP at **apply time** and attach that IP to the TG. On failover, just re-run `terraform apply` to refresh the target.
- **Enhanced Monitoring:** Disabled (`monitoring_interval = 0`) for faster provisioning. Enable only if you need 1s metrics.
- **Parameter group & reboot:** Instance is created with the custom parameter group, so `rds.logical_replication=1` is effective immediately. Reboot only needed if you change the param group later.
- **Security groups:** DB SG allows 5432 from NLB subnets (+ any extra CIDRs you set). NLB itself has no SGs.
- **Secrets/KMS access:** Secret policy allows RDI secrets role; KMS key allows RDI account root. Your account root remains admin.
- **Name collisions:** Use suffix variables to run multiple copies in parallel.

---

## Current environment

- **Account:** AWS SA Account
- **VPC:** `gabs-sa-sales-vpc`
- **Region:** `us-east-1`

---

## Cleanup

```bash
terraform destroy -var-file=terraform.tfvars
```

> Note: If a secret name was created and then deleted, AWS reserves the name during the recovery window. Either **restore** it (`aws secretsmanager restore-secret --secret-id <name>`) or re-run with a new suffix.
