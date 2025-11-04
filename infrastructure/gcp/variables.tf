variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for compute instance"
  type        = string
  default     = "us-central1-a"
}

variable "validator_name" {
  description = "Unique name for this validator node"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "production"
}

variable "machine_type" {
  description = "GCE machine type"
  type        = string
  default     = "e2-standard-2"
}

variable "boot_disk_size_gb" {
  description = "Size of boot disk in GB"
  type        = number
  default     = 100
}

variable "network_name" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "subnet_name" {
  description = "VPC subnet name"
  type        = string
  default     = "default"
}

variable "enable_external_ip" {
  description = "Whether to assign an external IP address"
  type        = bool
  default     = true
}

variable "admin_ssh_key" {
  description = "SSH public key for admin access"
  type        = string
}

variable "admin_ip_ranges" {
  description = "IP CIDR ranges allowed to SSH to the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "remote_ssh_enabled" {
  description = "Allow direct remote SSH (opens TCP/22). Default: false"
  type        = bool
  default     = false
}

variable "enable_api_public_access" {
  description = "Whether to allow public access to the API port (8000)"
  type        = bool
  default     = false
}

variable "api_allowed_ip_ranges" {
  description = "IP CIDR ranges allowed to access the API port"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_cloud_monitoring" {
  description = "Enable GCP Cloud Monitoring"
  type        = bool
  default     = true
}

variable "enable_cloud_logging" {
  description = "Enable GCP Cloud Logging"
  type        = bool
  default     = true
}

variable "enable_snapshots" {
  description = "Enable automatic disk snapshots"
  type        = bool
  default     = true
}

variable "snapshot_schedule" {
  description = "Snapshot schedule (daily, weekly)"
  type        = string
  default     = "daily"
}

variable "cometbft_version" {
  description = "CometBFT version to install"
  type        = string
  default     = "v0.38.0"
}

variable "vote_server_repo" {
  description = "Git repository URL for zcash-vote-server"
  type        = string
  default     = "https://github.com/alchemydc/zcash-vote-server"
}

variable "vote_server_branch" {
  description = "Git branch to checkout"
  type        = string
  default     = "main"
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    managed_by = "opentofu"
    component  = "zcash-vote-server"
  }
}

variable "cometbft_p2p_port" {
  description = "CometBFT P2P network port"
  type        = number
  default     = 26656

  validation {
    condition     = var.cometbft_p2p_port >= 1024 && var.cometbft_p2p_port <= 65535
    error_message = "Port must be between 1024 and 65535"
  }
}

# Tailscale integration variables
variable "enable_tailscale" {
  description = "Enable Tailscale for encrypted P2P networking"
  type        = bool
  default     = false
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key for headless authentication (sensitive)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tailscale_tailnet" {
  description = "Tailscale tailnet name (e.g., myorg.tailscale.net)"
  type        = string
  default     = ""
}

variable "tailscale_advertise_tags" {
  description = "Tailscale ACL tags to advertise (e.g., tag:validator)"
  type        = list(string)
  default     = []
}
