# FortiCNAPP Agent Deployment with AWS Systems Manager

Scripts to deploy FortiCNAPP agents on Linux and Windows EC2 instances using AWS Systems Manager.

## Overview

This solution uses the official FortiCNAPP installation methods:
- **Linux**: Official `install.sh` script from [FortiCNAPP documentation](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/538940/installing-using-the-install-sh-script)
- **Windows**: Official `LWDatacollector.msi` and `config.json` from [Windows installation prerequisites](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/902600/windows-agent-installation-prerequisites)

## Prerequisites

- AWS CLI configured with appropriate permissions
- AWS Systems Manager (SSM) agent installed on target EC2 instances
- EC2 instances with appropriate IAM roles for SSM access
- FortiCNAPP agent token

> **Note**: If your EC2 instances don't have AWS Systems Manager set up, see [WITHOUT-SSM.md](WITHOUT-SSM.md) for alternative deployment methods.

## Project Structure

```
forticnapp-aws-systems-manager/
├── README.md
├── QUICKSTART.md
├── WITHOUT-SSM.md              # Alternative deployment methods
├── LICENSE
├── linux/
│   └── deploy-linux.sh          # Simple Linux deployment script
└── windows/
    └── deploy-windows.sh       # Simple Windows deployment script
```

## Quick Start

### Deploy Linux Agents

```bash
cd linux
./deploy-linux.sh "your-agent-token-here"
```

### Deploy Windows Agents

```bash
cd windows
./deploy-windows.sh "your-agent-token-here"
```

### Deploy to Specific Instances

```bash
# Linux
./deploy-linux.sh "your-token" "i-1234567890abcdef0 i-0987654321fedcba0"

# Windows
./deploy-windows.sh "your-token" "i-1234567890abcdef0 i-0987654321fedcba0"
```

## How It Works

### Linux Deployment

The Linux script:
1. Downloads the official `install.sh` script from FortiCNAPP
2. Finds all Linux EC2 instances (or uses specified ones)
3. Runs the installation via AWS Systems Manager
4. Monitors deployment progress and verifies installation

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
