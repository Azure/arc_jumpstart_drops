variable "client_id" {
  description = "Please enter your client ID (AppId)"
  type        = string
  sensitive   = true
}

variable "client_secret" {
  description = "Please enter your password/application secret"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Please enter your tenant ID - Entra ID"
  type        = string
}

variable "subscription_id" {
  description = "Please enter your Azure ID subscription"
  type        = string
}

variable "admin_username" {
  description = "Windows VM user name"
  type        = string
}

variable "admin_password" {
  description = "Windows VM password"
  type        = string
  sensitive   = true
}
