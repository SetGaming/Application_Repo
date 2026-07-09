pipeline {
    agent {
        docker {
            image 'docker:27-cli'
            args '-u 0:0 -v /var/run/docker.sock:/var/run/docker.sock'
        }
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    parameters {
        string(
            name: 'AWS_REGION',
            defaultValue: 'us-east-1',
            description: 'AWS region containing the ECR repository'
        )

        string(
            name: 'ECR_REPOSITORY',
            defaultValue: 'calculator-app',
            description: 'Amazon ECR repository name'
        )

        string(
            name: 'APP_HOST',
            defaultValue: '10.0.4.23',
            description: 'Production EC2 private IP address'
        )

        string(
            name: 'APP_PORT',
            defaultValue: '5000',
            description: 'Application host port'
        )
    }

    environment {
        APP_USER = 'ec2-user'
        DEPLOY_DIR = '/opt/calculator-app'
    }

    stages {
        stage('Prepare Docker Agent') {
            steps {
                sh '''
                    set -e

                    apk add --no-cache \
                        bash \
                        git \
                        openssh-client \
                        curl

                    cat > /usr/local/bin/aws <<'AWS_WRAPPER'
#!/bin/sh
exec docker run --rm \
    --network host \
    -e AWS_REGION \
    -e AWS_DEFAULT_REGION \
    -e AWS_PAGER \
    public.ecr.aws/aws-cli/aws-cli:2.33.15 "$@"
AWS_WRAPPER

                    chmod +x /usr/local/bin/aws

                    docker pull \
                        public.ecr.aws/aws-cli/aws-cli:2.33.15

                    docker --version
                    git --version
                    git config --global --add safe.directory "$WORKSPACE"
                    aws --version
                    ssh -V
                '''
            }
        }

        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    set -e
                    git log -1 --oneline
                '''
            }
        }

        stage('Prepare Metadata') {
            steps {
                sh '''
                    set -e

                    AWS_REGION="${AWS_REGION:-us-east-1}"
                    ECR_REPOSITORY="${ECR_REPOSITORY:-calculator-app}"
                    APP_HOST="${APP_HOST:-10.0.4.23}"
                    APP_PORT="${APP_PORT:-5000}"

                    export AWS_REGION
                    export ECR_REPOSITORY
                    export APP_HOST
                    export APP_PORT

                    AWS_ACCOUNT_ID="$(
                        aws sts get-caller-identity \
                            --query Account \
                            --output text
                    )"

                    ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
                    IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}"
                    GIT_SHA="$(git rev-parse HEAD)"
                    GIT_SHORT="$(git rev-parse --short=7 HEAD)"

                    if [ -n "${CHANGE_ID:-}" ]; then
                        FLOW="pr"
                        IMAGE_TAG="pr-${CHANGE_ID}-${BUILD_NUMBER}"
                    elif [ "${BRANCH_NAME}" = "master" ]; then
                        FLOW="master"
                        IMAGE_TAG="master-${BUILD_NUMBER}-${GIT_SHORT}"
                    else
                        FLOW="branch"
                        IMAGE_TAG="branch-${BUILD_NUMBER}-${GIT_SHORT}"
                    fi

                    IMAGE_REF="${IMAGE_URI}:${IMAGE_TAG}"

                    cat > .pipeline.env <<PIPELINE_ENV
AWS_REGION=${AWS_REGION}
ECR_REPOSITORY=${ECR_REPOSITORY}
APP_HOST=${APP_HOST}
APP_PORT=${APP_PORT}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
ECR_REGISTRY=${ECR_REGISTRY}
IMAGE_URI=${IMAGE_URI}
IMAGE_TAG=${IMAGE_TAG}
IMAGE_REF=${IMAGE_REF}
GIT_SHA=${GIT_SHA}
GIT_SHORT=${GIT_SHORT}
FLOW=${FLOW}
PIPELINE_ENV

                    echo "Flow: ${FLOW}"
                    echo "Commit: ${GIT_SHA}"
                    echo "Image: ${IMAGE_REF}"
                '''
            }
        }

        stage('Build Container Image') {
            steps {
                sh '''
                    set -e

                    set -a
                    . ./.pipeline.env
                    set +a

                    docker build \
                        --build-arg "VCS_REF=${GIT_SHA}" \
                        --tag "${IMAGE_REF}" \
                        .

                    echo "Built once: ${IMAGE_REF}"
                '''
            }
        }

        stage('CI - Unit Tests') {
            steps {
                sh '''
                    set -e

                    set -a
                    . ./.pipeline.env
                    set +a

                    rm -rf test-results
                    mkdir -p test-results/unit
                    chmod -R 0777 test-results

                    docker run --rm \
                        -v "$WORKSPACE/test-results:/test-results" \
                        "${IMAGE_REF}" \
                        python -m pytest \
                            -v \
                            tests/test_calculator_logic.py \
                            --junitxml="/test-results/unit/unit.xml"
                '''
            }

            post {
                always {
                    junit(
                        testResults: 'test-results/unit/*.xml',
                        allowEmptyResults: false,
                        keepLongStdio: true
                    )

                    archiveArtifacts(
                        artifacts: 'test-results/unit/*.xml',
                        allowEmptyArchive: false,
                        fingerprint: true
                    )
                }
            }
        }

        stage('CD - Integration Tests') {
            when {
                branch 'master'
            }

            steps {
                sh '''
                    set -e

                    set -a
                    . ./.pipeline.env
                    set +a

                    mkdir -p test-results/integration
                    chmod -R 0777 test-results

                    docker run --rm \
                        -v "$WORKSPACE/test-results:/test-results" \
                        "${IMAGE_REF}" \
                        python -m pytest \
                            -v \
                            tests/test_calculator_app_integration.py \
                            --junitxml="/test-results/integration/integration.xml"
                '''
            }

            post {
                always {
                    junit(
                        testResults: 'test-results/integration/*.xml',
                        allowEmptyResults: false,
                        keepLongStdio: true
                    )

                    archiveArtifacts(
                        artifacts: 'test-results/integration/*.xml',
                        allowEmptyArchive: false,
                        fingerprint: true
                    )
                }
            }
        }

        stage('Push Image to ECR') {
            when {
                anyOf {
                    changeRequest target: 'master'
                    branch 'master'
                }
            }

            steps {
                sh '''
                    set -e

                    set -a
                    . ./.pipeline.env
                    set +a

                    aws ecr describe-repositories \
                        --region "$AWS_REGION" \
                        --repository-names "$ECR_REPOSITORY" \
                        >/dev/null 2>&1 || \
                    aws ecr create-repository \
                        --region "$AWS_REGION" \
                        --repository-name "$ECR_REPOSITORY" \
                        --image-scanning-configuration scanOnPush=true

                    aws ecr get-login-password \
                        --region "$AWS_REGION" |
                    docker login \
                        --username AWS \
                        --password-stdin \
                        "$ECR_REGISTRY"

                    docker push "$IMAGE_REF"

                    if [ "$FLOW" = "master" ]; then
                        docker tag \
                            "$IMAGE_REF" \
                            "${IMAGE_URI}:commit-${GIT_SHORT}"

                        docker tag \
                            "$IMAGE_REF" \
                            "${IMAGE_URI}:latest"

                        docker push "${IMAGE_URI}:commit-${GIT_SHORT}"
                        docker push "${IMAGE_URI}:latest"
                    fi

                    echo "Published image: ${IMAGE_REF}"
                '''
            }
        }

        stage('Deploy to Production EC2') {
            when {
                branch 'master'
            }

            steps {
                sshagent(credentials: ['application-ec2-ssh']) {
                    sh '''
                        set -e
                        set +x

                        set -a
                        . ./.pipeline.env
                        set +a

                        cat > deploy.env <<DEPLOY_ENV
IMAGE_URI=${IMAGE_URI}
IMAGE_TAG=${IMAGE_TAG}
APP_PORT=${APP_PORT}
SOURCE_COMMIT=${GIT_SHA}
DEPLOY_ENV

                        ssh \
                            -o StrictHostKeyChecking=accept-new \
                            -o ConnectTimeout=10 \
                            "${APP_USER}@${APP_HOST}" \
                            "mkdir -p '${DEPLOY_DIR}'"

                        scp \
                            -o StrictHostKeyChecking=accept-new \
                            docker-compose.yml \
                            "${APP_USER}@${APP_HOST}:${DEPLOY_DIR}/docker-compose.yml"

                        scp \
                            -o StrictHostKeyChecking=accept-new \
                            deploy.env \
                            "${APP_USER}@${APP_HOST}:${DEPLOY_DIR}/.env.new"

                        ssh \
                            -o StrictHostKeyChecking=accept-new \
                            "${APP_USER}@${APP_HOST}" \
                            "DEPLOY_DIR='${DEPLOY_DIR}' \
                             AWS_REGION='${AWS_REGION}' \
                             ECR_REGISTRY='${ECR_REGISTRY}' \
                             bash -s" <<'REMOTE_DEPLOY'
set -e

cd "$DEPLOY_DIR"

mv .env.new .env
chmod 600 .env

aws ecr get-login-password \
    --region "$AWS_REGION" |
docker login \
    --username AWS \
    --password-stdin \
    "$ECR_REGISTRY"

docker compose \
    --env-file .env \
    pull

docker compose \
    --env-file .env \
    up -d \
    --remove-orphans

docker compose \
    --env-file .env \
    ps
REMOTE_DEPLOY
                    '''
                }
            }
        }

        stage('Health Verification') {
            when {
                branch 'master'
            }

            steps {
                sshagent(credentials: ['application-ec2-ssh']) {
                    sh '''
                        set -e

                        for ATTEMPT in $(seq 1 12); do
                            echo "Health attempt ${ATTEMPT}/12"

                            if ssh \
                                -o StrictHostKeyChecking=accept-new \
                                "${APP_USER}@${APP_HOST}" \
                                "curl -fsS http://127.0.0.1:${APP_PORT}/health"
                            then
                                echo
                                echo "Health verification passed."
                                exit 0
                            fi

                            sleep $((ATTEMPT < 6 ? ATTEMPT * 2 : 10))
                        done

                        echo "Health verification failed."

                        ssh \
                            -o StrictHostKeyChecking=accept-new \
                            "${APP_USER}@${APP_HOST}" \
                            "docker ps -a && docker logs calculator-app || true"

                        exit 1
                    '''
                }
            }
        }
    }

    post {
        always {
            sh '''
                if [ -f .pipeline.env ]; then
                    set -a
                    . ./.pipeline.env
                    set +a

                    docker image rm \
                        "$IMAGE_REF" \
                        2>/dev/null || true
                fi

                rm -f \
                    .pipeline.env \
                    deploy.env
            '''
        }

        success {
            echo 'CI/CD pipeline completed successfully.'
        }

        failure {
            echo 'CI/CD pipeline failed.'
        }
    }
}
