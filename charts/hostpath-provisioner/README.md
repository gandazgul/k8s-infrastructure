# hostpath-provisioner

![Version: 0.2.2](https://img.shields.io/badge/Version-0.2.2-informational?style=flat-square)

A chart to install a storage provisioner for single node installs.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| gandazgul | <ravelo.carlos@gmail.com> |  |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| filesystemPath | string | `"/var/kubernetes"` |  |
| image.pullPolicy | string | `"Always"` |  |
| image.repository | string | `"quay.io/kubevirt/hostpath-provisioner"` |  |
| image.tag | string | `"latest"` |  |
| nodeSelector | object | `{}` |  |
| pvReclaimPolicy | string | `"Retain"` |  |
| replicaCount | int | `1` |  |
| resources | object | `{}` |  |
| tolerations | list | `[]` |  |

