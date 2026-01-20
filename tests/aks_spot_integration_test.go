package test

import (
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestAksSpotIntegration performs a full integration test by deploying
// an AKS cluster with spot nodes to Azure.
//
// This test requires:
//   - Azure credentials (ARM_* environment variables or CLI auth)
//   - Sufficient Azure quota for the VMs
//   - ~15-20 minutes to complete
//
// Run with: go test -v -timeout 30m -run TestAksSpotIntegration
func TestAksSpotIntegration(t *testing.T) {
	// Skip if not running integration tests
	if os.Getenv("RUN_INTEGRATION_TESTS") != "true" {
		t.Skip("Skipping integration test. Set RUN_INTEGRATION_TESTS=true to run.")
	}

	t.Parallel()

	// Generate unique names to avoid conflicts
	uniqueID := random.UniqueId()
	resourceGroupName := fmt.Sprintf("rg-terratest-%s", uniqueID)
	clusterName := fmt.Sprintf("aks-test-%s", uniqueID)
	location := "australiaeast"

	// Terraform options for prod environment (modified for testing)
	terraformOptions := &terraform.Options{
		TerraformDir:    "../terraform/environments/prod",
		TerraformBinary: "terraform",

		Vars: map[string]interface{}{
			// Override with test-specific values
			"resource_group_name": resourceGroupName,
			"cluster_name":        clusterName,
			"location":            location,
		},

		// Retry settings for flaky Azure operations
		MaxRetries:         3,
		TimeBetweenRetries: 5 * time.Second,
		RetryableTerraformErrors: map[string]string{
			".*": "Azure transient error, retrying...",
		},

		NoColor: true,
	}

	// Ensure we clean up resources after test
	defer terraform.Destroy(t, terraformOptions)

	// Deploy the infrastructure
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	actualClusterName := terraform.Output(t, terraformOptions, "cluster_name")
	clusterID := terraform.Output(t, terraformOptions, "cluster_id")

	// Validate outputs
	assert.Equal(t, clusterName, actualClusterName)
	assert.NotEmpty(t, clusterID)
	assert.Contains(t, clusterID, "/providers/Microsoft.ContainerService/managedClusters/",
		"Cluster ID should be a valid Azure resource ID")
}

// TestAksSpotNodePoolsCreated validates that spot node pools are created
// with correct configurations.
func TestAksSpotNodePoolsCreated(t *testing.T) {
	if os.Getenv("RUN_INTEGRATION_TESTS") != "true" {
		t.Skip("Skipping integration test. Set RUN_INTEGRATION_TESTS=true to run.")
	}

	t.Parallel()

	uniqueID := random.UniqueId()
	resourceGroupName := fmt.Sprintf("rg-terratest-spot-%s", uniqueID)
	clusterName := fmt.Sprintf("aks-spot-%s", uniqueID)

	terraformOptions := &terraform.Options{
		TerraformDir: "../terraform/environments/prod",
		Vars: map[string]interface{}{
			"resource_group_name": resourceGroupName,
			"cluster_name":        clusterName,
		},
		NoColor: true,
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Get node pools summary from output
	nodePoolsSummary := terraform.Output(t, terraformOptions, "node_pools_summary")

	// Verify spot pools exist in the summary
	assert.Contains(t, nodePoolsSummary, "spot",
		"Expected spot node pools in the summary")
}

