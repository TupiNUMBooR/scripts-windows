#!/usr/bin/env bash
set -euo pipefail
# audit-server-security.sh

. ./.env
: "${SSH_ADDRESS?}"

mkdir -p out

STAMP="$(date +%Y%m%d-%H%M%S)"
SAFE_HOST="$(printf '%s' "$SSH_ADDRESS" | tr -c '[:alnum:]_.@-' '_')"
OUT_FILE="out/server-security-audit-${SAFE_HOST}-${STAMP}.txt"
REMOTE_REPORT="/tmp/server-security-audit-${STAMP}.txt"
REMOTE_RUNNER="/tmp/server-security-audit-runner-${STAMP}.sh"

ssh "$SSH_ADDRESS" "umask 077; cat > '$REMOTE_RUNNER'" <<'REMOTE_SCRIPT'
set -u

REPORT="${REMOTE_REPORT:?}"
SUDO="sudo"
if ! command -v sudo >/dev/null 2>&1; then
  SUDO=""
fi

run_section() {
  printf '\n\n===== %s =====\n' "$1" >> "$REPORT"
}

run_cmd() {
  printf '\n$ %s\n' "$*" >> "$REPORT"
  "$@" >> "$REPORT" 2>&1 || printf '[exit %s]\n' "$?" >> "$REPORT"
}

run_sh() {
  printf '\n$ %s\n' "$1" >> "$REPORT"
  sh -c "$1" >> "$REPORT" 2>&1 || printf '[exit %s]\n' "$?" >> "$REPORT"
}

run_sudo_sh() {
  printf '\n$ sudo %s\n' "$1" >> "$REPORT"
  if [ -n "$SUDO" ]; then
    $SUDO sh -c "$1" >> "$REPORT" 2>&1 || printf '[exit %s]\n' "$?" >> "$REPORT"
  else
    sh -c "$1" >> "$REPORT" 2>&1 || printf '[exit %s]\n' "$?" >> "$REPORT"
  fi
}

: > "$REPORT"
chmod 600 "$REPORT" 2>/dev/null || true

run_section "Report Metadata"
run_cmd date -Is
run_cmd hostname
run_cmd whoami
run_cmd id
run_cmd uname -a
run_sh "command -v lsb_release >/dev/null 2>&1 && lsb_release -a || cat /etc/os-release"
run_cmd uptime

run_section "APT And DPKG Locks"
run_sh "ps -eo pid,ppid,user,lstart,etime,stat,cmd | grep -E '[a]pt|[d]pkg|unattended|packagekit'"
run_sudo_sh "command -v lsof >/dev/null 2>&1 && lsof /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend 2>/dev/null || true"
run_sudo_sh "tail -200 /var/log/apt/history.log 2>/dev/null"
run_sudo_sh "tail -200 /var/log/apt/term.log 2>/dev/null"
run_sudo_sh "tail -200 /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null"

run_section "Current Logins And Login History"
run_cmd who
run_cmd w
run_sh "last -a | head -80"
run_sh "lastb -a 2>/dev/null | head -80"
run_sudo_sh "lastlog | grep -v 'Never logged in'"

run_section "SSH And Auth Events"
run_sudo_sh "grep -Ei 'Accepted|Failed|Invalid user|authentication failure|sudo|session opened|session closed' /var/log/auth.log 2>/dev/null | tail -300"
run_sudo_sh "journalctl --since '14 days ago' -u ssh -u sshd --no-pager 2>/dev/null | tail -300"
run_sudo_sh "journalctl --since '14 days ago' --no-pager 2>/dev/null | grep -Ei 'Accepted|Failed|Invalid user|sudo|authentication failure' | tail -300"

run_section "Users Groups And Sudo Access"
run_cmd getent passwd
run_cmd getent group sudo
run_cmd getent group wheel
run_sudo_sh "find /etc/sudoers /etc/sudoers.d -maxdepth 1 -type f -print -exec sed -n '1,220p' {} \\; 2>/dev/null"

run_section "SSH Configuration And Authorized Keys"
run_sudo_sh "sshd -T 2>/dev/null | grep -Ei '^(permitrootlogin|passwordauthentication|pubkeyauthentication|authorizedkeysfile|allowusers|allowgroups|denyusers|denygroups|permituserenvironment)'"
run_sudo_sh "sed -n '1,240p' /etc/ssh/sshd_config 2>/dev/null"
run_sudo_sh "find /root /home -maxdepth 3 \\( -name authorized_keys -o -name config -o -name known_hosts \\) -type f -print -exec ls -la {} \\; -exec sed -n '1,220p' {} \\; 2>/dev/null"

run_section "Processes"
run_sh "ps auxww --sort=-%cpu | head -60"
run_sh "ps auxww --sort=-%mem | head -60"
run_sudo_sh "command -v pstree >/dev/null 2>&1 && pstree -ap || true"

run_section "Network Listeners And Connections"
run_sudo_sh "ss -tulpn"
run_sudo_sh "ss -antp | head -250"
run_sudo_sh "command -v lsof >/dev/null 2>&1 && lsof -i -P -n | head -250 || true"

run_section "Cron And Timers"
run_sh "crontab -l 2>/dev/null"
run_sudo_sh "crontab -l 2>/dev/null"
run_sudo_sh "find /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly /var/spool/cron /var/spool/cron/crontabs -maxdepth 2 -type f -print -exec ls -la {} \\; -exec sed -n '1,220p' {} \\; 2>/dev/null"
run_cmd systemctl list-timers --all --no-pager

run_section "Systemd Services"
run_cmd systemctl --type=service --state=running --no-pager
run_cmd systemctl list-unit-files --type=service --no-pager
run_sudo_sh "find /etc/systemd/system /lib/systemd/system -type f -mtime -30 -print -exec ls -la {} \\; 2>/dev/null"

run_section "Recently Changed Sensitive Paths"
run_sudo_sh "find /etc /root /home /usr/local/bin /usr/local/sbin /tmp /var/tmp -xdev -type f -mtime -14 -printf '%TY-%Tm-%Td %TH:%TM %u %g %m %p\n' 2>/dev/null | sort | tail -500"

run_section "Shell Startup Files"
run_sudo_sh "find /root /home -maxdepth 3 \\( -name '.bashrc' -o -name '.profile' -o -name '.bash_profile' -o -name '.zshrc' -o -name '.sshrc' \\) -type f -print -exec ls -la {} \\; -exec sed -n '1,220p' {} \\; 2>/dev/null"

run_section "Installed Packages Changed Recently"
run_sudo_sh "grep -E ' install | upgrade | remove | purge ' /var/log/apt/history.log 2>/dev/null | tail -300"
run_sh "command -v debsums >/dev/null 2>&1 && debsums -s || true"

run_section "Large Or Suspicious Temporary Files"
run_sudo_sh "find /tmp /var/tmp -xdev -mindepth 1 -maxdepth 3 -printf '%TY-%Tm-%Td %TH:%TM %u %g %m %s %p\n' 2>/dev/null | sort | tail -300"

run_section "Docker If Present"
run_sh "command -v docker >/dev/null 2>&1 && docker ps -a || true"
run_sh "command -v docker >/dev/null 2>&1 && docker images || true"

if command -v perl >/dev/null 2>&1; then
  perl -pi -e 's#bot[0-9]+:[A-Za-z0-9_-]+#bot<redacted>#g; s#(telegram\.org/)bot[A-Za-z0-9:_-]+#$1bot<redacted>#g' "$REPORT"
fi

printf '\nReport written to %s\n' "$REPORT"
REMOTE_SCRIPT

ssh -tt "$SSH_ADDRESS" "
  if command -v sudo >/dev/null 2>&1; then
    sudo -v
  fi
  REMOTE_REPORT='$REMOTE_REPORT' bash '$REMOTE_RUNNER'
  rc=\$?
  rm -f '$REMOTE_RUNNER'
  exit \$rc
"

ssh "$SSH_ADDRESS" "cat '$REMOTE_REPORT'; rm -f '$REMOTE_REPORT'" > "$OUT_FILE"

printf 'Downloaded report: %s\n' "$OUT_FILE"
du -h "$OUT_FILE"
