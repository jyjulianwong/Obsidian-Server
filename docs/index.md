---
hide:
  - navigation
  - toc
---

<div class="obsidian-hero" markdown>

![Obsidian](assets/logo.png){ .obsidian-hero__logo }

# One certificate. Every project trusts you.

Obsidian is a personal, central auth service that silently authenticates
your own pre-authorized devices — laptops, phones, servers — using **mutual
TLS**, and issues short-lived **JWTs** your other projects' APIs can verify
without ever calling Obsidian back.

<div class="obsidian-hero__actions" markdown>
[What is Obsidian?](what-is-obsidian.md){ .md-button .md-button--primary }
[API examples](examples/index.md){ .md-button }
</div>

</div>

<div class="obsidian-grid" markdown>

<div class="obsidian-card" markdown>
<span class="obsidian-card__icon">:material-key-variant:</span>
### No passwords, ever

Devices prove who they are with a client certificate presented during the
TLS handshake itself — there's nothing to type, phish, or leak.
</div>

<div class="obsidian-card" markdown>
<span class="obsidian-card__icon">:material-timer-sand:</span>
### Short-lived by default

Every issued JWT expires in an hour. A compromised token is a non-event by
the time anyone notices.
</div>

<div class="obsidian-card" markdown>
<span class="obsidian-card__icon">:material-lan-disconnect:</span>
### No callbacks per request

Your other services verify tokens locally against Obsidian's JWKS — one
key fetch, cached, and no network round-trip to Obsidian on the hot path.
</div>

<div class="obsidian-card" markdown>
<span class="obsidian-card__icon">:material-power-plug-off:</span>
### One switch to revoke

Every device is a row in a table. Flip it to revoked and the next token
request fails instantly — no cert rotation required.
</div>

</div>

## Where to go next

- **[What is Obsidian?](what-is-obsidian.md)** — the problem it solves and
  the vocabulary (mTLS, device certs, JWTs, JWKS) used throughout these docs.
- **[How it works](how-it-works.md)** — the request path from a device's
  handshake to a verified API call, with a diagram.
- **[API examples](examples/index.md)** — copy-paste snippets for
  integrating Obsidian into your own Python and JavaScript projects.

!!! tip "Looking for deployment instructions?"
    These docs cover the API surface for the projects that *consume*
    Obsidian tokens. For standing up Obsidian itself (Terraform, AWS,
    device provisioning), see the
    [repository README](https://github.com/jyjulianwong/Obsidian-Server#readme).
