# Service Account for the validator instance
resource "google_service_account" "validator" {
  account_id   = "${var.validator_name}-sa"
  display_name = "Service Account for ${var.validator_name}"
  description  = "Service account for zcash-vote-server validator node"
}

# IAM roles for the service account
resource "google_project_iam_member" "logging" {
  count   = var.enable_cloud_logging ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.validator.email}"
}


resource "google_project_iam_member" "monitoring" {
  count   = var.enable_cloud_monitoring ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.validator.email}"
}

# Grant Secret Manager access to the validator service account when Tailscale is enabled.
# This allows the startup script to retrieve a stored Tailscale auth key securely.
resource "google_project_iam_member" "secrets_accessor" {
  count   = var.enable_tailscale ? 1 : 0
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.validator.email}"
}

# Firewall rule for SSH access (created only when remote SSH is enabled)
resource "google_compute_firewall" "ssh" {
  count   = var.remote_ssh_enabled ? 1 : 0
  name    = "${var.validator_name}-allow-ssh"
  network = var.network_name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.admin_ip_ranges
  target_tags   = ["${var.validator_name}-ssh"]

  description = "Allow SSH access to ${var.validator_name} when remote_ssh_enabled = true"
}


# Firewall rule for CometBFT P2P (required for validator network)
# This rule is created only when Tailscale is NOT enabled so the P2P port is not exposed to the internet.
resource "google_compute_firewall" "cometbft_p2p" {
  count   = var.enable_tailscale ? 0 : 1
  name    = "${var.validator_name}-allow-cometbft-p2p"
  network = var.network_name

  allow {
    protocol = "tcp"
    ports    = [tostring(var.cometbft_p2p_port)]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.validator_name}"]

  description = "Allow CometBFT P2P connections for ${var.validator_name} (Tailscale disabled)"
}

# Firewall rule to allow SSH from IAP TCP forwarding IP range only.
# This allows `gcloud compute ssh --tunnel-through-iap` while keeping SSH closed to the public.
resource "google_compute_firewall" "ssh_iap" {
  name    = "${var.validator_name}-allow-ssh-iap"
  network = var.network_name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP TCP forwarding source CIDR (documented by Google)
  source_ranges = ["35.235.240.0/20"]

  target_tags   = ["${var.validator_name}"]

  description = "Allow SSH from IAP TCP forwarding only (enables gcloud --tunnel-through-iap)"
}

# Firewall rule for API access (optional)
resource "google_compute_firewall" "api" {
  count   = var.enable_api_public_access ? 1 : 0
  name    = "${var.validator_name}-allow-api"
  network = var.network_name

  allow {
    protocol = "tcp"
    ports    = ["8000"]
  }

  source_ranges = var.api_allowed_ip_ranges
  target_tags   = ["${var.validator_name}"]

  description = "Allow API access to ${var.validator_name}"
}

# Static external IP (optional)
resource "google_compute_address" "validator" {
  count        = var.enable_external_ip ? 1 : 0
  name         = "${var.validator_name}-ip"
  address_type = "EXTERNAL"
  region       = var.region

  labels = var.labels
}

# Disk snapshot schedule (optional)
resource "google_compute_resource_policy" "snapshot_schedule" {
  count  = var.enable_snapshots ? 1 : 0
  name   = "${var.validator_name}-snapshot-schedule"
  region = var.region

  snapshot_schedule_policy {
    schedule {
      dynamic "daily_schedule" {
        for_each = var.snapshot_schedule == "daily" ? [1] : []
        content {
          days_in_cycle = 1
          start_time    = "03:00"
        }
      }

      dynamic "weekly_schedule" {
        for_each = var.snapshot_schedule == "weekly" ? [1] : []
        content {
          day_of_weeks {
            day        = "SUNDAY"
            start_time = "03:00"
          }
        }
      }
    }

    retention_policy {
      max_retention_days    = 7
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
  }
}

# Compute instance for validator
resource "google_compute_instance" "validator" {
  name         = var.validator_name
  machine_type = var.machine_type
  zone         = var.zone

  tags = concat(["${var.validator_name}", "zcash-vote-validator"], var.remote_ssh_enabled ? ["${var.validator_name}-ssh"] : [])

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.boot_disk_size_gb
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = var.network_name
    subnetwork = var.subnet_name

    dynamic "access_config" {
      for_each = var.enable_external_ip ? [1] : []
      content {
        nat_ip = google_compute_address.validator[0].address
      }
    }
  }

  service_account {
    email  = google_service_account.validator.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    ssh-keys               = "ubuntu:${var.admin_ssh_key}"
    enable-oslogin         = "FALSE"
    block-project-ssh-keys = "TRUE"
    remote-ssh-enabled     = tostring(var.remote_ssh_enabled)
  }

  metadata_startup_script = templatefile("${path.module}/scripts/startup.sh", {
    cometbft_version    = var.cometbft_version
    vote_server_repo    = var.vote_server_repo
    vote_server_branch  = var.vote_server_branch
    validator_name      = var.validator_name
    enable_api_access   = var.enable_api_public_access
    api_allowed_ranges  = join(",", var.api_allowed_ip_ranges)
    cometbft_p2p_port   = var.cometbft_p2p_port
  })

  labels = merge(
    var.labels,
    {
      name        = var.validator_name
      environment = var.environment
    }
  )

  allow_stopping_for_update = true

  lifecycle {
    ignore_changes = [
      metadata_startup_script,
    ]
  }
}

# Attach snapshot policy to boot disk
resource "google_compute_disk_resource_policy_attachment" "snapshot" {
  count = var.enable_snapshots ? 1 : 0
  name  = google_compute_resource_policy.snapshot_schedule[0].name
  disk  = google_compute_instance.validator.boot_disk[0].source
  zone  = var.zone
}
