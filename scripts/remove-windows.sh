#!/bin/bash

# FortiCNAPP Windows Agent Removal
# This script removes FortiCNAPP agents from Windows EC2 instances via AWS Systems Manager

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${BLUE}[HEADER]${NC} $1"; }

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_IDS="$1"

# Check if help requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [instance-ids-or-file]"
    echo ""
    echo "Removes FortiCNAPP agents from Windows EC2 instances"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Remove from all Windows instances"
    echo "  $0 'i-1234567890abcdef0 i-0987654321fedcba0'  # Remove from specific instances"
    echo "  $0 instances.txt                     # Remove from instances in file"
    echo ""
    echo "Environment variables:"
    echo "  AWS_REGION    AWS region (default: us-east-1)"
    exit 0
fi

# Function to load instance IDs from file
load_instance_ids() {
    if [ -n "$INSTANCE_IDS" ] && [ -f "$INSTANCE_IDS" ]; then
        print_status "Loading instance IDs from file: $INSTANCE_IDS"
        INSTANCE_IDS=$(grep -v '^#' "$INSTANCE_IDS" | grep -v '^$' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
        if [ -z "$INSTANCE_IDS" ]; then
            print_error "No valid instance IDs found in file: $INSTANCE_IDS"
            exit 1
        fi
        print_status "Loaded instance IDs: $INSTANCE_IDS"
    fi
}

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

# Function to get Windows instances
get_windows_instances() {
    print_header "Finding Windows EC2 instances..."
    
    if [ -z "$INSTANCE_IDS" ]; then
        print_status "Finding all Windows instances..."
        INSTANCES=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --filters "Name=platform,Values=windows" "Name=instance-state-name,Values=running" \
            --query 'Reservations[*].Instances[*].InstanceId' \
            --output text | tr '\t' '\n')
    else
        print_status "Using specified instances..."
        INSTANCES=$(echo "$INSTANCE_IDS" | tr ' ' '\n')
    fi
    
    if [ -z "$INSTANCES" ]; then
        print_error "No Windows instances found"
        exit 1
    fi
    
    INSTANCE_COUNT=$(echo "$INSTANCES" | wc -l | tr -d ' ')
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

# Function to confirm removal
confirm_removal() {
    echo
    print_header "Removal Summary"
    print_status "AWS Region: $AWS_REGION"
    print_status "Target Instances: $INSTANCE_COUNT Windows instances"
    echo
    print_status "Target instances:"
    echo "$INSTANCES" | while read -r instance_id; do
        instance_name=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --instance-ids "$instance_id" \
            --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value|[0]' \
            --output text 2>/dev/null || echo "Unknown")
        echo "  - $instance_id ($instance_name)"
    done
    echo
    print_warning "This will REMOVE FortiCNAPP agents from the above instances."
    print_warning "This action will stop monitoring and data collection."
    echo
    
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Removal cancelled"
        exit 0
    fi
}

# Function to remove agents
remove_agents() {
    print_header "Removing FortiCNAPP agents..."
    
    print_status "Sending removal command to all instances..."
    
    # Create PowerShell removal script
    REMOVE_SCRIPT='
# Stop LaceworkAgent service
Write-Host "Stopping LaceworkAgent service..."
try {
    $service = Get-Service -Name "LaceworkAgent" -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            Stop-Service -Name "LaceworkAgent" -Force
            Write-Host "Service stopped"
        }
    } else {
        Write-Host "LaceworkAgent service not found"
    }
} catch {
    Write-Host "Error stopping service: $($_.Exception.Message)"
}

# Find and uninstall Lacework product
Write-Host "Finding Lacework installation..."
$product = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Lacework*" -or $_.Name -like "*FortiCNAPP*" }

if ($product) {
    Write-Host "Found product: $($product.Name)"
    Write-Host "Uninstalling..."
    
    try {
        $result = $product.Uninstall()
        if ($result.ReturnValue -eq 0) {
            Write-Host "SUCCESS: Product uninstalled successfully"
        } else {
            Write-Host "Uninstall returned code: $($result.ReturnValue)"
        }
    } catch {
        Write-Host "Error during uninstall: $($_.Exception.Message)"
    }
} else {
    Write-Host "No Lacework product found in installed programs"
    Write-Host "Attempting manual cleanup..."
}

# Remove directories
Write-Host "Removing FortiCNAPP directories..."
$dirsToRemove = @(
    "C:\Program Files\Lacework",
    "C:\Program Files (x86)\Lacework",
    "C:\ProgramData\Lacework"
)

foreach ($dir in $dirsToRemove) {
    if (Test-Path $dir) {
        try {
            Remove-Item -Path $dir -Recurse -Force
            Write-Host "Removed: $dir"
        } catch {
            Write-Host "Failed to remove $dir: $($_.Exception.Message)"
        }
    }
}

# Verify removal
Write-Host "Verifying removal..."
$serviceExists = Get-Service -Name "LaceworkAgent" -ErrorAction SilentlyContinue
$dirExists = Test-Path "C:\ProgramData\Lacework"

if (-not $serviceExists -and -not $dirExists) {
    Write-Host "SUCCESS: FortiCNAPP agent removed successfully"
} else {
    if ($serviceExists) {
        Write-Host "WARNING: LaceworkAgent service still exists"
    }
    if ($dirExists) {
        Write-Host "WARNING: Lacework directory still exists"
    }
}
'
    
    COMMAND_ID=$(aws ssm send-command \
        --region "$AWS_REGION" \
        --document-name "AWS-RunPowerShellScript" \
        --instance-ids $(echo "$INSTANCES" | tr '\n' ' ') \
        --parameters commands="$REMOVE_SCRIPT" \
        --comment "FortiCNAPP Windows Agent Removal" \
        --query 'Command.CommandId' \
        --output text)
    
    print_status "Command sent successfully. Command ID: $COMMAND_ID"
    
    # Monitor command execution
    print_header "Monitoring command execution..."
    
    while true; do
        # Get command status for all instances
        STATUS_OUTPUT=$(aws ssm list-command-invocations \
            --region "$AWS_REGION" \
            --command-id "$COMMAND_ID" \
            --query 'CommandInvocations[*].[InstanceId,Status]' \
            --output text)
        
        # Count statuses
        SUCCESS_COUNT=$(echo "$STATUS_OUTPUT" | grep -c "Success" || true)
        FAILED_COUNT=$(echo "$STATUS_OUTPUT" | grep -c -E "Failed|Cancelled|TimedOut" || true)
        IN_PROGRESS_COUNT=$(echo "$STATUS_OUTPUT" | grep -c "InProgress" || true)
        
        print_status "Status: $SUCCESS_COUNT Success, $FAILED_COUNT Failed, $IN_PROGRESS_COUNT In Progress (Total: $INSTANCE_COUNT)"
        
        # Check if all commands completed
        if [ $((SUCCESS_COUNT + FAILED_COUNT)) -eq "$INSTANCE_COUNT" ]; then
            break
        fi
        
        sleep 5
    done
    
    # Show detailed results
    print_header "Removal Results:"
    
    echo "$INSTANCES" | while read -r instance_id; do
        status=$(aws ssm get-command-invocation \
            --region "$AWS_REGION" \
            --command-id "$COMMAND_ID" \
            --instance-id "$instance_id" \
            --query 'Status' \
            --output text 2>/dev/null || echo "Unknown")
        
        instance_name=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --instance-ids "$instance_id" \
            --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value|[0]' \
            --output text 2>/dev/null || echo "Unknown")
        
        if [ "$status" = "Success" ]; then
            print_status "$instance_id ($instance_name): SUCCESS"
        else
            print_error "$instance_id ($instance_name): $status"
        fi
    done
    
    # Show failed instance details if any
    if [ "$FAILED_COUNT" -gt 0 ]; then
        print_header "Failed Instance Details:"
        echo "$INSTANCES" | while read -r instance_id; do
            status=$(aws ssm get-command-invocation \
                --region "$AWS_REGION" \
                --command-id "$COMMAND_ID" \
                --instance-id "$instance_id" \
                --query 'Status' \
                --output text 2>/dev/null || echo "Unknown")
            
            if [ "$status" != "Success" ]; then
                print_error "Instance: $instance_id"
                aws ssm get-command-invocation \
                    --region "$AWS_REGION" \
                    --command-id "$COMMAND_ID" \
                    --instance-id "$instance_id" \
                    --query 'StandardErrorContent' \
                    --output text 2>/dev/null || echo "No error details available"
                echo "---"
            fi
        done
    fi
}

# Main execution
main() {
    print_header "FortiCNAPP Windows Agent Removal"
    
    check_prerequisites
    load_instance_ids
    get_windows_instances
    confirm_removal
    remove_agents
    
    print_header "Removal completed!"
    print_status "FortiCNAPP agents have been removed from Windows instances."
}

# Run main function
main "$@"
