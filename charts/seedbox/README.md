# Seedbox Config

This will install a seedbox into k8s using a container that runs OpenVPN, Transmission and flexget.

OpenVPN needs a config and credentials, put your ovpn file in `yasr-volume/configs/openvpn/config.ovpn` and create 
a `credentials.conf` file with the first line being your username and the second line your password.

The config for transmission is generated automatically from the environment variables passed in.

The config for flexget should be in: `yasr-volume/configs/flexget/config.yaml` flexget will also store it's DB there. For my flexget config you can take a look at: https://github.com/gandazgul/flexget_config
