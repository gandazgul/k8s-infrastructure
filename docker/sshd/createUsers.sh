#!/bin/sh

for line in $(cat ./users.conf)
do
    username=`echo "$line" | awk -F: '{print $1}'`
    uid=`echo "$line" | awk -F: '{print $2}'`
    members=`echo "$line" | awk -F: '{print $3}'`

    if [ ! -z "$members" ]; then
        echo "Found group $username:$uid:$members"

        addgroup -g ${uid} ${username}

        OLDIFS=$IFS
        IFS=,
        for member in ${members}
        do
            addgroup ${member} ${username}
        done
        IFS=${OLDIFS}
    else
        echo "Found user $username:$uid"

        adduser -D -H -s /bin/bash -u ${uid} ${username}
        passwd -u ${username}
        addgroup ${username} wheel
    fi;
done
