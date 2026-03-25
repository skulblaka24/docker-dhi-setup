# Will store the .env in /tmp as on mac is stored in RAM

# Prerequisites:
# To run the agent: $ vault agent -config=vault-agent.hcl -log-level=info
# To setup the vault token: echo $VAULT_TOKEN > /tmp/vault-agent-token && chmod 600 /tmp/vault-agent-token

vault {
  address = "http://local.vault.starfly.fr:8200"
}

auto_auth {
  method "token_file" {
    config = {
      token_file_path = "/tmp/vault-agent-token"
    }
  }
}

template_config {
  static_secret_render_interval = "5m"
  exit_on_retry_failure         = true
}

# Render secrets to tmp env file ##########################################
template {
  contents = <<EOT
{{- with secret "docker-dhi-setup/data/postgres" -}}
POSTGRES_USER={{ .Data.data.username }}
POSTGRES_PASSWORD={{ .Data.data.password }}
POSTGRES_DB={{ .Data.data.db }}
{{- end }}
{{- with secret "docker-dhi-setup/data/redis" }}
REDIS_PASSWORD={{ .Data.data.password }}
{{- end }}
EOT

  destination = "/tmp/vault-env/.env"
  perms       = "0600"

  # Re-render triggers a compose restart for affected services only
  # command = "docker compose up -d --no-deps db redis"
}

# Render redis.conf with password inside ##########################################
template {
  contents = <<EOT
{{- with secret "docker-dhi-setup/data/redis" -}}
requirepass {{ .Data.data.password }}
{{- end }}
EOT

  destination = "/tmp/vault-env/redis.conf"
  perms       = "0600"

}