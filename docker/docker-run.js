const exec = require('child_process').spawn;
const execSync = require('child_process').execSync;
// const logger = require('../src/api/logger');
const logger = console;
logger.warning = console.warn;
const argv = require('minimist')(process.argv.slice(2));

console.log(argv);

// TODO: each docker folder can export a manifest of their params, docker-compose file?

const imageName = argv.image;
if (!imageName) {
    logger.error('DOCKER:BUILD', 'Please specify an image name with --image=');
    process.exit(1);
}

const stdio = [process.stdin, process.stdout, process.stderr];
const ioOptions = { detached: true, shell: true, stdio };
const username = execSync('whoami').toString('ascii').trim();
const dockerImageNameLatest = `${username}/${imageName}:latest`;

process.on('exit', (code) => {
    if (code !== 0) {
        logger.error('DOCKER:RUN', `Exiting with exit code: ${code}`);
    }

    logger.info('DOCKER:RUN', 'Shutting down');
    execSync(`docker stop ${imageName}`, { stdio });
    logger.info('DOCKER:RUN', 'Shut down complete');
});

process.on('SIGINT', () => {
    process.exit(0);
});

const runCommand = `docker run --rm --name=${imageName} ${argv._.join(' ')} docker.io/${dockerImageNameLatest}`;

try {
    logger.info('DOCKER:RUN', `Running: ${runCommand}`);
    exec(runCommand, ioOptions);
}
catch (error) {
    console.error('ERROR!');
    console.error(error.status);

    if (error.status > 0) {
        console.error('A fatal error has occurred.');
        console.error(error.message);
        process.exit(1);
    }
}
