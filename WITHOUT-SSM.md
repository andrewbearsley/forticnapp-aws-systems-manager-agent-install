# FortiCNAPP Agent Deployment - Without AWS Systems Manager

If your EC2 instances don't have AWS Systems Manager (SSM) set up, you can still deploy FortiCNAPP agents using direct installation methods.

## Prerequisites

- SSH access to Linux instances
- RDP access to Windows instances  
- FortiCNAPP agent token
- Network connectivity to FortiCNAPP endpoints

## Option 1: Direct Installation (Recommended)

### Linux Instances

**Single Instance:**
```bash
# SSH to your instance
ssh -i your-key.pem ec2-user@your-instance-ip

# Run the official installation script
curl -sSL https://packages.lacework.net/install.sh | bash -s -- -t "your-agent-token"
```

**Multiple Instances (using parallel SSH):**
```bash
# Create a script to install on multiple instances
cat > install-linux.sh << 'EOF'
#!/bin/bash
curl -sSL https://packages.lacework.net/install.sh | bash -s -- -t "$1"
EOF

# Install on multiple instances in parallel
parallel-ssh -h instances.txt -i "bash -s" < install-linux.sh "your-agent-token"
```

### Windows Instances

**Single Instance:**
```powershell
# RDP to your instance, then run PowerShell as Administrator

# Download the installer
$InstallerUrl = "https://packages.lacework.net/windows/lacework-agent.msi"
$InstallerPath = "$env:TEMP\LWDatacollector.msi"
Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath

# Create config.json
$ConfigPath = "$env:TEMP\config.json"
$ConfigContent = @"
{
  "tokens": {
    "AccessToken": "your-agent-token"
  }
}
"@
$ConfigContent | Out-File -FilePath $ConfigPath -Encoding UTF8

# Install the agent
$InstallArgs = @("/i", "`"$InstallerPath`"", "/quiet", "/norestart")
Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait

# Copy config file
$AgentConfigPath = "C:\ProgramData\Lacework\config\config.json"
if (Test-Path (Split-Path $AgentConfigPath)) {
    Copy-Item $ConfigPath $AgentConfigPath -Force
}

# Start the service
Start-Service -Name "LaceworkAgent"
```

## Option 2: User Data Scripts

### Linux User Data

Add this to your EC2 instance user data:

```bash
#!/bin/bash
# Install FortiCNAPP agent
curl -sSL https://packages.lacework.net/install.sh | bash -s -- -t "your-agent-token"
```

### Windows User Data

Add this PowerShell script to your Windows instance user data:

```powershell
# Download and install FortiCNAPP agent
$InstallerUrl = "https://packages.lacework.net/windows/lacework-agent.msi"
$InstallerPath = "$env:TEMP\LWDatacollector.msi"
Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath

# Create config.json
$ConfigPath = "$env:TEMP\config.json"
$ConfigContent = @"
{
  "tokens": {
    "AccessToken": "your-agent-token"
  }
}
"@
$ConfigContent | Out-File -FilePath $ConfigPath -Encoding UTF8

# Install the agent
$InstallArgs = @("/i", "`"$InstallerPath`"", "/quiet", "/norestart")
Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait

# Copy config file
$AgentConfigPath = "C:\ProgramData\Lacework\config\config.json"
if (Test-Path (Split-Path $AgentConfigPath)) {
    Copy-Item $ConfigPath $AgentConfigPath -Force
}

# Start the service
Start-Service -Name "LaceworkAgent"
```

## Option 3: Setup AWS Systems Manager (Recommended for Future)

If you want to use AWS Systems Manager for future deployments:

### 1. Install SSM Agent

**Linux (Amazon Linux 2):**
```bash
sudo yum install -y amazon-ssm-agent
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent
```

**Linux (Ubuntu):**
```bash
sudo snap install amazon-ssm-agent --classic
```

**Windows:**
Download and install from: https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-manual-agent-install.html

### 2. Configure IAM Role

Attach this policy to your EC2 instance role:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:UpdateInstanceInformation",
                "ssmmessages:CreateControlChannel",
                "ssmmessages:CreateDataChannel",
                "ssmmessages:OpenControlChannel",
                "ssmmessages:OpenDataChannel"
            ],
            "Resource": "*"
        }
    ]
}
```

### 3. Verify SSM Agent

```bash
# Check if instance appears in SSM
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-1234567890abcdef0"
```

## Option 4: Ansible/Chef/Puppet

### Ansible Playbook

```yaml
---
- name: Install FortiCNAPP agent on Linux
  hosts: linux_servers
  become: yes
  tasks:
    - name: Install FortiCNAPP agent
      shell: curl -sSL https://packages.lacework.net/install.sh | bash -s -- -t "{{ forticnapp_token }}"
      args:
        creates: /usr/bin/lacework

- name: Install FortiCNAPP agent on Windows
  hosts: windows_servers
  tasks:
    - name: Download FortiCNAPP installer
      win_get_url:
        url: https://packages.lacework.net/windows/lacework-agent.msi
        dest: C:\temp\LWDatacollector.msi
    
    - name: Create config.json
      win_copy:
        content: |
          {
            "tokens": {
              "AccessToken": "{{ forticnapp_token }}"
            }
          }
        dest: C:\temp\config.json
    
    - name: Install FortiCNAPP agent
      win_package:
        path: C:\temp\LWDatacollector.msi
        state: present
    
    - name: Copy config file
      win_copy:
        src: C:\temp\config.json
        dest: C:\ProgramData\Lacework\config\config.json
      become: yes
    
    - name: Start FortiCNAPP service
      win_service:
        name: LaceworkAgent
        state: started
```

## Verification

### Linux
```bash
# Check if agent is running
systemctl status lacework

# Check agent logs
journalctl -u lacework -f
```

### Windows
```powershell
# Check if agent service is running
Get-Service -Name "LaceworkAgent"

# Check agent logs
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='LaceworkAgent'} -MaxEvents 50
```

## Recommendation

1. **For immediate deployment**: Use Option 1 (Direct Installation)
2. **For new instances**: Use Option 2 (User Data Scripts)
3. **For long-term management**: Use Option 3 (Setup AWS Systems Manager)
4. **For existing automation**: Use Option 4 (Ansible/Chef/Puppet)

The AWS Systems Manager approach is still the most scalable and manageable solution for ongoing operations.
