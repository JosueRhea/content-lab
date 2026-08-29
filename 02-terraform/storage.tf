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
