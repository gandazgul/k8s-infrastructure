const execSync = require('child_process').execSync;
// const logger = require('../src/api/logger');
const logger = console;
logger.warning = console.warn;
const argv = require('minimist')(process.argv.slice(2));

const imageName = argv.image;
if (!imageName) {
    logger.error('DOCKER:BUILD', 'Please specify an image name with --image=');
    process.exit(1);
}

try {
    process.chdir(`docker/${imageName}`);

    console.log(`New directory: ${process.cwd()}`);
}
catch (err) {
    logger.error('DOCKER:BUILD', 'Chdir failed', err);
}

const ioOptions = { stdio: [process.stdin, process.stdout, process.stderr] };

const username = execSync('whoami').toString('ascii').trim();
const version = execSync('git log -n 1 --pretty=format:%h').toString('ascii').trim();
const dockerImageName = `${username}/${imageName}:v${version}`;
const dockerImageNameLatest = `${username}/${imageName}:latest`;

function run() {
    if (argv.force) {
        build();
    }
    else {
        logger.info('DOCKER:BUILD', `Checking docker image: ${dockerImageName}...`);

        const imageID = execSync(`docker images -q ${dockerImageName}`).toString();

        if (!imageID) {
            build();
        }
        else {
            logger.warning(
                'DOCKER:BUILD',
                'The tag already exists, commit something first to build new image or run with --force.'
            );
        }
    }
}

function build() {
    // Build and then tag the docker image with the current version AND "latest"
    const dockerBuildCommand = `docker build -t docker.io/${dockerImageName} -t docker.io/${dockerImageNameLatest} .`;
    const pushCommand = `docker push docker.io/${dockerImageName}`;
    const pushCommandLatest = `docker push docker.io/${dockerImageNameLatest}`;

    try {
        logger.info('DOCKER:BUILD', `Running: ${dockerBuildCommand}`);
        execSync(dockerBuildCommand, ioOptions);
        logger.info('DOCKER:BUILD', `Running: ${pushCommand}`);
        execSync(pushCommand, ioOptions);
        logger.info('DOCKER:BUILD', `Running: ${pushCommandLatest}`);
        execSync(pushCommandLatest, ioOptions);
    }
    catch (err) {
        logger.error('DOCKER:BUILD', 'A fatal error has occurred.', err.message);
        process.exit(1);
    }
}

run();
