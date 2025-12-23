variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "env_name" {
  type = string
}

variable "job_name" {
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

variable "storage_account_name" {
  type = string
}

variable "storage_account_key" {
  type = string
}

variable "share_name" {
  type = string
}

variable "source_zip_filename" {
  type = string
}
