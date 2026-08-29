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
