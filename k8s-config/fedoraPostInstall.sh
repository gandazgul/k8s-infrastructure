#!/bin/bash

sudo dnf -y install screen htop git

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
