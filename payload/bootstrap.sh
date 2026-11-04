#!/bin/sh
# Run from the immutable apps image. No disk partitioning or flashing here.
set -eu
BASE=${IOMEGA_MODERN_BASE:-/usr/local/iomega-modern}
ROOT=${IOMEGA_MODERN_ROOT:-/mnt/system/iomega-modern}
trap '' HUP
while ! grep -q ' /mnt/system ' /proc/mounts; do sleep 3; done
if [ -f "$ROOT/DISABLED" ]; then exit 0; fi
if [ ! -f "$ROOT/.integrated-runtime-v1" ]; then
    # Never overwrite an existing, unrelated manual installation.
    if [ -d "$ROOT" ] && [ ! -f "$ROOT/.integrated-installing" ]; then
        echo "Refusing to overwrite existing runtime: $ROOT"
        exit 1
    fi
    mkdir -p "$ROOT"
    chmod 755 "$ROOT"
    touch "$ROOT/.integrated-installing"
    tar -xzf "$BASE/runtime.tar.gz" -C "$ROOT"
    cp "$BASE/legacy_socket_compat.so" "$ROOT/lib/legacy_socket_compat.so"
    mkdir -p "$ROOT/etc" "$ROOT/dev" "$ROOT/proc" "$ROOT/srv/pools" "$ROOT/run" "$ROOT/var/run/samba" "$ROOT/var/log/samba" "$ROOT/var/lib/samba/private" "$ROOT/var/cache/samba" "$ROOT/var/lock" "$ROOT/tmp" "$ROOT/etc/ssl" "$ROOT/var/lib/nginx/body" "$ROOT/var/lib/nginx/proxy" "$ROOT/var/log/nginx"
    chmod 1777 "$ROOT/tmp"
    ln -sf busybox "$ROOT/bin/sh"
    ln -sf busybox "$ROOT/bin/ls"
    printf '%s\n' 'ix4-integrated-recovery experimental-0.3' > "$ROOT/.integrated-runtime-v1"
    rm -f "$ROOT/.integrated-installing"
fi
export IOMEGA_MODERN_BASE="$BASE" IOMEGA_MODERN_ROOT="$ROOT"
exec /bin/sh "$BASE/service.sh" supervise
