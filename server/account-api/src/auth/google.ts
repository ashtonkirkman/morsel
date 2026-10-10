/**
 * Google: OAuth 2.0 authorization-code flow with a *web* client (client id + secret live here).
 * The profile comes from the OpenID userinfo endpoint using the access token Google just
 * handed us over TLS, so there is no need to verify the id_token signature separately.
 */

import type { Env } from "../index";
import type { ProviderProfile } from "../db";
import type { OAuthProvider } from "./oauth";

const AUTHORIZE_URL = "https://accounts.google.com/o/oauth2/v2/auth";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo";

export const google: OAuthProvider = {
  name: "google",

  isConfigured(env) {
    return Boolean(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET);
  },

  authorizeUrl(env, redirectUri, state) {
    const params = new URLSearchParams({
      client_id: env.GOOGLE_CLIENT_ID ?? "",
      redirect_uri: redirectUri,
      response_type: "code",
      scope: "openid email profile",
      state,
      prompt: "select_account",
      access_type: "online",
    });
    return `${AUTHORIZE_URL}?${params.toString()}`;
  },

  async exchangeCode(env, code, redirectUri) {
    const tokenRes = await fetch(TOKEN_URL, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
      body: new URLSearchParams({
        code,
        client_id: env.GOOGLE_CLIENT_ID ?? "",
        client_secret: env.GOOGLE_CLIENT_SECRET ?? "",
        redirect_uri: redirectUri,
        grant_type: "authorization_code",
      }),
    });
    if (!tokenRes.ok) throw new Error(`google token ${tokenRes.status}: ${(await tokenRes.text()).slice(0, 200)}`);
    const token = (await tokenRes.json()) as { access_token?: string; id_token?: string };
    if (!token.access_token) throw new Error("google token response had no access_token");

    const infoRes = await fetch(USERINFO_URL, { headers: { authorization: `Bearer ${token.access_token}`, accept: "application/json" } });
    if (!infoRes.ok) throw new Error(`google userinfo ${infoRes.status}`);
    const info = (await infoRes.json()) as { sub?: string; email?: string; email_verified?: boolean; name?: string; picture?: string };
    if (!info.sub) throw new Error("google userinfo had no sub");
    const profile: ProviderProfile = {
      providerUserId: info.sub,
      email: info.email_verified === false ? undefined : info.email,
      emailVerified: info.email_verified === true,
      name: info.name,
      avatarUrl: info.picture,
      raw: info,
    };
    return profile;
  },
};
