---
name: check-domain-availability
description: Check whether a domain name is registered or available to buy, using RDAP plus a DNS nameserver lookup. Use when the user asks if a domain is taken, free, available, or registered, wants to find an open domain name, or asks to look up who owns/when a domain expires.
---

# Check Domain Availability

Decide whether a domain name is **registered** (taken) or **available** by combining two independent signals. Neither is sufficient alone — use both.

## How it works

1. **RDAP** (`https://rdap.org/domain/<name>`, the modern WHOIS replacement). rdap.org redirects to the authoritative registry, so always follow redirects (`curl -sL`).
   - HTTP `200` + JSON body → a registration record exists → **registered**.
   - HTTP `404` → no record at the registry → *looks* available.
2. **DNS NS lookup** (`dig +short NS <name>`).
   - NS records present → the domain is delegated → **registered**, full stop.
3. **Legacy WHOIS** (`whois <name>`) — *fallback only*. Used when RDAP gives no usable answer (timeout, redirect loop, or a TLD with no RDAP service) **and** there are no NS records. Some ccTLDs (e.g. `.ca`, `.br`, `.it`) aren't on rdap.org's bootstrap at all; WHOIS is the official protocol RDAP replaced and still answers for them.

**Why all three:** rdap.org does not cover every TLD. Registries like `.io` and `.de` return `404` from RDAP even for obviously-registered names (`google.io`, `google.de`, even `nic.io`). RDAP alone would falsely call those *available*. The NS check catches the registered ones; WHOIS covers what's left. A name is only reported **AVAILABLE** when RDAP is `404` (or WHOIS says "no match") **and** there are no NS records.

**WHOIS caveat:** WHOIS has no standardized response format. Registries phrase "not registered" differently — `No match`, `NOT FOUND`, `No Data Found`, `Status: free`, etc. — which is exactly why RDAP was created. The script matches the common phrasings best-effort; treat a WHOIS-derived verdict as weaker than an RDAP or NS one, and verify at a registrar.

## Usage

Run the script with one or more domains:

```
scripts/check_domain.sh example.com mycoolstartup.io somename.dev
```

It prints, per domain, the RDAP status, the NS result, and a verdict: **REGISTERED**, **AVAILABLE (likely)**, or **INCONCLUSIVE**. For registered domains it also shows registrar, registration/expiry dates, status, and nameservers (parsed from RDAP with `jq`).

For a quick one-off you can also just run the raw command and read the JSON:

```
curl -sL https://rdap.org/domain/example.com | jq .
```

## Verdict logic

| RDAP | NS records | Verdict |
|------|-----------|---------|
| 200  | any       | REGISTERED (registry record exists) |
| 404  | present   | REGISTERED (DNS delegation proves it; TLD just isn't in RDAP) |
| 404  | none      | AVAILABLE (likely) |
| no answer (000 / 302 loop / 403 / 429 / 5xx) | present | REGISTERED (via DNS delegation) |
| no answer | none | **WHOIS fallback** → REGISTERED, AVAILABLE, or INCONCLUSIVE |

When RDAP gives no answer and there are no NS records, the script automatically runs `whois` as a tiebreaker. If `whois` isn't installed, the verdict is INCONCLUSIVE.

## Notes

- Every RDAP request uses a timeout (`--max-time`, default 10s); some registry RDAP endpoints hang. Override with `RDAP_MAX_TIME=<seconds>`.
- **AVAILABLE is "likely", not a guarantee.** Premium names, registry holds, and pending registrations can still block purchase. Confirm final price and availability at a registrar before relying on it.
- Requires `curl` and `dig` (or `host`); `jq` is optional but gives nicer registered-domain details; `whois` is optional but enables the fallback for no-RDAP TLDs. Run `whois <name>` by hand to see the raw record.
- The script normalizes input — it strips `https://`, paths, and trailing dots, and lowercases — so pasting a URL works.
