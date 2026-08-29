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
