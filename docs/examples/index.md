# API examples

Every project that integrates with Obsidian falls into one of two roles.
Pick the one that matches what you're building — most projects only need
one of these, not both.

<div class="obsidian-grid" markdown>

<div class="obsidian-card" markdown>
<span class="obsidian-card__icon">:material-shield-check-outline:</span>
### Verify tokens

A backend API that should trust requests carrying an Obsidian-issued JWT.

<span class="obsidian-pill">Python · FastAPI</span>

[Read the guide &rarr;](python.md#verifying-a-token-fastapi)
</div>

<div class="obsidian-card" markdown>
<span class="obsidian-card__icon">:material-key-arrow-right:</span>
### Get a token — server / CLI

A backend job or command-line tool that needs to call another one of your
APIs on its own behalf.

<span class="obsidian-pill">Python</span>

[Read the guide &rarr;](python.md#getting-a-token-server-to-server-or-cli)
</div>

<div class="obsidian-card" markdown>
<span class="obsidian-card__icon">:material-web:</span>
### Get a token — browser

A frontend that needs a token silently, using a device certificate already
installed in the browser's keychain.

<span class="obsidian-pill">JavaScript</span>

[Read the guide &rarr;](javascript.md)
</div>

</div>

## Before you start

Every snippet below assumes an Obsidian deployment already exists and you
know two values from it:

| Value | Where it's used | Example |
|---|---|---|
| **Issuer URL** | The `iss` claim to check tokens against, and where devices request tokens from | `https://auth.jyjwong.com` |
| **JWKS URL** | Where to fetch the public key(s) used to verify tokens | `https://jwks.jyjwong.com/.well-known/jwks.json` |

These are deliberately **different domains** — the issuer requires a client
certificate for every route, the JWKS endpoint doesn't. See
[How it works](../how-it-works.md#2-verifying-a-token) for why.

The full source for every snippet on these pages lives in the
[`examples/`](https://github.com/jyjulianwong/Obsidian-Server/tree/main/examples)
directory of the repository, ready to copy into your own project.
