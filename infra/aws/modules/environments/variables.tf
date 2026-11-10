variable "environments_path" {
  type        = string
  description = "Folder with one <service>.yaml per app."
}

variable "github_owner_id" {
  type        = string
  default     = ""
  description = "GitHub ID of the owner of every app repo, for ID-form OIDC subjects. Empty when the caller does not read github_subjects."
}
