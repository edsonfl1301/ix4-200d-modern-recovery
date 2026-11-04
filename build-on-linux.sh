#!/bin/sh
# Build on a Linux host with debugfs/e2fsck/tar; modifies copies only.
set -eu
SOURCE=${1:?Usage: build-on-linux.sh original.tgz payload-directory output-directory}
PAYLOAD=${2:?Missing payload directory}
OUT=${3:?Missing output directory}
case "$OUT" in /mnt/system/recovery-integrated-build/*|/*/ix4-integrated-output) ;; *) echo 'Use a dedicated absolute output path ending ix4-integrated-output'; exit 2;; esac
[ ! -e "$OUT/BUILD_COMPLETE" ] || { echo 'Completed output exists; choose a new output directory'; exit 2; }
mkdir -p "$OUT/original" "$OUT/logs"
if [ ! -f "$OUT/original/zImage.md5" ]; then tar -xzf "$SOURCE" -C "$OUT/original"; fi
for name in apps config initrd oem zImage; do
    [ -f "$OUT/original/$name" ] && [ -f "$OUT/original/$name.md5" ]
    actual=$(md5sum "$OUT/original/$name" | awk '{print $1}')
    expected=$(cat "$OUT/original/$name.md5")
    [ "$actual" = "$expected" ] || { echo "Original checksum failed: $name"; exit 3; }
    case "$name" in
      apps) pinned=3c86c20242ab64609b8545f9bbd4520b;;
      config) pinned=3f332eae6481860d5407f6a1e1149205;;
      initrd) pinned=41094fcd536c68bf0c2458cceae3abfa;;
      oem) pinned=72b7dcfa7fc67d6cbbb7fcde40cea9f2;;
      zImage) pinned=a5fefe901e472891794bfcf267e3c167;;
    esac
    [ "$actual" = "$pinned" ] || { echo "Wrong original image: $name"; exit 3; }
    if [ -f "$OUT/$name" ]; then
        [ "$(md5sum "$OUT/$name" | awk '{print $1}')" = "$pinned" ] || { echo "Refusing to overwrite modified staging file: $name"; exit 3; }
    else cp -p "$OUT/original/$name" "$OUT/$name"; fi
done
# The loop above pins all five images and accepts only pristine staging copies.
check_fs() {
    if e2fsck -fn "$OUT/$1" > "$OUT/logs/$1-$2-fsck.txt" 2>&1; then result=0; else result=$?; fi
    echo "$result" > "$OUT/logs/$1-$2-fsck.exit"
    # The pinned vendor images contain existing empty symlinks and no lost+found.
    # Never repair them. Require identical diagnostics after modification below.
    [ "$result" = 0 ] || [ "$result" = 4 ]
}
check_fs apps before
check_fs config before
{
    echo 'cd /usr/local'
    echo 'mkdir iomega-modern'
    echo 'cd iomega-modern'
    for name in bootstrap.sh service.sh shares.awk nginx.conf.in runtime.tar.gz legacy_socket_compat.so RELEASE.txt; do
        printf 'write "%s/%s" %s\n' "$PAYLOAD" "$name" "$name"
        case "$name" in *.sh) mode=0100755;; *) mode=0100644;; esac
        printf 'set_inode_field %s mode %s\n' "$name" "$mode"
        printf 'set_inode_field %s uid 0\n' "$name"
        printf 'set_inode_field %s gid 0\n' "$name"
    done
} > "$OUT/logs/apps-debugfs.commands"
debugfs -w -f "$OUT/logs/apps-debugfs.commands" "$OUT/apps" > "$OUT/logs/apps-debugfs.txt" 2>&1
{
    echo 'cd /'
    echo 'rm rc.local'
    printf 'write "%s/rc.local" rc.local\n' "$PAYLOAD"
    echo 'set_inode_field rc.local mode 0100755'
    echo 'set_inode_field rc.local uid 0'
    echo 'set_inode_field rc.local gid 0'
    echo 'rm httpd.xml'
    printf 'write "%s/httpd.xml" httpd.xml\n' "$PAYLOAD"
    echo 'set_inode_field httpd.xml mode 0100644'
    echo 'set_inode_field httpd.xml uid 0'
    echo 'set_inode_field httpd.xml gid 0'
} > "$OUT/logs/config-debugfs.commands"
debugfs -w -f "$OUT/logs/config-debugfs.commands" "$OUT/config" > "$OUT/logs/config-debugfs.txt" 2>&1
check_fs apps after
check_fs config after
for image in apps config; do
    # Only the final used-inode/block counter may change. All diagnostic lines
    # including warnings, link errors and group checks must remain identical.
    sed '/files (.*non-contiguous).*blocks/d' "$OUT/logs/$image-before-fsck.txt" > "$OUT/logs/$image-before-diagnostics.txt"
    sed '/files (.*non-contiguous).*blocks/d' "$OUT/logs/$image-after-fsck.txt" > "$OUT/logs/$image-after-diagnostics.txt"
    cmp "$OUT/logs/$image-before-diagnostics.txt" "$OUT/logs/$image-after-diagnostics.txt"
done
for name in apps config initrd oem zImage; do
    md5sum "$OUT/$name" | awk '{print $1}' > "$OUT/$name.md5"
done
for name in initrd oem zImage; do cmp "$OUT/$name" "$OUT/original/$name"; done
(cd "$OUT" && sha256sum apps config initrd oem zImage > SHA256SUMS)
# Keep the vendor's ten-file tar layout; no noextraction shortcut is necessary.
(cd "$OUT" && GZIP=-1 tar -czf ix4-200d.tgz apps apps.md5 config config.md5 initrd initrd.md5 oem oem.md5 zImage zImage.md5)
touch "$OUT/BUILD_COMPLETE"
echo 'Integrated recovery built. Physical blank-disk installation is NOT yet validated.'
echo "$OUT/ix4-200d.tgz"
