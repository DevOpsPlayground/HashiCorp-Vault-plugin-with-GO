package playerdata

import (
	"context"
	"fmt"

	"github.com/hashicorp/vault/sdk/logical"
)

func Factory(ctx context.Context, conf *logical.BackendConfig) (logical.Backend, error) {
	return nil, fmt.Errorf("error backend not setup")
}
