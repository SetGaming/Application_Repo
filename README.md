# Calculator Application CI/CD

Python Flask calculator application deployed by Jenkins.

## Pull Request CI

1. Build the application image once
2. Run unit tests and publish JUnit results
3. Push `pr-<PR_ID>-<BUILD_NUMBER>` to Amazon ECR

## Merge-to-master CD

1. Build the application image once
2. Run unit and integration tests and publish JUnit results
3. Push a traceable master tag, commit tag, and `latest` to Amazon ECR
4. Deploy to the Application EC2 instance
5. Verify `/health` with retries

All Jenkins stages run in a Docker agent.
