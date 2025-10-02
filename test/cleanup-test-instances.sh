#!/bin/bash

# Cleanup Test EC2 Instances for FortiCNAPP Deployment Testing
# Terminates test instances and cleans up resources
# Usage: ./cleanup-test-instances.sh

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
KEY_NAME="forticnapp-test-key"
SECURITY_GROUP_NAME="forticnapp-test-sg"
ROLE_NAME="FortiCNAPP-SSM-Role"
LINUX_INSTANCE_NAME="forticnapp-test-linux"
WINDOWS_INSTANCE_NAME="forticnapp-test-windows"

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

# Function to find and terminate instances
terminate_instances() {
    print_header "Finding and terminating test instances..."
    
    # Find Linux instance
    LINUX_INSTANCE_ID=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=$LINUX_INSTANCE_NAME" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text)
    
    # Find Windows instance
    WINDOWS_INSTANCE_ID=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=$WINDOWS_INSTANCE_NAME" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text)
    
    # Terminate instances
    INSTANCES_TO_TERMINATE=""
    
    if [ -n "$LINUX_INSTANCE_ID" ] && [ "$LINUX_INSTANCE_ID" != "None" ]; then
        print_status "Found Linux instance: $LINUX_INSTANCE_ID"
        INSTANCES_TO_TERMINATE="$LINUX_INSTANCE_ID"
    fi
    
    if [ -n "$WINDOWS_INSTANCE_ID" ] && [ "$WINDOWS_INSTANCE_ID" != "None" ]; then
        print_status "Found Windows instance: $WINDOWS_INSTANCE_ID"
        if [ -n "$INSTANCES_TO_TERMINATE" ]; then
            INSTANCES_TO_TERMINATE="$INSTANCES_TO_TERMINATE $WINDOWS_INSTANCE_ID"
        else
            INSTANCES_TO_TERMINATE="$WINDOWS_INSTANCE_ID"
        fi
    fi
    
    if [ -n "$INSTANCES_TO_TERMINATE" ]; then
        print_status "Terminating instances: $INSTANCES_TO_TERMINATE"
        aws ec2 terminate-instances \
            --region "$AWS_REGION" \
            --instance-ids $INSTANCES_TO_TERMINATE
        
        print_status "Waiting for instances to terminate..."
        aws ec2 wait instance-terminated \
            --region "$AWS_REGION" \
            --instance-ids $INSTANCES_TO_TERMINATE
        
        print_status "Instances terminated successfully"
    else
        print_warning "No test instances found to terminate"
    fi
}

# Function to delete key pair
delete_key_pair() {
    print_header "Deleting key pair..."
    
    if aws ec2 describe-key-pairs --region "$AWS_REGION" --key-names "$KEY_NAME" &> /dev/null; then
        aws ec2 delete-key-pair \
            --region "$AWS_REGION" \
            --key-name "$KEY_NAME"
        
        # Remove local key file if it exists
        if [ -f "${KEY_NAME}.pem" ]; then
            rm "${KEY_NAME}.pem"
            print_status "Key pair $KEY_NAME deleted and local file removed"
        else
            print_status "Key pair $KEY_NAME deleted"
        fi
    else
        print_warning "Key pair $KEY_NAME not found"
    fi
}

# Function to delete security group
delete_security_group() {
    print_header "Deleting security group..."
    
    SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$SECURITY_GROUP_ID" != "None" ] && [ -n "$SECURITY_GROUP_ID" ]; then
        aws ec2 delete-security-group \
            --region "$AWS_REGION" \
            --group-id "$SECURITY_GROUP_ID"
        print_status "Security group $SECURITY_GROUP_NAME deleted"
    else
        print_warning "Security group $SECURITY_GROUP_NAME not found"
    fi
}

# Function to delete IAM role
delete_iam_role() {
    print_header "Deleting IAM role..."
    
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        # Detach policy
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || true
        
        # Remove role from instance profile
        aws iam remove-role-from-instance-profile \
            --instance-profile-name "$ROLE_NAME" \
            --role-name "$ROLE_NAME" 2>/dev/null || true
        
        # Delete instance profile
        aws iam delete-instance-profile \
            --instance-profile-name "$ROLE_NAME" 2>/dev/null || true
        
        # Delete role
        aws iam delete-role \
            --role-name "$ROLE_NAME"
        
        print_status "IAM role $ROLE_NAME deleted"
    else
        print_warning "IAM role $ROLE_NAME not found"
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    print_header "Cleanup Summary"
    
    print_status "The following resources have been cleaned up:"
    print_status "  ✅ EC2 instances (if found)"
    print_status "  ✅ Key pair (if found)"
    print_status "  ✅ Security group (if found)"
    print_status "  ✅ IAM role and instance profile (if found)"
    echo
    print_status "All test resources have been removed."
    print_status "You should no longer incur charges for these resources."
}

# Main execution
main() {
    print_header "FortiCNAPP Test Instance Cleanup"
    print_status "Region: $AWS_REGION"
    echo
    
    check_prerequisites
    terminate_instances
    delete_key_pair
    delete_security_group
    delete_iam_role
    show_cleanup_summary
    
    print_header "Cleanup completed successfully!"
}

# Show usage if help requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0"
    echo
    echo "Cleans up test EC2 instances and related resources:"
    echo "  - Terminates test instances"
    echo "  - Deletes key pair"
    echo "  - Deletes security group"
    echo "  - Deletes IAM role and instance profile"
    echo
    echo "Environment variables:"
    echo "  AWS_REGION    AWS region (default: us-east-1)"
    echo
    echo "This script removes all resources created by create-test-instances.sh"
    exit 0
fi

# Run main function
main "$@"
