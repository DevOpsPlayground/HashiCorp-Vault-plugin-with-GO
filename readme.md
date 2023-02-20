# Devops Playground Vault Plugin

## Step 0: Setup vault

Run start script to spin up a vault cluster, unseal is and output the root key for us to use.

```bash
sh ./start.sh
```

The last line of the output will be the vault root token. To make our life easyer we will be running the go build and vault set up commands, via make. So we need to add to token to the make file. On line 4 add the vault token after

```make
root_token = 
```

So you have something that looks like this:

```make
root_token = hvs.BzpVxzd7ayRURLBn92aG1V8D
```

And in the terminal you need to export 2 values to make sure we can connect to vault from it.

```bash
export VAULT_TOKEN=<token>
export VAULT_ADDR=http://127.0.0.1:8200
```

## Step 1: Backend

To allow vault to know what this plugin can do and what paths it uses, we set up a backend.

As part of the empty template we have set up an empty factory that gets run when vault trys to run the plugin.

The first step of setting up the backend is filling in the Factory block

Open the `backed.go` file

Replace the factory block with

```go
// Factory returns a new backend as logical.Backend
func Factory(ctx context.Context, conf *logical.BackendConfig) (logical.Backend, error) {
 b := backend()
 if err := b.Setup(ctx, conf); err != nil {
  return nil, err
 }
 return b, nil
}
```

This code will have some errors as it is trying to call functions we have yet to declare.

Lets declare them now copy to following under the Factory block:

```go
type playerDataBackend struct {
  *framework.Backend
}

func backend() *playerDataBackend {
  return nil
}
```

After this swap to your terminal and run the following to make sure all the import are loaded correctly:

```bash
go mod tidy
```

This stops all the errors, but there is still a few more steps to let us use this within vault. Replace the `backend()` function you just made with the following:

```go
func backend() *playerDataBackend {
  var b = playerDataBackend{}

  b.Backend = &framework.Backend{
    Help: "",
    PathsSpecial: &logical.Paths{
      LocalStorage:    []string{},
      SealWrapStorage: []string{},
    },
    Paths:       framework.PathAppend(),
    Secrets:     []*framework.Secret{},
    BackendType: logical.TypeLogical,
  }
  return &b
}
```

We also need to add a new import, at the top of the page change the import block to

```go
import (
  "context"
  "github.com/hashicorp/vault/sdk/framework"
  "github.com/hashicorp/vault/sdk/logical"
)
```

As we have changed the imports, we need to rerun go mod tidy. 

So in your command line run

```bash
go mod tidy
```

To see that this works in vault run

```bash
make build
```

This command build vault and gets a checksum of the file.
It then does some clean up of old plugin versions that might be in vault.
Then we register the new plugin and create a secret for them.

To make sure this has added a secret in vault you can run the following command:

```bash
vault secrets list
```

This lists all the secret engines that have been setup.

Next lets run the path-help command to see what our secret engine can do:

```bash
vault path-help DPG-Vault-Plugin/
```

It looks like not a lot, lets edit the code to add some help text.

Add this to the bottom of the `backend.go` file

```go
const backendHelp = `
Stores the player data
`
```

Then in the `Backend()` function change `Help: "",` to:

```go
Help: strings.TrimSpace(backendHelp),
```

We need one more import change. At the to of the file, replace the inport block with 

```go
import (
	"context"
	"strings"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)
```

Now we have a simple backend set up, time to set up a path.

## Step 2: Path

### schema

First step create a new file called path_player.go, this can either be done in the IDE or with:

```bash
touch path_player.go
```

The first thing we need to do is add a package line at the top to make go happy.

Add the following to the to top the `path_player.go` file

```go
package playerdata
```

once we have done that we can start adding the code to make the path. Add the following code at the bottem of the file:

```go
func pathPlayer(b *playerDataBackend) []*framework.Path {
  return []*framework.Path{
    {
      Pattern:         framework.GenericNameRegex("name"),
      Fields:          map[string]*framework.FieldSchema{},
      Operations:      map[logical.Operation]framework.OperationHandler{},
      HelpSynopsis:    "",
      HelpDescription: "",
    },
    {
      Pattern:         "?$",
      Operations:      map[logical.Operation]framework.OperationHandler{},
      HelpSynopsis:    "",
      HelpDescription: "",
    },
  }
}
```

You then need to add the required imports just below the line `package playerdata`

```go
import (

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)
```

Now if you buld the code again and run the help again.

You will see nothing has changed, that is because even though we have writen the path code, we havent told the backend about it yet.

Open back `backend.go` and replace:

```go
    Paths:       framework.PathAppend(),
```

with:

```go
  Paths: framework.PathAppend(
    pathPlayer(&b),
  ),
```

Now if you build and run the help command again, you will see there are some paths that match the 2 Patterns we added in the last step

Next we need to add the ability to read and write at the path.

The first step to that is to add the schema that give us the kv vaules that vault can take in.

In `path_players.go` replace:

```go
Fields:          map[string]*framework.FieldSchema{},
```

with:

```go
Fields: map[string]*framework.FieldSchema{
        "name": {
          Type:        framework.TypeLowerCaseString,
          Description: "Name of the playerSec",
          Required:    true,
        },
        "class": {
          Type:        framework.TypeString,
          Description: "class of the player",
          Required:    true,
        },
        "experience": {
          Type:        framework.TypeInt,
          Description: "experience for class",
          Required:    false,
        },
      },
```

underneath that line we need to replace:

```go
Operations:      map[logical.Operation]framework.OperationHandler{},
```

with:

```go
Operations: map[logical.Operation]framework.OperationHandler{
  logical.ReadOperation: &framework.PathOperation{
    Callback: b.pathPlayerRead,
  },
},
```

### Reading

This code block tells vault what functions to call when diffrent operations are called.

`b.pathPlayerRead` will error as we havent made that function yet, lets fix that now.

Before we define the function that is is complaining about we need to add 2 more bits of code.
We need a struct we can pass around and convert the input in to something we can save.

Add the following to the `path_player.go` file just under the imports

```go
type playerDataPlayerEntity struct {
  Class      string `json:"class"`
  Experience int    `json:"experience"`
}
```

To make our code more scalable and editable in the future we want to make a `getplayer` function our `pathPlayerRead` can call so we can split the geting the data and the vault parts.

add the following the to bottom of the file:

```go
func (b *playerDataBackend) getPlayer(ctx context.Context, s logical.Storage, name string) (*playerDataPlayerEntity, error) {
  if name == "" {
    return nil, fmt.Errorf("missing player name")
  }

  entry, err := s.Get(ctx, name)
  if err != nil {
    return nil, err
  }

  if entry == nil {
    return nil, nil
  }

  var player playerDataPlayerEntity

  if err := entry.DecodeJSON(&player); err != nil {
    return nil, err
  }

  return &player, nil
}
```

The above code checks if the name is passed in, as it is the key the rest of the data if stored under. It this uses `s.Get` to get the json data stored by vault and decodes it before returning the struct we made earlyer.

the last bit is to add the following to the bottem of the `path_player.go` file

```go
func (b *playerDataBackend) pathPlayerRead(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
  entry, err := b.getPlayer(ctx, req.Storage, d.Get("name").(string))
  if err != nil {
    return nil, err
  }
  if entry == nil {
    return nil, nil
  }
  return &logical.Response{
    Data: entry.toResponceData(),
  }, nil
}
```

We have split out the ResponceData in to its own function so lets add that now, add the following to the bottem of the file:

```go
func (r *playerDataPlayerEntity) toResponceData() map[string]interface{} {
  return map[string]interface{}{
    "class":      r.Class,
    "experience": r.Experience,
  }
}
```

Once we have writen the functions we need to add a few more imports to the top of the file, replace the import block with 

```go
import (
  "context"
  "fmt"

  "github.com/hashicorp/vault/sdk/framework"
  "github.com/hashicorp/vault/sdk/logical"
)
```

### Write

To be able to write to vault, just like reading we need to tell it what function to call on the write operation, replace:

```go
Operations: map[logical.Operation]framework.OperationHandler{
  logical.ReadOperation: &framework.PathOperation{
    Callback: b.pathPlayerRead,
  },
},
```

with:

```go
Operations: map[logical.Operation]framework.OperationHandler{
  logical.ReadOperation: &framework.PathOperation{
    Callback: b.pathPlayerRead,
  },
  logical.CreateOperation: &framework.PathOperation{
    Callback: b.pathPlayerWrite,
  },
  logical.UpdateOperation: &framework.PathOperation{
    Callback: b.pathPlayerWrite,
  },
},
```

We get 2 for 1 in this example as the code we use to create is the same code we call on update

Again we have split the code up, as we need to all the `setPlayer` function before the `pathPlayerWrite` function will work, so lets add that first.

Add the following to the bottom of the code:

```go
func setPlayer(ctx context.Context, s logical.Storage, name string, playerEntity *playerDataPlayerEntity) error {
  entry, err := logical.StorageEntryJSON(name, playerEntity)
  if err != nil {
    return err
  }
  if entry == nil {
    return fmt.Errorf("failed to create storage entry for player")
  }

  if err := s.Put(ctx, entry); err != nil {
    return err
  }
  return nil
}
```

The above code gets the struct for the data we want to save. turns it in to the format that vault wants, and then calls `s.put` to store it.

Once that is added we can finaly write to vault. Add this code to the bottom of your file:

```go
func (b *playerDataBackend) pathPlayerWrite(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
  name, ok := d.GetOk("name")
  if !ok {
    return logical.ErrorResponse("missing player name"), nil
  }

  playerEntry, err := b.getPlayer(ctx, req.Storage, name.(string))
  if err != nil {
    return nil, err
  }

  if playerEntry == nil {
    playerEntry = &playerDataPlayerEntity{}
  }

  createOperation := (req.Operation == logical.CreateOperation)

  if class, ok := d.GetOk("class"); ok {
    playerEntry.Class = class.(string)
  } else if !ok && createOperation {
    return nil, fmt.Errorf("missing class in role")
  }

  if exp, ok := d.GetOk("experience"); ok {
    playerEntry.Experience = exp.(int)
  } else if !ok && createOperation {
    return nil, fmt.Errorf("missing experience in role")
  }

  if err := setPlayer(ctx, req.Storage, name.(string), playerEntry); err != nil {
    return nil, err
  }
  return nil, nil
}
```

We can now read and write to vault, re build the plugin, and run the following command to save your first secret:

```bash
vault write DPG-Vault-Plugin/panda class=rdm
```

Now we have writen a secret time to see if we can read it. run:

```bash
vault read DPG-Vault-Plugin/panda
```

You should see the class you entered returned. And experience 0. Lets change that and at the same time prove that the update funcionality is working. Run the following code:

```bash
vault write DPG-Vault-Plugin/panda experience=10
vault read DPG-Vault-Plugin/panda
```

You will see that the panda now has 10 experience.

### list

No we can read and write values, lets enable the ability to list all of the secrets in this path.

This uses the `"?$"` pattern which will match anything that gets to it.

To let us have the list operation replace the following code just under `Pattern: "?$",`:

```go
Operations:      map[logical.Operation]framework.OperationHandler{},
```

with:

```go
Operations: map[logical.Operation]framework.OperationHandler{
  logical.ListOperation: &framework.PathOperation{
    Callback: b.pathPlayerList,
  },
},
```

Next add the `pathPlayerList` function to the bottom of the file:

```go
func (b *playerDataBackend) pathPlayerList(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
  entries, err := req.Storage.List(ctx, "")
  if err != nil {
    return nil, err
  }

  return logical.ListResponse(entries), nil
}
```

This code gets all the entries in the vault storage, and returns it.

You can now rebuild the plugin and test out the list (you need to remake the secret everytime you rebuild the plugin)

Run this code to show the list:

```bash
vault list DPG-Vault-Plugin/
```

### delete

While we can delete by rebuilding the secret engine, its worth adding the ability to choose to delete just one secret.

update the following code:

```go
Operations: map[logical.Operation]framework.OperationHandler{
  logical.ReadOperation: &framework.PathOperation{
    Callback: b.pathPlayerRead,
  },
  logical.CreateOperation: &framework.PathOperation{
    Callback: b.pathPlayerWrite,
  },
  logical.UpdateOperation: &framework.PathOperation{
    Callback: b.pathPlayerWrite,
  },
},
```

with:

```go
Operations: map[logical.Operation]framework.OperationHandler{
  logical.ReadOperation: &framework.PathOperation{
    Callback: b.pathPlayerRead,
  },
  logical.CreateOperation: &framework.PathOperation{
    Callback: b.pathPlayerWrite,
  },
  logical.UpdateOperation: &framework.PathOperation{
    Callback: b.pathPlayerWrite,
  },
  logical.DeleteOperation: &framework.PathOperation{
    Callback: b.pathPlayerDelete,
  },
},
```

Then add the following code to the bottom of the file, to run the vault delete code:

```go
func (b *playerDataBackend) pathPlayerDelete(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
  err := req.Storage.Delete(ctx, d.Get("name").(string))
  if err != nil {
    return nil, fmt.Errorf("error deleting playerData role: %w", err)
  }
  return nil, nil
}
```

This is a basic vault plugin made, In the next steps we will extend the plugin to let it do more than a basic kv.

## Step 3: computed value

One of the cool things you can do is have values you can read but not write (useful if you want to get data from another service)

In this example we will add a level vaule that gets compluted from the amout of experiance you have.

The first step is to add a function that calculates what level you are from your amount of experiance.

Add this to the bottom of the `path_player.go` file:

```go
func (r *playerDataPlayerEntity) GetLevel() int {
  return int(math.Floor(math.Sqrt(float64(r.Experience))))
}
```

Now we have a function to calculate the level time to add it to the output.

replace:

```go
func (r *playerDataPlayerEntity) toResponceData() map[string]interface{} {
  return map[string]interface{}{
    "class":      r.Class,
    "experience": r.Experience,
  }
}
```

with:

```go
func (r *playerDataPlayerEntity) toResponceData() map[string]interface{} {
  return map[string]interface{}{
    "class":      r.Class,
    "experience": r.Experience,
    "level":      r.GetLevel(),
  }
}
```

One last import change from this file to add the math package. Replace the import block at the top with:

```go
import (
	"context"
	"fmt"
	"math"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)
```

Now if we rebuild the plugin. Remake the secret and give the panda some experiance, the level should increase.

Here is a write command that will make the panda with a good amount of experiance

```bash
vault write DPG-Vault-Plugin/panda experience=1000
```

## step 4: config

While this example doesnt really have a need for the config part of vault secrets, it is a important part of how vault can connect to other services with out users being able to see the connection information.

To start with this make a new file called `path_config.go` or run:

```bash
touch path_config.go
```

The same as before we need to set up wht schema for the new path.

add the following to the bottom of the new file:

```go
package playerdata

import (
	"context"
	"fmt"
	"errors"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

func pathConfig(b *playerDataBackend) *framework.Path {
  return &framework.Path{
    Pattern: "config",
    Fields: map[string]*framework.FieldSchema{
      "starting_level": {
        Type:        framework.TypeInt,
        Description: "base level to start at",
        Required:    true,
        DisplayAttrs: &framework.DisplayAttributes{
          Name:      "starting_level",
          Sensitive: false,
        },
      },
    },
    Operations:      map[logical.Operation]framework.OperationHandler{},
    HelpSynopsis:    "",
    HelpDescription: "",
  }
}

```

This tells vault what we want to be able to config, normaly this would be a username and password. But here we are going to use it to define what level players start at.

Now go back to `backend.go` and add the path to the `Backend` function

replace:

```go
Paths: framework.PathAppend(
  pathPlayer(&b),
),
```

with:

```go
Paths: framework.PathAppend(
  []*framework.Path{
    pathConfig(&b),
  },
  pathPlayer(&b),
),
```

The path can now be seen in vault but we havent got any operations so lets go back to the `path_config.go` file and add them.

replace:

```go
Operations:      map[logical.Operation]framework.OperationHandler{},
```

with:

```go
Operations: map[logical.Operation]framework.OperationHandler{
  logical.ReadOperation: &framework.PathOperation{
    Callback: b.pathConfigRead,
  },
  logical.CreateOperation: &framework.PathOperation{
    Callback: b.pathConfigWrite,
  },
  logical.UpdateOperation: &framework.PathOperation{
    Callback: b.pathConfigWrite,
  },
  logical.DeleteOperation: &framework.PathOperation{
    Callback: b.pathConfigDelete,
  },
},
```

Before we add the crud functions there is some helper code that we need first.

Add this above the `pathConfig` block of the code:

```go
const (
  configStoragePath = "config"
)

type playerDataConfig struct {
  StartingLevel int `json:"starting_level"`
}

func getConfig(ctx context.Context, s logical.Storage) (*playerDataConfig, error) {
  entry, err := s.Get(ctx, configStoragePath)
  if err != nil {
    return nil, err
  }

  if entry == nil {
    return &playerDataConfig{}, nil
  }

  config := new(playerDataConfig)
  if err := entry.DecodeJSON(&config); err != nil {
    return nil, fmt.Errorf("error reading root configuration: %w", err)
  }

  // return the config, we are done
  return config, nil
}
```

Then at the bottom of the file add the follwing to let us read, write and delete:

```go
func (b *playerDataBackend) pathConfigRead(ctx context.Context, req *logical.Request, data *framework.FieldData) (*logical.Response, error) {
  c, err := getConfig(ctx, req.Storage)
  if err != nil {
    return nil, err
  }

  return &logical.Response{
    Data: map[string]interface{}{
      "starting_level": c.StartingLevel,
    },
  }, nil
}

func (b *playerDataBackend) pathConfigWrite(ctx context.Context, req *logical.Request, data *framework.FieldData) (*logical.Response, error) {
  config, err := getConfig(ctx, req.Storage)
  if err != nil {
    return nil, err
  }

  createOperation := (req.Operation == logical.CreateOperation)

  if config == nil {
    if !createOperation {
      return nil, errors.New("config not found during update operation")
    }
    config = new(playerDataConfig)
  }

  if starting_level, ok := data.GetOk("starting_level"); ok {
    config.StartingLevel = starting_level.(int)
  } else if !ok && createOperation {
    return nil, fmt.Errorf("missing starting_level in configuration")
  }

  entry, err := logical.StorageEntryJSON(configStoragePath, config)
  if err != nil {
    return nil, err
  }

  if err := req.Storage.Put(ctx, entry); err != nil {
    return nil, err
  }

  return nil, nil
}

func (b *playerDataBackend) pathConfigDelete(ctx context.Context, req *logical.Request, data *framework.FieldData) (*logical.Response, error) {
  err := req.Storage.Delete(ctx, configStoragePath)

  if err != nil {
    return nil, err
  }
  return nil, nil
}
```

Now we have done all of that but if we run it, there is an error that gets thown when we try and write data. To fix this we need to add an exsistance check.

add the following to the bottom of the file:

```go
func (b *playerDataBackend) pathConfigExistenceCheck(ctx context.Context, req *logical.Request, data *framework.FieldData) (bool, error) {
  out, err := req.Storage.Get(ctx, req.Path)
  if err != nil {
    return false, fmt.Errorf("existence check failed: %w", err)
  }

  return out != nil, nil
}
```

Then in the `PathConfig` function add the following in to the block that is returned, just above `HelpSynopsis`:

```go
ExistenceCheck:  b.pathConfigExistenceCheck,
```

Now we can read and write the config, we need to edit the `path_player.go` file to call this config we are setting.

Lets edit the `GetLevel` function to take in a stating level int and use it to calculate the new level.

replace:

```go
func (r *playerDataPlayerEntity) GetLevel() int {
  return int(math.Floor(math.Sqrt(float64(r.Experience))))
}
```

with:

```go
func (r *playerDataPlayerEntity) GetLevel(startingLevel int) int {
  return startingLevel + int(math.Floor(math.Sqrt(float64(r.Experience))))
}
```

We now get an error in `toResponceData` lets edit that function to take in a config and pass though the start level to the `GetLevel` function

replace:

```go
func (r *playerDataPlayerEntity) toResponceData() map[string]interface{} {
  return map[string]interface{}{
    "class":      r.Class,
    "experience": r.Experience,
    "level":      r.GetLevel(),
  }
}
```

with:

```go
func (r *playerDataPlayerEntity) toResponceData(config *playerDataConfig) map[string]interface{} {
  return map[string]interface{}{
    "class":      r.Class,
    "experience": r.Experience,
    "level":      r.GetLevel(config.StartingLevel),
  }
}
```

Now following the error train when we call `toResponceData` in `pathPlayerRead` it needs us to pass though a config, so lets edit that function to get the config and pass it though.

replace:

```go
return &logical.Response{
  Data: entry.toResponceData(),
}, nil
```

with

```go
config, err := getConfig(ctx, req.Storage)

if err != nil {
  return nil, err
}
if config == nil {
  config = &playerDataConfig{}
}

return &logical.Response{
  Data: entry.toResponceData(config),
}, nil
```

Now when you remake it, if you set the config, then write and read from the panda secret you can see the level will be increased by what you have set as the starting_level.

If you run the following commands:

```bash
vault write DPG-Vault-Plugin/config starting_level=10
vault write DPG-Vault-Plugin/panda class=rdm
vault read DPG-Vault-Plugin/panda
```

The level should be at 10 over 0
