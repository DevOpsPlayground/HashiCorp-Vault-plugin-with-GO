#!/bin/bash

nohup /usr/bin/vault server -config /home/playground/workdir/HashiCorp-Vault-plugin-with-GO/vault/config.hcl &

sleep 5
export VAULT_ADDR='http://127.0.0.1:8200'
echo $VAULT_ADDR
TOKENS=$(vault operator init -format=json -key-shares=1 -key-threshold=1)
echo $TOKENS | jq -r '.unseal_keys_b64[0]';
vault operator unseal $(echo $TOKENS | jq -r .unseal_keys_b64[0])
echo $(echo $TOKENS | jq -r '.root_token')
