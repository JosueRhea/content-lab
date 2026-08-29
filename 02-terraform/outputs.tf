output "studio_url" {
  description = "Supabase Studio. Give this one to the audience."
  value       = "http://${aws_eip.supabase.public_ip}:8000"
}

output "public_ip" {
  value = aws_eip.supabase.public_ip
}

output "session_manager" {
  description = "Shell on the box. No SSH key, no bastion, no open port 22."
  value       = "aws ssm start-session --target ${aws_instance.supabase.id} --region ${var.region}"
}

output "boot_progress" {
  description = "Watch the stack come up (cloud-init takes ~5-7 min on first boot)."
  value       = "aws ssm start-session --target ${aws_instance.supabase.id} --region ${var.region} --document-name AWS-StartInteractiveCommand --parameters command='tail -f /var/log/supabase-boot.log'"
}

output "dashboard_credentials" {
  description = "Studio login."
  value       = "supabase / ${random_id.dashboard_password.hex}"
  sensitive   = true
}

output "instance_id" {
  description = "Used by the kill-and-recover beat."
  value       = aws_instance.supabase.id
}
