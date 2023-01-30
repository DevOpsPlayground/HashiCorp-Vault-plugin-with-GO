plugin_name = DPG-Vault-Plugin
SHA := $(shell shasum -a 256 vault/plugins/$(plugin_name) | cut -d ' ' -f1)
build:
	GOOS=linux GOARCH=amd64 go build -o vault/plugins/$(plugin_name) ./cmd/$(plugin_name)/main.go
	
	@echo $(SHA)
	$(MAKE) install SHA256=$(SHA) root_token=$(root_token)

install:
	export VAULT_TOKEN=$(root_token) ;\
	vault plugin deregister $(plugin_name); \
	vault secrets disable $(plugin_name); \
	vault plugin register -sha256=$(SHA256) secret $(plugin_name); \
	vault secrets enable $(plugin_name)

