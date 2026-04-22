package rh_identity_transform

import (
	"net/http"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

type Entitlement struct {
	IsEntitled bool
	IsTrial    bool
}

var defaultEntitlements = map[string]Entitlement{
	"insights":         {IsEntitled: true},
	"smart_management": {IsEntitled: true},
	"openshift":        {IsEntitled: true},
	"hybrid":           {IsEntitled: true},
	"migrations":       {IsEntitled: true},
	"ansible":          {IsEntitled: true},
	"cost_management":  {IsEntitled: true},
}

type User struct {
	Username   string `json:"username"`
	Email      string `json:"email"`
	FirstName  string `json:"first_name"`
	LastName   string `json:"last_name"`
	IsActive   bool   `json:"is_active"`
	IsOrgAdmin bool   `json:"is_org_admin"`
	IsInternal bool   `json:"is_internal"`
	Locale     string `json:"locale"`
	UserId     string `json:"user_id"`
}

type Internal struct {
	OrgId    string `json:"org_id"`
	AuthTime int64  `json:"auth_time"`
}

type Identity struct {
	Typ           string   `json:"type"`
	AuthType      string   `json:"auth_type"`
	AccountNumber string   `json:"account_number"`
	OrgId         string   `json:"org_id"`
	User          User     `json:"user"`
	Internal      Internal `json:"internal"`
}

type EntitledIdentity struct {
	Entitlements map[string]Entitlement `json:"entitlements"`
	Identity     Identity               `json:"identity"`
}

func ExtractToken(r *http.Request) (string, bool) {
	var tokenStr string
	authHeader := r.Header["Authorization"]
	cookies := r.Cookies()
	i := slices.IndexFunc(cookies, func(c *http.Cookie) bool {
		return c.Name == "cs_jwt"
	})

	if len(cookies) > 0 && i != -1 {
		tokenStr = cookies[i].Value
	}
	if len(authHeader) > 0 && strings.TrimSpace(tokenStr) == "" {
		re := regexp.MustCompile("^Bearer (.*)$")
		if f := re.FindStringSubmatch(authHeader[0]); len(f) > 1 {
			tokenStr = f[1]
		}
	}

	if strings.TrimSpace(tokenStr) == "" {
		return "", false
	}

	return tokenStr, true
}

func BuildIdentity(claims map[string]interface{}) EntitledIdentity {
	getClaimString := func(key string) string {
		if val, ok := claims[key]; ok {
			if strVal, typeOk := val.(string); typeOk {
				return strVal
			}
			// Optionally handle conversion from other types if expected (e.g., float64 to string for numbers)
			if numVal, typeOk := val.(float64); typeOk {
				return strconv.FormatFloat(numVal, 'f', -1, 64)
			}
		}
		return ""
	}

	getClaimBool := func(key string) bool {
		if val, ok := claims[key]; ok {
			if boolVal, typeOk := val.(bool); typeOk {
				return boolVal
			}
		}
		return false
	}

	getClaimInt64 := func(key string) int64 {
		if val, ok := claims[key]; ok {
			// JWT numbers are typically float64
			if numVal, typeOk := val.(float64); typeOk {
				return int64(numVal)
			}
		}
		return 0
	}

	identity := EntitledIdentity{
		Entitlements: defaultEntitlements,
		Identity: Identity{
			Typ:           "User",
			AuthType:      "basic-auth",
			AccountNumber: getClaimString("account_number"),
			OrgId:         getClaimString("org_id"),
			User: User{
				Username:   getClaimString("username"),
				Email:      getClaimString("email"),
				FirstName:  getClaimString("first_name"),
				LastName:   getClaimString("last_name"),
				IsActive:   true,
				IsOrgAdmin: getClaimBool("is_org_admin"),
				IsInternal: getClaimBool("is_internal"),
				Locale:     "en-US",
				UserId:     getClaimString("user_id"),
			},
			Internal: Internal{
				OrgId:    getClaimString("org_id"),
				AuthTime: getClaimInt64("auth_time"),
			},
		},
	}

	return identity
}
