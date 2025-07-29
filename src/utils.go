package main

// safeTokenPreview creates a safe preview of the token for logging purposes
func safeTokenPreview(token string) string {
	if len(token) == 0 {
		return "<empty>"
	}
	if len(token) <= 8 {
		return "<short>"
	}
	return token[:8] + "..."
}
