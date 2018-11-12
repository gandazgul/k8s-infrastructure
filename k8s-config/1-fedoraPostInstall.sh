#!/bin/bash

printf "Upgrade =====================================================================================================\n"
sudo dnf -y update || exit 1

printf "Install screen, and other tools =============================================================================\n"
sudo dnf -y install screen htop git p7zip rdiff-backup
# unrar is not on the repos
sudo dnf install http://download1.rpmfusion.org/nonfree/fedora/releases/28/Everything/x86_64/os/Packages/u/unrar-5.6.2-1.fc28.x86_64.rpm

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

# addgroup public
# adduser rafag 1004, renepor 1003

# Restore plex backups
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
