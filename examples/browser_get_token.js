/**
 * Drop this into any other project's frontend to get an Obsidian access
 * token silently, then call your own API with it.
 *
 * Requires the device's client certificate to already be installed in the
 * OS/browser keychain (see README "Installing a device certificate").
 *
 * Caveat — browsers show a certificate-picker dialog the first time a site
 * requests a client cert (there is no JS API to suppress it). It is
 * per-browser-profile and one-time until the cert is deleted or the profile
 * is reset — not a per-request prompt. On managed devices you can pre-select
 * it automatically via the browser's AutoSelectCertificateForUrls enterprise
 * policy; see the README for the exact policy JSON.
 */

const OBSIDIAN_ISSUER = "https://auth.jyjwong.com"; // set to your Obsidian deployment

async function getAccessToken() {
  const response = await fetch(`${OBSIDIAN_ISSUER}/auth/token`, {
    method: "POST",
  });
  if (!response.ok) {
    throw new Error(`Obsidian token request failed: ${response.status}`);
  }
  const { access_token, expires_in } = await response.json();
  return { access_token, expires_in };
}

async function callProtectedApi() {
  const { access_token } = await getAccessToken();

  const response = await fetch("https://api.jyjwong.com/reports", {
    headers: { Authorization: `Bearer ${access_token}` },
  });
  return response.json();
}
