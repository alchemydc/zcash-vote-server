# Backend configuration for OpenTofu/Terraform state storage
# Uncomment and configure after creating a GCS bucket for state storage

# terraform {
#   backend "gcs" {
#     bucket = "your-project-terraform-state"
#     prefix = "zcash-vote-server/validators"
#   }
# }

# To create the state bucket, run:
# gcloud storage buckets create gs://your-project-terraform-state \
#   --project=YOUR_PROJECT_ID \
#   --location=US \
#   --uniform-bucket-level-access

# To enable versioning for state backup:
# gcloud storage buckets update gs://your-project-terraform-state --versioning
