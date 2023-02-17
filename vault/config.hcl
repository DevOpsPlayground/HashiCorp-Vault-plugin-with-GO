plugin_directory = "/home/playground/workdir/HashiCorp-Vault-plugin-with-GO/vault/plugins"
api_addr         = "http://127.0.0.1:8200"

storage "inmem" {}

ui = true
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
}
