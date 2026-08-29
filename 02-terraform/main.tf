terraform {
  required_version = ">= 1.6"

  required_providers {
    aws    = { source = "hashicorp/aws", version = ">= 5.40, < 7.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }

  # Uncomment for the "state is shared infrastructure" segment.
  # Note use_lockfile: as of Terraform 1.10+ S3 does its own locking, so the old
  # DynamoDB lock table is no longer needed. Worth calling out live -- most
  # tutorials still tell people to create that table.
  #
  # backend "s3" {
  #   bucket       = "your-tf-state-bucket"
  #   key          = "content-lab/supabase/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "content-lab"
      Demo      = "supabase-iac"
      ManagedBy = "terraform"
    }
  }
}

# =============================================================================
# NETWORK -- minimal public VPC
# =============================================================================

# Minimal public VPC. No NAT gateway on purpose: it is ~$32/mo and buys us
# nothing here, since the instance sits in a public subnet and reaches SSM
# through the internet gateway.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = var.name }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# SECURITY -- what can reach the box
# =============================================================================

resource "aws_security_group" "supabase" {
  name        = "${var.name}-sg"
  description = "Supabase self-host. Kong only; no SSH, no exposed Postgres."
  vpc_id      = aws_vpc.main.id

  # Kong -- the single front door. Studio and every API route come through here.
  ingress {
    description = "Supabase API gateway (Kong)"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Note what is NOT here:
  #   - no :22. Access is via SSM Session Manager, so there is no key pair to
  #     lose, no bastion to run, and no open SSH port to get scanned.
  #   - no :5432. Postgres stays inside the Docker network. In the manual demo
  #     it is very tempting to open it "just to connect with psql". Don't.

  egress {
    description = "All outbound (Docker Hub, apt, SSM, GitHub)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-sg" }
}

# =============================================================================
# IAM -- the instance's own identity
# =============================================================================

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Gives us `aws ssm start-session` instead of SSH.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Scoped to exactly one secret -- not secretsmanager:* on Resource "*".
# This is the least-privilege beat: show the policy, then show the ARN it names.
data "aws_iam_policy_document" "secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.supabase.arn]
  }
}

resource "aws_iam_role_policy" "secrets" {
  name   = "${var.name}-read-secret"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.secrets.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-profile"
  role = aws_iam_role.instance.name
}

# =============================================================================
# SECRETS -- generated here, never typed
# =============================================================================

# Every credential is generated here and never typed by a human.
#
# random_id (hex) rather than random_password: hex has no shell-special or
# quote characters, so it drops into a .env file without escaping games.
#
# HONEST CAVEAT, worth saying on camera: these values land in Terraform state in
# plaintext. That is exactly why the S3 backend sets encrypt = true and why state
# buckets are locked down. Terraform does not make secrets disappear -- it moves
# where they live.

resource "random_id" "postgres_password" { byte_length = 24 }
resource "random_id" "jwt_secret" { byte_length = 32 }      # 64 hex chars
resource "random_id" "secret_key_base" { byte_length = 32 } # 64 hex chars
resource "random_id" "vault_enc_key" { byte_length = 16 }   # must be exactly 32
resource "random_id" "dashboard_password" { byte_length = 12 }

resource "aws_secretsmanager_secret" "supabase" {
  name                    = "${var.name}-env"
  description             = "Supabase self-host credentials"
  recovery_window_in_days = 0 # demo convenience: destroy really destroys
}

resource "aws_secretsmanager_secret_version" "supabase" {
  secret_id = aws_secretsmanager_secret.supabase.id
  secret_string = jsonencode({
    POSTGRES_PASSWORD  = random_id.postgres_password.hex
    JWT_SECRET         = random_id.jwt_secret.hex
    SECRET_KEY_BASE    = random_id.secret_key_base.hex
    VAULT_ENC_KEY      = random_id.vault_enc_key.hex
    DASHBOARD_USERNAME = "supabase"
    DASHBOARD_PASSWORD = random_id.dashboard_password.hex
  })
}

# =============================================================================
# STORAGE -- Postgres data outlives the instance
# =============================================================================

# Postgres data lives on its own EBS volume, not the root disk.
#
# This is the payoff for demo trap #3. In the manual build, terminating the
# instance destroys the database with it. Here the volume outlives the instance:
# terminate, apply, and the data is still there.

resource "aws_ebs_volume" "data" {
  availability_zone = aws_subnet.public.availability_zone
  size              = var.data_volume_gb
  type              = "gp3"
  encrypted         = true
  tags              = { Name = "${var.name}-data" }

  # Uncomment once you trust it -- stops a stray `destroy` taking the DB.
  # lifecycle { prevent_destroy = true }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf" # Nitro renames this; user-data resolves it by volume ID.
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.supabase.id
}

# =============================================================================
# COMPUTE -- the box and its stable address
# =============================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# The stable identity that the manual demo lacked. Reboot, replace, rebuild --
# the address the audience is hitting does not change.
resource "aws_eip" "supabase" {
  domain = "vpc"
  tags   = { Name = var.name }
}

resource "aws_instance" "supabase" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.supabase.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/user-data.sh", {
    secret_arn      = aws_secretsmanager_secret.supabase.arn
    region          = var.region
    public_host     = aws_eip.supabase.public_ip
    supabase_commit = var.supabase_commit
    data_volume_id  = aws_ebs_volume.data.id
  })

  tags = { Name = var.name }
}

resource "aws_eip_association" "supabase" {
  instance_id   = aws_instance.supabase.id
  allocation_id = aws_eip.supabase.id
}
