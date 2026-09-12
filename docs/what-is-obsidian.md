# What is Obsidian?

Obsidian is a small, self-hosted auth service for people who run several of
their own projects — each with its own UI and API — and don't want to bolt
a separate login system onto every one of them, or share one password
between them either.

It is **not** a general-purpose identity provider for end users. It has no
concept of "sign up," no password reset flow, no user database. It answers
one question, for devices *you* own:

> "Is this laptop/phone/server one of mine, and if so, here's a token that
> proves it for the next hour."

Every other project you run just verifies that token and gets on with its
own job.

## The problem it solves

If you run three side projects, each with its own API, you're usually
choosing between:

- **A login page per project** — you now maintain three auth flows, three
  password hashes (or three OAuth integrations), three "forgot password"
  emails.
- **One shared static secret** — an API key baked into every client. It
  works, until it leaks, and then every project shares the blast radius.
- **A full identity provider** (Auth0, Cognito, Keycloak...) — correct for
  a product with real end users, a lot of setup and ongoing cost for
  something that only needs to authenticate *you*, on *your own hardware*.

Obsidian is the fourth option: one central service that knows which of your
devices are trusted, issuing tokens that are cheap to verify and short-lived
enough that leaking one barely matters.

## The building blocks

| Term | What it means here |
|---|---|
| **mTLS** (mutual TLS) | Both sides of the TLS handshake present a certificate. Normally only the server does (that's how HTTPS proves *the server's* identity to you); mTLS also has the *client* prove its identity to the server — here, that's how a device proves it's really your laptop. |
| **Device certificate** | A key pair + certificate issued to one specific device, signed by Obsidian's own private CA. Installing it in the OS/browser keychain is a one-time setup step per device. |
| **JWT** (JSON Web Token) | A short, signed, string like `eyJhbGc...`. Obsidian signs one after a successful mTLS handshake, containing the device's identity and an expiry (`exp`) — typically one hour out. |
| **JWKS** (JSON Web Key Set) | The *public* half of the key Obsidian signs JWTs with, published at a well-known URL. Any of your other services can fetch it once, cache it, and verify tokens locally — no call back to Obsidian per request. |
| **Issuer (`iss`)** | The identity Obsidian stamps into every token it issues. Your resource servers check this claim so they don't accept a token signed by *something else* that happens to reuse the same verification code. |

## Who should — and shouldn't — use this

**Good fit** if you:

- Run several personal or small-team projects that all need to trust
  "yes, this really is me / one of my devices."
- Are comfortable owning a private CA and provisioning device certificates
  yourself (see the [README](https://github.com/jyjulianwong/Obsidian-Server#readme)
  for the scripts that do this).
- Want token verification to be a local, offline operation for the services
  consuming it.

**Not a fit** if you need to authenticate arbitrary third-party users —
that's what a real identity provider is for. Obsidian's trust model starts
and ends at "devices I have personally provisioned a certificate for."

## Next

Continue to **[How it works](how-it-works.md)** for the full request path,
or jump straight to the **[API examples](examples/index.md)** if you just
want to integrate a project against an existing Obsidian deployment.
