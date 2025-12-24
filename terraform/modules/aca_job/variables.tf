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

variable "share_name" {
  type = string
}

variable "source_zip_filename" {
  type = string
}

variable "app_subdirectory" {
  type = string
  description = "Subdirectory in the app folder (e.g. java, go, python)"
}

variable "image_name" {
  type = string
  description = "Name of the image to push to ACR"
}

variable "tags" {
  type    = map(string)
  default = {}
}
