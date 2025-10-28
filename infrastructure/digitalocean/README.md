# DigitalOcean Deployment for zcash-vote-server

Coming soon! DigitalOcean deployment support is planned for future releases.

## Planned Features

- Droplet provisioning
- VPC and firewall configuration
- Reserved IP allocation
- DigitalOcean monitoring integration
- Automated snapshots

## Contributing

If you'd like to contribute DigitalOcean support, please see the GCP implementation in `../gcp/` as a reference.

The implementation should follow similar patterns:
- Use common installation scripts from `../common/scripts/`
- Support environment variable configuration
- Provide clear documentation
- Include security best practices

## In the Meantime

You can manually deploy on DigitalOcean by:
1. Create an Ubuntu 22.04 Droplet
2. SSH to the droplet
3. Run the common installation scripts manually:
   ```bash
   curl -O https://raw.githubusercontent.com/alchemydc/zcash-vote-server/main/infrastructure/common/scripts/install-base.sh
   curl -O https://raw.githubusercontent.com/alchemydc/zcash-vote-server/main/infrastructure/common/scripts/install-cometbft.sh
   curl -O https://raw.githubusercontent.com/alchemydc/zcash-vote-server/main/infrastructure/common/scripts/build-vote-server.sh
   
   sudo bash install-base.sh
   sudo bash install-cometbft.sh
   sudo bash build-vote-server.sh
   ```
4. Configure CometBFT and start services as documented in the GCP guide

## DigitalOcean-Specific Considerations

- Droplet size: Standard 4GB+ recommended (s-2vcpu-4gb or larger)
- Block storage: Consider attaching a volume for blockchain data
- Firewall: Use DigitalOcean Cloud Firewalls for port management
- Monitoring: Enable DigitalOcean monitoring and alerts
