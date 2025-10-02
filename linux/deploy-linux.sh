#!/bin/bash

# Simple FortiCNAPP Linux Agent Deployment
# Downloads install.sh and deploys to Linux instances via AWS Systems Manager
# Usage: ./deploy-linux.sh <agent-token> [instance-ids]

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
INSTALL_SCRIPT_URL="https://packages.lacework.net/install.sh"
INSTALL_SCRIPT_PATH="${SCRIPT_DIR}/install.sh"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Check arguments
if [ $# -lt 1 ]; then
    print_error "Usage: $0 <agent-token> [instance-ids]"
    print_status "Example: $0 'your-token-here' 'i-1234567890abcdef0 i-0987654321fedcba0'"
    print_status "Example: $0 'your-token-here'  # Deploy to all Linux instances"
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

# Function to download install.sh
download_install_script() {
    print_header "Downloading FortiCNAPP install.sh script..."
    
    if [ -f "$INSTALL_SCRIPT_PATH" ]; then
        print_warning "install.sh already exists. Skipping download."
        return
    fi
    
    print_status "Downloading from: $INSTALL_SCRIPT_URL"
    curl -sSL "$INSTALL_SCRIPT_URL" -o "$INSTALL_SCRIPT_PATH"
    
    if [ ! -f "$INSTALL_SCRIPT_PATH" ]; then
        print_error "Failed to download install.sh script"
        exit 1
    fi
    
    chmod +x "$INSTALL_SCRIPT_PATH"
    print_status "install.sh downloaded successfully"
}

# Function to get Linux instances
get_linux_instances() {
    print_header "Finding Linux EC2 instances..."
    
    if [ -n "$INSTANCE_IDS" ]; then
        print_status "Using specified instance IDs: $INSTANCE_IDS"
        INSTANCES="$INSTANCE_IDS"
    else
        print_status "Finding all Linux instances..."
        INSTANCES=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --filters \
                "Name=instance-state-name,Values=running" \
            --query 'Reservations[*].Instances[?Platform!=`windows`].[InstanceId]' \
            --output text | tr '\t' '\n' | sort -u)
    fi
    
    if [ -z "$INSTANCES" ]; then
        print_error "No Linux instances found"
        exit 1
    fi
    
    INSTANCE_COUNT=$(echo "$INSTANCES" | wc -w)
    print_status "Found $INSTANCE_COUNT Linux instances:"
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
    
    # Create SSM command to run install.sh with token
    COMMAND_ID=$(aws ssm send-command \
        --region "$AWS_REGION" \
        --document-name "AWS-RunShellScript" \
        --instance-ids "${INSTANCE_ARRAY[@]}" \
        --parameters "commands=[\"curl -sSL https://packages.lacework.net/install.sh | bash -s -- -t $AGENT_TOKEN\"]" \
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
        
        sleep 10
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
        --document-name "AWS-RunShellScript" \
        --instance-ids "${INSTANCE_ARRAY[@]}" \
        --parameters 'commands=["systemctl is-active lacework"]' \
        --query 'Command.CommandId' \
        --output text)
    
    print_status "Verification command sent. Command ID: $VERIFY_COMMAND_ID"
    
    sleep 30
    
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
            print_status "$instance_id ($instance_name): Agent is running"
        else
            print_warning "$instance_id ($instance_name): Agent status unknown"
        fi
    done
}

# Main execution
main() {
    print_header "FortiCNAPP Linux Agent Deployment"
    print_status "Region: $AWS_REGION"
    print_status "Agent Token: ${AGENT_TOKEN:0:10}..."
    
    check_prerequisites
    download_install_script
    get_linux_instances
    deploy_agents
    verify_installation
    
    print_header "Deployment completed!"
    print_status "You can monitor agent logs with: journalctl -u lacework -f"
}

# Run main function
main "$@"
