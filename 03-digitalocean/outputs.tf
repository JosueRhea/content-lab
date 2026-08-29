output "studio_url" {
  description = "Supabase Studio. Give this one to the audience."
  value       = "http://${digitalocean_reserved_ip.supabase.ip_address}:8000"
}

output "public_ip" {
  value = digitalocean_reserved_ip.supabase.ip_address
}

output "ssh" {
  description = "No Session Manager here -- this is the only way in."
  value       = "ssh root@${digitalocean_reserved_ip.supabase.ip_address}"
}

output "boot_progress" {
  value = "ssh root@${digitalocean_reserved_ip.supabase.ip_address} tail -f /var/log/supabase-boot.log"
}

output "droplet_id" {
  description = "Used by the kill-and-recover beat."
  value       = digitalocean_droplet.supabase.id
}

output "dashboard_credentials" {
  description = "Studio login. Printed in the clear so it lands in the apply output."
  value       = "supabase / ${random_id.dashboard_password.hex}"
}

output "summary" {
  description = "Everything you need, in one block at the end of apply."
  value       = <<-EOT

    Studio     http://${digitalocean_reserved_ip.supabase.ip_address}:8000
    Username   supabase
    Password   ${random_id.dashboard_password.hex}

    Droplet    ${digitalocean_droplet.supabase.id}
    Shell      ssh root@${digitalocean_reserved_ip.supabase.ip_address}
    Boot log   ssh root@${digitalocean_reserved_ip.supabase.ip_address} tail -f /var/log/supabase-boot.log
  EOT
}
