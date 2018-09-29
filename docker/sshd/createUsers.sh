#!/bin/sh

for line in $(cat ./users.conf)
do
    username=`echo "$line" | awk -F: '{print $1}'`
    uid=`echo "$line" | awk -F: '{print $2}'`
    gid=`echo "$line" | awk -F: '{print $3}'`
    members=`echo "$line" | awk -F: '{print $4}'`

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

        addgroup -g ${gid} ${username}
        adduser -D -H -s /bin/bash -u ${uid} -G ${username} ${username}
#        wget https://github.com/${username}.keys
#        if [ -f ${username}.keys ]; then
#            mkdir /home/${username}/.ssh/
#            cp ${username}.keys /home/${username}/.ssh/authorized_keys
#            rm -f ${username}.keys
#            chown -R ${username}:${username} /home/${username}/.ssh/
#            chmod 700 /home/${username}/.ssh
#            chmod 600 /home/${username}/.ssh/authorized_keys
#        fi;
        passwd -u ${username}
        addgroup ${username} wheel
    fi;
done
