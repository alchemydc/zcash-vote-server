# GCP Deployment for zcash-vote-server

This directory contains OpenTofu/Terraform configuration for deploying a zcash-vote-server validator node on Google Cloud Platform.

## Prerequisites

1. **OpenTofu or Terraform** installed (>= 1.0)
   ```bash
   # Install OpenTofu (recommended)
   brew install opentofu
   
   # Or use Terraform
   brew install terraform
   ```

2. **Google Cloud SDK** installed and configured
   ```bash
   # Install gcloud CLI
   brew install google-cloud-sdk
   
   # Authenticate
   gcloud auth login
   ```

3. **SSH key pair** for instance access (without GCP IAP proxying)
   ```bash
   # Generate if you don't have one
   ssh-keygen -t rsa -b 4096 -C "your-email@example.com"
   ```

4. **GCP Project** with billing enabled
   - For new projects: Organization access and billing account
   - For existing projects: Project Owner or Editor role

## Bootstrap Setup

**IMPORTANT:** Before deploying validators, you must run the bootstrap script to set up GCP project infrastructure.

### What Bootstrap Does

The bootstrap script (`bootstrap.sh`) prepares your GCP project by:
- Creating or configuring a GCP project
- Enabling required APIs (Compute, IAM, Logging, Monitoring)
- Creating a Terraform service account with minimal permissions
- Configuring short-lived access tokens via service account impersonation
- Optionally creating a GCS bucket for remote state storage

### Bootstrap for Existing Project

If you have an existing GCP project:

```bash
# 1. Configure bootstrap variables
cp gcloud.env.example gcloud.env
nano gcloud.env  # Set TF_VAR_project_id, region, zone

# 2. Run bootstrap
./bootstrap.sh

# 3. (Optional) Use remote state
./bootstrap.sh --with-state-bucket
```

### Bootstrap for New Project

If you want to create a new GCP project:

```bash
# 1. Configure bootstrap variables
cp gcloud.env.example gcloud.env
nano gcloud.env  # Set TF_VAR_project_id, TF_VAR_org_id, TF_VAR_billing_account

# 2. Run bootstrap with project creation
./bootstrap.sh --create-project --with-state-bucket
```

Get your organization ID and billing account:
```bash
gcloud organizations list --format="value(ID)"
gcloud billing accounts list --format="value(name)"
```

### Bootstrap Output

After successful bootstrap:
- Terraform service account created: `terraform@PROJECT_ID.iam.gserviceaccount.com`
- IAM roles granted for infrastructure management
- Short-lived token generation configured in `gcloud.env`
- Backend configuration created (if using `--with-state-bucket`)
- Terraform initialized and ready to use

### Important Notes

- Access tokens expire after 1 hour
- Re-source `gcloud.env` to get a new token: `source gcloud.env`
- The bootstrap only needs to be run once per project
- Use `cleanup.sh` to remove bootstrap resources if needed

## Quick Start

### 1. Configure Variables

Copy the example environment file and fill in your values:

```bash
cp gcloud.env.example gcloud.env
nano gcloud.env
```

Required values:
- `TF_VAR_project_id`: Your GCP project ID
- `TF_VAR_validator_name`: Unique name for this validator
- `TF_VAR_admin_ssh_key`: Your SSH public key
- `TF_VAR_admin_ip_ranges`: Your IP address for SSH access

### 2. Initialize OpenTofu

```bash
# Load environment variables
source gcloud.env

# Initialize
tofu init
```

### 3. Plan Deployment

```bash
# Review what will be created
tofu plan
```

### 4. Deploy

```bash
# Create infrastructure
tofu apply
```

Review the planned changes and type `yes` to proceed.

## Deployment Modes

This Terraform module supports two deployment modes, controlled by the `TF_VAR_deployment_mode` variable:

1.  **Docker (Default)**: `export TF_VAR_deployment_mode="docker"`
    -   Provisions a VM with Docker Engine and the Ops Agent.
    -   Does **NOT** automatically compile or start the validator software.
    -   **Action Required**: You must SSH into the instance and run the setup client manually.
    -   **Pros**: Faster provisioning, cleaner environment.
    -   **Cons**: Relies on pre-built binaries and Docker images (trust requirement).

2.  **Legacy (Source Build)**: `export TF_VAR_deployment_mode="legacy"`
    -   Compiles `zcash-vote-server` and `cometbft` from source.
    -   Installs and starts systemd services automatically.
    -   **Pros**: Full control over the build process, no binary trust required.
    -   **Cons**: Slow provisioning (compilation takes time), more complex startup script.

### Docker Mode Security Assumptions

If you choose the Docker mode (default), be aware of the following:
*   **Trust**: You trust the pre-compiled `client` binary and the `hhanh00/zcash-vote-docker` images.
*   **Privilege**: The setup script adds the `zcash-vote` user to the `docker` group, effectively granting root-level access.
*   **Manual Step**: The voting software will not run until you manually execute the client.

### Docker Mode Workflow

1.  **Provision**: `tofu apply`
2.  **Connect**: `tofu output ssh_command`
3.  **Setup**:
    ```bash
    sudo su - zcash-vote
    ./client-x86_64 //$COORDINATOR_IP$:$COORDINATOR_PORT <your-node-name>
    ```


### 5. Post-Deployment Configuration

After deployment completes, the instance will automatically:
- Install all dependencies
- Build zcash-vote-server
- Install CometBFT
- Set up systemd services (but not start them)

You must manually configure:

1. **SSH to the instance:**
   ```bash
   # Get SSH command from outputs
   tofu output ssh_command
   
   # Connect
   ssh ubuntu@<EXTERNAL_IP>
   ```

2. **Coordinate with other validators** to get:
   - genesis.json file
   - Peer node IDs and addresses

3. **Configure CometBFT:**
   ```bash
   # Copy genesis file
   sudo -u zcash-vote cp genesis.json /opt/zcash-vote/.cometbft/config/
   
   # Edit config to add peers
   sudo -u zcash-vote nano /opt/zcash-vote/.cometbft/config/config.toml
   # Update persistent_peers line
   ```

4. **Start services:**
   ```bash
   sudo systemctl start cometbft
   sudo systemctl start zcash-vote-server
   ```

5. **Verify operation:**
   ```bash
   sudo systemctl status cometbft
   sudo systemctl status zcash-vote-server
   sudo journalctl -u cometbft -f
   ```

See `/opt/zcash-vote/POST_DEPLOYMENT.md` on the instance for detailed instructions.

## Configuration Options

### Network Security

By default:
- SSH is restricted to IPs in `admin_ip_ranges`
- CometBFT P2P is open for the validator network and the port is configurable via `TF_VAR_cometbft_p2p_port` (default: `26656`)
  - The configured port is applied at both the GCP firewall (defense-in-depth) and the instance-level UFW rules by the startup scripts.
  - To change the port, set the variable in your `gcloud.env` before running OpenTofu/terraform:
    ```bash
    # edit gcloud.env or export directly
    export TF_VAR_cometbft_p2p_port=26666
    source gcloud.env
    tofu plan
    ```
  - After deployment, the Terraform output `cometbft_p2p_address` will include the chosen port for peer configuration.
- API (port 8000) is NOT publicly accessible

To enable public API access:
```bash
export TF_VAR_enable_api_public_access=true
export TF_VAR_api_allowed_ip_ranges='["0.0.0.0/0"]'
```

### Machine Type

Default is `e2-standard-2` (2 vCPU, 8GB RAM). To change:
```bash
export TF_VAR_machine_type="e2-medium"  # Smaller (2 vCPU, 4GB)
export TF_VAR_machine_type="e2-standard-4"  # Larger (4 vCPU, 16GB)
```

### Disk Size

Default boot disk is 100GB. To change:
```bash
export TF_VAR_boot_disk_size_gb=200
```

### Snapshots

Automatic daily snapshots are enabled by default. To disable or change:
```bash
export TF_VAR_enable_snapshots=false
# or
export TF_VAR_snapshot_schedule="weekly"
```

## Outputs

After deployment, useful information is available via outputs:

```bash
# Get all outputs
tofu output

# Get specific output
tofu output external_ip
tofu output cometbft_p2p_address
tofu output post_deployment_instructions
```

## State Management

### Local State (Default)

By default, Terraform state is stored locally in `terraform.tfstate`. This is fine for:
- Testing and development
- Single-operator deployments
- Non-production environments

### Remote State (Recommended for Production)

For production or team environments, use the bootstrap script to create remote state storage:

```bash
# Bootstrap with remote state bucket
./bootstrap.sh --with-state-bucket
```

This automatically:
- Creates a GCS bucket: `PROJECT_ID-zcash-vote-tfstate`
- Enables versioning on the bucket
- Generates `backend.tf` configuration
- Initializes Terraform with remote state

If you've already bootstrapped without `--with-state-bucket`, you can:

1. Create bucket manually:
   ```bash
   PROJECT_ID=$(gcloud config get-value project)
   gsutil mb -l us-central1 gs://${PROJECT_ID}-zcash-vote-tfstate
   gsutil versioning set on gs://${PROJECT_ID}-zcash-vote-tfstate
   ```

2. Create `backend.tf`:
   ```hcl
   terraform {
     backend "gcs" {
       bucket = "YOUR_PROJECT_ID-zcash-vote-tfstate"
       prefix = "validators"
     }
   }
   ```

3. Migrate existing state:
   ```bash
   source gcloud.env
   tofu init -migrate-state
   ```

## Monitoring

The instance includes:
- GCP Cloud Logging integration
- Systemd journal logs
- Service status monitoring

View logs:
```bash
# On the instance
sudo journalctl -u cometbft -f
sudo journalctl -u zcash-vote-server -f

# Or via GCP Console
gcloud logging read "resource.type=gce_instance AND resource.labels.instance_id=INSTANCE_ID"
```

## Maintenance

### Update Software

To update zcash-vote-server or CometBFT:

```bash
# SSH to instance
ssh ubuntu@<IP>

# Update vote server
cd /opt/zcash-vote/zcash-vote-server
sudo -u zcash-vote git pull
sudo -u zcash-vote cargo build --release
sudo systemctl restart zcash-vote-server

# Update CometBFT (download new version manually)
```

### Backup

Automatic snapshots are enabled. To create manual backup:
```bash
gcloud compute disks snapshot DISK_NAME --zone=ZONE
```

### Destroy Infrastructure

To remove all resources:
```bash
source gcloud.env
tofu destroy
```

**Warning:** This will permanently delete the validator instance and all data.

## Troubleshooting

### Can't SSH to instance
- Verify your IP is in `admin_ip_ranges`
- Check firewall rules: `gcloud compute firewall-rules list`
- Try using gcloud: `gcloud compute ssh INSTANCE_NAME --zone=ZONE`

### Services won't start
- Check startup script logs: `sudo journalctl -u google-startup-scripts -f`
- Verify installation: `sudo systemctl status cometbft`
- Check for errors: `/var/log/zcash-vote-setup.log`

### Not syncing blocks
- Verify genesis.json is configured
- Check persistent_peers configuration
- Ensure network connectivity to other validators
- Verify at least 2/3 of validators are online

## Support

For issues specific to:
- Infrastructure code: File issue in this repository
- zcash-vote-server: https://github.com/alchemydc/zcash-vote-server/issues
- CometBFT: https://github.com/cometbft/cometbft/issues
