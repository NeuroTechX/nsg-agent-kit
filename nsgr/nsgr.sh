#!/usr/bin/env bash
# nsgr.sh — minimal NSG-R (CIPRES REST) client for submitting jobs to NSG/Expanse.
#
# Credentials come from the environment (never hard-code a password):
#   NSG_URL      e.g. https://nsgr.sdsc.edu:8443/cipresrest/v1
#   NSG_USER     your NSG username
#   NSG_APPKEY   your Application ID (cipres-appkey header)
#   NSG_PASSWORD exported in your shell only (read -s NSG_PASSWORD; export NSG_PASSWORD)
#   NSG_EXTRA    optional extra "-F vparam.x_=y" args, space-separated (tool-specific)
#
# The password is passed to curl via -u and is never echoed by this script.
#
# Usage:
#   ./nsgr.sh submit <TOOL_ID> <job.zip>
#   ./nsgr.sh list
#   ./nsgr.sh whoami            # account status + canSubmit (no budget API exists)
#   ./nsgr.sh status <JOBHANDLE>
#   ./nsgr.sh fetch  <JOBHANDLE> <dest_dir>
#   ./nsgr.sh tlscheck [warn_days]   # server certificate expiry; needs only NSG_URL, no credentials
#
# Every call verifies the server certificate. If it has expired (nsgr.sdsc.edu, 2026-11-20) curl
# exits 60 and this script exits 75 (EX_TEMPFAIL): wait for SDSC to renew it. Never add -k -- every
# request carries your password and app key.
set -euo pipefail

if [ "${1:-}" = tlscheck ]; then
  : "${NSG_URL:?set NSG_URL (source nsgr/config.env)}"
  hostport="$(printf '%s' "$NSG_URL" | sed -E 's#^https://([^/]+).*#\1#')"
  case "$hostport" in *:*) ;; *) hostport="$hostport:443" ;; esac
  warn_days="${2:-14}"
  end="$(echo | timeout 20 openssl s_client -connect "$hostport" -servername "${hostport%%:*}" 2>/dev/null \
         | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)" || true
  [ -n "$end" ] || { echo "tlscheck: no certificate from $hostport (host down?)" >&2; exit 75; }
  left=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
  echo "$hostport certificate notAfter=$end ($left days left)"
  if [ "$left" -lt 0 ]; then
    echo "tlscheck: EXPIRED -- every API call will fail (curl 60). Tell nsghelp@sdsc.edu; do not use -k." >&2
    exit 75
  fi
  [ "$left" -lt "$warn_days" ] && echo "tlscheck: WARNING expires in $left days" >&2
  exit 0
fi

: "${NSG_URL:?set NSG_URL (source nsgr/config.env)}"
: "${NSG_USER:?set NSG_USER}"
: "${NSG_APPKEY:?set NSG_APPKEY}"
: "${NSG_PASSWORD:?export NSG_PASSWORD in your shell (do not store it on disk)}"

auth=(-u "${NSG_USER}:${NSG_PASSWORD}" -H "cipres-appkey:${NSG_APPKEY}")

curl() {  # certificate failures (60 expired/untrusted, 51 name mismatch) are server-side: exit 75
  local rc=0; command curl "$@" || rc=$?
  if [ "$rc" -eq 60 ] || [ "$rc" -eq 51 ]; then
    echo "nsgr.sh: TLS verification of ${NSG_URL} failed (curl $rc) -- run './nsgr.sh tlscheck'" >&2
    exit 75
  fi
  return "$rc"
}
base="${NSG_URL}/job/${NSG_USER}"

cmd="${1:-help}"; shift || true

case "$cmd" in
  submit)
    tool="${1:?tool id, e.g. PYTORCH_EXPANSE}"; zip="${2:?path to job.zip}"
    [ -f "$zip" ] || { echo "no such zip: $zip" >&2; exit 1; }
    # shellcheck disable=SC2206
    extra=(${NSG_EXTRA:-})
    echo "submitting $zip to tool=$tool ..." >&2
    curl -sS "${auth[@]}" "$base" \
      -F tool="$tool" \
      -F input.infile_=@"$zip" \
      -F metadata.statusEmail=true \
      "${extra[@]}"
    echo
    ;;
  list)
    curl -sS "${auth[@]}" "$base"
    echo
    ;;
  whoami)
    # NSG exposes NO budget/quota API (checked: /usage /account /allocation /quota all 404).
    # This profile record is the only machine-readable entitlement signal -- `canSubmit`.
    curl -sS "${auth[@]}" "${NSG_URL}/user/${NSG_USER}" | tr '>' '>\n' \
      | grep -E 'username|role|active|canSubmit|institution' | sed 's/<[^>]*>//g' | sed '/^$/d'
    echo "(NSG has no per-user SU accounting; for allocation questions: nsghelp@sdsc.edu)"
    ;;
  status)
    handle="${1:?job handle, e.g. NGBW-JOB-...}"
    curl -sS "${auth[@]}" "$base/$handle"
    echo
    ;;
  fetch)
    handle="${1:?job handle}"; dest="${2:?dest dir}"
    mkdir -p "$dest"
    echo "listing outputs for $handle ..." >&2
    listing="$(curl -sS "${auth[@]}" "$base/$handle/output")"
    # extract every downloadUri; works with or without xmllint
    urls="$(printf '%s' "$listing" | grep -oE 'https://[^<]*/output/[0-9]+' || true)"
    if [ -z "$urls" ]; then
      echo "no output urls found — is the job terminalStage=true? raw listing:" >&2
      printf '%s\n' "$listing" >&2
      exit 1
    fi
    while IFS= read -r u; do
      [ -z "$u" ] && continue
      echo "  downloading $u" >&2
      # -OJ honours the server-provided filename; land files in $dest
      ( cd "$dest" && curl -sS -OJ "${auth[@]}" "$u" )
    done <<< "$urls"
    echo "done -> $dest" >&2
    ;;
  *)
    sed -n '1,26p' "$0"
    ;;
esac
