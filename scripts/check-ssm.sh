#!/bin/bash

# FortiCNAPP EC2 Systems Manager Check
# Checks if EC2 instances are managed by AWS Systems Manager
# Usage: ./check-ssm.sh [instance-ids]

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
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_IDS="$1"

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

# Function to get all EC2 instances
get_all_instances() {
    print_header "Finding all EC2 instances in region: $AWS_REGION"
    
    ALL_INSTANCES=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=instance-state-name,Values=running" \
        --query 'Reservations[*].Instances[*].[InstanceId,Platform,State.Name,Tags[?Key==`Name`].Value|[0]]' \
        --output text | awk '{print $1}')
    
    if [ -z "$ALL_INSTANCES" ]; then
        print_warning "No running EC2 instances found in region $AWS_REGION"
        exit 0
    fi
    
    INSTANCE_COUNT=$(echo "$ALL_INSTANCES" | wc -w)
    print_status "Found $INSTANCE_COUNT running EC2 instances"
}

# Function to get SSM-managed instances
get_ssm_instances() {
    print_header "Finding instances managed by Systems Manager"
    
    SSM_INSTANCES=$(aws ssm describe-instance-information \
        --region "$AWS_REGION" \
        --query 'InstanceInformationList[*].[InstanceId,ComputerName,PlatformType,PingStatus,LastPingDateTime]' \
        --output text 2>/dev/null | awk '{print $1}' || true)
    
    if [ -z "$SSM_INSTANCES" ]; then
        print_warning "No instances found in Systems Manager"
        SSM_INSTANCES=""
    else
        SSM_COUNT=$(echo "$SSM_INSTANCES" | wc -w)
        print_status "Found $SSM_COUNT instances managed by Systems Manager"
    fi
}

# Function to check specific instances
check_specific_instances() {
    print_header "Checking specific instances: $INSTANCE_IDS"
    
    for instance_id in $INSTANCE_IDS; do
        print_status "Checking instance: $instance_id"
        
        # Get instance details
        INSTANCE_INFO=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --instance-ids "$instance_id" \
            --query 'Reservations[*].Instances[*].[InstanceId,Platform,State.Name,Tags[?Key==`Name`].Value|[0]]' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$INSTANCE_INFO" = "NOT_FOUND" ]; then
            print_error "Instance $instance_id not found or not accessible"
            continue
        fi
        
        INSTANCE_NAME=$(echo "$INSTANCE_INFO" | awk '{print $4}')
        PLATFORM=$(echo "$INSTANCE_INFO" | awk '{print $2}')
        STATE=$(echo "$INSTANCE_INFO" | awk '{print $3}')
        
        # Convert None platform to Linux for better display
        if [ "$PLATFORM" = "None" ] || [ -z "$PLATFORM" ]; then
            PLATFORM="Linux"
        fi
        
        # Check if instance is in SSM
        SSM_INFO=$(aws ssm describe-instance-information \
            --region "$AWS_REGION" \
            --filters "Key=InstanceIds,Values=$instance_id" \
            --query 'InstanceInformationList[*].[InstanceId,ComputerName,PlatformType,PingStatus,LastPingDateTime]' \
            --output text 2>/dev/null || echo "NOT_IN_SSM")
        
        if [ "$SSM_INFO" = "NOT_IN_SSM" ]; then
            print_warning "❌ $instance_id ($INSTANCE_NAME) - NOT managed by SSM"
            print_status "   Platform: $PLATFORM, State: $STATE"
        else
            PING_STATUS=$(echo "$SSM_INFO" | awk '{print $4}')
            LAST_PING=$(echo "$SSM_INFO" | awk '{print $5}')
            COMPUTER_NAME=$(echo "$SSM_INFO" | awk '{print $2}')
            
            if [ "$PING_STATUS" = "Online" ]; then
                print_status "✅ $instance_id ($INSTANCE_NAME) - SSM Online"
                print_status "   Computer Name: $COMPUTER_NAME"
                print_status "   Last Ping: $LAST_PING"
            else
                print_warning "⚠️  $instance_id ($INSTANCE_NAME) - SSM $PING_STATUS"
                print_status "   Last Ping: $LAST_PING"
            fi
        fi
        echo
    done
}

# Function to show summary
show_summary() {
    print_header "Summary"
    
    if [ -n "$INSTANCE_IDS" ]; then
        print_status "Checked specific instances: $INSTANCE_IDS"
    else
        print_status "Total EC2 instances: $INSTANCE_COUNT"
        print_status "SSM-managed instances: ${SSM_COUNT:-0}"
        
        if [ "$INSTANCE_COUNT" -gt 0 ]; then
            NOT_SSM_COUNT=$((INSTANCE_COUNT - ${SSM_COUNT:-0}))
            print_status "Not SSM-managed: $NOT_SSM_COUNT"
        fi
    fi
    
    echo
    print_status "To set up SSM on instances, see:"
    print_status "https://docs.aws.amazon.com/systems-manager/latest/userguide/setup.html"
}

# Function to show all instances table
show_instances_table() {
    if [ -z "$INSTANCE_IDS" ]; then
        print_header "All EC2 Instances vs SSM Status"
        echo
        
        # Create a table showing all instances and their SSM status
        printf "%-20s %-20s %-10s %-10s %-20s\n" "Instance ID" "Name" "Platform" "SSM Status" "Last Ping"
        printf "%-20s %-20s %-10s %-10s %-20s\n" "--------------------" "--------------------" "----------" "----------" "--------------------"
        
        for instance_id in $ALL_INSTANCES; do
            # Get instance details
            INSTANCE_INFO=$(aws ec2 describe-instances \
                --region "$AWS_REGION" \
                --instance-ids "$instance_id" \
                --query 'Reservations[*].Instances[*].[InstanceId,Platform,State.Name,Tags[?Key==`Name`].Value|[0]]' \
                --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [ "$INSTANCE_INFO" = "NOT_FOUND" ]; then
                continue
            fi
            
            INSTANCE_NAME=$(echo "$INSTANCE_INFO" | awk '{print $4}')
            PLATFORM=$(echo "$INSTANCE_INFO" | awk '{print $2}')
            
            # Convert None platform to Linux for better display
            if [ "$PLATFORM" = "None" ] || [ -z "$PLATFORM" ]; then
                PLATFORM="Linux"
            fi
            
            # Check SSM status
            SSM_INFO=$(aws ssm describe-instance-information \
                --region "$AWS_REGION" \
                --filters "Key=InstanceIds,Values=$instance_id" \
                --query 'InstanceInformationList[*].[InstanceId,ComputerName,PlatformType,PingStatus,LastPingDateTime]' \
                --output text 2>/dev/null || echo "NOT_IN_SSM")
            
            if [ "$SSM_INFO" = "NOT_IN_SSM" ]; then
                SSM_STATUS="❌ No"
                LAST_PING="N/A"
            else
                PING_STATUS=$(echo "$SSM_INFO" | awk '{print $4}')
                LAST_PING=$(echo "$SSM_INFO" | awk '{print $5}')
                if [ "$PING_STATUS" = "Online" ]; then
                    SSM_STATUS="✅ Yes"
                else
                    SSM_STATUS="⚠️  $PING_STATUS"
                fi
            fi
            
            printf "%-20s %-20s %-10s %-10s %-20s\n" "$instance_id" "${INSTANCE_NAME:-Unknown}" "${PLATFORM:-Linux}" "$SSM_STATUS" "$LAST_PING"
        done
        echo
    fi
}

# Main execution
main() {
    print_header "FortiCNAPP EC2 Systems Manager Check"
    print_status "Region: $AWS_REGION"
    
    check_prerequisites
    
    if [ -n "$INSTANCE_IDS" ]; then
        check_specific_instances
    else
        get_all_instances
        get_ssm_instances
        show_instances_table
    fi
    
    show_summary
}

# Show usage if no arguments and help requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [instance-ids]"
    echo
    echo "Examples:"
    echo "  $0                                    # Check all instances"
    echo "  $0 i-1234567890abcdef0               # Check specific instance"
    echo "  $0 'i-1234567890abcdef0 i-0987654321fedcba0'  # Check multiple instances"
    echo
    echo "Environment variables:"
    echo "  AWS_REGION    AWS region (default: us-east-1)"
    exit 0
fi

# Run main function
main "$@"
