const fs = require('fs');
const path = require('path');
const https = require('https');
const crypto = require('crypto');

const KEY_ID = process.env.ASC_KEY_ID || 'WDXGY9WX55';
const ISSUER_ID = process.env.ASC_ISSUER_ID || '2be0734f-943a-4d61-9dc9-5d9045c46fec';
const API_KEY_PATH = process.env.ASC_KEY_PATH || `${process.env.USERPROFILE}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`;
const BUNDLE_IDENTIFIER = process.env.BUNDLE_IDENTIFIER || 'com.snarfnet.airsynth';
const BUNDLE_NAME = process.env.BUNDLE_NAME || 'AIR SYNTH';
const CERTIFICATE_ID = process.env.ASC_CERTIFICATE_ID || 'XXUMBS62JN';
const OUTPUT_DIR = process.env.SIGNING_OUTPUT_DIR || `${process.env.USERPROFILE}/AIR_SYNTH_SIGNING`;

function makeJWT() {
  const key = fs.readFileSync(API_KEY_PATH, 'utf8');
  const now = Math.floor(Date.now() / 1000) - 60;
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ iss: ISSUER_ID, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' })).toString('base64url');
  const sign = crypto.createSign('SHA256');
  sign.update(`${header}.${payload}`);
  sign.end();
  return `${header}.${payload}.${sign.sign({ key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
}

function api(method, requestPath, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const req = https.request({
      hostname: 'api.appstoreconnect.apple.com',
      path: requestPath,
      method,
      headers: {
        Authorization: `Bearer ${makeJWT()}`,
        'Content-Type': 'application/json',
        ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {}),
      },
    }, (res) => {
      let raw = '';
      res.on('data', (chunk) => { raw += chunk; });
      res.on('end', () => {
        let parsed = raw;
        try { parsed = raw ? JSON.parse(raw) : {}; } catch {}
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(parsed);
        } else {
          reject(new Error(`HTTP ${res.statusCode} ${method} ${requestPath}\n${JSON.stringify(parsed, null, 2)}`));
        }
      });
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function getOrCreateBundleId() {
  const query = encodeURIComponent(BUNDLE_IDENTIFIER);
  const existing = await api('GET', `/v1/bundleIds?filter[identifier]=${query}&limit=1`);
  if (existing.data?.length) return existing.data[0];

  return (await api('POST', '/v1/bundleIds', {
    data: {
      type: 'bundleIds',
      attributes: {
        name: BUNDLE_NAME,
        identifier: BUNDLE_IDENTIFIER,
        platform: 'IOS',
      },
    },
  })).data;
}

async function createProfile(bundleId) {
  const stamp = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  return (await api('POST', '/v1/profiles', {
    data: {
      type: 'profiles',
      attributes: {
        name: `${BUNDLE_NAME} App Store ${stamp}`,
        profileType: 'IOS_APP_STORE',
      },
      relationships: {
        bundleId: { data: { type: 'bundleIds', id: bundleId } },
        certificates: {
          data: [{ type: 'certificates', id: CERTIFICATE_ID }],
        },
      },
    },
  })).data;
}

async function main() {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  const bundle = await getOrCreateBundleId();
  console.log(`Bundle ID: ${bundle.attributes.identifier} (${bundle.id})`);
  const profile = await createProfile(bundle.id);
  const profilePath = path.join(OUTPUT_DIR, 'AppStore.mobileprovision');
  fs.writeFileSync(profilePath, Buffer.from(profile.attributes.profileContent, 'base64'));
  fs.writeFileSync(path.join(OUTPUT_DIR, 'profile_name.txt'), profile.attributes.name);
  console.log(`Profile: ${profile.attributes.name} (${profile.id})`);
  console.log(`Saved: ${profilePath}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
