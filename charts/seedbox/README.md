# seedbox

A Helm chart for a seedbox that uses alpine-seedbox, OpenVPN, Transmission, Flexget, jackett, sonarr, radarr

![Version: 0.3.2](https://img.shields.io/badge/Version-0.3.2-informational?style=flat-square) ![AppVersion: 1.0](https://img.shields.io/badge/AppVersion-1.0-informational?style=flat-square)

# Seedbox Config

This will install a seedbox into k8s using a container that runs OpenVPN, Transmission, Sonarr, Radarr and flexget.

OpenVPN needs a config and credentials, put your ovpn file in `yasr-volume/configs/openvpn/vpn.conf` and create
a `credentials.conf` file with the first line being your username and the second line your password.

The config for transmission is generated automatically the first time and then can be customized from Transmission UI.
If you need to modify settings.json manually remember to scale the deployment to 0 first (to delete the pod)
then scale back to 1 after modifying settings otherwise transmission oveerides your changes when it shuts down.

The config for flexget should be in: `yasr-volume/configs/flexget/config.yaml` flexget will also store it's DB there.
For my flexget config you can take a look at: https://github.com/gandazgul/flexget_config

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| dnsConfig.nameservers[0] | string | `"8.8.8.8"` |  |
| dnsConfig.nameservers[1] | string | `"8.8.4.4"` |  |
| dnsPolicy | string | `"None"` |  |
| flexget.enabled | bool | `false` |  |
| flexget.image.name | string | `"wiserain/flexget"` |  |
| flexget.image.pullPolicy | string | `"IfNotPresent"` |  |
| flexget.image.tag | string | `"3.1.21"` |  |
| flexget.ingress.enabled | bool | `false` |  |
| flexget.name | string | `"flexget"` |  |
| flexget.resources.limits.cpu | string | `"500m"` |  |
| flexget.resources.limits.memory | string | `"1000Mi"` |  |
| flexget.resources.requests.cpu | string | `"100m"` |  |
| flexget.resources.requests.memory | string | `"100Mi"` |  |
| flexget.service.port | int | `3539` |  |
| flexget.service.type | string | `"ClusterIP"` |  |
| flexget.volumeMounts[0].mountPath | string | `"/config"` |  |
| flexget.volumeMounts[0].name | string | `"yasr-volume"` |  |
| flexget.volumeMounts[0].subPath | string | `"configs/flexget"` |  |
| flexget.volumeMounts[1].mountPath | string | `"/main"` |  |
| flexget.volumeMounts[1].name | string | `"main-volume"` |  |
| flexget.volumeMounts[2].mountPath | string | `"/data"` |  |
| flexget.volumeMounts[2].name | string | `"yasr-volume"` |  |
| flexget.volumeMounts[2].subPath | string | `"configs/transmission"` |  |
| flexget.volumeMounts[3].mountPath | string | `"/etc/localtime"` |  |
| flexget.volumeMounts[3].name | string | `"tz-config"` |  |
| flexget.volumeMounts[3].readOnly | bool | `true` |  |
| jackett.enabled | bool | `true` |  |
| jackett.image.name | string | `"linuxserver/jackett"` |  |
| jackett.image.pullPolicy | string | `"Always"` |  |
| jackett.image.tag | string | `"amd64-latest"` |  |
| jackett.ingress.enabled | bool | `false` |  |
| jackett.name | string | `"jackett"` |  |
| jackett.resources.limits.cpu | string | `"500m"` |  |
| jackett.resources.limits.memory | string | `"1000Mi"` |  |
| jackett.resources.requests.cpu | string | `"100m"` |  |
| jackett.resources.requests.memory | string | `"100Mi"` |  |
| jackett.service.port | int | `9117` |  |
| jackett.service.type | string | `"ClusterIP"` |  |
| jackett.volumeMounts[0].mountPath | string | `"/config"` |  |
| jackett.volumeMounts[0].name | string | `"yasr-volume"` |  |
| jackett.volumeMounts[0].subPath | string | `"configs/jackett"` |  |
| jackett.volumeMounts[1].mountPath | string | `"/downloads"` |  |
| jackett.volumeMounts[1].name | string | `"yasr-volume"` |  |
| jackett.volumeMounts[1].subPath | string | `"configs/jackett/downloads"` |  |
| jackett.volumeMounts[2].mountPath | string | `"/etc/localtime"` |  |
| jackett.volumeMounts[2].name | string | `"tz-config"` |  |
| jackett.volumeMounts[2].readOnly | bool | `true` |  |
| nodeSelector | object | `{}` |  |
| radarr.enabled | bool | `true` |  |
| radarr.env[0].name | string | `"PUID"` |  |
| radarr.env[0].value | string | `"1000"` |  |
| radarr.env[1].name | string | `"PGID"` |  |
| radarr.env[1].value | string | `"1000"` |  |
| radarr.image.name | string | `"linuxserver/radarr"` |  |
| radarr.image.pullPolicy | string | `"Always"` |  |
| radarr.image.tag | string | `"amd64-latest"` |  |
| radarr.ingress.enabled | bool | `false` |  |
| radarr.name | string | `"radarr"` |  |
| radarr.resources.limits.cpu | string | `"1000m"` |  |
| radarr.resources.limits.memory | string | `"2000Mi"` |  |
| radarr.resources.requests.cpu | string | `"100m"` |  |
| radarr.resources.requests.memory | string | `"100Mi"` |  |
| radarr.service.port | int | `7878` |  |
| radarr.service.type | string | `"ClusterIP"` |  |
| replicaCount | int | `1` |  |
| sonarr.enabled | bool | `true` |  |
| sonarr.env[0].name | string | `"PUID"` |  |
| sonarr.env[0].value | string | `"1000"` |  |
| sonarr.env[1].name | string | `"PGID"` |  |
| sonarr.env[1].value | string | `"1000"` |  |
| sonarr.image.name | string | `"linuxserver/sonarr"` |  |
| sonarr.image.pullPolicy | string | `"Always"` |  |
| sonarr.image.tag | string | `"amd64-latest"` |  |
| sonarr.ingress.enabled | bool | `false` |  |
| sonarr.name | string | `"sonarr"` |  |
| sonarr.resources.limits.cpu | string | `"1000m"` |  |
| sonarr.resources.limits.memory | string | `"2000Mi"` |  |
| sonarr.resources.requests.cpu | string | `"100m"` |  |
| sonarr.resources.requests.memory | string | `"100Mi"` |  |
| sonarr.service.port | int | `8989` |  |
| sonarr.service.type | string | `"ClusterIP"` |  |
| tolerations | list | `[]` |  |
| transmission.env[0].name | string | `"PGID"` |  |
| transmission.env[0].value | string | `"1000"` |  |
| transmission.env[1].name | string | `"PUID"` |  |
| transmission.env[1].value | string | `"1000"` |  |
| transmission.env[2].name | string | `"TZ"` |  |
| transmission.env[2].value | string | `"America/New_York"` |  |
| transmission.image.name | string | `"linuxserver/transmission"` |  |
| transmission.image.pullPolicy | string | `"Always"` |  |
| transmission.image.tag | string | `"latest"` |  |
| transmission.ingress.enabled | bool | `false` |  |
| transmission.name | string | `"transmission"` |  |
| transmission.resources.limits.cpu | string | `"1000m"` |  |
| transmission.resources.limits.memory | string | `"2000Mi"` |  |
| transmission.resources.requests.cpu | string | `"100m"` |  |
| transmission.resources.requests.memory | string | `"100Mi"` |  |
| transmission.service.additionalPorts[0].name | string | `"51413-tcp"` |  |
| transmission.service.additionalPorts[0].port | int | `51413` |  |
| transmission.service.additionalPorts[0].protocol | string | `"TCP"` |  |
| transmission.service.additionalPorts[1].name | string | `"51412-udp"` |  |
| transmission.service.additionalPorts[1].port | int | `51413` |  |
| transmission.service.additionalPorts[1].protocol | string | `"UDP"` |  |
| transmission.service.port | int | `9091` |  |
| transmission.service.portName | string | `"9091-tcp"` |  |
| transmission.service.protocol | string | `"TCP"` |  |
| transmission.service.type | string | `"ClusterIP"` |  |
| transmission.volumeMounts[0].mountPath | string | `"/data"` |  |
| transmission.volumeMounts[0].name | string | `"yasr-volume"` |  |
| transmission.volumeMounts[0].subPath | string | `"configs/transmission"` |  |
| transmission.volumeMounts[1].mountPath | string | `"/config"` |  |
| transmission.volumeMounts[1].name | string | `"yasr-volume"` |  |
| transmission.volumeMounts[1].subPath | string | `"configs/transmission"` |  |
| transmission.volumeMounts[2].mountPath | string | `"/watch"` |  |
| transmission.volumeMounts[2].name | string | `"yasr-volume"` |  |
| transmission.volumeMounts[2].subPath | string | `"configs/transmission/watch"` |  |
| transmission.volumeMounts[3].mountPath | string | `"/etc/localtime"` |  |
| transmission.volumeMounts[3].name | string | `"tz-config"` |  |
| transmission.volumeMounts[3].readOnly | bool | `true` |  |
| volumes[0].name | string | `"yasr-volume"` |  |
| volumes[0].persistentVolumeClaim.claimName | string | `"yasr-volume"` |  |
| volumes[1].name | string | `"main-volume"` |  |
| volumes[1].persistentVolumeClaim.claimName | string | `"main-volume"` |  |
| volumes[2].hostPath.path | string | `"/dev/net/tun"` |  |
| volumes[2].name | string | `"dev-tun"` |  |
| volumes[3].hostPath.path | string | `"/etc/localtime"` |  |
| volumes[3].name | string | `"tz-config"` |  |
| vpn.image.name | string | `"qmcgaw/private-internet-access"` |  |
| vpn.image.pullPolicy | string | `"IfNotPresent"` |  |
| vpn.image.tag | string | `"v3.8.0"` |  |
| vpn.name | string | `"vpn"` |  |
| vpn.resources.limits.cpu | string | `"500m"` |  |
| vpn.resources.limits.memory | string | `"100Mi"` |  |
| vpn.resources.requests.cpu | string | `"100m"` |  |
| vpn.resources.requests.memory | string | `"100Mi"` |  |
| vpn.volumeMounts[0].mountPath | string | `"/vpn"` |  |
| vpn.volumeMounts[0].name | string | `"yasr-volume"` |  |
| vpn.volumeMounts[0].subPath | string | `"configs/openvpn"` |  |
| vpn.volumeMounts[1].mountPath | string | `"/dev/net/tun"` |  |
| vpn.volumeMounts[1].name | string | `"dev-tun"` |  |
| vpn.volumeMounts[2].mountPath | string | `"/etc/localtime"` |  |
| vpn.volumeMounts[2].name | string | `"tz-config"` |  |
| vpn.volumeMounts[2].readOnly | bool | `true` |  |
| vpn.volumeMounts[3].mountPath | string | `"/tmp/gluetun/"` |  |
| vpn.volumeMounts[3].name | string | `"yasr-volume"` |  |
| vpn.volumeMounts[3].subPath | string | `"configs/transmission/"` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.4.0](https://github.com/norwoodj/helm-docs/releases/v1.4.0)
