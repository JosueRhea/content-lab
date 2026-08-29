# Same generation as the AWS build...
resource "random_id" "postgres_password" { byte_length = 24 }
resource "random_id" "jwt_secret" { byte_length = 32 }
resource "random_id" "secret_key_base" { byte_length = 32 }
resource "random_id" "vault_enc_key" { byte_length = 16 }
resource "random_id" "dashboard_password" { byte_length = 12 }

# ...but with nowhere to put them.
#
# THIS IS THE MOST IMPORTANT DIFFERENCE IN THE WHOLE BUILD.
#
# On AWS, four IAM resources gave the instance its own identity, and it fetched
# credentials from Secrets Manager at boot. Nothing sensitive was ever written
# into the launch configuration.
#
# DigitalOcean droplets have no equivalent identity and DO has no secret manager
# for droplets. So the credentials have to be injected straight into user_data --
# and DO user_data is readable for the droplet's whole life at
#     http://169.254.169.254/metadata/v1/user-data
# by ANY process on the box, root or not.
#
# We are not fixing that here; we are showing it. It is the sharpest possible
# demonstration that "just switch providers" is never just a rewrite: the AWS
# config depended on a capability that does not exist over here.
#
# Doing this properly on DO means an external secret store (Vault, Doppler,
# Infisical) -- which needs its own bootstrap token, which lands in user_data
# anyway. You reduce the blast radius; you do not eliminate it.
