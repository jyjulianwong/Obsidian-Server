# JavaScript

<span class="obsidian-pill">Browser · fetch</span>

## Getting a token silently in the browser

Use this in a frontend that should authenticate as one of your devices
without any login UI — the device's client certificate, once installed in
the OS/browser keychain, proves its identity during the TLS handshake for
the `/auth/token` request itself.

```js title="browser_get_token.js"
--8<-- "examples/browser_get_token.js"
```

Call `getAccessToken()` before hitting your own API, then attach the token
as a normal `Authorization: Bearer` header — exactly like the
`callProtectedApi()` helper above does.

!!! warning "The certificate picker is one-time, not per-request"
    The first time a browser profile visits a site that requests a client
    certificate, it shows a picker dialog — there's no JS API to suppress
    it. It's **per browser profile**, not per request: once selected, it's
    remembered until the certificate is removed or the profile is reset.

    On a device you manage yourself, some browsers support pre-selecting
    the certificate for a given origin via an enterprise policy (Chrome's
    `AutoSelectCertificateForUrls`), removing the picker entirely. See the
    [repository README](https://github.com/jyjulianwong/Obsidian-Server#installing-a-device-certificate)
    for the exact policy JSON — it's a convenience, not a requirement.

## Prerequisite: installing the device certificate

This snippet assumes the browser already has a client certificate for this
device installed. That's a one-time, per-device setup step — bundling the
key + cert into a `.p12` file and importing it into the OS/browser keychain
— covered in the
[README's "Installing a device certificate" section](https://github.com/jyjulianwong/Obsidian-Server#installing-a-device-certificate).
It isn't part of the frontend code itself, so it isn't duplicated here.
