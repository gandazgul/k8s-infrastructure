# smartthings-mqtt-bridge

![Version: 0.2.1](https://img.shields.io/badge/Version-0.2.1-informational?style=flat-square) ![AppVersion: 3.0.0](https://img.shields.io/badge/AppVersion-3.0.0-informational?style=flat-square)

A Helm chart for the smartthings-mqtt-bridge

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| gandazgul | <ravelo.carlos@gmail.com> |  |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"stjohnjohnson/smartthings-mqtt-bridge"` |  |
| image.tag | string | `"latest"` |  |
| ingress.enabled | bool | `false` |  |
| nameOverride | string | `"smartthings-mqtt-bridge"` |  |
| nodeSelector | object | `{}` |  |
| replicaCount | int | `1` |  |
| resources | object | `{}` |  |
| service.port | int | `8080` |  |
| service.type | string | `"ClusterIP"` |  |
| tolerations | list | `[]` |  |

