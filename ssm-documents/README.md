# SSM Documents for FortiCNAPP Agent Deployment

This directory contains AWS Systems Manager (SSM) documents for deploying FortiCNAPP agents to EC2 instances.

## Documents

### Installation Documents

#### `forticnapp-linux-agent.json`
SSM document for deploying FortiCNAPP agents to Linux EC2 instances.

**Features:**
- Downloads official `install.sh` script from FortiCNAPP
- Installs agent with provided token
- Verifies installation and service status
- Cleans up temporary files

**Parameters:**
- `AgentToken` (required): FortiCNAPP agent token
- `DownloadUrl` (optional): URL to download install.sh (default: https://packages.lacework.net/install.sh)
- `InstallPath` (optional): Path to download script (default: /tmp/install.sh)

#### `forticnapp-windows-agent.json`
SSM document for deploying FortiCNAPP agents to Windows EC2 instances.

**Features:**
- Downloads `LWDatacollector.msi` installer
- Creates `config.json` with agent token
- Stops existing agent service if running
- Installs MSI silently
- Copies config file to correct location
- Starts agent service
- Verifies installation
- Cleans up temporary files

**Parameters:**
- `AgentToken` (required): FortiCNAPP agent token
- `DownloadUrl` (optional): URL to download MSI (default: https://packages.lacework.net/windows/installer/LWDatacollector.msi)
- `InstallPath` (optional): Path to download MSI (default: C:\temp\LWDatacollector.msi)
- `ConfigPath` (optional): Path to create config.json (default: C:\temp\config.json)

### Removal Documents

#### `forticnapp-linux-remove.json`
SSM document for removing FortiCNAPP agents from Linux EC2 instances.

**Features:**
- Stops datacollector service
- Disables service from auto-start
- Removes packages (apt/yum/rpm)
- Deletes directories and config files
- Removes systemd service files
- Verifies complete removal

**Parameters:**
- None required

#### `forticnapp-windows-remove.json`
SSM document for removing FortiCNAPP agents from Windows EC2 instances.

**Features:**
- Stops LaceworkAgent service
- Uninstalls MSI package
- Removes installation directories
- Removes configuration files
- Verifies complete removal

**Parameters:**
- None required

## Usage

### Using the Deployment Script

The `deploy-via-ssm-doc.sh` script automates the entire process:

```bash
# Deploy to specific instances
./scripts/deploy-via-ssm-doc.sh "your-token" instance-ids "i-1234567890abcdef0 i-0987654321fedcba0"

# Deploy to instances from file
./scripts/deploy-via-ssm-doc.sh "your-token" file instances.txt

# Deploy to instances by tag
./scripts/deploy-via-ssm-doc.sh "your-token" tag "Environment=Production"

# Deploy to all running instances
./scripts/deploy-via-ssm-doc.sh "your-token" all
```

### Manual SSM Document Usage

#### 1. Create the SSM Documents

**Installation documents:**
```bash
# Create Linux installation document
aws ssm create-document \
  --region us-east-1 \
  --content "file://ssm-documents/forticnapp-linux-agent.json" \
  --name "FortiCNAPP-Linux-Agent" \
  --document-type "Command" \
  --document-format "JSON"

# Create Windows installation document
aws ssm create-document \
  --region us-east-1 \
  --content "file://ssm-documents/forticnapp-windows-agent.json" \
  --name "FortiCNAPP-Windows-Agent" \
  --document-type "Command" \
  --document-format "JSON"
```

**Removal documents:**
```bash
# Create Linux removal document
aws ssm create-document \
  --region us-east-1 \
  --content "file://ssm-documents/forticnapp-linux-remove.json" \
  --name "FortiCNAPP-Linux-Remove" \
  --document-type "Command" \
  --document-format "JSON"

# Create Windows removal document
aws ssm create-document \
  --region us-east-1 \
  --content "file://ssm-documents/forticnapp-windows-remove.json" \
  --name "FortiCNAPP-Windows-Remove" \
  --document-type "Command" \
  --document-format "JSON"
```

#### 2. Deploy to Specific Instances

```bash
# Deploy to Linux instances
aws ssm send-command \
  --region us-east-1 \
  --document-name "FortiCNAPP-Linux-Agent" \
  --instance-ids "i-1234567890abcdef0" \
  --parameters "AgentToken=your-token-here"

# Deploy to Windows instances
aws ssm send-command \
  --region us-east-1 \
  --document-name "FortiCNAPP-Windows-Agent" \
  --instance-ids "i-0987654321fedcba0" \
  --parameters "AgentToken=your-token-here"

# Remove from Linux instances
aws ssm send-command \
  --region us-east-1 \
  --document-name "FortiCNAPP-Linux-Remove" \
  --instance-ids "i-1234567890abcdef0"

# Remove from Windows instances
aws ssm send-command \
  --region us-east-1 \
  --document-name "FortiCNAPP-Windows-Remove" \
  --instance-ids "i-0987654321fedcba0"
```

#### 3. Deploy to Instances by Tag

```bash
# Get instances by tag
INSTANCES=$(aws ec2 describe-instances \
  --region us-east-1 \
  --filters "Name=tag:Environment,Values=Production" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text)

# Deploy to Linux instances
aws ssm send-command \
  --region us-east-1 \
  --document-name "FortiCNAPP-Linux-Agent" \
  --instance-ids $INSTANCES \
  --parameters "AgentToken=your-token-here"
```

#### 4. Monitor Command Execution

```bash
# Check command status
aws ssm get-command-invocation \
  --region us-east-1 \
  --command-id "command-id-here" \
  --instance-id "i-1234567890abcdef0"

# List all commands
aws ssm list-commands \
  --region us-east-1 \
  --command-id "command-id-here"
```

## Targeting Options

### 1. Instance IDs
Target specific instances by their IDs:
```bash
aws ssm send-command --instance-ids "i-1234567890abcdef0 i-0987654321fedcba0"
```

### 2. EC2 Tags
Target instances by tags:
```bash
# Get instances by tag
aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=Production"
```

### 3. SSM Tags
Target managed instances by SSM tags:
```bash
aws ssm send-command \
  --targets "Key=tag:Environment,Values=Production"
```

### 4. Resource Groups
Target instances in a resource group:
```bash
aws ssm send-command \
  --targets "Key=resource-groups:Name,Values=Production-Servers"
```

## Benefits of SSM Documents

1. **Reusable**: Create once, use many times
2. **Versioned**: SSM tracks document versions
3. **Auditable**: All executions are logged
4. **Flexible**: Support parameters and conditional logic
5. **Integrated**: Work with AWS Config, CloudTrail, etc.
6. **Targeted**: Support multiple targeting options

## Troubleshooting

### Common Issues

1. **Document Already Exists**
   - Update existing document: `aws ssm update-document`
   - Or delete and recreate: `aws ssm delete-document`

2. **Permission Issues**
   - Ensure IAM role has `ssm:SendCommand` permission
   - Verify instance has SSM agent running

3. **Target Not Found**
   - Check instance IDs are correct
   - Verify instances are in "running" state
   - Ensure instances are managed by SSM

### Logs and Monitoring

- **SSM Logs**: Check `/var/log/amazon/ssm/` (Linux) or `C:\ProgramData\Amazon\SSM\Logs\` (Windows)
- **AWS Console**: Systems Manager > Run Command
- **CloudWatch**: SSM command execution metrics

## Security Considerations

1. **Token Security**: Never hardcode tokens in documents
2. **IAM Permissions**: Use least privilege principle
3. **Network Security**: Ensure instances can reach FortiCNAPP endpoints
4. **Audit Trail**: Monitor all SSM command executions
