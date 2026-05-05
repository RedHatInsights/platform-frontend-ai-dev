package main

import "testing"

func TestNeedsStdinGPGCombinedFlags(t *testing.T) {
	cases := []struct {
		name string
		tool string
		args []string
		want bool
	}{
		{"git signing", "gpg", []string{"--status-fd=2", "-bsau", "ABCD1234"}, true},
		{"short -s", "gpg", []string{"-s", "file.txt"}, true},
		{"short -b", "gpg", []string{"-b", "file.txt"}, true},
		{"long --sign", "gpg", []string{"--sign", "file.txt"}, true},
		{"long --detach-sign", "gpg", []string{"--detach-sign", "file.txt"}, true},
		{"long --import", "gpg", []string{"--import"}, true},
		{"long --verify", "gpg", []string{"--verify", "file.sig"}, true},
		{"combined -se", "gpg", []string{"-se", "-r", "user@example.com"}, true},
		{"list keys no stdin", "gpg", []string{"--list-keys"}, false},
		{"list secret keys no stdin", "gpg", []string{"--list-secret-keys", "--keyid-format", "long"}, false},
		{"armor only no stdin", "gpg", []string{"-a", "--export", "ABCD1234"}, false},
		{"gh credential", "gh", []string{"auth", "git-credential", "get"}, true},
		{"glab credential", "glab", []string{"credential-helper", "get"}, true},
		{"gh pr view no stdin", "gh", []string{"pr", "view", "42"}, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := needsStdin(tc.tool, tc.args)
			if got != tc.want {
				t.Errorf("needsStdin(%q, %v) = %v, want %v", tc.tool, tc.args, got, tc.want)
			}
		})
	}
}
