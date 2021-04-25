#!/bin/bash

# Might as well ask for password up-front, right?
sudo -v

# Keep-alive: update existing sudo time stamp if set, otherwise do nothing.
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

printf "Upgrade =====================================================================================================\n"
sudo dnf -y update || exit 1

printf "Install screen, and other tools =============================================================================\n"
sudo dnf -y install screen htop git p7zip rdiff-backup fail2ban

printf "Setting up fail2ban for sshd ================================================================================\n"
sudo cp ./jail.local /etc/fail2ban/jail.local
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd

echo -n "Do you wish to setup the HDD mounts? (y/n)? "
read answer
if [ "$answer" != "${answer#[Yy]}" ] ;then
    sudo mkdir /media/main
    sudo mkdir /media/backup
    sudo mkdir /media/yasr

    printf '\n# **** My Mounts ****' | sudo tee -a /etc/fstab
    printf "\n\nLABEL=MAINDISK /media/main auto defaults 0 3" | sudo tee -a /etc/fstab
    printf "\nLABEL=BACKUPDISK /media/backup auto defaults 0 3" | sudo tee -a /etc/fstab
    printf "\nLABEL=YASRDISK /media/yasr auto defaults 0 3" | sudo tee -a /etc/fstab

    sudo mount /media/main
    sudo mount /media/backup
    sudo mount /media/yasr
else
    echo No
fi

echo "%wheel ALL=(ALL) NOPASSWD:ALL" | sudo tee --append /etc/sudoers

# TODO:
# addgroup public
# adduser rafag 1004, renepor 1003

# TODO Restore plex backups
#/media/main/plex_db_backup$ sudo cp com.plexapp.plugins.library.blobs.db-2018-09-28 /media/yasr/configs/plex/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/com.plexapp.plugins.library.blobs.db
#gandazgul@k8s:/media/main/plex_db_backup$ sudo cp com.plexapp.plugins.trakttv.db /media/yasr/configs/plex/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/
#gandazgul@k8s:/media/main/plex_db_backup$ sudo cp com.plexapp.plugins.library.db-2018-09-28 /media/yasr/configs/plex/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/com.plexapp.plugins.library.db
#gandazgul@k8s:/media/main/plex_db_backup$ sudo rm  /media/yasr/configs/plex/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/com.plexapp.plugins.library.blobs.db-*
#gandazgul@k8s:/media/main/plex_db_backup$ sudo rm  /media/yasr/configs/plex/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/com.plexapp.plugins.library.db-*
#gandazgul@k8s:/media/main/plex_db_backup$ sudo rm  /media/yasr/configs/plex/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/com.plexapp.
#com.plexapp.dlna.db                   com.plexapp.dlna.db-wal               com.plexapp.plugins.library.db        com.plexapp.plugins.trakttv.db-shm
#com.plexapp.dlna.db-shm               com.plexapp.plugins.library.blobs.db  com.plexapp.plugins.trakttv.db        com.plexapp.plugins.trakttv.db-wal
#gandazgul@k8s:/media/main/plex_db_backup$ sudo rm  /media/yasr/configs/plex/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/com.plexapp.
#com.plexapp.dlna.db                   com.plexapp.dlna.db-wal               com.plexapp.plugins.library.db        com.plexapp.plugins.trakttv.db-shm
#com.plexapp.dlna.db-shm               com.plexapp.plugins.library.blobs.db  com.plexapp.plugins.trakttv.db        com.plexapp.plugins.trakttv.db-wal
#gandazgul@k8s:/media/main/plex_db_backup$ sudo rm  /media/yasr/configs/plex/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/com.plexapp.
#com.plexapp.dlna.db                   com.plexapp.dlna.db-wal               com.plexapp.plugins.library.db        com.plexapp.plugins.trakttv.db-shm
#com.plexapp.dlna.db-shm               com.plexapp.plugins.library.blobs.db  com.plexapp.plugins.trakttv.db        com.plexapp.plugins.trakttv.db-wal
#gandazgul@k8s:/media/main/plex_db_backup$ sudo rm  /media/yasr/configs/plex/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/com.plexapp.
#com.plexapp.dlna.db                   com.plexapp.dlna.db-wal               com.plexapp.plugins.library.db        com.plexapp.plugins.trakttv.db-shm
#com.plexapp.dlna.db-shm               com.plexapp.plugins.library.blobs.db  com.plexapp.plugins.trakttv.db        com.plexapp.plugins.trakttv.db-wal
#gandazgul@k8s:/media/main/plex_db_backup$ sudo rm  /media/yasr/configs/plex/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/com.plexapp.plugins.trakttv.db-
#com.plexapp.plugins.trakttv.db-shm  com.plexapp.plugins.trakttv.db-wal
#gandazgul@k8s:/media/main/plex_db_backup$ sudo rm  /media/yasr/configs/plex/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/com.plexapp.plugins.trakttv.db-*
#gandazgul@k8s:/media/main/plex_db_backup$
