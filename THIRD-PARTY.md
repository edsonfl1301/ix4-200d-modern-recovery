# Third-party components and publication status

This public repository distributes newly written source code and build instructions, not firmware binaries.

- The recovery base is the user-supplied Iomega Cloud Edition 3.2.6.17887 archive. It includes proprietary vendor components. It is not covered by this project's MIT license.
- Samba 4.18.11 and its dependencies, nginx 1.26.3, OpenSSL 3.0.22, musl and BusyBox originate from official OpenWrt 24.10.4 ARM xscale package feeds. `packages-manifest.json` records versions, package licenses, URLs and downloaded hashes.
- OpenWrt package recipe and patch sources: https://github.com/openwrt/packages/tree/openwrt-24.10 and https://github.com/openwrt/openwrt/tree/openwrt-24.10 . A public binary release still needs a complete corresponding-source/notice review, including exact recipe revisions and build options.
- Samba upstream: https://www.samba.org/ and https://github.com/samba-team/samba . nginx upstream: https://nginx.org/ . OpenSSL upstream: https://openssl-library.org/ . musl: https://musl.libc.org/ . BusyBox: https://busybox.net/ .
- `legacy_socket_compat.c` is newly written project code. It handles only the optional Linux `SO_REUSEPORT` unsupported-option error in this isolated single-listener use case. It does not change authentication, SMB signing, encryption or other socket errors.

Do not assume a functional compatibility build is a complete security update. The base OS and some component branches remain old. No claim of upstream support or security audit is made.
