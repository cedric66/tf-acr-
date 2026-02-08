package test

import (
	"os"
	"strconv"
	"time"
)

// TestConfig holds all configurable test parameters.
// Values can be set via environment variables or fall back to sensible defaults.
type TestConfig struct {
	// Azure Configuration
	Location           string
	SubscriptionID     string
	TenantID           string

	// Terraform Configuration
	TerraformDir       string
	TerraformBinary    string

	// Test Behavior
	MaxRetries         int
	RetryDelay         time.Duration
	DeploymentTimeout  time.Duration

	// Resource Naming
	ResourceGroupPrefix string
	ClusterNamePrefix   string

	// Feature Flags
	SkipDestroy        bool
	VerboseLogging     bool
}

// NewTestConfig creates a test configuration from environment variables with defaults.
func NewTestConfig() *TestConfig {
	return &TestConfig{
		// Azure defaults
		Location:           getEnvOrDefault("TEST_AZURE_LOCATION", "australiaeast"),
		SubscriptionID:     os.Getenv("ARM_SUBSCRIPTION_ID"),
		TenantID:           os.Getenv("ARM_TENANT_ID"),

		// Terraform defaults
		TerraformDir:       getEnvOrDefault("TEST_TERRAFORM_DIR", "../terraform/environments/prod"),
		TerraformBinary:    getEnvOrDefault("TEST_TERRAFORM_BINARY", "terraform"),

		// Test behavior defaults
		MaxRetries:         getEnvAsInt("TEST_MAX_RETRIES", 3),
		RetryDelay:         getEnvAsDuration("TEST_RETRY_DELAY", 5*time.Second),
		DeploymentTimeout:  getEnvAsDuration("TEST_DEPLOYMENT_TIMEOUT", 30*time.Minute),

		// Naming defaults
		ResourceGroupPrefix: getEnvOrDefault("TEST_RG_PREFIX", "rg-terratest"),
		ClusterNamePrefix:   getEnvOrDefault("TEST_CLUSTER_PREFIX", "aks-test"),

		// Feature flags
		SkipDestroy:        getEnvAsBool("TEST_SKIP_DESTROY", false),
		VerboseLogging:     getEnvAsBool("TEST_VERBOSE", false),
	}
}

// getEnvOrDefault returns the environment variable value or a default.
func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvAsInt returns the environment variable as an integer or a default.
func getEnvAsInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}

// getEnvAsDuration returns the environment variable as a duration or a default.
func getEnvAsDuration(key string, defaultValue time.Duration) time.Duration {
	if value := os.Getenv(key); value != "" {
		if duration, err := time.ParseDuration(value); err == nil {
			return duration
		}
	}
	return defaultValue
}

// getEnvAsBool returns the environment variable as a boolean or a default.
func getEnvAsBool(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		boolValue, err := strconv.ParseBool(value)
		if err == nil {
			return boolValue
		}
	}
	return defaultValue
}
