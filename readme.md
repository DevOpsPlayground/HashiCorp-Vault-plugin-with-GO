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

This stops all the errors, but there is still a few more steps to let us use this within vault. Replace the `bachend()` function you just made with the following:

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

Now we have a simple backend set up, time to set up a path.

## Path

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
type playerDataPlayerEntity struct {
  Class      string `json:"class"`
  Experience int    `json:"experience"`
}

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
    Callback: b.pathPlayerStatsRead,
  },
  logical.CreateOperation: &framework.PathOperation{
    Callback: b.pathPlayerStatsWrite,
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
