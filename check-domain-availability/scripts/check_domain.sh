#!/usr/bin/env bash
#
# check_domain.sh — Decide whether a domain name is registered or available.
#
# Combines two independent signals:
#   1. RDAP (https://rdap.org bootstrap -> the authoritative registry):
#        HTTP 200 => a registration record exists  => REGISTERED
#        HTTP 404 => no registration record         => looks available
#   2. DNS NS lookup (dig):
#        NS records present => the domain is delegated => REGISTERED
#
# Why both? rdap.org does not cover every TLD. Some registries (e.g. .io, .de)
# return 404 from RDAP even for clearly-registered names. The DNS NS check
# catches those false "available" results. A name is only reported AVAILABLE
# when RDAP says 404 AND there are no NS records.
#
# Usage:
#   check_domain.sh example.com [domain2 ...]
#
# Exit status: 0 on success (including "registered"/"available" verdicts),
#              2 on usage error.

set -u

RDAP_BASE="https://rdap.org/domain"
MAX_TIME="${RDAP_MAX_TIME:-10}"   # per-request curl timeout (seconds)

if [ "$#" -eq 0 ]; then
  echo "usage: $(basename "$0") <domain> [domain ...]" >&2
  exit 2
fi

have() { command -v "$1" >/dev/null 2>&1; }

# --- DNS NS lookup; prints space-separated nameservers (may be empty) ---
ns_records() {
  local domain="$1"
  if have dig; then
    dig +short +time=3 +tries=1 NS "$domain" 2>/dev/null | sed 's/\.$//' | tr '\n' ' '
  elif have host; then
    host -t NS "$domain" 2>/dev/null | awk '/name server/ {print $NF}' | sed 's/\.$//' | tr '\n' ' '
  fi
}

# --- RDAP fetch; sets globals RDAP_CODE and RDAP_BODY_FILE ---
rdap_fetch() {
  local domain="$1"
  RDAP_BODY_FILE="$(mktemp -t rdap.XXXXXX)"
  RDAP_CODE="$(curl -sL --max-time "$MAX_TIME" \
    -H 'Accept: application/rdap+json' \
    -o "$RDAP_BODY_FILE" -w '%{http_code}' \
    "$RDAP_BASE/$domain" 2>/dev/null)"
}

# --- Legacy WHOIS classifier; echoes "registered", "available", or "unknown".
#     Used only as a last-resort tiebreaker for TLDs RDAP doesn't cover.
#     WHOIS has no standard format, so this is best-effort string matching. ---
whois_classify() {
  local domain="$1" out
  have whois || { echo "unavailable"; return 0; }
  out="$(whois "$domain" 2>/dev/null)"
  [ -z "$out" ] && { echo "unknown"; return 0; }

  # "Not registered" phrasings vary by registry; cover the common ones.
  if printf '%s' "$out" | grep -qiE 'no match|not found|no data found|no entries found|no object found|domain not found|not registered|status:[[:space:]]*free|status:[[:space:]]*available|available for registration'; then
    echo "available"; return 0
  fi
  # Registration markers.
  if printf '%s' "$out" | grep -qiE 'registr(ar|y|ant)|creat(ion|ed)|expir|name server|nserver|domain status'; then
    echo "registered"; return 0
  fi
  echo "unknown"
}

# --- Pull human-readable details out of an RDAP JSON body (best effort) ---
rdap_details() {
  local file="$1"
  have jq || return 0
  jq -r '
    def ev(a): (.events // [])[] | select(.eventAction==a) | .eventDate;
    "    registrar:   " + (
        [ (.entities // [])[] | select(.roles // [] | index("registrar"))
          | (.vcardArray[1][] | select(.[0]=="fn") | .[3]) ] | first // "n/a"),
    "    registered:  " + ((ev("registration")) // "n/a"),
    "    expires:     " + ((ev("expiration")) // "n/a"),
    "    status:      " + ((.status // []) | join(", ") | if .=="" then "n/a" else . end),
    "    nameservers: " + ((.nameservers // [] | map(.ldhName) | join(", ")) | ascii_downcase | if .=="" then "n/a" else . end)
  ' "$file" 2>/dev/null
}

overall=0

for domain in "$@"; do
  # Normalize: strip scheme, path, trailing dot, lowercase.
  domain="$(printf '%s' "$domain" \
    | sed -E 's#^[a-zA-Z]+://##; s#/.*$##; s#\.$##' \
    | tr '[:upper:]' '[:lower:]')"

  echo "== $domain =="

  if ! printf '%s' "$domain" | grep -q '\.'; then
    echo "  SKIP: '$domain' is not a domain name (no dot)."
    echo
    continue
  fi

  rdap_fetch "$domain"
  ns="$(ns_records "$domain")"
  ns="${ns%% }"   # trim trailing space

  rdap_state="other($RDAP_CODE)"
  case "$RDAP_CODE" in
    200) rdap_state="found (200)";;
    404) rdap_state="not found (404)";;
    000) rdap_state="no response / timeout";;
  esac

  echo "  RDAP: $rdap_state"
  if [ -n "$ns" ]; then
    echo "  DNS:  NS records present -> $ns"
  else
    echo "  DNS:  no NS records"
  fi

  # --- Verdict ---
  if [ "$RDAP_CODE" = "200" ] || [ -n "$ns" ]; then
    echo "  VERDICT: REGISTERED (taken)"
    if [ "$RDAP_CODE" = "200" ]; then
      rdap_details "$RDAP_BODY_FILE"
    elif [ -n "$ns" ]; then
      echo "    (RDAP did not return a record for this TLD, but DNS delegation proves it is registered)"
    fi
  elif [ "$RDAP_CODE" = "404" ]; then
    echo "  VERDICT: AVAILABLE (likely) — no registry record and no DNS delegation."
    echo "    Confirm final price/availability at a registrar before relying on this."
  else
    # RDAP gave no usable answer and there are no NS records. Fall back to
    # legacy WHOIS, which covers some TLDs that RDAP and the NS check miss.
    whois_verdict="$(whois_classify "$domain")"
    case "$whois_verdict" in
      registered)
        echo "  WHOIS: registration record found"
        echo "  VERDICT: REGISTERED (taken) — via legacy WHOIS fallback";;
      available)
        echo "  WHOIS: no registration record found"
        echo "  VERDICT: AVAILABLE (likely) — via legacy WHOIS fallback."
        echo "    Confirm final price/availability at a registrar before relying on this.";;
      unavailable)
        echo "  VERDICT: INCONCLUSIVE — RDAP gave no answer, no NS records, and 'whois' is not installed."
        echo "    Install whois, retry, or check this TLD's registry directly."
        overall=1;;
      *)
        echo "  WHOIS: ran but result was unparseable"
        echo "  VERDICT: INCONCLUSIVE — no signal agreed. Check this TLD's registry directly."
        overall=1;;
    esac
  fi

  rm -f "$RDAP_BODY_FILE"
  echo
done

exit 0
