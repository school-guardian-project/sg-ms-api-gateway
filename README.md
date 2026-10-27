# sg-ms-api-gateway

## Routing and CORS

Kong runs in DB-less mode with `kong/kong.yml` mounted by Docker Compose.
The first service CORS plugin defines the `common_cors` YAML anchor; the other
services reuse it. Keep the definition before every alias. The policy preserves
the existing web/mobile origins and handles preflight requests in Kong
(`preflight_continue: false`), before `sg-jwt` validates authenticated requests.
Credentialed requests require an explicitly allowed origin, not `*`.

| Public prefix | Upstream | Strip prefix |
|---|---|---|
| `/api/v1/auth` | `ms-iam:8080` | No |
| `/notification` | `ms-notification:8080` | Yes |
| `/api/v1/password` | `ms-forgot-information:8080` | No |
| `/api/v1/email/change` | `ms-forgot-information:8080` | No |
| `/api/v1/phone/change` | `ms-forgot-information:8080` | No |

Email and phone changes remain JWT-protected; password recovery remains public.
Preflight requests do not need an access token. Do not remove authentication
from business endpoints to fix CORS. Other existing service routes are unchanged.

## Validate and deploy

Run from this repository with Docker available:

```powershell
docker compose run --rm --no-deps kong kong config parse /opt/kong/kong.yml
```

Only after validation succeeds:

```powershell
docker compose up -d --force-recreate kong
docker logs --since 5m --timestamps kong
```

Check the active routes and plugins locally on the deployment host:

```powershell
curl.exe -sS "http://127.0.0.1:8001/routes?size=100"
curl.exe -sS "http://127.0.0.1:8001/plugins?size=100"
```

Test browser-style preflights against the deployed HTTPS gateway:

```powershell
$Gateway = 'https://school-guardian.duckdns.org'
$Origin = 'https://guardian-escolar.vercel.app'
$Checks = @(
  @{ Path = '/notification/api/v1/notifications/alert-types'; Method = 'GET' },
  @{ Path = '/notification/api/v1/notifications/alerts'; Method = 'GET' },
  @{ Path = '/api/v1/email/change/request'; Method = 'POST' },
  @{ Path = '/api/v1/phone/change/request'; Method = 'POST' }
)
foreach ($Check in $Checks) {
  curl.exe -i -X OPTIONS "$Gateway$($Check.Path)" `
    -H "Origin: $Origin" `
    -H "Access-Control-Request-Method: $($Check.Method)" `
    -H "Access-Control-Request-Headers: authorization,content-type"
}
```

Expect a successful response (normally 204), the exact allowed origin,
`Access-Control-Allow-Credentials: true`, and the requested methods/headers.
Confirm authenticated GET/POST requests separately: passing preflight does not
prove that a controller exists in the deployed upstream image.

Run the repeatable, non-delivery smoke checks with Node.js 22 or later:

```powershell
node .\scripts\verify-gateway.mjs
node .\scripts\verify-gateway.mjs https://school-guardian.duckdns.org https://guardian-escolar.vercel.app
```

Kong 3.9 may return 200 rather than 204 for successful preflights; both are
accepted. The script also checks that anonymous business requests remain
protected, unlisted origins are rejected, public password recovery reaches
validation, refresh without a cookie returns 401, and IAM exposes RSA public
keys. It never requests a valid verification code or sends email/SMS.
Set `GATEWAY_TEST_ACCESS_TOKEN` privately to a real administrator access token
to additionally check profile, alert types, paginated alerts and authenticated
email/phone DTO validation. Without a token those checks are explicitly skipped.

Deploy the notification image containing `GET /api/v1/notifications/alert-types`
alongside the administrator dashboard. Keep Angular's `API_URL` and, when using
Kong for recovery, `API_FORGOT_INFORMATION_URL` pointed at the same HTTPS gateway
origin without path prefixes. Rebuild Vercel after changing build-time variables.
An anonymous `POST /api/v1/auth/refresh` without a session cookie returning 401
is expected; do not replace it with a successful response.
