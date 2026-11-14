# Helpers shared by the update actions. Source it, do not run it.

# cooldown_seconds <period>: seconds in a cooldown period such as 7d, 12h, 30m. A bare number
# is days, 0 disables the cooldown. Same syntax as npm-check-updates --cooldown.
cooldown_seconds() {
  local period="${1:-0}"
  if [[ ! "$period" =~ ^([0-9]+)([dhm]?)$ ]]; then
    echo "ERROR: invalid cooldown '$period', use for example 7d, 12h or 30m" >&2
    return 1
  fi
  local amount="${BASH_REMATCH[1]}"
  case "${BASH_REMATCH[2]:-d}" in
    d) echo $((amount * 86400)) ;;
    h) echo $((amount * 3600)) ;;
    m) echo $((amount * 60)) ;;
  esac
}

# warn <title> <message>: a workflow annotation in CI, a plain line otherwise. Used when a
# language version is held back by the cooldown, so it shows on the run page.
warn() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::warning title=$1::$2"
  else
    echo "WARNING: $1: $2" >&2
  fi
}

# age_days <epoch seconds> <now epoch seconds>
age_days() {
  echo $(( ($2 - $1) / 86400 ))
}
