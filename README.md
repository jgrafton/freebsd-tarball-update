# FreeBSD Tarball Update

This is a simple script that updates FreeBSD systems using ZFS boot environments.

It works by creating a boot environment from the current system, upgrading the boot environment and then activating it.

The basic update process is thus:

1. Determine kernel version and update
1. Download tarballs for the latest snapshot
1. Create a new boot environment
1. Mount the new boot environment
1. Extract downloaded tarballs (kernel, base, and src) into the new boot environment
1. Upgrade the packages in the chrooted boot environment
1. Temporarily activate the new boot environment with the -T flag
1. Tell user to reboot the host and rerun script
1. After reboot, fully activate the new boot environment
1. Run etcupdate against the host
1. Delete old files and libraries
1. Proclaim update complete!

The script must be run as a super user and will give you 5 seconds to press control-C before beginning downloads.
```shell
# ./freebsd-tarball-update
```

By default, the script uses `/var/db/freebsd-tarball-update` as a work directory.

