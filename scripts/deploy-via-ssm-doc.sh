#!/bin/bash

# FortiCNAPP Agent Deployment via SSM Documents
# This script deploys FortiCNAPP agents using custom SSM documents with EC2 targeting

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCUMENTS_DIR="$(dirname "$SCRIPT_DIR")/ssm-documents"

# Check arguments
if [ $# -lt 2 ]; then
    print_error "Usage: $0 <agent-token> <target-type> [target-value]"
    print_status "Target types:"
    print_status "  instance-ids    - Specific instance IDs (space-separated)"
    print_status "  file            - Instance IDs from file"
    print_status "  tag             - EC2 instances by tag (format: Key=Value)"
    print_status "  all             - All running instances"
    print_status ""
    print_status "Examples:"
    print_status "  $0 'your-token' instance-ids 'i-1234567890abcdef0 i-0987654321fedcba0'"
    print_status "  $0 'your-token' file instances.txt"
    print_status "  $0 'your-token' tag 'Environment=Production'"
    print_status "  $0 'your-token' all"
    exit 1
fi

AGENT_TOKEN="$1"
TARGET_TYPE="$2"
TARGET_VALUE="$3"

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

# Function to create SSM documents
create_ssm_documents() {
    print_header "Creating SSM documents..."
    
    # Create Linux document
    if [ -f "$DOCUMENTS_DIR/forticnapp-linux-agent.json" ]; then
        print_status "Creating FortiCNAPP Linux agent SSM document..."
        aws ssm create-document \
            --region "$AWS_REGION" \
            --content "file://$DOCUMENTS_DIR/forticnapp-linux-agent.json" \
            --name "FortiCNAPP-Linux-Agent" \
            --document-type "Command" \
            --document-format "JSON" \
            --tags "Key=Purpose,Value=FortiCNAPP,Key=Platform,Value=Linux" \
            --output text > /dev/null
        print_status "Linux SSM document created successfully"
    else
        print_error "Linux SSM document not found: $DOCUMENTS_DIR/forticnapp-linux-agent.json"
        exit 1
    fi
    
    # Create Windows document
    if [ -f "$DOCUMENTS_DIR/forticnapp-windows-agent.json" ]; then
        print_status "Creating FortiCNAPP Windows agent SSM document..."
        aws ssm create-document \
            --region "$AWS_REGION" \
            --content "file://$DOCUMENTS_DIR/forticnapp-windows-agent.json" \
            --name "FortiCNAPP-Windows-Agent" \
            --document-type "Command" \
            --document-format "JSON" \
            --tags "Key=Purpose,Value=FortiCNAPP,Key=Platform,Value=Windows" \
            --output text > /dev/null
        print_status "Windows SSM document created successfully"
    else
        print_error "Windows SSM document not found: $DOCUMENTS_DIR/forticnapp-windows-agent.json"
        exit 1
    fi
}

# Function to get target instances
get_target_instances() {
    print_header "Finding target instances..."
    
    case "$TARGET_TYPE" in
        "instance-ids")
            if [ -z "$TARGET_VALUE" ]; then
                print_error "Instance IDs required for instance-ids target type"
                exit 1
            fi
            INSTANCE_IDS="$TARGET_VALUE"
            print_status "Target instances: $INSTANCE_IDS"
            ;;
        "file")
            if [ -z "$TARGET_VALUE" ] || [ ! -f "$TARGET_VALUE" ]; then
                print_error "Valid file path required for file target type"
                exit 1
            fi
            INSTANCE_IDS=$(grep -v '^#' "$TARGET_VALUE" | grep -v '^$' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            if [ -z "$INSTANCE_IDS" ]; then
                print_error "No valid instance IDs found in file: $TARGET_VALUE"
                exit 1
            fi
            print_status "Target instances from file: $INSTANCE_IDS"
            ;;
        "tag")
            if [ -z "$TARGET_VALUE" ]; then
                print_error "Tag required for tag target type (format: Key=Value)"
                exit 1
            fi
            TAG_KEY=$(echo "$TARGET_VALUE" | cut -d'=' -f1)
            TAG_VALUE=$(echo "$TARGET_VALUE" | cut -d'=' -f2)
            
            print_status "Finding instances with tag: $TAG_KEY=$TAG_VALUE"
            INSTANCE_IDS=$(aws ec2 describe-instances \
                --region "$AWS_REGION" \
                --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" "Name=instance-state-name,Values=running" \
                --query 'Reservations[*].Instances[*].InstanceId' \
                --output text | tr '\t' ' ')
            
            if [ -z "$INSTANCE_IDS" ]; then
                print_error "No running instances found with tag: $TAG_KEY=$TAG_VALUE"
                exit 1
            fi
            print_status "Target instances by tag: $INSTANCE_IDS"
            ;;
        "all")
            print_status "Finding all running instances..."
            INSTANCE_IDS=$(aws ec2 describe-instances \
                --region "$AWS_REGION" \
                --filters "Name=instance-state-name,Values=running" \
                --query 'Reservations[*].Instances[*].InstanceId' \
                --output text | tr '\t' ' ')
            
            if [ -z "$INSTANCE_IDS" ]; then
                print_error "No running instances found"
                exit 1
            fi
            print_status "All running instances: $INSTANCE_IDS"
            ;;
        *)
            print_error "Invalid target type: $TARGET_TYPE"
            exit 1
            ;;
    esac
}

# Function to get instance details
get_instance_details() {
    print_header "Getting instance details..."
    
    # Get instance details
    INSTANCE_DETAILS=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids $INSTANCE_IDS \
        --query 'Reservations[*].Instances[*].[InstanceId,Platform,State.Name,Tags[?Key==`Name`].Value|[0]]' \
        --output text)
    
    # Count instances by platform
    LINUX_COUNT=0
    WINDOWS_COUNT=0
    
    while IFS=$'\t' read -r instance_id platform state name; do
        case "$platform" in
            "windows")
                WINDOWS_COUNT=$((WINDOWS_COUNT + 1))
                ;;
            *)
                LINUX_COUNT=$((LINUX_COUNT + 1))
                ;;
        esac
    done <<< "$INSTANCE_DETAILS"
    
    print_status "Found $LINUX_COUNT Linux instances and $WINDOWS_COUNT Windows instances"
}

# Function to confirm deployment
confirm_deployment() {
    echo
    print_header "Deployment Summary"
    print_status "AWS Region: $AWS_REGION"
    print_status "Agent Token: ${AGENT_TOKEN:0:10}..."
    print_status "Target Type: $TARGET_TYPE"
    print_status "Total Instances: $((LINUX_COUNT + WINDOWS_COUNT))"
    echo
    
    print_status "Instance details:"
    echo "$INSTANCE_DETAILS" | while IFS=$'\t' read -r instance_id platform state name; do
        platform_display=${platform:-linux}
        echo "  - $instance_id ($name) - $platform_display"
    done
    echo
    
    print_warning "This will deploy FortiCNAPP agents using SSM documents."
    print_warning "Existing agents will be updated/reconfigured if present."
    echo
    
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deployment cancelled"
        exit 0
    fi
}

# Function to deploy to Linux instances
deploy_linux_instances() {
    if [ $LINUX_COUNT -eq 0 ]; then
        return 0
    fi
    
    print_header "Deploying to Linux instances..."
    
    # Get Linux instance IDs
    LINUX_INSTANCES=$(echo "$INSTANCE_DETAILS" | awk -F'\t' '$2 != "windows" {print $1}' | tr '\n' ' ')
    
    print_status "Deploying to Linux instances: $LINUX_INSTANCES"
    
    # Send command
    COMMAND_ID=$(aws ssm send-command \
        --region "$AWS_REGION" \
        --document-name "FortiCNAPP-Linux-Agent" \
        --instance-ids $LINUX_INSTANCES \
        --parameters "AgentToken=$AGENT_TOKEN" \
        --comment "FortiCNAPP Linux Agent Deployment" \
        --query 'Command.CommandId' \
        --output text)
    
    print_status "Linux deployment command sent. Command ID: $COMMAND_ID"
    
    # Monitor command
    monitor_command "$COMMAND_ID" "Linux"
}

# Function to deploy to Windows instances
deploy_windows_instances() {
    if [ $WINDOWS_COUNT -eq 0 ]; then
        return 0
    fi
    
    print_header "Deploying to Windows instances..."
    
    # Get Windows instance IDs
    WINDOWS_INSTANCES=$(echo "$INSTANCE_DETAILS" | awk -F'\t' '$2 == "windows" {print $1}' | tr '\n' ' ')
    
    print_status "Deploying to Windows instances: $WINDOWS_INSTANCES"
    
    # Send command
    COMMAND_ID=$(aws ssm send-command \
        --region "$AWS_REGION" \
        --document-name "FortiCNAPP-Windows-Agent" \
        --instance-ids $WINDOWS_INSTANCES \
        --parameters "AgentToken=$AGENT_TOKEN" \
        --comment "FortiCNAPP Windows Agent Deployment" \
        --query 'Command.CommandId' \
        --output text)
    
    print_status "Windows deployment command sent. Command ID: $COMMAND_ID"
    
    # Monitor command
    monitor_command "$COMMAND_ID" "Windows"
}

# Function to monitor command execution
monitor_command() {
    local command_id="$1"
    local platform="$2"
    
    print_header "Monitoring $platform deployment..."
    
    # Wait for command to complete
    while true; do
        STATUS=$(aws ssm get-command-invocation \
            --region "$AWS_REGION" \
            --command-id "$command_id" \
            --instance-id $(echo "$INSTANCE_DETAILS" | head -1 | cut -f1) \
            --query 'Status' \
            --output text 2>/dev/null || echo "InProgress")
        
        case "$STATUS" in
            "Success")
                print_status "$platform deployment completed successfully"
                break
                ;;
            "Failed"|"Cancelled"|"TimedOut")
                print_error "$platform deployment failed with status: $STATUS"
                break
                ;;
            "InProgress")
                print_status "Deployment in progress..."
                sleep 10
                ;;
            *)
                print_status "Status: $STATUS"
                sleep 10
                ;;
        esac
    done
}

# Function to show results
show_results() {
    print_header "Deployment Results"
    
    if [ $LINUX_COUNT -gt 0 ]; then
        print_status "Linux instances: $LINUX_COUNT"
    fi
    
    if [ $WINDOWS_COUNT -gt 0 ]; then
        print_status "Windows instances: $WINDOWS_COUNT"
    fi
    
    print_status "Deployment completed!"
    print_status "Check AWS Systems Manager console for detailed results."
}

# Main execution
main() {
    print_header "FortiCNAPP Agent Deployment via SSM Documents"
    
    check_prerequisites
    create_ssm_documents
    get_target_instances
    get_instance_details
    confirm_deployment
    deploy_linux_instances
    deploy_windows_instances
    show_results
    
    print_header "Deployment completed!"
    print_status "SSM documents created:"
    print_status "  - FortiCNAPP-Linux-Agent"
    print_status "  - FortiCNAPP-Windows-Agent"
    print_status "You can reuse these documents for future deployments."
}

# Run main function
main "$@"
