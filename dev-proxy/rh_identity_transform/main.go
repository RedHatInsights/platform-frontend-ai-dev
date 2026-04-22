package rh_identity_transform

import (
	"encoding/base64"
	"encoding/json"
	"net/http"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/caddyserver/caddy/v2/caddyconfig/httpcaddyfile"
	"github.com/caddyserver/caddy/v2/modules/caddyhttp"
	"github.com/golang-jwt/jwt/v5"
)

func init() {
	caddy.RegisterModule(RhIdentityTransform{})
	httpcaddyfile.RegisterHandlerDirective("rh_identity_transform", parseCaddyfile)
}

type RhIdentityTransform struct{}

func (RhIdentityTransform) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "http.handlers.rh_identity_transform",
		New: func() caddy.Module { return new(RhIdentityTransform) },
	}
}

func (rht *RhIdentityTransform) Provision(ctx caddy.Context) error {
	return nil
}

func (rht *RhIdentityTransform) Validate() error {
	return nil
}

func (rht RhIdentityTransform) ServeHTTP(w http.ResponseWriter, r *http.Request, next caddyhttp.Handler) error {
	tokenStr, ok := ExtractToken(r)
	if !ok {
		next.ServeHTTP(w, r)
	}

	token, _ := jwt.Parse(tokenStr, nil)
	if token == nil {
		return next.ServeHTTP(w, r)
	}

	claims, _ := token.Claims.(jwt.MapClaims)
	identity := BuildIdentity(claims)
	identityJSON, err := json.Marshal(identity)
	if err != nil {
		return next.ServeHTTP(w, r)
	}

	identityB64 := base64.StdEncoding.EncodeToString(identityJSON)
	r.Header.Set("x-rh-identity", identityB64)

	return next.ServeHTTP(w, r)
}

func (rht *RhIdentityTransform) UnmarshalCaddyfile(d *caddyfile.Dispenser) error {
	d.Next()
	return nil
}

func parseCaddyfile(h httpcaddyfile.Helper) (caddyhttp.MiddlewareHandler, error) {
	var r RhIdentityTransform
	err := r.UnmarshalCaddyfile(h.Dispenser)
	return r, err
}

var (
	_ caddy.Provisioner           = (*RhIdentityTransform)(nil)
	_ caddy.Validator             = (*RhIdentityTransform)(nil)
	_ caddyhttp.MiddlewareHandler = (*RhIdentityTransform)(nil)
	_ caddyfile.Unmarshaler       = (*RhIdentityTransform)(nil)
)
