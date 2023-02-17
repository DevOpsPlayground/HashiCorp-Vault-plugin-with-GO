plugin_name = DPG-Vault-Plugin
SHA := $(shell sha256sum vault/plugins/$(plugin_name) | cut -d ' ' -f1)

build:
        go mod tidy
	GOOS=linux GOARCH=amd64 go build -o vault/plugins/$(plugin_name) ./cmd/$(plugin_name)/main.go
	$(MAKE) install

install:
	vault plugin deregister $(plugin_name); \
	vault secrets disable $(plugin_name); \
	vault plugin register -sha256=$(SHA) secret $(plugin_name); \
	vault secrets enable $(plugin_name)

