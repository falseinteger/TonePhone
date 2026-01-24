# Security Policy

## Reporting a Vulnerability

**Do not report security vulnerabilities through public GitHub issues.**

If you discover a security vulnerability in TonePhone, please report it privately.

### Contact

Use GitHub's private security advisory feature:

1. Go to https://github.com/falseinteger/TonePhone/security/advisories
2. Click "New draft security advisory"
3. Fill in the details

This keeps the report private until a fix is ready.

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fixes (optional)

### Response

You can expect:
- Acknowledgment within 48 hours
- Assessment of severity and impact
- Timeline for fix if applicable
- Credit in release notes (if desired)

## Scope

This policy covers:
- TonePhone application code
- Bridge layer code
- Build scripts and configuration

This policy does not cover:
- baresip, libre, or librem (report to their respective projects)
- Third-party dependencies
- SIP servers or infrastructure you operate

## Security Considerations

TonePhone handles sensitive data:
- SIP credentials
- Call audio
- Call metadata

### How TonePhone Protects Data

- Credentials stored in system Keychain
- No analytics or telemetry
- No cloud sync
- All data stored locally
- TLS for SIP signaling (when server supports)
- SRTP/DTLS-SRTP for media encryption

### User Responsibilities

- Use strong SIP passwords
- Use TLS-enabled SIP servers
- Keep macOS/iOS updated
- Review app permissions

## Known Limitations

- No certificate pinning in v1
- No custom CA support
- Call history stored unencrypted locally
- Logs may contain call metadata (not credentials)

---

Thank you for helping keep TonePhone secure.
