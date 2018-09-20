#!/bin/sh

if [ ! -f /etc/ssmtp/ssmtp.conf ]; then
    echo "There's no config to send emails"
    exit 1
fi

if [ -z "$MAIL_TO" ]; then
    echo "You have to specify MAIL_TO environment var with the email to send alerts to"
    exit 1
fi

# if df | grep /hdd outputs more then one line something is not right with this script
if [ `df | grep /hdd | wc -l` -gt 1 ]; then
    echo "'df | grep /hdd' output was more than one line. Someone should take a look."

    DF_OUTPUT=`df | grep /hdd`

    # send email
    printf "To:$MAIL_TO" >> /tmp/mail.txt
    printf "From:<Size Checker at k8s> $MAIL_TO" >> /tmp/mail.txt
    printf "Subject:Size checker: df output had more than 1 line\n\n" >> /tmp/mail.txt
    printf "Please check size-checker, df output was too long. $DF_OUTPUT" >> /tmp/mail.txt

    ssmtp -t < /tmp/mail.txt

    exit 1
fi

# Get used space in KB:
NEW_SIZE=`df | grep /hdd | awk -F' ' '{gsub(/[ \t]+$/, "", $2); print $3}'`

if [ -f /hdd/size.txt ]; then
    # Get previous space number (in KB)
    PREV_SIZE=`cat /hdd/size.txt`
else
    # first run
    PREV_SIZE=${NEW_SIZE}
fi

#Compare with prev
if [ $(( PREV_SIZE - NEW_SIZE )) -gt 5242880 ]; then
    HUMAN_PREV_SIZE=$(( PREV_SIZE / 1024 / 1024 ))
    HUMAN_NEW_SIZE=$(( NEW_SIZE / 1024 / 1024 ))

    #sound the alarm
    echo "Something is wrong, HDD size went down more than 5G. Old size: ${HUMAN_PREV_SIZE}G -> New size: ${HUMAN_NEW_SIZE}G"

    printf "To:$MAIL_TO" >> /tmp/mail.txt
    printf "From:<Size Checker at k8s> $MAIL_TO" >> /tmp/mail.txt
    printf "Subject:Size checker: HDD size decreased more than 5G\n\n" >> /tmp/mail.txt
    printf "Please check what happened to the HDD. Old size: ${HUMAN_PREV_SIZE}G -> New size: ${HUMAN_NEW_SIZE}G." >> /tmp/mail.txt

    ssmtp -t < /tmp/mail.txt

    #stop backups?
fi

# Save new size
echo "$NEW_SIZE" > /hdd/size.txt
