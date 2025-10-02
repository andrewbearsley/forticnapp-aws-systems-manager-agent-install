#!/bin/bash

# Simple FortiCNAPP Windows Agent Deployment
# Downloads LWDatacollector.msi and config.json, then deploys to Windows instances
# Usage: ./deploy-windows.sh <agent-token> [instance-ids]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${BLUE}[HEADER]${NC} $1"; }

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MSI_URL="https://packages.lacework.net/windows/lacework-agent.msi"
MSI_PATH="${SCRIPT_DIR}/LWDatacollector.msi"
CONFIG_PATH="${SCRIPT_DIR}/config.json"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Check arguments
if [ $# -lt 1 ]; then
    print_error "Usage: $0 <agent-token> [instance-ids]"
    print_status "Example: $0 'your-token-here' 'i-1234567890abcdef0 i-0987654321fedcba0'"
    print_status "Example: $0 'your-token-here'  # Deploy to all Windows instances"
    exit 1
fi

AGENT_TOKEN="$1"
INSTANCE_IDS="$2"

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    print_status "Prerequisites check passed"
}

# Function to download Windows agent files
download_windows_files() {
    print_header "Downloading FortiCNAPP Windows agent files..."
    
    # Download MSI installer
    if [ ! -f "$MSI_PATH" ]; then
        print_status "Downloading LWDatacollector.msi from: $MSI_URL"
        curl -sSL "$MSI_URL" -o "$MSI_PATH"
        
        if [ ! -f "$MSI_PATH" ]; then
            print_error "Failed to download LWDatacollector.msi"
            exit 1
        fi
        print_status "LWDatacollector.msi downloaded successfully"
    else
        print_warning "LWDatacollector.msi already exists. Skipping download."
    fi
    
    # Create config.json with agent token
    print_status "Creating config.json with agent token..."
    cat > "$CONFIG_PATH" << EOF
{
  "tokens": {
    "AccessToken": "$AGENT_TOKEN"
  }
}
EOF
    
    print_status "config.json created successfully"
}

# Function to get Windows instances
get_windows_instances() {
    print_header "Finding Windows EC2 instances..."
    
    if [ -n "$INSTANCE_IDS" ]; then
        print_status "Using specified instance IDs: $INSTANCE_IDS"
        INSTANCES="$INSTANCE_IDS"
    else
        print_status "Finding all Windows instances..."
        INSTANCES=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --filters \
                "Name=instance-state-name,Values=running" \
                "Name=platform,Values=windows" \
            --query 'Reservations[*].Instances[*].[InstanceId]' \
            --output text | tr '\t' '\n' | sort -u)
    fi
    
    if [ -z "$INSTANCES" ]; then
        print_error "No Windows instances found"
        exit 1
    fi
    
    INSTANCE_COUNT=$(echo "$INSTANCES" | wc -w)
    print_status "Found $INSTANCE_COUNT Windows instances:"
    echo "$INSTANCES" | while read -r instance_id; do
        instance_name=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --instance-ids "$instance_id" \
            --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value|[0]' \
            --output text 2>/dev/null || echo "Unknown")
        echo "  - $instance_id ($instance_name)"
    done
}

# Function to deploy agents
deploy_agents() {
    print_header "Deploying FortiCNAPP agents..."
    
    # Convert instances to array
    INSTANCE_ARRAY=($INSTANCES)
    
    print_status "Sending installation command to all instances..."
    
    # Create PowerShell script for installation
    PS_SCRIPT='$ErrorActionPreference = "Stop"
$TempDir = Join-Path $env:TEMP "forticnapp-install"
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    # Download MSI installer
    $InstallerUrl = "https://packages.lacework.net/windows/lacework-agent.msi"
    $InstallerPath = Join-Path $TempDir "LWDatacollector.msi"
    Write-Host "Downloading FortiCNAPP agent installer..."
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
    
    # Create config.json
    $ConfigPath = Join-Path $TempDir "config.json"
    $ConfigContent = @"
{
  "tokens": {
    "AccessToken": "'$AGENT_TOKEN'"
  }
}
"@
    $ConfigContent | Out-File -FilePath $ConfigPath -Encoding UTF8
    
    # Stop existing service if running
    $Service = Get-Service -Name "LaceworkAgent" -ErrorAction SilentlyContinue
    if ($Service -and $Service.Status -eq "Running") {
        Write-Host "Stopping existing FortiCNAPP agent service..."
        Stop-Service -Name "LaceworkAgent" -Force
    }
    
    # Install the agent
    Write-Host "Installing FortiCNAPP agent..."
    $InstallArgs = @("/i", "`"$InstallerPath`"", "/quiet", "/norestart")
    $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait -PassThru
    
    if ($Process.ExitCode -eq 0) {
        Write-Host "FortiCNAPP agent installed successfully"
        
        # Copy config file
        $AgentConfigPath = "C:\ProgramData\Lacework\config\config.json"
        if (Test-Path (Split-Path $AgentConfigPath)) {
            Copy-Item $ConfigPath $AgentConfigPath -Force
            Write-Host "Configuration file copied successfully"
        }
        
        # Start the service
        Write-Host "Starting FortiCNAPP agent service..."
        Start-Service -Name "LaceworkAgent" -ErrorAction Stop
        
        # Wait for service to start
        $Timeout = 30
        $Timer = 0
        do {
            Start-Sleep -Seconds 1
            $Timer++
            $Service = Get-Service -Name "LaceworkAgent" -ErrorAction SilentlyContinue
        } while ($Service.Status -ne "Running" -and $Timer -lt $Timeout)
        
        if ($Service.Status -eq "Running") {
            Write-Host "FortiCNAPP agent service started successfully"
        } else {
            throw "Service failed to start within timeout period"
        }
    } else {
        throw "Installation failed with exit code: $($Process.ExitCode)"
    }
} catch {
    Write-Error "Installation failed: $($_.Exception.Message)"
    throw
} finally {
    # Clean up temporary directory
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}'
    
    # Send PowerShell command to all instances
    COMMAND_ID=$(aws ssm send-command \
        --region "$AWS_REGION" \
        --document-name "AWS-RunPowerShellScript" \
        --instance-ids "${INSTANCE_ARRAY[@]}" \
        --parameters "commands=[\"$PS_SCRIPT\"]" \
        --query 'Command.CommandId' \
        --output text)
    
    print_status "Command sent successfully. Command ID: $COMMAND_ID"
    
    # Monitor command execution
    print_header "Monitoring command execution..."
    
    while true; do
        COMMAND_STATUS=$(aws ssm list-command-invocations \
            --region "$AWS_REGION" \
            --command-id "$COMMAND_ID" \
            --query 'CommandInvocations[*].[InstanceId,Status]' \
            --output text)
        
        TOTAL_INSTANCES=$(echo "$COMMAND_STATUS" | wc -l)
        SUCCESS_COUNT=$(echo "$COMMAND_STATUS" | grep -c "Success" || true)
        FAILED_COUNT=$(echo "$COMMAND_STATUS" | grep -c "Failed" || true)
        IN_PROGRESS_COUNT=$(echo "$COMMAND_STATUS" | grep -c "InProgress" || true)
        
        print_status "Status: $SUCCESS_COUNT Success, $FAILED_COUNT Failed, $IN_PROGRESS_COUNT In Progress (Total: $TOTAL_INSTANCES)"
        
        if [ "$IN_PROGRESS_COUNT" -eq 0 ]; then
            break
        fi
        
        sleep 15
    done
    
    # Show final results
    print_header "Deployment Results:"
    echo "$COMMAND_STATUS" | while read -r instance_id status; do
        instance_name=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --instance-ids "$instance_id" \
            --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value|[0]' \
            --output text 2>/dev/null || echo "Unknown")
        
        if [ "$status" = "Success" ]; then
            print_status "$instance_id ($instance_name): SUCCESS"
        else
            print_error "$instance_id ($instance_name): FAILED"
        fi
    done
    
    # Show failed instances details
    if [ "$FAILED_COUNT" -gt 0 ]; then
        print_header "Failed Instance Details:"
        echo "$COMMAND_STATUS" | grep "Failed" | while read -r instance_id status; do
            print_error "Instance: $instance_id"
            aws ssm get-command-invocation \
                --region "$AWS_REGION" \
                --command-id "$COMMAND_ID" \
                --instance-id "$instance_id" \
                --query 'StandardErrorContent' \
                --output text
            echo "---"
        done
    fi
}

# Function to verify installation
verify_installation() {
    print_header "Verifying agent installation..."
    
    INSTANCE_ARRAY=($INSTANCES)
    
    VERIFY_COMMAND_ID=$(aws ssm send-command \
        --region "$AWS_REGION" \
        --document-name "AWS-RunPowerShellScript" \
        --instance-ids "${INSTANCE_ARRAY[@]}" \
        --parameters 'commands=["Get-Service -Name \"LaceworkAgent\" | Select-Object Name, Status"]' \
        --query 'Command.CommandId' \
        --output text)
    
    print_status "Verification command sent. Command ID: $VERIFY_COMMAND_ID"
    
    sleep 45
    
    VERIFY_STATUS=$(aws ssm list-command-invocations \
        --region "$AWS_REGION" \
        --command-id "$VERIFY_COMMAND_ID" \
        --query 'CommandInvocations[*].[InstanceId,Status]' \
        --output text)
    
    print_header "Agent Status Verification:"
    echo "$VERIFY_STATUS" | while read -r instance_id status; do
        instance_name=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --instance-ids "$instance_id" \
            --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value|[0]' \
            --output text 2>/dev/null || echo "Unknown")
        
        if [ "$status" = "Success" ]; then
            print_status "$instance_id ($instance_name): Agent service found"
        else
            print_warning "$instance_id ($instance_name): Agent status unknown"
        fi
    done
}

# Main execution
main() {
    print_header "FortiCNAPP Windows Agent Deployment"
    print_status "Region: $AWS_REGION"
    print_status "Agent Token: ${AGENT_TOKEN:0:10}..."
    
    check_prerequisites
    download_windows_files
    get_windows_instances
    deploy_agents
    verify_installation
    
    print_header "Deployment completed!"
    print_status "You can monitor agent logs with: Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='LaceworkAgent'} -MaxEvents 50"
}

# Run main function
main "$@"
