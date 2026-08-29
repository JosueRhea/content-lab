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
