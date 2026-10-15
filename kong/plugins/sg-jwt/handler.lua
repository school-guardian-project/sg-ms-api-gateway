-- sg-jwt: gateway-level RS256 access-token validation.
--
-- The API gateway is the single authority that validates JWTs. It fetches the
-- JWKS published by ms-iam, verifies the RS256 signature and the standard time
-- claims, then forwards the authenticated identity to the internal services as
-- trusted X-User-* headers. Any inbound X-User-* header is stripped first so a
-- client can never spoof its own identity.
local cjson = require "cjson.safe"
local http = require "resty.http"
local pkey_lib = require "resty.openssl.pkey"

local JWKS_TTL = 300 -- seconds

local _M = {
  PRIORITY = 950, -- after cors (1110) / jwt (1450), before rate-limiting (910)
  VERSION = "1.1.0",
}

-- Per-worker cache of the JWKS document.
local jwks_cache = { keys = nil, fetched_at = 0 }

local IDENTITY_HEADERS = {
  "x-user-id",
  "x-user-role",
  "x-user-role-name",
  "x-user-email",
  "x-user-permissions",
  "x-campus-id",
  "x-school-id",
}

local function b64url_decode(input)
  if not input then
    return nil
  end
  input = input:gsub("-", "+"):gsub("_", "/")
  local pad = #input % 4
  if pad > 0 then
    input = input .. string.rep("=", 4 - pad)
  end
  return ngx.decode_base64(input)
end

local function fetch_jwks(url, force)
  local now = ngx.now()
  if not force and jwks_cache.keys and (now - jwks_cache.fetched_at) < JWKS_TTL then
    return jwks_cache.keys
  end

  local httpc = http.new()
  httpc:set_timeouts(500, 1500, 3000)
  local res, err = httpc:request_uri(url, { method = "GET" })
  if not res then
    return nil, "cannot reach JWKS endpoint: " .. tostring(err)
  end
  if res.status ~= 200 then
    return nil, "JWKS endpoint returned HTTP " .. res.status
  end

  local decoded = cjson.decode(res.body)
  if type(decoded) ~= "table" or type(decoded.keys) ~= "table" then
    return nil, "invalid JWKS payload"
  end

  jwks_cache.keys = decoded.keys
  jwks_cache.fetched_at = now
  return decoded.keys
end

local function find_jwk(keys, kid)
  for _, key in ipairs(keys) do
    if not kid or key.kid == kid then
      return key
    end
  end
  return nil
end

local function is_public_path(path, public_paths)
  for _, prefix in ipairs(public_paths) do
    if path == prefix or path:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

local function audience_matches(aud, expected)
  if type(aud) == "string" then
    return aud == expected
  end
  if type(aud) == "table" then
    for _, value in ipairs(aud) do
      if value == expected then
        return true
      end
    end
  end
  return false
end

function _M:access(conf)
  -- Never trust identity headers coming from the client.
  for _, header in ipairs(IDENTITY_HEADERS) do
    kong.service.request.clear_header(header)
  end

  local path = kong.request.get_path()
  if is_public_path(path, conf.public_paths) then
    return
  end

  local auth = kong.request.get_header("authorization")
  if not auth then
    return kong.response.exit(401, { message = "Missing Authorization header" })
  end

  local token = auth:match("^%s*[Bb]earer%s+(.+)$")
  if not token then
    return kong.response.exit(401, { message = "Invalid Authorization header" })
  end

  local header_b64, payload_b64, signature_b64 = token:match("^([^.]+)%.([^.]+)%.([^.]+)$")
  if not header_b64 then
    return kong.response.exit(401, { message = "Malformed token" })
  end

  local header = cjson.decode(b64url_decode(header_b64) or "")
  local payload = cjson.decode(b64url_decode(payload_b64) or "")
  local signature = b64url_decode(signature_b64)
  if type(header) ~= "table" or type(payload) ~= "table" or not signature then
    return kong.response.exit(401, { message = "Malformed token" })
  end

  if header.alg ~= "RS256" then
    return kong.response.exit(401, { message = "Unsupported token algorithm" })
  end

  local keys, err = fetch_jwks(conf.jwks_url, false)
  if not keys then
    kong.log.err("sg-jwt: ", err)
    return kong.response.exit(500, { message = "Authentication service unavailable" })
  end

  local jwk = find_jwk(keys, header.kid)
  if not jwk then
    -- Key rotation: refresh once before rejecting an unknown kid.
    keys, err = fetch_jwks(conf.jwks_url, true)
    if keys then
      jwk = find_jwk(keys, header.kid)
    end
  end
  if not jwk then
    return kong.response.exit(401, { message = "Unknown signing key" })
  end

  local public_key, key_err = pkey_lib.new(cjson.encode(jwk), { format = "JWK" })
  if not public_key then
    kong.log.err("sg-jwt: cannot load JWK: ", key_err)
    return kong.response.exit(500, { message = "Authentication service error" })
  end

  local verified = public_key:verify(signature, header_b64 .. "." .. payload_b64, "sha256")
  if not verified then
    return kong.response.exit(401, { message = "Invalid token signature" })
  end

  local now = ngx.time()
  if payload.exp and now >= payload.exp then
    return kong.response.exit(401, { message = "Token expired" })
  end
  if payload.nbf and now < payload.nbf then
    return kong.response.exit(401, { message = "Token not yet valid" })
  end
  if conf.issuer and payload.iss ~= conf.issuer then
    return kong.response.exit(401, { message = "Invalid token issuer" })
  end
  if conf.audience and not audience_matches(payload.aud, conf.audience) then
    return kong.response.exit(401, { message = "Invalid token audience" })
  end
  if not payload.sub then
    return kong.response.exit(401, { message = "Token missing subject" })
  end

  kong.service.request.set_header("X-User-Id", tostring(payload.sub))
  if payload.roleId ~= nil then
    kong.service.request.set_header("X-User-Role", tostring(payload.roleId))
  end
  if payload.role then
    kong.service.request.set_header("X-User-Role-Name", tostring(payload.role))
  end
  if payload.email then
    kong.service.request.set_header("X-User-Email", tostring(payload.email))
  end
  if payload.permissions ~= nil then
    local permissions
    if type(payload.permissions) == "table" then
      permissions = table.concat(payload.permissions, ",")
    else
      permissions = tostring(payload.permissions)
    end
    if permissions ~= "" then
      kong.service.request.set_header("X-User-Permissions", permissions)
    end
  end
  if payload.campusId then
    kong.service.request.set_header("X-Campus-Id", tostring(payload.campusId))
  end
  if payload.schoolId then
    kong.service.request.set_header("X-School-Id", tostring(payload.schoolId))
  end

  local correlation_id = kong.request.get_header("x-correlation-id")
  if not correlation_id or correlation_id == "" then
    correlation_id = payload.jti or ngx.var.request_id
  end
  kong.service.request.set_header("X-Correlation-Id", correlation_id)
end

return _M
