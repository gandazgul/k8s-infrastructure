const { spawn: exec, execSync } = require('child_process');
const argv = require('minimist')(process.argv.slice(2));

console.log(argv);

const imageName = argv.image;
if (!imageName) {
    console.error('DOCKER:BUILD', 'Please specify an image name with --image=');
    process.exit(1);
}

const stdio = [process.stdin, process.stdout, process.stderr];
const ioOptions = { detached: true, shell: true, stdio };
const username = execSync('whoami').toString('ascii').trim();
const imageNameLatest = `docker.io/${username}/${imageName}:latest`;

process.on('exit', (code) => {
    if (code !== 0) {
        console.error('CONTAINERS:RUN', `Exiting with exit code: ${code}`);
    }

    console.info('CONTAINERS:RUN', 'Shutting down');
    execSync(`podman stop ${imageName}`, { stdio });
    console.info('CONTAINERS:RUN', 'Shut down complete');
});

process.on('SIGINT', () => {
    process.exit(0);
});

const runCommand = `podman run --rm --name=${imageName} ${imageNameLatest} ${argv._.join(' ')}`;

try {
    console.info('CONTAINERS:RUN', `Running: ${runCommand}`);
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
