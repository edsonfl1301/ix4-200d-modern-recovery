#!/bin/sh
# Generic service for blank-disk recovery. Never partitions, formats or flashes.
set -eu
BASE=${IOMEGA_MODERN_BASE:-/usr/local/iomega-modern}
ROOT=${IOMEGA_MODERN_ROOT:-/mnt/system/iomega-modern}
SMB_PORT=${IOMEGA_SMB_PORT:-445}
HTTPS_PORT=${IOMEGA_HTTPS_PORT:-443}
TEST=${IOMEGA_MODERN_TEST:-0}
SOURCE=${IOMEGA_SHARE_SOURCE:-/mnt/system/config/smb.conf}
LOG=$ROOT/var/log/modern-supervisor.log

running() {
    [ -f "$1" ] || return 1
    pid=$(cat "$1")
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    [ "$(readlink "/proc/$pid/exe" 2>/dev/null || true)" = "$2" ]
}

sync_file() {
    if [ -f "$1" ] && ! cmp -s "$1" "$2"; then
        cp "$1" "$2.next"
        chmod "$3" "$2.next"
        mv "$2.next" "$2"
    fi
}

prepare_runtime() {
    grep -q " $ROOT/dev " /proc/mounts || mount --bind /dev "$ROOT/dev"
    grep -q " $ROOT/proc " /proc/mounts || mount --bind /proc "$ROOT/proc"
    for name in passwd group hosts resolv.conf; do sync_file "/etc/$name" "$ROOT/etc/$name" 644; done
}

start_tls() {
    if [ ! -s "$ROOT/etc/ssl/iomega.key" ] || [ ! -s "$ROOT/etc/ssl/iomega.crt" ]; then
        host=$(hostname | tr -cd 'A-Za-z0-9.-' | cut -c1-63)
        [ -n "$host" ] || host=iomega
        san="DNS:$host,DNS:localhost,IP:127.0.0.1"
        for address in $(/sbin/ip -o -4 addr show scope global | awk '{split($4,a,"/"); print a[1]}'); do
            san="$san,IP:$address"
        done
        echo 'Generating a unique local HTTPS certificate (first boot).'
        OPENSSL_CONF=/dev/null chroot "$ROOT" /usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 365 -subj "/CN=$host" -addext "subjectAltName=$san" -keyout /etc/ssl/iomega.key -out /etc/ssl/iomega.crt
        chmod 600 "$ROOT/etc/ssl/iomega.key"
    fi
    sed "s/@HTTPS_PORT@/$HTTPS_PORT/g" "$BASE/nginx.conf.in" > "$ROOT/etc/nginx.conf.next"
    if ! cmp -s "$ROOT/etc/nginx.conf.next" "$ROOT/etc/nginx.conf"; then
        mv "$ROOT/etc/nginx.conf.next" "$ROOT/etc/nginx.conf"
    else rm -f "$ROOT/etc/nginx.conf.next"; fi
    chown nobody "$ROOT/var/lib/nginx/body" "$ROOT/var/lib/nginx/proxy"
    if ! running "$ROOT/var/run/nginx-modern.pid" "$ROOT/usr/sbin/nginx"; then
        chroot "$ROOT" /usr/sbin/nginx -t -c /etc/nginx.conf
        chroot "$ROOT" /usr/sbin/nginx -c /etc/nginx.conf
    fi
}

generate_smb() {
    cat <<EOF
[global]
    workgroup = WORKGROUP
    netbios name = IOMEGA-MODERN
    server string = ix4 integrated recovery experimental-0.3
    server role = standalone server
    security = user
    passdb backend = smbpasswd:/etc/samba/smbpasswd
    map to guest = Never
    server min protocol = SMB2_02
    server max protocol = SMB3
    server signing = mandatory
    ntlm auth = ntlmv2-only
    smb ports = $SMB_PORT
    disable netbios = yes
    load printers = no
    printing = bsd
    printcap name = /dev/null
    disable spoolss = yes
    multicast dns register = no
    log file = /var/log/samba/log.%m
    log level = 1
    max log size = 256
    state directory = /var/lib/samba
    cache directory = /var/cache/samba
    lock directory = /var/lock
    pid directory = /var/run/samba
    private dir = /var/lib/samba/private
    use sendfile = yes
EOF
    awk -f "$BASE/shares.awk" "$ROOT/run/source-smb.conf"
}

start_smb() {
    # Initial setup must create an authenticated user and mount the data volume.
    [ -s /etc/samba/private/smbpasswd ] || return 0
    [ -s "$SOURCE" ] || return 0
    grep -q ' /mnt/pools/' /proc/mounts || return 0
    mkdir -p "$ROOT/etc/samba"
    sync_file /etc/samba/private/smbpasswd "$ROOT/etc/samba/smbpasswd" 600
    grep -q " $ROOT/srv/pools " /proc/mounts || mount --rbind /mnt/pools "$ROOT/srv/pools"
    cp "$SOURCE" "$ROOT/run/source-smb.conf"
    sleep 1
    cmp -s "$SOURCE" "$ROOT/run/source-smb.conf" || return 1
    generate_smb > "$ROOT/etc/samba/smb.conf.next"
    if ! cmp -s "$ROOT/etc/samba/smb.conf.next" "$ROOT/etc/samba/smb.conf"; then
        chroot "$ROOT" /usr/bin/testparm -s /etc/samba/smb.conf.next >/dev/null
        [ ! -s "$ROOT/etc/samba/smb.conf" ] || cp -p "$ROOT/etc/samba/smb.conf" "$ROOT/etc/samba/smb.conf.last-good"
        mv "$ROOT/etc/samba/smb.conf.next" "$ROOT/etc/samba/smb.conf"
        for child in $(pidof smbd 2>/dev/null || true); do
            if [ "$(readlink "/proc/$child/exe" 2>/dev/null || true)" = "$ROOT/usr/sbin/smbd" ]; then kill -HUP "$child" || true; fi
        done
    else rm -f "$ROOT/etc/samba/smb.conf.next"; fi
    if [ "$TEST" != 1 ]; then
        if ! grep -q '^smb ports = 139$' /mnt/system/config/smb.conf; then
            [ -f "$ROOT/stock-smb.conf.before-modern" ] || cp -p /mnt/system/config/smb.conf "$ROOT/stock-smb.conf.before-modern"
            awk '{if(tolower($0) ~ /^[[:space:]]*smb ports[[:space:]]*=/)next; print; if(tolower($0) ~ /^\[global\]/) print "smb ports = 139"}' /mnt/system/config/smb.conf > /mnt/system/config/smb.conf.integrated-next
            cat /mnt/system/config/smb.conf.integrated-next > /mnt/system/config/smb.conf
            rm -f /mnt/system/config/smb.conf.integrated-next
        fi
        listener=$(netstat -lntp 2>/dev/null | awk '$4 ~ /:445$/ {split($7,a,"/"); print a[1]; exit}')
        if [ -n "$listener" ] && [ "$(readlink "/proc/$listener/exe" 2>/dev/null || true)" = /mnt/apps/usr/local/samba/sbin/smbd ]; then
            /usr/local/samba/bin/smbcontrol "$listener" shutdown
            sleep 2
        fi
    fi
    if ! running "$ROOT/var/run/samba/smbd.pid" "$ROOT/usr/sbin/smbd"; then
        chroot "$ROOT" /bin/busybox env LD_PRELOAD=/lib/legacy_socket_compat.so /usr/sbin/smbd -D -s /etc/samba/smb.conf
    fi
}

start_services() {
    prepare_runtime
    start_tls
    start_smb
}

health() {
    smb=FAIL; tls=FAIL; backend=FAIL
    listener=$(netstat -lntp 2>/dev/null | awk -v port=":$SMB_PORT" '$4 ~ (port "$") {split($7,a,"/");print a[1];exit}')
    if [ -n "$listener" ] && [ "$(readlink "/proc/$listener/exe" 2>/dev/null || true)" = "$ROOT/usr/sbin/smbd" ]; then smb=LISTENING; fi
    # Unique first-boot certificate always contains loopback. Host curl cannot
    # negotiate modern TLS; run OpenSSL from the isolated runtime instead.
    chroot "$ROOT" /usr/bin/openssl s_client -connect "127.0.0.1:$HTTPS_PORT" -verify_ip 127.0.0.1 -CAfile /etc/ssl/iomega.crt -verify_return_error -brief </dev/null > "$ROOT/var/log/tls-health.log" 2>&1 &
    probe=$!
    ( sleep 8; if [ "$(readlink "/proc/$probe/exe" 2>/dev/null || true)" = "$ROOT/usr/bin/openssl" ]; then kill -TERM "$probe" 2>/dev/null || true; fi ) &
    guard=$!
    wait "$probe" && tls=OK || true
    kill "$guard" 2>/dev/null || true
    wait "$guard" 2>/dev/null || true
    curl --max-time 8 -sf http://127.0.0.1/login.html -o /dev/null && backend=OK || true
    { date; echo "SMB=$smb TLS=$tls BACKEND=$backend"; } > "$ROOT/run/health.txt.next"
    mv "$ROOT/run/health.txt.next" "$ROOT/run/health.txt"
    [ "$smb" = LISTENING ] && [ "$tls" = OK ] && [ "$backend" = OK ]
}

case "${1:-status}" in
  start) start_services;;
  supervise)
    trap '' HUP
    if [ -f "$ROOT/run/supervisor.pid" ]; then
        oldpid=$(cat "$ROOT/run/supervisor.pid")
        case "$oldpid" in ''|*[!0-9]*) oldpid=0;; esac
        if [ "$oldpid" != 0 ] && [ -r "/proc/$oldpid/cmdline" ] && tr '\000' ' ' < "/proc/$oldpid/cmdline" | grep -q 'service.sh supervise'; then exit 0; fi
    fi
    echo $$ > "$ROOT/run/supervisor.pid"
    trap 'rm -f "$ROOT/run/supervisor.pid"; exit 0' TERM INT
    while [ ! -f "$ROOT/DISABLED" ]; do
        # Separate process makes set -e effective inside every startup attempt.
        if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 262144 ]; then mv "$LOG" "$LOG.1"; fi
        /bin/sh "$BASE/service.sh" start >> "$LOG" 2>&1 || echo "$(date): startup failed; retaining existing configuration; retry in 30s" >> "$LOG"
        /bin/sh "$BASE/service.sh" health >> "$LOG" 2>&1 || echo "$(date): health check failed; no forced restart of live services" >> "$LOG"
        sleep 30 & wait $! || true
    done
    ;;
  status)
    netstat -lntp 2>/dev/null | grep -E ":$SMB_PORT |:$HTTPS_PORT " || true
    chroot "$ROOT" /usr/bin/smbstatus
    ;;
  health) health; cat "$ROOT/run/health.txt";;
  *) echo 'Usage: start | supervise | status | health'; exit 2;;
esac
