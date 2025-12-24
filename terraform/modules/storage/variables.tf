variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "share_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
