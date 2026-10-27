import assert from 'node:assert/strict';

const gateway = new URL(process.argv[2] ?? 'http://127.0.0.1:8000');
const origin = process.argv[3] ?? 'https://guardian-escolar.vercel.app';
const token = process.env.GATEWAY_TEST_ACCESS_TOKEN;

async function request(path, options = {}) {
  const response = await fetch(new URL(path, gateway), {
    redirect: 'manual',
    signal: AbortSignal.timeout(30000),
    ...options,
  });
  return response;
}

function verifyCors(response) {
  assert.equal(response.headers.get('access-control-allow-origin'), origin);
  assert.equal(response.headers.get('access-control-allow-credentials'), 'true');
}

const preflights = [
  ['/notification/api/v1/notifications/alert-types', 'GET'],
  ['/notification/api/v1/notifications/alerts', 'GET'],
  ['/api/v1/email/change/request', 'POST'],
  ['/api/v1/phone/change/request', 'POST'],
  ['/api/v1/password/forgot', 'POST'],
  ['/api/v1/auth/login', 'POST'],
  ['/api/v1/auth/refresh', 'POST'],
];

for (const [path, method] of preflights) {
  const response = await request(path, {
    method: 'OPTIONS',
    headers: {
      Origin: origin,
      'Access-Control-Request-Method': method,
      'Access-Control-Request-Headers': 'authorization,content-type',
    },
  });
  assert.ok(response.status === 200 || response.status === 204, `${path}: ${response.status}`);
  verifyCors(response);
  const methods = response.headers.get('access-control-allow-methods')?.split(',').map(s => s.trim());
  const headers = response.headers.get('access-control-allow-headers')?.toLowerCase().split(',').map(s => s.trim());
  assert.ok(methods?.includes(method), `${path}: requested method missing`);
  assert.ok(headers?.includes('authorization') && headers.includes('content-type'), `${path}: requested headers missing`);
  console.log(`PASS preflight ${method} ${path}: ${response.status}`);
}

const rejectedOrigin = await request(preflights[0][0], {
  method: 'OPTIONS',
  headers: {
    Origin: 'https://untrusted.invalid',
    'Access-Control-Request-Method': 'GET',
    'Access-Control-Request-Headers': 'authorization',
  },
});
assert.notEqual(rejectedOrigin.headers.get('access-control-allow-origin'), '*');
assert.notEqual(rejectedOrigin.headers.get('access-control-allow-origin'), 'https://untrusted.invalid');
console.log('PASS unlisted origin is not allowed');

for (const [path, method] of preflights.slice(0, 4)) {
  const response = await request(path, { method, headers: { Origin: origin } });
  assert.equal(response.status, 401, `${path}: anonymous business request must remain protected`);
  verifyCors(response);
  console.log(`PASS anonymous ${method} ${path}: 401`);
}

const refresh = await request('/api/v1/auth/refresh', {
  method: 'POST',
  headers: { Origin: origin },
});
assert.equal(refresh.status, 401, 'Refresh without a session cookie must return 401');
verifyCors(refresh);
console.log('PASS refresh without session: 401');

const recovery = await request('/api/v1/password/forgot', {
  method: 'POST',
  headers: { Origin: origin, 'Content-Type': 'application/json' },
  body: '{}',
});
assert.equal(recovery.status, 400, 'Public recovery must reach DTO validation without authentication');
verifyCors(recovery);
console.log('PASS public password recovery reaches DTO validation: 400 (no email sent)');

const jwks = await request('/.well-known/jwks.json');
assert.equal(jwks.status, 200, 'IAM public signing keys must be reachable');
const keys = await jwks.json();
assert.ok(Array.isArray(keys.keys) && keys.keys.some(key => key.kty === 'RSA' && key.n && key.e));
console.log('PASS IAM JWKS: 200 with RSA public key');

if (token) {
  const headers = { Origin: origin, Authorization: `Bearer ${token}` };
  const profile = await request('/api/v1/auth/profile', { headers });
  assert.equal(profile.status, 200, 'Authenticated profile');
  verifyCors(profile);
  const types = await request('/notification/api/v1/notifications/alert-types', { headers });
  assert.equal(types.status, 200, 'Authenticated alert catalog');
  verifyCors(types);
  const catalog = await types.json();
  assert.ok(Array.isArray(catalog) && catalog.every(type => Number.isInteger(type.id) && typeof type.name === 'string'));
  const alerts = await request('/notification/api/v1/notifications/alerts?page=0&size=10', { headers });
  assert.equal(alerts.status, 200, 'Authenticated alert listing');
  verifyCors(alerts);
  const listing = await alerts.json();
  assert.ok(Array.isArray(listing.content) && Number.isInteger(listing.totalElements));
  assert.ok(listing.content.length <= 10);
  for (const [path] of preflights.slice(2, 4)) {
    const response = await request(path, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: '{}',
    });
    assert.equal(response.status, 400, `${path}: authenticated request must reach DTO validation`);
    verifyCors(response);
  }
  console.log('PASS authenticated profile, catalog, paginated alerts and change DTO validation');
} else {
  console.log('SKIP authenticated checks: set GATEWAY_TEST_ACCESS_TOKEN to a real admin access token');
}
