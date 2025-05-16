variable "client_id" {
  description = "Veuillez insérer votre client ID (AppId)"
  type        = string
  sensitive   = true
}

variable "client_secret" {
  description = "Veuillez insérer votre mot de passe/secret d'application"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Veuillez insérer votre tenant ID Azure AD"
  type        = string
}

variable "subscription_id" {
  description = "Veuillez insérer votre subscription ID Azure"
  type        = string
}

variable "admin_username" {
  description = "Nom d'utilisateur de la VM Windows"
  type        = string
}

variable "admin_password" {
  description = "Mot de passe de la VM Windows"
  type        = string
  sensitive   = true
}
