# Agent Instructions: k8s-infrastructure

This file provides comprehensive guidelines for AI coding agents operating within this GitOps repository. This
repository utilizes Flux v2 for Kubernetes deployment alongside Node.js-based container tooling. Agents must read and
adhere to these rules when analyzing, modifying, or creating code in this project.

## 1. Build, Lint, and Test Commands

### 1.1 Linting

The codebase relies on `pre-commit` hooks for validation. Agent tasks should ensure code passes these pre-commit checks
before completing operations.

- **Run all pre-commit hooks:**
  ```bash
  pre-commit run --all-files
  ```
- **Lint a specific file:**
  ```bash
  pre-commit run --files path/to/file.yaml
  ```
- **YAML specific linting (recommended prior to committing):**
  ```bash
  yamllint path/to/file.yaml
  ```

If formatting errors occur, rely on `end-of-file-fixer` and `trailing-whitespace` automatic corrections by running the
hook again.

### 1.2 Container Builds

Custom Docker containers reside under the `containers/` directory and use Node.js scripts for orchestration. Always run
`npm install` in the project root if packages are missing.

- **Build a specific image:**
  ```bash
  node containers/container-build.js --image=<directory-name>
  ```
- **Run a specific image locally:**
  ```bash
  node containers/container-run.js --image=<directory-name>
  ```

### 1.3 Testing and Validation

Currently, the codebase does not utilize an automated programmatic test suite (like Jest or Go tests). Testing is
achieved by statically validating Kubernetes YAML manifests and ensuring Bash/JS scripts execute cleanly.

- **Dry-run a single Kubernetes manifest:**
  ```bash
  kubectl apply --dry-run=client -f path/to/manifest.yaml
  ```
- **Validate Flux Kustomizations:**
  ```bash
  kustomize build path/to/directory
  ```
- **Testing Container Scripts:** Run the build/run scripts on sample directories and ensure they return an exit code
  `0`. Implement `process.exit(1)` on errors for any new utility scripts to ensure pipelines fail securely.

## 2. Code Style Guidelines

### 2.1 Kubernetes & Flux Manifests (YAML)

- **Formatting:** Strictly 2 spaces for indentation. Never use tabs. Arrays should be aligned with their parent keys.
- **Document Separation:** Always use `---` to separate multiple Kubernetes objects within the same `.yaml` file.
- **Naming Conventions:**
    - Standard Kubernetes resources (deployments, services, PVCs) and namespaces should use `lower-kebab-case`.
    - App definition files inside the `apps/` directory currently use `PascalCase.yaml` (e.g., `HomeAssistant.yaml`,
      `Paperless.yaml`). Adhere to this convention for new app manifests to maintain consistency.
    - Core infrastructure files generally use `PascalCase`, although some folders are using kebab-case. New files should
      follow `PascalCase`.
- **Flux Architecture Conventions:**
    - **Applications:** Deployments go in the `apps/` directory and should primarily utilize the apps/generic deployment
      configured as an overlay. If an official helm chart exists then use a `HelmRelease` kind. Group `HelmRepository`
      definitions at the top of the file if they don't already exist globally.
    - **Infrastructure:** Core infrastructure belongs in `infrastructure/` and its subdirectories (like `kube-system/`,
      `monitoring/`, etc.).
    - **Storage:** Avoid using `emptyDir` for application data that requires persistence. This cluster heavily utilizes
      hostpath provisions mapping to the local "YASR" volume structure. Reference
      `infrastructure/storage/hostpath-provisioner/README.md`.

### 2.2 JavaScript (Container Build Tools)

- **Environment:** Node.js CommonJS format (use `const module = require('module')`, do not use ES6 `import`).
- **Formatting:**
    - Use 4 spaces for indentation inside `.js` files.
    - add `else`, `catch`, and `finally` blocks on new lines for better readability.
    - Add a new line before return statements and before control flow statements (`if`, `for`, `while`).
- **Naming:**
    - Use `camelCase` for variables and function names (`imageName`, `fullImageName`).
    - Use `UPPER_SNAKE_CASE` for global constants or environment toggles.
- **Error Handling:** Use `try...catch` blocks for system or shell operations (`execSync`, `process.chdir`). Ensure
  error logs are well-prefixed with the context. Example:
  ```javascript
  try {
      process.chdir(`containers/${imageName}`);
  }
  catch (err) {
      console.error('CONTAINER:BUILD', 'Chdir failed', err);
      process.exit(1);
  }
  ```
- **Dependencies:** Keep external dependencies to an absolute minimum. Use native `child_process` and `fs` modules where
  possible. Currently, `minimist` is the only argument parser.

### 2.3 Shell Scripts (.sh)

- **Shebang:** Always start with `#!/bin/bash`.
- **Variables:** Use curly braces for variables to prevent expansion errors (e.g., `${VARIABLE}`).
- **Safety:** Use `set -e` at the top of scripts to ensure they fail fast on error.
- **Paths:** Keep shell script footprints minimal; use exact paths or rely on `process.cwd()` consistency when scripts
  are invoked from the root.

## 3. Security and Secrets Management

- **No Raw Secrets:** Never commit raw passwords, database connection strings, tokens, or sensitive API keys to the
  repository.
- **Sealed Secrets:** This project uses `SealedSecretsController` (
  `infrastructure/kube-system/SealedSecretsController.yaml`). If an agent must create a `Secret`, add it to
  clusters/<username>/secrets.env and use ./infrastructure/setup/configure-cluster.sh to update the cluster's sealed
  secrets.
- **RBAC:** Review any newly added Role or ClusterRole to ensure the principle of least privilege is strictly followed.

## 4. Agent Operational Directives

- **Context Gathering:** Before making significant changes, execute `grep` and `glob` searches to understand custom
  patterns, especially how persistent volumes (`pvc.yaml`) interact with applications.
  - When you need to search docs, use `context7` mcp tools.
- **Proactive Scaffolding:** When asked to add a new application, draft the full `HelmRelease` configuration, suggest
  appropriate persistent volume claims, configure an Ingress route if applicable, and run a dry-run validation using
  Kustomize/Kubectl.
- **Commit Granularity:** Make atomic commits. Since changes are continuously reconciled by Flux, ensure commit messages
  clearly state the application being updated or the specific infrastructure change.
- **Immutability:** Treat existing cluster components as immutable unless an upgrade is explicitly requested. Do not
  modify global `HelmRepository` resources if an app-specific setup works perfectly.
- To search the web use `tavily` mcp tools. Search and scrape sites like StackOverflow, GitHub Issues, and official
  documentation for Kubernetes, Flux, and related tools. Always
  verify the credibility of sources and cross-reference information when possible.

## 5. Directory Structure Overview

To speed up codebase exploration, agents should reference this map:

- `apps/`: User-facing applications and services managed via Flux (e.g., Plex, HomeAssistant, Nextcloud).
- `clusters/`: Cluster-specific Flux sync manifests and root Kustomizations.
- `containers/`: Custom Dockerfile definitions and Node.js utility build scripts.
- `infrastructure/`: Core system components (cert-manager, kube-system, monitoring, storage).
- `install-k8s/`: Bash scripts for bootstrapping new nodes and initial cluster setup.
