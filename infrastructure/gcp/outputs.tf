locals {
  ssh_key = tostring(var.remote_ssh_enabled && var.enable_external_ip)

  ssh_map = {
    "true" = format("ssh ubuntu@%s", google_compute_address.validator[0].address)
    "false" = format("gcloud compute ssh %s --zone %s --tunnel-through-iap", google_compute_instance.validator.name, var.zone)
  }

  ssh_command = local.ssh_map[local.ssh_key]

  comet_map = {
    "true"  = format("%s:%d", google_compute_address.validator[0].address, var.cometbft_p2p_port)
    "false" = format("%s:%d", google_compute_instance.validator.network_interface[0].network_ip, var.cometbft_p2p_port)
  }

  cometbft_addr = local.comet_map[tostring(var.enable_external_ip)]
}

output "instance_name" {
  description = "Name of the validator instance"
  value       = google_compute_instance.validator.name
}

output "instance_id" {
  description = "Instance ID"
  value       = google_compute_instance.validator.instance_id
}

output "external_ip" {
  description = "External IP address of the validator (if enabled)"
  value       = var.enable_external_ip ? google_compute_address.validator[0].address : null
}

output "internal_ip" {
  description = "Internal IP address of the validator"
  value       = google_compute_instance.validator.network_interface[0].network_ip
}

output "zone" {
  description = "Zone where the instance is deployed"
  value       = google_compute_instance.validator.zone
}

output "service_account_email" {
  description = "Service account email"
  value       = google_service_account.validator.email
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = local.ssh_command
}

output "cometbft_p2p_address" {
  description = "CometBFT P2P address for peer configuration"
  value       = local.cometbft_addr
}

output "api_endpoint" {
  description = "API endpoint (if public access is enabled)"
  value       = var.enable_api_public_access && var.enable_external_ip ? "http://${google_compute_address.validator[0].address}:8000" : "Not publicly accessible"
}

output "post_deployment_instructions" {
  description = "Next steps after deployment"
  value       = <<-EOT
    
    Deployment complete! Next steps:
    
    1. SSH to the instance:
       ${local.ssh_command}
    
    2. Check installation logs:
       sudo journalctl -u google-startup-scripts -f
    
    3. After installation completes, configure CometBFT:
       a. Coordinate with other validators to get genesis.json
       b. Place genesis file: sudo -u zcash-vote cp genesis.json /opt/zcash-vote/.cometbft/config/
       c. Configure persistent peers in /opt/zcash-vote/.cometbft/config/config.toml
    
    4. Start services:
       sudo systemctl start cometbft
       sudo systemctl start zcash-vote-server
    
    5. Verify services:
       sudo systemctl status cometbft
       sudo systemctl status zcash-vote-server
       
    6. Check logs:
       sudo journalctl -u cometbft -f
       sudo journalctl -u zcash-vote-server -f
    
    Your CometBFT P2P address for peer configuration:
       ${local.cometbft_addr}
    
  EOT
}
