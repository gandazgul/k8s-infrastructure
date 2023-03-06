const { execSync } = require('child_process');
const argv = require('minimist')(process.argv.slice(2));

const imageName = argv.image;
if (!imageName) {
    console.error('CONTAINER:BUILD', 'Please specify an image name with --image=');
    process.exit(1);
}

try {
    process.chdir(`containers/${imageName}`);

    console.log(`New directory: ${process.cwd()}`);
}
catch (err) {
    console.error('CONTAINER:BUILD', 'Chdir failed', err);
}

const ioOptions = { stdio: [process.stdin, process.stdout, process.stderr] };

const username = execSync('whoami').toString('ascii').trim();
const version = execSync('git log -n 1 --pretty=format:%h').toString('ascii').trim();
const fullImageName = `docker.io/${username}/${imageName}:v${version}`;
const imageNameLatest = `docker.io/${username}/${imageName}:latest`;

function run() {
    if (argv.force) {
        build();
    }
    else {
        console.info('CONTAINER:BUILD', `Checking image: ${fullImageName}...`);

        const imageID = execSync(`podman images -q ${fullImageName}`).toString();

        if (!imageID) {
            build();
        }
        else {
            console.warn('CONTAINER:BUILD', 'The tag already exists, commit something first to build new image or run with --force.');
        }
    }
}

function build() {
    // Build and then tag the image with the current version AND "latest"
    const loginCommand = `podman login --username=${username} docker.io`
    const buildCommand = `podman build -t ${fullImageName} -t ${imageNameLatest} .`;
    const pushCommand = `podman push ${fullImageName}`;
    const pushCommandLatest = `podman push ${imageNameLatest}`;

    try {
        console.info('CONTAINER:BUILD', `Running: ${buildCommand}`);
        execSync(buildCommand, ioOptions);
        console.info('CONTAINER:BUILD', `Running: ${loginCommand}`);
        execSync(loginCommand, ioOptions);
        console.info('CONTAINER:BUILD', `Running: ${pushCommand}`);
        execSync(pushCommand, ioOptions);
        console.info('CONTAINER:BUILD', `Running: ${pushCommandLatest}`);
        execSync(pushCommandLatest, ioOptions);
    }
    catch (err) {
        console.error('CONTAINER:BUILD', 'A fatal error has occurred.', err.message);
        process.exit(1);
    }
}

run();
