const fs = require('fs');
const https = require('https');
const crypto = require('crypto');

const KEY_ID = process.env.ASC_KEY_ID || 'WDXGY9WX55';
const ISSUER_ID = process.env.ASC_ISSUER_ID || '2be0734f-943a-4d61-9dc9-5d9045c46fec';
const API_KEY_PATH = process.env.ASC_KEY_PATH || `${process.env.USERPROFILE}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`;
const BUNDLE_IDENTIFIER = 'com.snarfnet.airsynth';
const NAME = 'AIR SYNTH';
const SKU = 'AIR-SYNTH-001';

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

async function main() {
  const bundleQuery = encodeURIComponent(BUNDLE_IDENTIFIER);
  const bundle = (await api('GET', `/v1/bundleIds?filter[identifier]=${bundleQuery}&limit=1`)).data[0];
  if (!bundle) throw new Error('Bundle ID not found.');

  const existing = await api('GET', `/v1/apps?filter[bundleId]=${bundle.id}&limit=1`);
  if (existing.data?.length) {
    console.log(`App exists: ${existing.data[0].id}`);
    return;
  }

  const created = await api('POST', '/v1/apps', {
    data: {
      type: 'apps',
      attributes: {
        name: NAME,
        bundleId: BUNDLE_IDENTIFIER,
        sku: SKU,
        primaryLocale: 'ja',
        platform: 'IOS',
      },
      relationships: {
        bundleId: {
          data: { type: 'bundleIds', id: bundle.id },
        },
      },
    },
  });
  console.log(`Created app: ${created.data.id}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
