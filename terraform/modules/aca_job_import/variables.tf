variable "job_name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "container_app_environment_id" {
  type = string
}

variable "acr_id" {
  type = string
}

variable "acr_login_server" {
  type = string
}

variable "acr_username" {
  type = string
  sensitive = true
}

variable "acr_password" {
  type = string
  sensitive = true
}

variable "images_to_copy" {
  type        = map(string)
  description = "Map of source image to destination tag (without registry prefix)"
  # Example: { "maven:3.9" = "maven:3.9", "cgr.dev/chainguard/jre:latest" = "chainguard/jre:latest" }
}

variable "tags" {
  type    = map(string)
  default = {}
}
