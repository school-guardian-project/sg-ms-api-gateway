-- Schema for the sg-jwt plugin.
-- Validates RS256 access tokens against the IAM JWKS and injects the
-- authenticated identity into X-User-* headers for downstream services.
return {
  name = "sg-jwt",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { jwks_url = { type = "string", required = true } },
          { issuer = { type = "string" } },
          { audience = { type = "string" } },
          {
            public_paths = {
              type = "array",
              elements = { type = "string" },
              default = {},
            },
          },
        },
      },
    },
  },
}
