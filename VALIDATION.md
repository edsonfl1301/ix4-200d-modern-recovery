# Validation of experimental 0.3

This report contains only generic test results. Physical blank-disk recovery has
**not** been performed and is required before treating this recovery as validated.

## Checks completed

- An isolated first-boot simulation ran on an actual ix4-200d, using alternate
  SMB and HTTPS ports without disconnecting the production Windows mappings.
- A Python SMB client on Windows negotiated SMB 3.1.1 with signing required.
- A 1 MiB random file was created, read back byte-for-byte and deleted.
- HTTPS returned HTTP 200 using the unique first-boot certificate with certificate
  verification enabled. No certificate-validation bypass was used for this check.
- An invalid share source was rejected with exit code 2. The hash of the active
  Samba configuration was identical before and after rejection.
- The final image preserved the exact ten-file vendor archive layout. All MD5
  sidecars matched their images. The embedded payload matched the source files.
- Kernel, initrd and OEM images remained identical to the pinned vendor inputs.
- Filesystem diagnostics were identical to the original images apart from the
  expected inode/block usage summary. Existing vendor warnings were not repaired.
- Test daemons were stopped and their bind mounts were unmounted afterwards.

## Not covered

- A complete USB restoration, disk partitioning or NAND writing on spare hardware.
- A separate Windows 10 machine or every Windows 11 release and configuration.
- Replacement drives of 4 TB or the minimum usable drive count.
- Factory reset and a later official firmware update after installation.
- Successful external torrent data transfer, printing or iPhone photo backup.
- A security audit or an upgrade of the original kernel and operating system.

Binary components remain Samba 4.18.11, nginx 1.26.3 and OpenSSL 3.0.22. Functional
compatibility must not be presented as current security maintenance for this NAS.
