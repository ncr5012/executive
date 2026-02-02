# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Executive, please report it responsibly.

**Email:** nick@vibeotter.com

Please include:
- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge receipt within 72 hours and aim to provide a resolution timeline promptly.

## Security Considerations

### Autopilot Mode

Autopilot mode auto-approves **all** tool calls and permission requests without human review. This significantly increases susceptibility to prompt injection attacks. Do not use autopilot mode with untrusted code or repositories. We really appreciate novel ideas to combat prompt injection risk for the community — if you have thoughts on mitigations or detection strategies, please reach out or open an issue.

### Cookie Secret (Cloud)

The cloud server uses a signed cookie for session management. The default fallback secret (`'change-me'`) is insecure. Always run `node setup.js` before starting the cloud server to generate a cryptographically secure cookie secret.

### API Keys

API keys are stored in `~/.executive-key` on each machine. Treat these keys as secrets — they grant full access to register sessions and push task updates to the dashboard.

### Network Exposure

- **Local mode:** Binds to `0.0.0.0:7777` by default. On trusted networks this is fine; on untrusted networks, use firewall rules to restrict access.
- **Cloud mode:** Intended to be placed behind a reverse proxy (nginx) with HTTPS. Do not expose the Express server directly to the internet without TLS.
