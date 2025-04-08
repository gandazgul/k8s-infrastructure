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

if (!process.env.EMAIL) {
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

// Get the IP address
const response = await fetch('https://ifconfig.co/ip');
const responseText = await response.text();
const ipAddress = responseText.toString().replace('\n', '').trim();

if (
    !apiEmail ||
    !apiToken ||
    !clusterDomain ||
    !zoneId ||
    !ipAddress
) {
    console.error('Missing required environment variables.');
    process.exit(1);
}

if (!/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/.test(ipAddress)) {
    console.error('IP response from ifconfig.co is not a valid IP address: ', ipAddress);
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
