import { execSync } from 'node:child_process';
import fs from 'node:fs';
import * as k8s from '@kubernetes/client-node';

const PVC_NAME = process.env.PVC_NAME || 'immich-postgres-1';
const NAMESPACE = process.env.NAMESPACE || 'default';
const SOURCE_BASE = process.env.SOURCE_BASE || '/var/kubernetes';
const BACKUP_DEST = process.env.BACKUP_DEST || '/media/backup';

async function main() {
    // Configure the K8s client
    const kc = new k8s.KubeConfig();

    try {
        kc.loadFromCluster();

        console.log('Loaded in-cluster K8s config');
    }
    catch {
        kc.loadFromDefault();

        console.log('Loaded default K8s config (local dev)');
    }

    const coreApi = kc.makeApiClient(k8s.CoreV1Api);

    // Find the PVC
    console.log(`Looking for PVC "${PVC_NAME}" in namespace "${NAMESPACE}"...`);

    const pvcResponse = await coreApi.readNamespacedPersistentVolumeClaim({
        name: PVC_NAME,
        namespace: NAMESPACE,
    });

    const pvName = pvcResponse.spec?.volumeName;

    if (!pvName) {
        console.error(`PVC "${PVC_NAME}" has no bound volume (spec.volumeName is empty).`);
        process.exit(1);
    }

    console.log(`PVC "${PVC_NAME}" is bound to PV "${pvName}"`);

    // Construct the source path
    const sourcePath = `${SOURCE_BASE}/${PVC_NAME}-${pvName}`;

    if (!fs.existsSync(sourcePath)) {
        console.error(`Source folder does not exist: ${sourcePath}`);
        process.exit(1);
    }

    console.log(`Source folder found: ${sourcePath}`);
    console.log(`Backup destination: ${BACKUP_DEST}`);

    // Run rsync
    const rsyncCommand = `rsync -havurz --delete "${sourcePath}/" "${BACKUP_DEST}/"`;
    console.log(`Running: ${rsyncCommand}`);

    try {
        execSync(rsyncCommand, { stdio: [process.stdin, process.stdout, process.stderr] });
        execSync(`chmod 750 "${BACKUP_DEST}"`, { stdio: [process.stdin, process.stdout, process.stderr] });

        console.log('Backup completed successfully.');
    }
    catch (err) {
        console.error('rsync failed:', err.message);
        process.exit(1);
    }
}

main().catch((err) => {
    console.error('Fatal error:', err);
    process.exit(1);
});
