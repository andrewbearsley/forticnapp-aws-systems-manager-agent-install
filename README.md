# FortiCNAPP Agent Deployment with AWS Systems Manager

Scripts to deploy FortiCNAPP agents on Linux and Windows EC2 instances using AWS Systems Manager.

## Overview

This solution uses the official FortiCNAPP agent installation methods:
- **Linux**: Official `install.sh` script from [FortiCNAPP documentation](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/538940/installing-using-the-install-sh-script)
- **Windows**: Official `LWDatacollector.msi` and `config.json` from [Windows installation prerequisites](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/902600/windows-agent-installation-prerequisites)

## Prerequisites

- AWS CLI configured with appropriate permissions
- AWS Systems Manager (SSM) agent installed on target EC2 instances
- EC2 instances with appropriate IAM roles for SSM access
- FortiCNAPP agent token

> **Note**: If your EC2 instances don't have AWS Systems Manager set up, see [WITHOUT-SSM.md](WITHOUT-SSM.md) for alternative deployment methods.
> 
> **Need to set up SSM?** See the [AWS Systems Manager setup guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup.html) for EC2 instances.

## AWS CloudShell Usage

AWS CloudShell is pre-configured with AWS CLI and works perfectly with these scripts:

```bash
# Clone the repository
git clone https://github.com/andrewbearsley/forticnapp-aws-systems-manager-agent-install.git
cd forticnapp-aws-systems-manager-agent-install

# Deploy Linux agents
cd scripts && ./deploy-linux.sh "your-agent-token-here"

# Deploy Windows agents  
cd scripts && ./deploy-windows.sh "your-agent-token-here"
```

### Check if EC2 Instances are SSM-Ready

Before deploying, verify your instances are managed by Systems Manager:

```bash
# Check all instances in current region
cd scripts && ./check-ssm.sh

# Check specific instances
cd scripts && ./check-ssm.sh "i-1234567890abcdef0 i-0987654321fedcba0"

# Setup SSM on existing instances (if not ready)
cd scripts && ./setup-ssm.sh "i-1234567890abcdef0"

# Manual check commands
aws ssm describe-instance-information --query 'InstanceInformationList[*].[InstanceId,ComputerName,PlatformType,PingStatus]' --output table
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-1234567890abcdef0"
```

**Expected output for SSM-ready instances:**
- `PingStatus: Online` 
- `LastPingDateTime: Recent timestamp`
- `PlatformType: Linux` or `Windows`

## AWS Region Support

**Works with all AWS regions!** The scripts automatically:
- Use your current AWS CLI region configuration
- Fall back to `us-east-1` if no region is set
- Allow override via `AWS_REGION` environment variable

```bash
# Use specific region
export AWS_REGION="eu-west-1"
cd scripts && ./deploy-linux.sh "your-token"

# Or specify inline
AWS_REGION="ap-southeast-1" cd scripts && ./deploy-windows.sh "your-token"
```

## Project Structure

```
forticnapp-aws-systems-manager/
├── README.md
├── QUICKSTART.md
├── WITHOUT-SSM.md              # Alternative deployment methods
├── LICENSE
├── scripts/
│   ├── check-ssm.sh            # Check SSM readiness
│   ├── setup-ssm.sh            # Setup SSM on existing instances
│   ├── deploy-linux.sh          # Linux deployment script
│   └── deploy-windows.sh       # Windows deployment script
└── test/
    ├── README.md               # Test environment documentation
    ├── create-test-instances.sh # Create test EC2 instances
    └── cleanup-test-instances.sh # Clean up test resources
```

## Quick Start

### Deploy Linux Agents

```bash
cd scripts
./deploy-linux.sh "your-agent-token-here"
```

### Deploy Windows Agents

```bash
cd scripts
./deploy-windows.sh "your-agent-token-here"
```

### Deploy to Specific Instances

```bash
# Linux
cd scripts && ./deploy-linux.sh "your-token" "i-1234567890abcdef0 i-0987654321fedcba0"

# Windows
cd scripts && ./deploy-windows.sh "your-token" "i-1234567890abcdef0 i-0987654321fedcba0"
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

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_REGION` | AWS region for deployment | us-east-1 |

## Verification

### Check Agent Status

**Linux:**
```bash
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --instance-ids "i-1234567890abcdef0" \
  --parameters 'commands=["systemctl status lacework"]'
```

**Windows:**
```bash
aws ssm send-command \
  --document-name "AWS-RunPowerShellScript" \
  --instance-ids "i-0987654321fedcba0" \
  --parameters 'commands=["Get-Service -Name \"LaceworkAgent\""]'
```

### Monitor Agent Logs

**Linux:**
```bash
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --instance-ids "i-1234567890abcdef0" \
  --parameters 'commands=["journalctl -u lacework -f"]'
```

**Windows:**
```bash
aws ssm send-command \
  --document-name "AWS-RunPowerShellScript" \
  --instance-ids "i-0987654321fedcba0" \
  --parameters 'commands=["Get-WinEvent -FilterHashtable @{LogName=\"Application\"; ProviderName=\"LaceworkAgent\"} -MaxEvents 50"]'
```

## Testing

For testing the deployment scripts, you can create test EC2 instances:

```bash
# Create test instances (Linux + Windows with SSM)
cd test && ./create-test-instances.sh

# Wait 2-3 minutes for SSM registration, then check
cd ../scripts && ./check-ssm.sh

# Test deployment
cd scripts && ./deploy-linux.sh "your-token"
cd scripts && ./deploy-windows.sh "your-token"

# Clean up when done (important to avoid charges!)
cd ../test && ./cleanup-test-instances.sh
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
