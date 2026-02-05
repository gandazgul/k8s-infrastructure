import fs from 'node:fs';
import path from 'node:path';
import { populate, parse } from 'dotenv';
import { Cloudflare } from "cloudflare";
import { findUp } from "find-up";

// Load environment variables
// cluster name is special, it should be called with it locally or setup manually in the .env file
const clusterName = process.env.CLUSTER_NAME;

if (!clusterName) {
    console.error('Missing required environment variable: CLUSTER_NAME');
    process.exit(1);
}

if (!process.env.CLOUDFLARE_API_EMAIL) {
    const gitIgnore = await findUp('.gitignore');
    const projectDir = path.dirname(gitIgnore);
    const config = parse(fs.readFileSync(path.join(projectDir, 'clusters', clusterName, 'secrets.env'), 'utf8'));
    populate(process.env, config);
}

// all these others come from the secrets.env file for that cluster
const clusterDomain = process.env.CLUSTER_DOMAIN_NAME; // Domain name for the cluster
const apiEmail = process.env.CLOUDFLARE_API_EMAIL; // Cloudflare account email
const apiToken = process.env.CLOUDFLARE_API_TOKEN;
const zoneId = process.env.CLOUDFLARE_ZONE_ID; // Zone ID for the domain

// Get the IP address using multiple fallback services
const ipServices = [
    'https://api.ipify.org',
    'https://icanhazip.com',
    'https://checkip.amazonaws.com',
];

let ipAddress = null;
for (const service of ipServices) {
    try {
        const response = await fetch(service, {
            headers: { 'User-Agent': 'cloudflare-ddns/1.0' }
        });
        if (response.ok) {
            ipAddress = (await response.text()).trim();
            if (/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/.test(ipAddress)) {
                console.log(`Got IP ${ipAddress} from ${service}`);
                break;
            }
        }
    } catch (e) {
        console.warn(`Failed to get IP from ${service}:`, e.message);
    }
    ipAddress = null;
}

if (!ipAddress) {
    console.error('Failed to get public IP from any service');
    process.exit(1);
}

if (!apiEmail || !apiToken || !clusterDomain || !zoneId) {
    console.error('Missing required environment variables (CLOUDFLARE_API_EMAIL, CLOUDFLARE_API_TOKEN, CLUSTER_DOMAIN_NAME, or CLOUDFLARE_ZONE_ID)');
    process.exit(1);
}

// Initialize Cloudflare SDK
const cf = new Cloudflare({
    apiEmail,
    apiToken,
});

try {
    const recordName = `${clusterName}.clusters.${clusterDomain}`;

    // Get the DNS record
    const recordsResponse = await cf.dns.records.list({
        zone_id: zoneId,
    });

    const clusterDDNSRecord = recordsResponse.result.find(record => record.name === recordName);

    // Update the DNS record
    const updateRecordResponse = await cf.dns.records.update(clusterDDNSRecord.id, {
        zone_id: zoneId,
        type: 'A',
        name: recordName,
        content: ipAddress,
        ttl: 120,
    });

    console.log('DNS record created successfully:', updateRecordResponse);
}
catch (error) {
    console.error('Error creating DNS record:', error);
}
