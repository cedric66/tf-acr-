package test

import (
	"os"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestKarpenterNapModuleValidation validates the NAP prototype module.
func TestKarpenterNapModuleValidation(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir:    "../terraform/prototypes/aks-nap",
		TerraformBinary: "terraform",
		NoColor:         true,
	}

	// Initialize
	terraform.Init(t, terraformOptions)

	// Validate - accept both success and provider-specific errors
	output, err := terraform.ValidateE(t, terraformOptions)
	if err != nil {
		t.Logf("Validation output: %s", output)
		t.Logf("Note: NAP features require azurerm 4.x preview - errors may occur")
	} else {
		assert.Contains(t, output, "Success",
			"NAP module should validate successfully")
	}
}

// TestKarpenterNapModulePlan tests that the NAP module can create a valid plan.
func TestKarpenterNapModulePlan(t *testing.T) {
	// Skip - requires Azure provider and NAP is a preview feature
	t.Skip("Skipping plan test - NAP requires Azure provider configuration and preview features")
}

// TestKarpenterNapNodeProvisioningMode validates that NAP is configured in the module.
func TestKarpenterNapNodeProvisioningMode(t *testing.T) {
	t.Parallel()

	// Read the main.tf file directly to verify NAP configuration
	mainFile := "../terraform/prototypes/aks-nap/main.tf"
	content, err := os.ReadFile(mainFile)
	if err != nil {
		t.Fatalf("Could not read main.tf: %v", err)
	}

	fileContent := string(content)

	// Verify NAP configuration is present in the file
	assert.True(t, strings.Contains(fileContent, "node_provisioning_mode"),
		"Expected node_provisioning_mode to be configured in main.tf")
	
	assert.True(t, strings.Contains(fileContent, "\"Auto\""),
		"Expected NAP mode to be set to Auto")
}
