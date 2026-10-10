/**
 * Facebook Login: authorization-code flow against the Graph API. Every Graph call carries
 * `appsecret_proof` (HMAC-SHA256 of the access token with the app secret) as Facebook
 * recommends for server-side calls.
 */

import type { Env } from "../index";
import type { ProviderProfile } from "../db";
import { hmacSha256Hex } from "../jwt";
import type { OAuthProvider } from "./oauth";

const GRAPH_VERSION = "v19.0";
const AUTHORIZE_URL = `https://www.facebook.com/${GRAPH_VERSION}/dialog/oauth`;
const TOKEN_URL = `https://graph.facebook.com/${GRAPH_VERSION}/oauth/access_token`;
const ME_URL = `https://graph.facebook.com/${GRAPH_VERSION}/me`;

export const facebook: OAuthProvider = {
  name: "facebook",

  isConfigured(env) {
    return Boolean(env.FACEBOOK_APP_ID && env.FACEBOOK_APP_SECRET);
  },

  authorizeUrl(env, redirectUri, state) {
    const params = new URLSearchParams({
      client_id: env.FACEBOOK_APP_ID ?? "",
      redirect_uri: redirectUri,
      response_type: "code",
      scope: "public_profile,email",
      state,
    });
    return `${AUTHORIZE_URL}?${params.toString()}`;
  },

  async exchangeCode(env, code, redirectUri) {
    const appSecret = env.FACEBOOK_APP_SECRET ?? "";
    const tokenParams = new URLSearchParams({
      client_id: env.FACEBOOK_APP_ID ?? "",
      client_secret: appSecret,
      redirect_uri: redirectUri,
      code,
    });
    const tokenRes = await fetch(`${TOKEN_URL}?${tokenParams.toString()}`, { headers: { accept: "application/json" } });
    if (!tokenRes.ok) throw new Error(`facebook token ${tokenRes.status}: ${(await tokenRes.text()).slice(0, 200)}`);
    const token = (await tokenRes.json()) as { access_token?: string };
    if (!token.access_token) throw new Error("facebook token response had no access_token");

    const proof = await hmacSha256Hex(appSecret, token.access_token);
    const meParams = new URLSearchParams({
      fields: "id,name,email,picture.type(large)",
      access_token: token.access_token,
      appsecret_proof: proof,
    });
    const meRes = await fetch(`${ME_URL}?${meParams.toString()}`, { headers: { accept: "application/json" } });
    if (!meRes.ok) throw new Error(`facebook /me ${meRes.status}`);
    const me = (await meRes.json()) as { id?: string; name?: string; email?: string; picture?: { data?: { url?: string } } };
    if (!me.id) throw new Error("facebook /me had no id");
    const profile: ProviderProfile = {
      providerUserId: me.id,
      email: me.email,
      emailVerified: Boolean(me.email), // Facebook only returns verified emails
      name: me.name,
      avatarUrl: me.picture?.data?.url,
      raw: { id: me.id, name: me.name, email: me.email },
    };
    return profile;
  },
};
