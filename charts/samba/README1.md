# Samba Helm Chart

This container will mount any number of volumes you configure to it. You can main /etc/samba to override its config, 
if you want to use the default's or don't want to deal with configs then read the container's author's README @ https://github.com/dperson/samba.

## Users and Passwords

To get a smbpasswd file run this on your current samba installation:
`sudo pdbedit -Lw`

If you need to install samba on a linux vm/machine and run `pdbedit --create -u testuser` it will ask you for a 
password and add it to the DB, then you can run the command above to export it in smbpasswd format

To import this file, put it alongside your config (or somewhere else that will be mounted on the container) and set this environment variable:
env:
  - name: IMPORT
    value: "/etc/samba/smbpasswd"

## Access

hostNetwork is set to true by default this will make samba available on the node where its running. (Perhaps I should allow affinity to be set as well)

You can also turn this off and samba then will only be available within the cluster to other pods.

## Example config:

```
[global]
    workgroup = WORKGROUP
    os level = 20
    load printers = no
    disable spoolss = yes
    unix password sync = no
    mangled names = no

[ShareName]
    writeable = yes
    force directory mode = 775
    directory mode = 775
    force group = [group here]
    force user = root
    delete readonly = yes
    path = /shared/path/to/folder
    force create mode = 664
    create mode = 664
    available = yes
    browsable = yes
    public = yes

[HomeFolder]
    force user = testuser
    force group = testuser
    writeable = yes
    create mode = 664
    directory mode = 775
    path = /shared/testuser
```
