resource "google_logging_metric" "cometbft_block_height" {
  name        = "cometbft_block_height"
  description = "Extract CometBFT committed block height from syslog jsonPayload.message"
  project     = var.project_id

  filter = <<-EOT
    resource.type="gce_instance"
    logName="projects/${var.project_id}/logs/syslog"
    jsonPayload.message=~"Committed state.*height="
  EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "DISTRIBUTION"
    unit         = "1"
    display_name = "CometBFT Block Height Distribution"

    labels {
      key        = "instance_name"
      value_type = "STRING"
    }

    labels {
      key        = "zone"
      value_type = "STRING"
    }
  }

  bucket_options {
    linear_buckets {
      num_finite_buckets = 10
      width              = 500000
      offset             = 0
    }
  }

  value_extractor = "REGEXP_EXTRACT(jsonPayload.message, \"height=([0-9]+)\")"

  label_extractors = {
    instance_name = "EXTRACT(labels.compute.googleapis.com/resource_name)"
    zone          = "EXTRACT(resource.labels.zone)"
  }

  depends_on = [google_project_iam_member.logging]
}
