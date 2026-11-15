# DogVape
DogVape SCRIPT

## Execution

```lua
script_key = "DOGVAPE-XXXX-XXXX"; loadstring(game:HttpGet('https://raw.githubusercontent.com/0lyzll/DogVape/main/init.lua'), 'init.lua')({})
```

`script_key` is optional. Leave it out (or leave the placeholder) and a key
prompt appears instead.

## Keys

Keys live in [`keys.json`](keys.json) and are checked at load time, then cached
in `DogVape/profiles/key.txt` so the prompt only shows once per install.

```json
{
  "keys": {
    "DOGVAPE-XXXX-XXXX": { "role": "user", "name": "someone" }
  }
}
```

- Valid keys are matched ignoring case, spaces, dashes and underscores.
- The value can be a plain role string (`"user"`) or an object with `role` / `name`.
- `role` is exposed to the GUI as `_DogVaperole`, `name` as `_DogVapename`.
- Add or remove keys by editing `keys.json` and pushing; no script change needed.

The key system is client-side only. Anyone who can read `init.lua` can bypass it,
so it stops casual reuse of the loader string, not a determined user.

Made by DogVape.
