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

  # Backup command formats
  direct_backup_validator_cmd = format(
    "ssh ubuntu@%s 'sudo cat /opt/zcash-vote/.cometbft/config/priv_validator_key.json'",
    google_compute_address.validator[0].address
  )

  direct_backup_node_cmd = format(
    "ssh ubuntu@%s 'sudo cat /opt/zcash-vote/.cometbft/config/node_key.json'",
    google_compute_address.validator[0].address
  )

  iap_backup_validator_cmd = format(
    "gcloud compute ssh %s --zone %s --tunnel-through-iap --command='sudo cat /opt/zcash-vote/.cometbft/config/priv_validator_key.json'",
    google_compute_instance.validator.name,
    var.zone
  )

  iap_backup_node_cmd = format(
    "gcloud compute ssh %s --zone %s --tunnel-through-iap --command='sudo cat /opt/zcash-vote/.cometbft/config/node_key.json'",
    google_compute_instance.validator.name,
    var.zone
  )

  backup_validator_map = {
    "true"  = local.direct_backup_validator_cmd
    "false" = local.iap_backup_validator_cmd
  }

  backup_node_map = {
    "true"  = local.direct_backup_node_cmd
    "false" = local.iap_backup_node_cmd
  }
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

output "backup_validator_key_command" {
  description = "Command to print the validator private key (priv_validator_key.json). SENSITIVE - store securely offline."
  value       = local.backup_validator_map[local.ssh_key]
}

output "backup_node_key_command" {
  description = "Command to print the node identity key (node_key.json). SENSITIVE - store securely offline."
  value       = local.backup_node_map[local.ssh_key]
}

output "validator_address_command" {
  description = "Command to show the validator address (safe to share)."
  value       = "${local.ssh_command} 'sudo -u zcash-vote cometbft show-address --home /opt/zcash-vote/.cometbft'"
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

    7. Backup critical keys (MANDATORY for production)
       The validator private key (priv_validator_key.json) and the node identity key (node_key.json)
       are required to recover or move this validator. Back them up securely immediately after
       deployment. These files are sensitive and must NOT be committed to source control.
    
       a. Retrieve the sensitive keys from the deployed instance:
          node key: `${local.backup_node_map[local.ssh_key]}`
          validator key: `${local.backup_validator_map[local.ssh_key]}`
    
       b. Save keys to secure local files, or preferably a password manager, etc.
    
       c. Secure storage recommendations:
          - Store backups offline (encrypted USB, hardware security module, or an encrypted vault)
          - Encrypt files at rest and keep access restricted (GPG, age, or a KMS-backed envelope)
          - Never transmit unencrypted private keys over email or push to public storage
    
    Your CometBFT P2P address which will be shared with peers:
       ${local.cometbft_addr}
    
  EOT
}
