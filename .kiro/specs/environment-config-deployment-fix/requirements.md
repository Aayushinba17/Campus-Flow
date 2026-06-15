# Requirements Document

## Introduction

This document specifies requirements for fixing critical infrastructure issues in the CampusFlow application related to environment configuration, deployment pipeline, secret management, and AWS region consistency. The application currently has hardcoded values causing 500 internal server errors, exposed secrets in version control, AWS region mismatches between services, and no proper environment separation between local development and production deployment.

## Glossary

- **System**: The CampusFlow application backend (Python FastAPI)
- **Flutter_Client**: The CampusFlow mobile application (Flutter/Dart)
- **Environment**: A deployment context (local development, staging, production)
- **Secret**: Sensitive credential data including API keys, OAuth credentials, and AWS access keys
- **Configuration_Manager**: Component responsible for loading and validating environment variables
- **Deployment_Target**: The infrastructure where the application runs (localhost, EC2 instance)
- **OAuth_Callback_URL**: The redirect URI registered with Google OAuth for Classroom integration
- **AWS_Region**: Geographic region where AWS services are accessed (us-east-1, ap-south-1)
- **Rekognition_Service**: AWS service for text detection in images (only available in specific regions)
- **DynamoDB_Service**: AWS NoSQL database service
- **S3_Service**: AWS object storage service
- **Base_URL**: The HTTP endpoint used by Flutter_Client to communicate with System
- **Environment_Variable**: Configuration value loaded from .env files or system environment
- **Secret_Manager**: System for managing sensitive credentials outside version control
- **Error_Handler**: Component that catches exceptions and returns meaningful error responses
- **Health_Check**: Endpoint that validates system configuration and service connectivity

## Requirements

### Requirement 1: Environment-Based Configuration

**User Story:** As a developer, I want the application to automatically use different configurations for local development versus production deployment, so that I don't need to manually change hardcoded values when switching environments.

#### Acceptance Criteria

1. THE System SHALL load configuration from environment variables rather than hardcoded values
2. WHEN running in local development environment, THE System SHALL use localhost-based URLs and development credentials
3. WHEN running in production environment, THE System SHALL use EC2 public IP or domain and production credentials
4. THE Flutter_Client SHALL determine Base_URL from build-time environment configuration
5. WHERE environment variables are missing or invalid, THE Configuration_Manager SHALL fail startup with descriptive error messages

### Requirement 2: Secret Management and Security

**User Story:** As a system administrator, I want secrets removed from version control and properly managed, so that credentials are not exposed publicly and can be rotated without code changes.

#### Acceptance Criteria

1. THE System SHALL NOT store Secret values in version-controlled files
2. THE System SHALL provide template files (.env.example) documenting required Secret variables without exposing actual values
3. WHEN System starts, THE Configuration_Manager SHALL validate that all required Secret variables are present
4. IF any required Secret is missing, THEN THE Configuration_Manager SHALL log which specific secrets are missing and prevent application startup
5. THE System SHALL load AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, GEMINI_API_KEY, GOOGLE_CLIENT_ID, and GOOGLE_CLIENT_SECRET from Environment_Variable sources only

### Requirement 3: AWS Multi-Region Service Support

**User Story:** As a system architect, I want proper handling of AWS services across different regions, so that services unavailable in certain regions work correctly and don't cause runtime errors.

#### Acceptance Criteria

1. THE System SHALL configure Rekognition_Service to use us-east-1 region regardless of default AWS_Region setting
2. THE System SHALL configure DynamoDB_Service and S3_Service to use the region specified in AWS_Region environment variable
3. WHEN Rekognition_Service is called, THE System SHALL handle cross-region requests with proper error handling
4. IF AWS service calls fail due to region issues, THEN THE Error_Handler SHALL return HTTP 503 with region-specific error details
5. THE System SHALL document which services run in which regions in deployment documentation

### Requirement 4: OAuth Callback Configuration

**User Story:** As a developer integrating Google Classroom, I want OAuth callback URLs to automatically match the deployment environment, so that OAuth flows work in both local testing and production without manual configuration changes.

#### Acceptance Criteria

1. THE System SHALL load OAuth_Callback_URL from GOOGLE_REDIRECT_URI environment variable
2. WHEN System is deployed to EC2, THE OAuth_Callback_URL SHALL use the EC2 public IP or domain name
3. WHERE local development requires OAuth testing, THE System SHALL provide mock OAuth flow documentation as an alternative
4. THE System SHALL validate OAuth_Callback_URL format on startup and fail with descriptive error if invalid
5. WHEN Google OAuth redirect occurs, THE System SHALL use the configured OAuth_Callback_URL without fallback to hardcoded values

### Requirement 5: Local Development Environment Support

**User Story:** As a developer, I want to run the complete application locally on Windows without requiring EC2 deployment, so that I can develop and test features quickly.

#### Acceptance Criteria

1. WHEN Flutter_Client runs in Android emulator, THE System SHALL support Base_URL using 10.0.2.2 (Android emulator localhost bridge)
2. THE System SHALL provide local development environment configuration template
3. WHEN running locally, THE System SHALL use mock data or test credentials where production services are unavailable
4. THE System SHALL document which features require public URLs (OAuth callbacks) versus which work fully offline
5. WHEN developer switches from local to production, THE System SHALL require only environment variable changes without code modifications

### Requirement 6: Comprehensive Error Handling

**User Story:** As a developer debugging production issues, I want meaningful error messages instead of generic 500 errors, so that I can quickly identify and fix configuration or service problems.

#### Acceptance Criteria

1. WHEN AWS service calls fail, THE Error_Handler SHALL catch exceptions and return HTTP status codes with specific error details
2. IF Rekognition_Service fails, THEN THE Error_Handler SHALL return HTTP 503 with message indicating Rekognition service unavailability
3. IF DynamoDB_Service connection fails, THEN THE Error_Handler SHALL return HTTP 503 with message indicating database connectivity issue
4. WHEN OAuth token refresh fails, THE Error_Handler SHALL return HTTP 401 with message indicating re-authentication required
5. THE System SHALL log all errors with timestamp, error type, and contextual information to aid debugging
6. IF Environment_Variable validation fails, THEN THE System SHALL log specific missing or invalid variables before shutdown

### Requirement 7: Configuration Validation on Startup

**User Story:** As a DevOps engineer, I want the application to validate its configuration when starting up, so that deployment issues are caught immediately rather than discovered during runtime.

#### Acceptance Criteria

1. WHEN System starts, THE Configuration_Manager SHALL validate all required Environment_Variable values are present
2. WHEN System starts, THE Configuration_Manager SHALL validate AWS credentials are properly formatted
3. WHEN System starts, THE Configuration_Manager SHALL validate OAuth_Callback_URL uses https in production or http in development
4. IF any validation fails, THEN THE System SHALL prevent startup and output clear error messages indicating which configuration is invalid
5. THE System SHALL provide a Health_Check endpoint that returns configuration status for monitoring

### Requirement 8: Deployment Documentation

**User Story:** As a new developer or DevOps engineer, I want clear step-by-step deployment documentation, so that I can set up local development and production environments correctly.

#### Acceptance Criteria

1. THE System SHALL provide README_DEPLOYMENT.md documenting local development setup
2. THE System SHALL provide README_DEPLOYMENT.md documenting EC2 production setup
3. THE System SHALL provide .env.example templates for both Flutter_Client and System backend
4. THE documentation SHALL include AWS region configuration explanation and service-specific region requirements
5. THE documentation SHALL include Google OAuth setup steps with callback URL configuration
6. THE documentation SHALL include troubleshooting section for common configuration errors

### Requirement 9: Flutter Environment Configuration

**User Story:** As a Flutter developer, I want build-time environment configuration, so that the mobile app automatically connects to the correct backend based on build environment.

#### Acceptance Criteria

1. THE Flutter_Client SHALL support loading Base_URL from environment-specific configuration files
2. WHEN building for development, THE Flutter_Client SHALL use localhost or emulator bridge URLs
3. WHEN building for production, THE Flutter_Client SHALL use production EC2 IP or domain
4. THE Flutter_Client SHALL provide mechanism to switch environments without modifying source code
5. THE Flutter_Client SHALL validate Base_URL is reachable during app initialization and show error if backend is unreachable

### Requirement 10: Backward Compatibility During Migration

**User Story:** As a project maintainer, I want the configuration migration to maintain backward compatibility, so that existing deployments continue working while new environment-based configuration is adopted.

#### Acceptance Criteria

1. WHERE Environment_Variable is not set, THE System MAY fall back to default values with deprecation warnings
2. THE System SHALL log warnings when using fallback default values instead of environment variables
3. WHEN migration is complete, THE System SHALL remove fallback defaults and require explicit environment configuration
4. THE migration documentation SHALL provide clear timeline and steps for transitioning from hardcoded to environment-based configuration
5. THE System SHALL support gradual migration where some values use environment variables while others temporarily use defaults
