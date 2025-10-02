# FortiCNAPP Agent Deployment with AWS Systems Manager

Deployment of FortiCNAPP agents for Windows and Linux EC2 instances using AWS Systems Manager.

This solution uses the FortiCNAPP agent installation methods:
- **Linux**: `install.sh` script from [FortiCNAPP docs - Linux Agent Installation](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/538940/installing-using-the-install-sh-script)
- **Windows**: `LWDatacollector.msi` and `config.json` from [FortiCNAPP docs - Windows Agent Installation](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/902600/windows-agent-installation-prerequisites)

## Quick Start

### Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **FortiCNAPP agent token** from your FortiCNAPP account (FortiCNAPP Console > Settings > Agent Tokens)
3. **EC2 instances** with SSM agent installed and proper IAM roles

> **Need to set up SSM?** See the [AWS Systems Manager setup guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup.html) for EC2 instances.

### AWS CloudShell (Recommended)

```bash
# Clone the repository
git clone https://github.com/andrewbearsley/forticnapp-aws-systems-manager-agent-install.git
cd forticnapp-aws-systems-manager-agent-install

# Set AWS region
export AWS_REGION="your-aws-region"

# Check SSM status for all instances
./scripts/check-ssm.sh

# [Optional] Setup SSM on all instances
./scripts/setup-ssm.sh

# [Optional] Setup SSM on specific instances
./scripts/setup-ssm.sh "i-1234567890abcdef0"
./scripts/setup-ssm.sh instances.txt

# Deploy Linux agents
./scripts/deploy-linux.sh "your-agent-token-here"

# Deploy Windows agents
./scripts/deploy-windows.sh "your-agent-token-here"
```

### Check if EC2 Instances are SSM-Ready

Before deploying, verify your instances are managed by Systems Manager:

```bash

# Check specific instances
./scripts/check-ssm.sh "i-1234567890abcdef0 i-0987654321fedcba0"

# Check instances from file
./scripts/check-ssm.sh instances.txt

# Setup SSM on existing instances (if not ready)
./scripts/setup-ssm.sh "i-1234567890abcdef0"
./scripts/setup-ssm.sh instances.txt
```

**Expected output for SSM-ready instances:**
- `PingStatus: Online` 
- `LastPingDateTime: Recent timestamp`
- `PlatformType: Linux` or `Windows`

### Local Environment

If running from your local machine:

```bash
# Clone the repository
git clone https://github.com/andrewbearsley/forticnapp-aws-systems-manager-agent-install.git
cd forticnapp-aws-systems-manager-agent-install

# Ensure AWS CLI is configured
aws configure list

# Deploy agents
export AWS_REGION="your-aws-region"
./scripts/deploy-linux.sh "your-agent-token-here"
./scripts/deploy-windows.sh "your-agent-token-here"
```

### Deploy to Specific Instances

```bash
# Linux - specific instances
./scripts/deploy-linux.sh "your-token" "i-1234567890abcdef0 i-0987654321fedcba0"

# Windows - specific instances
./scripts/deploy-windows.sh "your-token" "i-1234567890abcdef0 i-0987654321fedcba0"

# Using instance list file
./scripts/deploy-linux.sh "your-token" instances.txt
./scripts/deploy-windows.sh "your-token" instances.txt
```

### Instance List Files

For managing large numbers of instances, you can create a file with instance IDs:

```bash
# Create instance list file
cat > instances.txt << EOF
# Production Linux servers
i-1234567890abcdef0
i-0987654321fedcba0

# Production Windows servers
i-abcdef1234567890
i-fedcba0987654321
EOF

# Use with any script
./scripts/setup-ssm.sh instances.txt
./scripts/deploy-linux.sh "your-token" instances.txt
./scripts/check-ssm.sh instances.txt
```

**File format:**
- One instance ID per line
- Lines starting with `#` are comments
- Empty lines are ignored
- See `instances.txt.example` for reference

## AWS Region Support

**Works with all AWS regions!** The scripts automatically:
- Use your current AWS CLI region configuration
- Fall back to `us-east-1` if no region is set
- Allow override via `AWS_REGION` environment variable

```bash
# Use specific region
export AWS_REGION="eu-west-1"
./scripts/deploy-linux.sh "your-token"

# Or specify inline
AWS_REGION="ap-southeast-1" ./scripts/deploy-windows.sh "your-token"
```

## Project Structure

```
forticnapp-aws-systems-manager/
├── scripts/
│   ├── deploy-linux.sh          # Linux agent deployment
│   ├── deploy-windows.sh        # Windows agent deployment
│   ├── check-ssm.sh            # Check SSM readiness
│   └── setup-ssm.sh            # Setup SSM on existing instances
├── test/
│   ├── create-test-instances.sh # Create test EC2 instances
│   ├── cleanup-test-instances.sh # Cleanup test instances
│   └── README.md               # Test environment documentation
├── instances.txt.example       # Example instance list file format
├── README.md                   # This file
├── WITHOUT-SSM.md             # Alternative deployment methods
└── .gitignore                 # Git ignore file
```

## What Happens

### Linux Deployment
1. Downloads official `install.sh` from FortiCNAPP
2. Finds all Linux EC2 instances
3. Runs installation via AWS Systems Manager with correct token syntax
4. Monitors progress and verifies installation

**Installation Command:**
```bash
curl -sSL https://packages.lacework.net/install.sh -o /tmp/install.sh && sudo bash /tmp/install.sh YOUR_TOKEN
```

### Windows Deployment
1. Downloads official `LWDatacollector.msi` installer
2. Creates `config.json` with your agent token
3. Finds all Windows EC2 instances
4. Runs installation via AWS Systems Manager PowerShell
5. Monitors progress and verifies installation

## Verification

### Check Agent Status

**Linux:**
```bash
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --instance-ids "i-1234567890abcdef0" \
  --parameters 'commands=["systemctl status datacollector"]'
```

**Windows:**
```bash
aws ssm send-command \
  --document-name "AWS-RunPowerShellScript" \
  --instance-ids "i-0987654321fedcba0" \
  --parameters 'commands=["Get-Service -Name \"LaceworkAgent\""]'
```

## Troubleshooting

### Common Issues

1. **SSM Agent Not Installed**
   - Ensure SSM agent is installed and running
   - Verify IAM roles have SSM permissions

2. **Network Connectivity**
   - Check security groups allow outbound HTTPS
   - Verify instances can reach FortiCNAPP endpoints

3. **Permission Issues**
   - Ensure deployment user has SSM and EC2 permissions
   - Verify FortiCNAPP token is valid

### Useful Commands

```bash
# Check SSM agent status
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-1234567890abcdef0"

# List recent commands
aws ssm list-commands --max-items 10

# Get command details
aws ssm get-command-invocation --command-id "command-id" --instance-id "i-1234567890abcdef0"
```

## How It Works

### Linux Deployment

The Linux script:
1. Downloads the official `install.sh` script from FortiCNAPP
2. Finds all Linux EC2 instances (or uses specified ones)
3. Runs the installation via AWS Systems Manager with correct token syntax
4. Monitors deployment progress and verifies installation

**Installation Command:**
```bash
curl -sSL https://packages.lacework.net/install.sh -o /tmp/install.sh && sudo bash /tmp/install.sh YOUR_TOKEN
```

**Supported Linux Distributions:**
- Amazon Linux 2
- Ubuntu 18.04+
- CentOS 7+
- RHEL 7+

### Windows Deployment

The Windows script:
1. Downloads the official `LWDatacollector.msi` installer
2. Creates `config.json` with your agent token
3. Finds all Windows EC2 instances (or uses specified ones)
4. Runs the installation via AWS Systems Manager PowerShell
5. Monitors deployment progress and verifies installation

**Supported Windows Versions:**
- Windows Server 2016+
- Windows Server 2019+
- Windows Server 2022+

## Project Structure

```
forticnapp-aws-systems-manager/
├── scripts/
│   ├── deploy-linux.sh          # Linux agent deployment
│   ├── deploy-windows.sh        # Windows agent deployment
│   ├── check-ssm.sh            # Check SSM readiness
│   └── setup-ssm.sh            # Setup SSM on existing instances
├── test/
│   ├── create-test-instances.sh # Create test EC2 instances
│   ├── cleanup-test-instances.sh # Cleanup test instances
│   └── README.md               # Test environment documentation
├── instances.txt.example       # Example instance list file format
├── README.md                   # This file
├── WITHOUT-SSM.md             # Alternative deployment methods
└── .gitignore                 # Git ignore file
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_REGION` | AWS region for deployment | us-east-1 |

## Troubleshooting

### SSM Connection Issues

If instances show "ConnectionLost" status after running `setup-ssm.sh`:

**Root Cause:** The SSM agent needs to be restarted to pick up new IAM role credentials.

**Solutions:**

1. **Restart SSM Agent via SSH:**
   ```bash
   # Get instance public IP
   aws ec2 describe-instances --instance-ids i-1234567890abcdef0 --query 'Reservations[*].Instances[*].PublicIpAddress' --output text
   
   # SSH to instance and restart SSM agent
   ssh -i your-key.pem ec2-user@PUBLIC_IP
   sudo systemctl restart amazon-ssm-agent
   sudo systemctl status amazon-ssm-agent
   ```

2. **Restart EC2 Instance:**
   ```bash
   aws ec2 reboot-instances --instance-ids i-1234567890abcdef0
   ```

3. **Wait for Automatic Restart:**
   - Wait 5-10 minutes for the agent to automatically restart (less reliable)

**Verify Fix:**
```bash
./scripts/check-ssm.sh i-1234567890abcdef0
```

### Common Issues

1. **SSM Agent Not Installed**
   - Ensure SSM agent is installed and running
   - Verify IAM roles have SSM permissions

2. **Network Connectivity**
   - Check security groups allow outbound HTTPS
   - Verify instances can reach FortiCNAPP endpoints

3. **Permission Issues**
   - Ensure deployment user has SSM and EC2 permissions
   - Verify FortiCNAPP token is valid

### Useful Commands

```bash
# Check SSM agent status
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-1234567890abcdef0"

# List recent commands
aws ssm list-commands --max-items 10

# Get command details
aws ssm get-command-invocation --command-id "command-id" --instance-id "i-1234567890abcdef0"
```

## Log Locations

**Linux:**
- Agent logs: `/var/log/lacework/`
- Service status: `systemctl status datacollector`
- SSM logs: `/var/log/amazon/ssm/`

**Windows:**
- Agent logs: `C:\ProgramData\Lacework\Logs\`
- SSM logs: `C:\ProgramData\Amazon\SSM\Logs\`

## Documentation

- [FortiCNAPP Linux Installation](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/538940/installing-using-the-install-sh-script)
- [FortiCNAPP Windows Installation](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/902600/windows-agent-installation-prerequisites)
- [AWS Systems Manager Setup Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup.html)

## Testing

For testing the deployment scripts, you can create test EC2 instances:

```bash
# Create test instances (Linux + Windows with SSM)
cd test && ./create-test-instances.sh

# Wait 2-3 minutes for SSM registration, then check
./scripts/check-ssm.sh

# Test deployment
./scripts/deploy-linux.sh "your-token"
./scripts/deploy-windows.sh "your-token"

# Test with specific instances
./scripts/deploy-linux.sh "your-token" "i-test123 i-test456"
./scripts/deploy-windows.sh "your-token" "i-test789"

# Clean up when done (important to avoid charges!)
cd test && ./cleanup-test-instances.sh
```

**⚠️ Cost Warning**: Test instances incur AWS charges (~$0.05/hour). Always run cleanup when done!

## Troubleshooting

### Common Issues

1. **SSM Agent Not Installed**
   - Ensure SSM agent is installed and running on target instances
   - Verify IAM roles have necessary SSM permissions

2. **Network Connectivity**
   - Check security groups allow outbound HTTPS traffic
   - Verify instances can reach FortiCNAPP endpoints

3. **Permission Issues**
   - Ensure deployment user has SSM and EC2 permissions
   - Verify FortiCNAPP token is valid and not expired

### Log Locations

**Linux:**
- Agent logs: `/var/log/lacework/`
- Service status: `systemctl status datacollector`
- SSM logs: `/var/log/amazon/ssm/`

**Windows:**
- Agent logs: `C:\ProgramData\Lacework\Logs\`
- SSM logs: `C:\ProgramData\Amazon\SSM\Logs\`

## Support and Documentation

- [FortiCNAPP Administration Guide](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/)
- [Linux Installation Guide](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/538940/installing-using-the-install-sh-script)
- [Windows Installation Prerequisites](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/902600/windows-agent-installation-prerequisites)
- [AWS Systems Manager Documentation](https://docs.aws.amazon.com/systems-manager/)

## License

This project is licensed under the MIT License - see the LICENSE file for details.
