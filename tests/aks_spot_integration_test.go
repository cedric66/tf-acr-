package test

import (
	"encoding/json"
	"fmt"
	"os"
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// deferredDestroy conditionally destroys Terraform resources based on test config.
// Use this instead of defer terraform.Destroy(t, options) to respect TEST_SKIP_DESTROY flag.
func deferredDestroy(t *testing.T, options *terraform.Options, config *TestConfig, resourceName string) {
	if !config.SkipDestroy {
		terraform.Destroy(t, options)
	} else {
		t.Logf("Skipping destroy for resources: %s (TEST_SKIP_DESTROY=true)", resourceName)
	}
}

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

	// Load test configuration from environment or defaults
	config := NewTestConfig()

	// Generate unique names to avoid conflicts
	uniqueID := random.UniqueId()
	resourceGroupName := fmt.Sprintf("%s-%s", config.ResourceGroupPrefix, uniqueID)
	clusterName := fmt.Sprintf("%s-%s", config.ClusterNamePrefix, uniqueID)

	// Terraform options using centralized configuration
	terraformOptions := &terraform.Options{
		TerraformDir:    config.TerraformDir,
		TerraformBinary: config.TerraformBinary,

		Vars: map[string]interface{}{
			// Override with test-specific values
			"resource_group_name": resourceGroupName,
			"cluster_name":        clusterName,
			"location":            config.Location,
		},

		// Retry settings for flaky Azure operations
		MaxRetries:         config.MaxRetries,
		TimeBetweenRetries: config.RetryDelay,
		RetryableTerraformErrors: map[string]string{
			".*": "Azure transient error, retrying...",
		},

		NoColor: true,
	}

	// Ensure we clean up resources after test (unless skip flag is set)
	defer deferredDestroy(t, terraformOptions, config, resourceGroupName)

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

	config := NewTestConfig()
	uniqueID := random.UniqueId()
	resourceGroupName := fmt.Sprintf("%s-spot-%s", config.ResourceGroupPrefix, uniqueID)
	clusterName := fmt.Sprintf("%s-spot-%s", config.ClusterNamePrefix, uniqueID)

	terraformOptions := &terraform.Options{
		TerraformDir:    config.TerraformDir,
		TerraformBinary: config.TerraformBinary,
		Vars: map[string]interface{}{
			"resource_group_name": resourceGroupName,
			"cluster_name":        clusterName,
			"location":            config.Location,
		},
		MaxRetries:         config.MaxRetries,
		TimeBetweenRetries: config.RetryDelay,
		NoColor:            true,
	}

	defer deferredDestroy(t, terraformOptions, config, resourceGroupName)
	terraform.InitAndApply(t, terraformOptions)

	// Get node pools summary from output
	nodePoolsSummary := terraform.Output(t, terraformOptions, "node_pools_summary")

	// Verify spot pools exist in the summary
	assert.Contains(t, nodePoolsSummary, "spot",
		"Expected spot node pools in the summary")
}

// SpotNodePoolInfo represents the structure of spot node pool output
type SpotNodePoolInfo struct {
	ID             string  `json:"id"`
	Name           string  `json:"name"`
	VMSize         string  `json:"vm_size"`
	Zones          []string `json:"zones"`
	MinCount       int     `json:"min_count"`
	MaxCount       int     `json:"max_count"`
	Priority       string  `json:"priority"`
	SpotMaxPrice   float64 `json:"spot_max_price"`
	EvictionPolicy string  `json:"eviction_policy"`
}

// TestAksSpotNodePoolAttributes validates that spot node pools have
// the correct Spot-specific configurations.
func TestAksSpotNodePoolAttributes(t *testing.T) {
	if os.Getenv("RUN_INTEGRATION_TESTS") != "true" {
		t.Skip("Skipping integration test. Set RUN_INTEGRATION_TESTS=true to run.")
	}

	t.Parallel()

	config := NewTestConfig()
	uniqueID := random.UniqueId()
	resourceGroupName := fmt.Sprintf("%s-spot-attrs-%s", config.ResourceGroupPrefix, uniqueID)
	clusterName := fmt.Sprintf("%s-spot-attrs-%s", config.ClusterNamePrefix, uniqueID)

	terraformOptions := &terraform.Options{
		TerraformDir:    config.TerraformDir,
		TerraformBinary: config.TerraformBinary,
		Vars: map[string]interface{}{
			"resource_group_name": resourceGroupName,
			"cluster_name":        clusterName,
			"location":            config.Location,
		},
		MaxRetries:         config.MaxRetries,
		TimeBetweenRetries: config.RetryDelay,
		NoColor:            true,
	}

	defer deferredDestroy(t, terraformOptions, config, resourceGroupName)
	terraform.InitAndApply(t, terraformOptions)

	// Get spot node pools output as JSON
	spotNodePoolsJSON := terraform.OutputJson(t, terraformOptions, "spot_node_pools")
	
	var spotNodePools map[string]SpotNodePoolInfo
	err := json.Unmarshal([]byte(spotNodePoolsJSON), &spotNodePools)
	require.NoError(t, err, "Failed to parse spot_node_pools output")

	// Validate that we have at least one spot pool
	require.NotEmpty(t, spotNodePools, "Expected at least one spot node pool")

	for poolName, pool := range spotNodePools {
		t.Run(fmt.Sprintf("SpotPool_%s", poolName), func(t *testing.T) {
			// Validate priority is "spot"
			assert.Equal(t, "spot", pool.Priority,
				"Spot pool %s should have priority 'spot'", poolName)

			// Validate eviction policy is "Delete" (required for AKS spot)
			assert.Equal(t, "Delete", pool.EvictionPolicy,
				"Spot pool %s should have eviction_policy 'Delete'", poolName)

			// Validate spot_max_price is set (either -1 for unlimited or a positive value)
			assert.True(t, pool.SpotMaxPrice == -1 || pool.SpotMaxPrice > 0,
				"Spot pool %s should have spot_max_price of -1 (on-demand ceiling) or a positive value, got %f",
				poolName, pool.SpotMaxPrice)

			// Validate min_count is 0 (spot pools should be able to scale to zero)
			assert.Equal(t, 0, pool.MinCount,
				"Spot pool %s should have min_count 0 to allow scaling to zero during capacity shortages",
				poolName)

			// Validate max_count is reasonable (greater than 0)
			assert.Greater(t, pool.MaxCount, 0,
				"Spot pool %s should have max_count > 0", poolName)

			// Validate at least one zone is configured
			assert.NotEmpty(t, pool.Zones,
				"Spot pool %s should have at least one availability zone", poolName)

			// Validate VM size is set
			assert.NotEmpty(t, pool.VMSize,
				"Spot pool %s should have a VM size configured", poolName)
		})
	}
}

// TestAksAutoscalerProfile validates the cluster autoscaler is configured
// correctly for spot node handling.
func TestAksAutoscalerProfile(t *testing.T) {
	if os.Getenv("RUN_INTEGRATION_TESTS") != "true" {
		t.Skip("Skipping integration test. Set RUN_INTEGRATION_TESTS=true to run.")
	}

	t.Parallel()

	config := NewTestConfig()
	uniqueID := random.UniqueId()
	resourceGroupName := fmt.Sprintf("%s-autoscaler-%s", config.ResourceGroupPrefix, uniqueID)
	clusterName := fmt.Sprintf("%s-autoscaler-%s", config.ClusterNamePrefix, uniqueID)

	terraformOptions := &terraform.Options{
		TerraformDir:    config.TerraformDir,
		TerraformBinary: config.TerraformBinary,
		Vars: map[string]interface{}{
			"resource_group_name": resourceGroupName,
			"cluster_name":        clusterName,
			"location":            config.Location,
		},
		MaxRetries:         config.MaxRetries,
		TimeBetweenRetries: config.RetryDelay,
		NoColor:            true,
	}

	defer deferredDestroy(t, terraformOptions, config, resourceGroupName)
	terraform.InitAndApply(t, terraformOptions)

	// Get the priority expander configmap output
	priorityExpanderManifest := terraform.Output(t, terraformOptions, "priority_expander_manifest")

	// Validate that priority expander config contains spot pool references
	assert.Contains(t, priorityExpanderManifest, "spot",
		"Priority expander should reference spot node pools")

	// Validate that priority expander config contains standard pool fallback
	assert.Contains(t, priorityExpanderManifest, "std",
		"Priority expander should reference standard node pools for fallback")
}

// TestAksNodePoolDiversity validates that spot pools use diverse VM sizes
// to reduce correlated eviction risk.
func TestAksNodePoolDiversity(t *testing.T) {
	if os.Getenv("RUN_INTEGRATION_TESTS") != "true" {
		t.Skip("Skipping integration test. Set RUN_INTEGRATION_TESTS=true to run.")
	}

	t.Parallel()

	config := NewTestConfig()
	uniqueID := random.UniqueId()
	resourceGroupName := fmt.Sprintf("%s-diversity-%s", config.ResourceGroupPrefix, uniqueID)
	clusterName := fmt.Sprintf("%s-diversity-%s", config.ClusterNamePrefix, uniqueID)

	terraformOptions := &terraform.Options{
		TerraformDir:    config.TerraformDir,
		TerraformBinary: config.TerraformBinary,
		Vars: map[string]interface{}{
			"resource_group_name": resourceGroupName,
			"cluster_name":        clusterName,
			"location":            config.Location,
		},
		MaxRetries:         config.MaxRetries,
		TimeBetweenRetries: config.RetryDelay,
		NoColor:            true,
	}

	defer deferredDestroy(t, terraformOptions, config, resourceGroupName)
	terraform.InitAndApply(t, terraformOptions)

	// Get spot node pools output as JSON
	spotNodePoolsJSON := terraform.OutputJson(t, terraformOptions, "spot_node_pools")
	
	var spotNodePools map[string]SpotNodePoolInfo
	err := json.Unmarshal([]byte(spotNodePoolsJSON), &spotNodePools)
	require.NoError(t, err, "Failed to parse spot_node_pools output")

	// Collect unique VM sizes
	vmSizes := make(map[string]bool)
	for _, pool := range spotNodePools {
		vmSizes[pool.VMSize] = true
	}

	// Validate that we have at least 2 different VM sizes for diversity
	assert.GreaterOrEqual(t, len(vmSizes), 2,
		"Expected at least 2 different VM sizes for spot pool diversity, got %d: %v",
		len(vmSizes), vmSizes)

	// Collect unique zones
	zones := make(map[string]bool)
	for _, pool := range spotNodePools {
		for _, zone := range pool.Zones {
			zones[zone] = true
		}
	}

	// Validate that pools span at least 2 zones for availability
	assert.GreaterOrEqual(t, len(zones), 2,
		"Expected spot pools to span at least 2 availability zones, got %d: %v",
		len(zones), zones)
}
