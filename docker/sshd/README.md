# SSHD Server

To create your own:

1. Copy users.example.conf into users.conf and customize. The format of each line is: `user_name:uid:gid`.
    You can also create groups, `group_name:gid::comma,separated,user,list`. On the group format note the double colons
    between gid and the user list
2. Run `docker build -t docker.io/[USERNAME]/sshd:latest -t docker.io/[USERNAME]/sshd:v1 .` to build the container.
3. Run `docker push [USERNAME]/sshd:v1 && docker push [USERNAME]/sshd:latest` to push your container to the hub
4. By default the createUsers.sh script doesnt create passwords, mount a volume into /home to get the user's homes with 
    authorized_keys. 
