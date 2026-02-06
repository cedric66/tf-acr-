// Package test contains Terratest tests for the tf-acr Terraform modules.
//
// These tests validate that Terraform configurations are syntactically correct,
// produce expected outputs, and (optionally) deploy working infrastructure.
//
// Test Levels:
//   - Unit Tests: Validate Terraform syntax and structure without deploying
//   - Integration Tests: Deploy to Azure and validate resources (requires credentials)
//
// Running Tests:
//
//	cd tests
//	go mod tidy
//	go test -v -timeout 30m ./...
//
// Environment Variables Required for Integration Tests:
//   - ARM_SUBSCRIPTION_ID
//   - ARM_TENANT_ID
//   - ARM_CLIENT_ID
//   - ARM_CLIENT_SECRET (or use Azure CLI auth)
package test
