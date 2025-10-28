# AWS Deployment for zcash-vote-server

Coming soon! AWS deployment support is planned for future releases.

## Planned Features

- EC2 instance provisioning
- VPC and security group configuration
- Elastic IP allocation
- CloudWatch monitoring integration
- Automated snapshots via EBS

## Contributing

If you'd like to contribute AWS support, please see the GCP implementation in `../gcp/` as a reference.

The implementation should follow similar patterns:
- Use common installation scripts from `../common/scripts/`
- Support environment variable configuration
- Provide clear documentation
- Include security best practices

## In the Meantime

You can manually deploy on AWS by:
1. Launch an Ubuntu 22.04 EC2 instance
2. SSH to the instance
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
