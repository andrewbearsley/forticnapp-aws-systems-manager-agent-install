# FortiCNAPP Agent Deployment - Quick Start

Simple deployment of FortiCNAPP agents using official installation methods and AWS Systems Manager.

## Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **FortiCNAPP agent token** from your account
3. **EC2 instances** with SSM agent installed and proper IAM roles

> **Need to set up SSM?** See the [AWS Systems Manager setup guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup.html) for EC2 instances.

## AWS CloudShell (Recommended)

AWS CloudShell is pre-configured and ready to use:

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
```

**Look for:**
- `PingStatus: Online` 
- `LastPingDateTime: Recent timestamp`
- `PlatformType: Linux` or `Windows`

## Local Environment

If running from your local machine:

```bash
# Clone the repository
git clone https://github.com/andrewbearsley/forticnapp-aws-systems-manager-agent-install.git
cd forticnapp-aws-systems-manager-agent-install

# Ensure AWS CLI is configured
aws configure list

# Deploy agents
cd scripts && ./deploy-linux.sh "your-agent-token-here"
cd scripts && ./deploy-windows.sh "your-agent-token-here"
```

## AWS Region Support

**Works with all AWS regions!** The scripts automatically detect your AWS CLI region configuration.

```bash
# Check current region
aws configure get region

# Use specific region
export AWS_REGION="eu-west-1"
cd scripts && ./deploy-linux.sh "your-token"

# Or specify inline
AWS_REGION="ap-southeast-1" cd scripts && ./deploy-windows.sh "your-token"
```

## Deploy to Specific Instances

```bash
# Linux - specific instances
cd scripts && ./deploy-linux.sh "your-token" "i-1234567890abcdef0 i-0987654321fedcba0"

# Windows - specific instances
cd scripts && ./deploy-windows.sh "your-token" "i-1234567890abcdef0 i-0987654321fedcba0"
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

## Documentation

- [FortiCNAPP Linux Installation](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/538940/installing-using-the-install-sh-script)
- [FortiCNAPP Windows Installation](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/902600/windows-agent-installation-prerequisites)
