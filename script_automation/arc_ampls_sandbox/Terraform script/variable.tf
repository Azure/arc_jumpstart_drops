# Client ID (AppId) of the Azure AD application (service principal)
variable "client_id" {
  description = "Please enter your Client ID (AppId)"
  type        = string
  default     = "00000000-0000-0000-0000-000000000000" # <-- Replace with your real AppId
}

# Secret/password of the Azure AD application
variable "client_secret" {
  description = "Please enter your application password/secret"
  type        = string
  sensitive   = true
  default     = "fake-client-secret-123" # <-- Replace with your real client secret
}

# Azure Active Directory Tenant ID
variable "tenant_id" {
  description = "Please enter your Azure AD Tenant ID"
  type        = string
  default     = "11111111-1111-1111-1111-111111111111" # <-- Replace with your real tenant ID
}

# Azure Subscription ID
variable "subscription_id" {
  description = "Please enter your Azure Subscription ID"
  type        = string
  default     = "22222222-2222-2222-2222-222222222222" # <-- Replace with your real subscription ID
}

# Admin username for the Windows VM
variable "admin_username" {
  description = "Username for the Windows VM"
  type        = string
  default     = "arcadmin" # <-- You can change this if needed
}

# Admin password for the Windows VM
variable "admin_password" {
  description = "Password for the Windows VM"
  type        = string
  sensitive   = true
  default     = "ArcP@ssword123!" # <-- Replace with a secure password
}
