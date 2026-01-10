variable "resource_group_name" {
  description = "Name of the resource group"
  default     = "rg121"
}

variable "acr_name" {
  description = "Name of the Azure Container Registry"
  default     = "acr121"
}

variable "aks_name" {
  description = "Name of the AKS cluster"
  default     = "cluster121"
}
