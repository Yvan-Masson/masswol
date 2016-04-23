# masswol.sh
Simple shell script to boot, check and shutdown many remote computers.

A typical use case: as a sysadmin I want to boot many computers using
Wake on LAN. After waiting two minutes, I want to check that they are
all running. I then do my sysadmin stuff. Finally, I want them to
shutdown.

If you router is well configured, the script is able to boot computers
that are behind it.

For more details, read the beginning of the script or run it without
argument to show the help.

*Notes*:
- Be carefull with the "shutdown" feature: other users, connected on the
computer you are using, can read your password. The script should
better be adapted to handle SSH keys, but I do not plan to do it now.
- There are probably many bugs: do not expect high quality





