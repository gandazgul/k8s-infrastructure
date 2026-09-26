# TeslaMate

TeslaMate 4.2.0 records Tesla drive and charge history in PostgreSQL and serves the project's bundled dashboards from a
dedicated TeslaMate Grafana instance. It reuses the cluster's existing Mosquitto broker and stores durable data under
`configs/teslamate/` on `yasr-volume`, so the existing YASR backup covers its database and Grafana state.

## Access

- Grafana: `https://tesla-grafana.${CLUSTER_DOMAIN_NAME}`
- Grafana administrator password: retrieve it from the reconciled `teslamate-secrets` Secret using an administrative
  terminal; do not copy it into Git or shared chat.
- TeslaMate setup UI: intentionally has no public ingress. After reconciliation, access it from an administrative
  workstation with:

  ```bash
  kubectl -n default port-forward service/teslamate 4000:4000
  ```

  Then browse to `http://127.0.0.1:4000` and enter Owner API access and refresh tokens generated with one of the tools
  documented by TeslaMate.

## Security and operations

- Database, encryption, and Grafana administrator passwords are stored in `teslamate-secrets`, committed only as a
  strict-scope SealedSecret.
- Home Assistant MQTT discovery is disabled initially to avoid duplicate entities during the pilot. TeslaMate still
  publishes its normal MQTT topics.
- The TeslaMate application is kept private because it does not provide front-door authentication. Grafana is exposed
  through TLS and requires its generated administrator password.
- Images are pinned to TeslaMate 4.2.0 and PostgreSQL 18 rather than floating `latest` tags.

After deployment, verify vehicle sleep behavior while both TeslaMate and Home Assistant are connected before treating
the pilot as permanent.
