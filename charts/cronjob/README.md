# cronjob

![Version: 0.1.2](https://img.shields.io/badge/Version-0.1.2-informational?style=flat-square) ![AppVersion: 1.0](https://img.shields.io/badge/AppVersion-1.0-informational?style=flat-square)

A Helm chart for creating cron jobs

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| gandazgul | <ravelo.carlos@gmail.com> |  |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| concurrencyPolicy | string | `"Forbid"` |  |
| failedJobsHistoryLimit | int | `1` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"busybox"` |  |
| image.tag | string | `"latest"` |  |
| initContainer.enabled | bool | `false` |  |
| schedule | string | `"*/5 * * * *"` |  |
| successfulJobsHistoryLimit | int | `3` |  |

