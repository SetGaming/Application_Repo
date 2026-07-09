# Calculator Application — Single Jenkins CI/CD Pipeline

This repository contains the Python calculator application and the complete CI/CD pipeline used for the practical.

The project demonstrates one Jenkins Multibranch Pipeline with two conditional flows:

- **Pull Request CI**
- **Merge-to-master CD**

Both flows are defined in the same `Jenkinsfile`.

---

## Project Goal

```text
Developer changes code
    ↓
Pushes a branch to GitHub
    ↓
Opens a Pull Request into master
    ↓
Jenkins performs CI
    ↓
PR is merged into master
    ↓
Jenkins performs CD
    ↓
Production-final runs the new image
```

The pipeline builds a Docker image, verifies it with tests, stores it in Amazon ECR, and deploys approved master builds to a dedicated Production EC2 instance.

---

## Architecture

```text
Application_Repo
    ↓ GitHub webhook
Jenkins Multibranch Pipeline on Platform-final
    ↓ temporary docker:27-cli agent
Build the calculator image once
    ↓
Run tests against that exact image
    ↓
Push the same image to Amazon ECR
    ↓ master only
SSH to Production-final
    ↓
Production-final pulls the exact ECR image
    ↓
Docker Compose starts calculator-app
    ↓
Jenkins verifies /health
```

### Infrastructure

| Component | Responsibility |
|---|---|
| `Application_Repo` | Source, tests, Dockerfile, Compose file and Jenkinsfile |
| `Platform-final` EC2 | Runs Jenkins and performs build/test/push/deploy |
| Amazon ECR | Stores immutable, versioned application images |
| `Production-final` EC2 | Pulls and runs the approved application image |
| `calculator-app` container | Runs the Flask health service on port `5000` |

Current lab values:

```text
AWS region: us-east-1
AWS account: 992382545251
ECR repository: calculator-app
Production private IP: 10.0.4.23
Application port: 5000
Health endpoint: /health
```

---

## One Pipeline, Two Flows

This project does not use separate CI and CD jobs.

```text
One Multibranch Pipeline
    ↓
One Jenkinsfile
    ├── PR event      → CI flow
    └── master event  → CD flow
```

Jenkins may display separate branch jobs such as `PR-1` and `master`, but they are executions of the same Jenkinsfile.

| Trigger | Tests | ECR Push | Production Deployment |
|---|---|---|---|
| Pull Request into `master` | Unit tests | Yes | No |
| Push or merge to `master` | Unit + integration tests | Yes | Yes |

---

## Pull Request CI Flow

A Pull Request opened or updated against `master` runs the fixed CI order:

```text
PR opened or synchronized
    ↓
1. Build Container Image
    ↓
2. Unit Test
    ↓
Publish and archive JUnit XML
    ↓
3. Push Image to ECR
    ↓
Stop — no production deployment
```

PR image tag:

```text
pr-<PR_ID>-<BUILD_NUMBER>
```

Example:

```text
calculator-app:pr-1-12
```

Important behavior:

- The image is built once
- Unit tests run inside the built image
- The pipeline fails when a test fails
- JUnit results are visible in Jenkins
- The XML report is retained as a build artifact
- The PR image is pushed to ECR
- Deployment and health-verification stages are skipped

---

## Merge-to-Master CD Flow

A push or merged Pull Request on `master` runs:

```text
master updated
    ↓
1. Build Container Image
    ↓
2. Unit + Integration Tests
    ↓
Publish and archive JUnit XML
    ↓
3. Push Image to ECR
    ↓
4. Deploy to Production EC2
    ↓
5. Health Verification
```

The master image is tagged using:

```text
master-<BUILD_NUMBER>-<SHORT_COMMIT>
commit-<SHORT_COMMIT>
latest
```

Example:

```text
calculator-app:master-8-2f5976c
calculator-app:commit-2f5976c
calculator-app:latest
```

All tags point to the same image digest.

---

## Why the Image Is Built Once

The pipeline follows:

```text
Build image A
    ↓
Test image A
    ↓
Push image A
    ↓
Deploy image A
```

It does not rebuild after tests.

This guarantees that the production server receives the same artifact that passed the quality gates.

```text
Tested artifact = Published artifact = Deployed artifact
```

---

## Source Traceability

The pipeline records the full Git commit in the image label:

```text
org.opencontainers.image.revision=<FULL_GIT_SHA>
```

The production tag also contains the Jenkins build number and short commit:

```text
master-<BUILD_NUMBER>-<SHORT_COMMIT>
```

Traceability path:

```text
Running production container
    ↓ image tag
Jenkins build number
    ↓ commit suffix
Git commit
    ↓
Exact source code used to create the image
```

---

## Repository Structure

```text
Application_Repo
├── api.py
├── calculator_app.py
├── calculator_logic.py
├── requirements.txt
├── tests/
│   ├── test_calculator_logic.py
│   └── test_calculator_app_integration.py
├── Dockerfile
├── docker-compose.yml
├── Jenkinsfile
├── .dockerignore
├── .gitignore
├── .env.example
└── README.md
```

---

## Application Container

The Dockerfile:

- Uses `python:3.9-slim`
- Installs Flask and pytest
- Copies the calculator source and tests
- Runs as the non-root user `appuser`
- Exposes port `5000`
- Includes an internal `/health` Docker health check
- Stores the source commit in an OCI image label

For this practical, Flask runs the supplied lightweight API directly.

Health endpoint:

```http
GET /health
```

Expected response:

```json
{"status":"ok"}
```

---

## Tests

### Pull Request

PR CI runs the unit test file:

```text
tests/test_calculator_logic.py
```

It verifies:

- Addition
- Subtraction
- Multiplication
- Division

### Master

Master CD runs:

```text
tests/test_calculator_logic.py
tests/test_calculator_app_integration.py
```

This currently produces:

```text
4 unit tests
+
2 integration tests
=
6 tests
```

JUnit output is written to `test-results/`, published in Jenkins, archived, and fingerprinted.

---

## Docker Agent Execution

The Jenkinsfile uses a top-level Docker agent:

```text
docker:27-cli
```

The agent mounts:

```text
/var/run/docker.sock
```

Every stage runs in the Docker agent:

```text
Prepare Docker Agent
Checkout
Prepare Metadata
Build Container Image
Test
Push Image to ECR
Deploy to Production EC2
Health Verification
```

The agent installs or loads:

- Bash
- Git
- OpenSSH client
- Curl
- Official AWS CLI container wrapper

---

## AWS and ECR Flow

No AWS keys are stored in this repository.

```text
Jenkins Docker agent
    ↓ EC2 role credentials
aws sts get-caller-identity
    ↓
ECR login
    ↓
docker push
```

The production host uses its EC2 role to:

```text
Authenticate to ECR
    ↓
Pull the selected image
```

ECR registry:

```text
992382545251.dkr.ecr.us-east-1.amazonaws.com
```

---

## Production Deployment

The pipeline uses the Jenkins SSH credential:

```text
application-ec2-ssh
```

The credential name is retained for compatibility, but it connects to `Production-final`.

Jenkins does not copy source code to production.

It transfers only:

```text
docker-compose.yml
deployment .env values
```

Deployment path:

```text
/opt/calculator-app
```

Remote deployment:

```text
Jenkins SSH connection
    ↓
Create /opt/calculator-app
    ↓
Copy docker-compose.yml
    ↓
Copy new deployment environment
    ↓
Production ECR login
    ↓
docker compose pull
    ↓
docker compose up -d --remove-orphans
```

The deployment environment identifies:

- Exact ECR image URI
- Exact image tag
- Host port
- Source commit

---

## Health Verification

Deployment is not considered successful immediately after the container starts.

Jenkins connects to `Production-final` and probes:

```text
http://127.0.0.1:5000/health
```

The check uses multiple attempts with increasing delays.

```text
Attempt 1
    ↓ failed? wait
Attempt 2
    ↓ failed? wait longer
...
Attempt 12
    ↓ still failed?
Fail the pipeline and print container diagnostics
```

A successful response:

```json
{"status":"ok"}
```

causes the pipeline to finish successfully.

---

## GitHub Integration

The repository webhook sends:

- Push events
- Pull Request events

to Jenkins.

```text
GitHub event
    ↓
Jenkins Multibranch scan
    ↓
Relevant branch or PR job starts automatically
```

Jenkins uses an authenticated GitHub API credential for branch and PR discovery.

---

## Security

- No AWS access keys in Git
- No GitHub token in Git
- No SSH private key in Git
- AWS authentication uses EC2 instance roles
- SSH private key is stored in Jenkins Credentials
- Production receives no source repository
- Application runs as a non-root container user
- `.env`, PEM, key and Python cache files are ignored
- Temporary pipeline environment files are deleted after the build
- The local build image is removed from Platform-final during cleanup

---

## Successful Master Build Evidence

A successful master run should show:

```text
Flow: master
    ↓
Image: <ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com/calculator-app:master-<BUILD>-<COMMIT>
    ↓
6 passed
    ↓
Recording test results
    ↓
Archiving artifacts
    ↓
Login Succeeded
    ↓
Published image: <IMAGE_REFERENCE>
    ↓
Container calculator-app Started
    ↓
{"status":"ok"}
    ↓
Health verification passed
    ↓
Finished: SUCCESS
```

---

## How the PR Flow Is Validated

This README update is intentionally delivered through a feature branch and Pull Request.

Expected validation:

```text
Feature branch pushed
    ↓
PR opened into master
    ↓
Jenkins discovers PR-<ID>
    ↓
Build Container Image
    ↓
Unit tests only
    ↓
JUnit report published
    ↓
pr-<ID>-<BUILD> pushed to ECR
    ↓
Deploy stage skipped
    ↓
Health Verification skipped
```

After the PR CI build succeeds, merge the PR.

The merge must then trigger the full master CD flow automatically.

---

## Teacher Validation Checklist

### PR CI

- [ ] Opening the PR automatically creates or starts a `PR-<ID>` Jenkins job
- [ ] The image is built once
- [ ] Unit tests pass
- [ ] JUnit report is visible and archived
- [ ] ECR contains `pr-<ID>-<BUILD_NUMBER>`
- [ ] No production deployment occurs

### Master CD

- [ ] Merging the PR automatically starts `master`
- [ ] Unit and integration tests pass
- [ ] ECR contains master, commit and latest tags
- [ ] The image tag is traceable to the Git commit
- [ ] Production-final pulls and starts the new image
- [ ] `/health` succeeds with retry logic
- [ ] Jenkins finishes with `SUCCESS`

---

## Complete Flow

```text
Feature branch
    ↓
Pull Request into master
    ↓
PR CI: build → unit test → JUnit → ECR push
    ↓
Review and merge
    ↓
Master CD: build → unit + integration tests → JUnit → ECR push
    ↓
SSH deployment to Production-final
    ↓
Docker Compose pull and restart
    ↓
/health verification
    ↓
Successful production release
```
