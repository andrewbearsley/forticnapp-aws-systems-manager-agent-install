#!/bin/bash

# Setup Systems Manager on Existing EC2 Instances
# Installs SSM agent and configures IAM role for existing instances
# Usage: ./setup-ssm.sh [instance-ids]

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
ROLE_NAME="FortiCNAPP-SSM-Role"
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

# Function to get all instances if none specified
get_all_instances() {
    if [ -z "$INSTANCE_IDS" ]; then
        print_header "Finding all running EC2 instances in region: $AWS_REGION"
        
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
        INSTANCE_IDS="$ALL_INSTANCES"
    else
        print_header "Using specified instances: $INSTANCE_IDS"
    fi
}

# Function to create IAM role for SSM
create_ssm_role() {
    print_header "Creating IAM role for Systems Manager..."
    
    # Check if role exists
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        print_warning "IAM role $ROLE_NAME already exists"
    else
        # Create trust policy
        cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
        
        # Create role
        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document file://trust-policy.json
        
        # Attach SSM policy
        aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        
        # Create instance profile
        aws iam create-instance-profile \
            --instance-profile-name "$ROLE_NAME"
        
        # Add role to instance profile
        aws iam add-role-to-instance-profile \
            --instance-profile-name "$ROLE_NAME" \
            --role-name "$ROLE_NAME"
        
        # Clean up
        rm trust-policy.json
        
        print_status "IAM role $ROLE_NAME created with SSM permissions"
    fi
}

# Function to install SSM agent on instances
install_ssm_agent() {
    print_header "Installing SSM agent on instances..."
    
    for instance_id in $INSTANCE_IDS; do
        print_status "Processing instance: $instance_id"
        
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
        
        print_status "Instance: $instance_id ($INSTANCE_NAME)"
        print_status "Platform: $PLATFORM, State: $STATE"
        
        # Check if instance is already in SSM
        SSM_CHECK=$(aws ssm describe-instance-information \
            --region "$AWS_REGION" \
            --filters "Key=InstanceIds,Values=$instance_id" \
            --query 'InstanceInformationList[*].InstanceId' \
            --output text 2>/dev/null || echo "NOT_IN_SSM")
        
        if [ "$SSM_CHECK" = "$instance_id" ]; then
            print_warning "Instance $instance_id is already managed by SSM"
            continue
        fi
        
        # Install SSM agent based on platform
        if [ "$PLATFORM" = "windows" ]; then
            install_ssm_windows "$instance_id"
        else
            install_ssm_linux "$instance_id"
        fi
    done
}

# Function to install SSM agent on Linux
install_ssm_linux() {
    local instance_id="$1"
    print_status "Installing SSM agent on Linux instance: $instance_id"
    
    # Create user data script for SSM agent installation
    cat > ssm-install-linux.sh << 'EOF'
#!/bin/bash
# Install SSM agent on Linux
if command -v yum &> /dev/null; then
    # Amazon Linux, RHEL, CentOS
    yum update -y
    yum install -y amazon-ssm-agent
elif command -v apt-get &> /dev/null; then
    # Ubuntu, Debian
    apt-get update
    apt-get install -y snapd
    snap install amazon-ssm-agent --classic
elif command -v zypper &> /dev/null; then
    # SUSE
    zypper install -y amazon-ssm-agent
else
    # Generic installation
    curl -s https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm -o amazon-ssm-agent.rpm
    rpm -Uvh amazon-ssm-agent.rpm
fi

# Start and enable SSM agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
systemctl status amazon-ssm-agent
EOF
    
    # Upload and execute the script
    aws ssm send-command \
        --region "$AWS_REGION" \
        --document-name "AWS-RunShellScript" \
        --instance-ids "$instance_id" \
        --parameters "commands=[\"$(cat ssm-install-linux.sh | base64 -w 0 | base64 -d)\"]" \
        --query 'Command.CommandId' \
        --output text
    
    # Clean up
    rm ssm-install-linux.sh
    
    print_status "SSM agent installation command sent to $instance_id"
}

# Function to install SSM agent on Windows
install_ssm_windows() {
    local instance_id="$1"
    print_status "Installing SSM agent on Windows instance: $instance_id"
    
    # Create PowerShell script for SSM agent installation
    cat > ssm-install-windows.ps1 << 'EOF'
# Install SSM agent on Windows
$SSMAgentUrl = "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe"
$SSMAgentInstaller = "$env:TEMP\AmazonSSMAgentSetup.exe"

try {
    Invoke-WebRequest -Uri $SSMAgentUrl -OutFile $SSMAgentInstaller
    Start-Process -FilePath $SSMAgentInstaller -ArgumentList "/S" -Wait
    Write-Host "SSM Agent installed successfully"
} catch {
    Write-Error "Failed to install SSM Agent: $_"
}
EOF
    
    # Upload and execute the script
    aws ssm send-command \
        --region "$AWS_REGION" \
        --document-name "AWS-RunPowerShellScript" \
        --instance-ids "$instance_id" \
        --parameters "commands=[\"$(cat ssm-install-windows.ps1 | base64 -w 0 | base64 -d)\"]" \
        --query 'Command.CommandId' \
        --output text
    
    # Clean up
    rm ssm-install-windows.ps1
    
    print_status "SSM agent installation command sent to $instance_id"
}

# Function to attach IAM role to instances
attach_iam_role() {
    print_header "Attaching IAM role to instances..."
    
    for instance_id in $INSTANCE_IDS; do
        print_status "Attaching IAM role to instance: $instance_id"
        
        # Check if instance already has an IAM role
        CURRENT_ROLE=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --instance-ids "$instance_id" \
            --query 'Reservations[*].Instances[*].IamInstanceProfile.Arn' \
            --output text 2>/dev/null || echo "None")
        
        if [ "$CURRENT_ROLE" != "None" ] && [ -n "$CURRENT_ROLE" ]; then
            print_warning "Instance $instance_id already has an IAM role: $CURRENT_ROLE"
            continue
        fi
        
        # Attach IAM role to instance
        aws ec2 associate-iam-instance-profile \
            --region "$AWS_REGION" \
            --instance-id "$instance_id" \
            --iam-instance-profile Name="$ROLE_NAME"
        
        print_status "IAM role attached to instance: $instance_id"
    done
}

# Function to wait for SSM registration
wait_for_ssm_registration() {
    print_header "Waiting for SSM registration..."
    
    print_status "Waiting 30 seconds for SSM agents to register..."
    sleep 30
    
    # Check SSM registration status
    for instance_id in $INSTANCE_IDS; do
        print_status "Checking SSM registration for: $instance_id"
        
        # Wait up to 2 minutes for SSM registration
        for i in {1..12}; do
            SSM_STATUS=$(aws ssm describe-instance-information \
                --region "$AWS_REGION" \
                --filters "Key=InstanceIds,Values=$instance_id" \
                --query 'InstanceInformationList[*].PingStatus' \
                --output text 2>/dev/null || echo "NotRegistered")
            
            if [ "$SSM_STATUS" = "Online" ]; then
                print_status "✅ Instance $instance_id is now online in SSM"
                break
            elif [ "$SSM_STATUS" = "NotRegistered" ]; then
                print_warning "⏳ Instance $instance_id not yet registered (attempt $i/12)"
                sleep 10
            else
                print_warning "⚠️ Instance $instance_id status: $SSM_STATUS (attempt $i/12)"
                sleep 10
            fi
        done
        
        if [ "$SSM_STATUS" != "Online" ]; then
            print_error "❌ Instance $instance_id failed to register with SSM"
        fi
    done
}

# Function to show final status
show_final_status() {
    print_header "Final SSM Status Check"
    
    # Run the check-ssm script if it exists
    if [ -f "../scripts/check-ssm.sh" ]; then
        print_status "Running SSM status check..."
        ../scripts/check-ssm.sh $INSTANCE_IDS
    else
        print_status "Manual SSM status check:"
        aws ssm describe-instance-information \
            --region "$AWS_REGION" \
            --query 'InstanceInformationList[*].[InstanceId,ComputerName,PlatformType,PingStatus,LastPingDateTime]' \
            --output table
    fi
}

# Function to show next steps
show_next_steps() {
    print_header "Next Steps"
    
    print_status "SSM setup completed! You can now:"
    print_status "1. Verify SSM status: cd scripts && ./check-ssm.sh"
    print_status "2. Deploy FortiCNAPP agents:"
    print_status "   cd scripts && ./deploy-linux.sh 'your-token'"
    print_status "   cd scripts && ./deploy-windows.sh 'your-token'"
    echo
    print_status "Instance IDs that were configured:"
    for instance_id in $INSTANCE_IDS; do
        print_status "  - $instance_id"
    done
}

# Main execution
main() {
    print_header "FortiCNAPP SSM Setup for Existing Instances"
    print_status "Region: $AWS_REGION"
    echo
    
    check_prerequisites
    get_all_instances
    create_ssm_role
    install_ssm_agent
    attach_iam_role
    wait_for_ssm_registration
    show_final_status
    show_next_steps
    
    print_header "SSM setup completed!"
}

# Show usage if help requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [instance-ids]"
    echo
    echo "Sets up Systems Manager on existing EC2 instances:"
    echo "  - Creates IAM role with SSM permissions"
    echo "  - Installs SSM agent on instances"
    echo "  - Attaches IAM role to instances"
    echo "  - Waits for SSM registration"
    echo
    echo "Examples:"
    echo "  $0                                    # Setup SSM on all running instances"
    echo "  $0 i-1234567890abcdef0               # Setup SSM on specific instance"
    echo "  $0 'i-1234567890abcdef0 i-0987654321fedcba0'  # Setup SSM on multiple instances"
    echo
    echo "Environment variables:"
    echo "  AWS_REGION    AWS region (default: us-east-1)"
    exit 0
fi

# Run main function
main "$@"
