#!/bin/bash

# Create Test EC2 Instances for FortiCNAPP Deployment Testing
# Creates both Linux and Windows instances with SSM support
# Usage: ./create-test-instances.sh

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
LINUX_INSTANCE_NAME="forticnapp-test-linux"
WINDOWS_INSTANCE_NAME="forticnapp-test-windows"

# AMI IDs (us-east-1)
LINUX_AMI="ami-0c02fb55956c7d316"  # Amazon Linux 2
WINDOWS_AMI="ami-0c7c4e3c6b4941f0f"  # Windows Server 2022 Base

# Instance types
LINUX_INSTANCE_TYPE="t3.micro"
WINDOWS_INSTANCE_TYPE="t3.medium"

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

# Function to create key pair
create_key_pair() {
    print_header "Creating key pair..."
    
    if aws ec2 describe-key-pairs --region "$AWS_REGION" --key-names "$KEY_NAME" &> /dev/null; then
        print_warning "Key pair $KEY_NAME already exists"
    else
        aws ec2 create-key-pair \
            --region "$AWS_REGION" \
            --key-name "$KEY_NAME" \
            --query 'KeyMaterial' \
            --output text > "${KEY_NAME}.pem"
        
        chmod 400 "${KEY_NAME}.pem"
        print_status "Key pair $KEY_NAME created and saved to ${KEY_NAME}.pem"
    fi
}

# Function to create security group
create_security_group() {
    print_header "Creating security group..."
    
    # Get default VPC ID
    VPC_ID=$(aws ec2 describe-vpcs \
        --region "$AWS_REGION" \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        print_error "No default VPC found in region $AWS_REGION"
        exit 1
    fi
    
    print_status "Using VPC: $VPC_ID"
    
    # Check if security group exists
    if aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
        --query 'SecurityGroups[0].GroupId' \
        --output text | grep -q "sg-"; then
        
        SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
            --region "$AWS_REGION" \
            --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
            --query 'SecurityGroups[0].GroupId' \
            --output text)
        print_warning "Security group $SECURITY_GROUP_NAME already exists: $SECURITY_GROUP_ID"
    else
        # Create security group
        SECURITY_GROUP_ID=$(aws ec2 create-security-group \
            --region "$AWS_REGION" \
            --group-name "$SECURITY_GROUP_NAME" \
            --description "Security group for FortiCNAPP test instances" \
            --vpc-id "$VPC_ID" \
            --query 'GroupId' \
            --output text)
        
        # Add SSH rule (port 22)
        aws ec2 authorize-security-group-ingress \
            --region "$AWS_REGION" \
            --group-id "$SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0
        
        # Add RDP rule (port 3389)
        aws ec2 authorize-security-group-ingress \
            --region "$AWS_REGION" \
            --group-id "$SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 3389 \
            --cidr 0.0.0.0/0
        
        # Add HTTPS rule (port 443) for FortiCNAPP
        aws ec2 authorize-security-group-ingress \
            --region "$AWS_REGION" \
            --group-id "$SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 443 \
            --cidr 0.0.0.0/0
        
        print_status "Security group $SECURITY_GROUP_NAME created: $SECURITY_GROUP_ID"
    fi
}

# Function to create IAM role for SSM
create_ssm_role() {
    print_header "Creating IAM role for Systems Manager..."
    
    ROLE_NAME="FortiCNAPP-SSM-Role"
    
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

# Function to create Linux instance
create_linux_instance() {
    print_header "Creating Linux test instance..."
    
    # Check if instance already exists
    EXISTING_INSTANCE=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=$LINUX_INSTANCE_NAME" "Name=instance-state-name,Values=running,pending" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text)
    
    if [ -n "$EXISTING_INSTANCE" ] && [ "$EXISTING_INSTANCE" != "None" ]; then
        print_warning "Linux instance $LINUX_INSTANCE_NAME already exists: $EXISTING_INSTANCE"
        LINUX_INSTANCE_ID="$EXISTING_INSTANCE"
    else
        # Create user data script for SSM agent
        cat > linux-user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
EOF
        
        # Launch instance
        LINUX_INSTANCE_ID=$(aws ec2 run-instances \
            --region "$AWS_REGION" \
            --image-id "$LINUX_AMI" \
            --count 1 \
            --instance-type "$LINUX_INSTANCE_TYPE" \
            --key-name "$KEY_NAME" \
            --security-group-ids "$SECURITY_GROUP_ID" \
            --iam-instance-profile Name="FortiCNAPP-SSM-Role" \
            --user-data file://linux-user-data.sh \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$LINUX_INSTANCE_NAME},{Key=Purpose,Value=FortiCNAPP-Test}]" \
            --query 'Instances[0].InstanceId' \
            --output text)
        
        # Clean up
        rm linux-user-data.sh
        
        print_status "Linux instance $LINUX_INSTANCE_NAME created: $LINUX_INSTANCE_ID"
    fi
}

# Function to create Windows instance
create_windows_instance() {
    print_header "Creating Windows test instance..."
    
    # Check if instance already exists
    EXISTING_INSTANCE=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=$WINDOWS_INSTANCE_NAME" "Name=instance-state-name,Values=running,pending" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text)
    
    if [ -n "$EXISTING_INSTANCE" ] && [ "$EXISTING_INSTANCE" != "None" ]; then
        print_warning "Windows instance $WINDOWS_INSTANCE_NAME already exists: $EXISTING_INSTANCE"
        WINDOWS_INSTANCE_ID="$EXISTING_INSTANCE"
    else
        # Create user data script for SSM agent
        cat > windows-user-data.ps1 << 'EOF'
<powershell>
# Install SSM Agent
$SSMAgentUrl = "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe"
$SSMAgentInstaller = "$env:TEMP\AmazonSSMAgentSetup.exe"
Invoke-WebRequest -Uri $SSMAgentUrl -OutFile $SSMAgentInstaller
Start-Process -FilePath $SSMAgentInstaller -ArgumentList "/S" -Wait
</powershell>
EOF
        
        # Launch instance
        WINDOWS_INSTANCE_ID=$(aws ec2 run-instances \
            --region "$AWS_REGION" \
            --image-id "$WINDOWS_AMI" \
            --count 1 \
            --instance-type "$WINDOWS_INSTANCE_TYPE" \
            --key-name "$KEY_NAME" \
            --security-group-ids "$SECURITY_GROUP_ID" \
            --iam-instance-profile Name="FortiCNAPP-SSM-Role" \
            --user-data file://windows-user-data.ps1 \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$WINDOWS_INSTANCE_NAME},{Key=Purpose,Value=FortiCNAPP-Test}]" \
            --query 'Instances[0].InstanceId' \
            --output text)
        
        # Clean up
        rm windows-user-data.ps1
        
        print_status "Windows instance $WINDOWS_INSTANCE_NAME created: $WINDOWS_INSTANCE_ID"
    fi
}

# Function to wait for instances to be running
wait_for_instances() {
    print_header "Waiting for instances to be running..."
    
    for instance_id in "$LINUX_INSTANCE_ID" "$WINDOWS_INSTANCE_ID"; do
        if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
            print_status "Waiting for instance $instance_id to be running..."
            aws ec2 wait instance-running \
                --region "$AWS_REGION" \
                --instance-ids "$instance_id"
            print_status "Instance $instance_id is now running"
        fi
    done
}

# Function to get instance information
get_instance_info() {
    print_header "Instance Information"
    
    for instance_id in "$LINUX_INSTANCE_ID" "$WINDOWS_INSTANCE_ID"; do
        if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
            INSTANCE_INFO=$(aws ec2 describe-instances \
                --region "$AWS_REGION" \
                --instance-ids "$instance_id" \
                --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,PrivateIpAddress,State.Name,Tags[?Key==`Name`].Value|[0]]' \
                --output text)
            
            INSTANCE_NAME=$(echo "$INSTANCE_INFO" | awk '{print $5}')
            PUBLIC_IP=$(echo "$INSTANCE_INFO" | awk '{print $2}')
            PRIVATE_IP=$(echo "$INSTANCE_INFO" | awk '{print $3}')
            STATE=$(echo "$INSTANCE_INFO" | awk '{print $4}')
            
            print_status "$INSTANCE_NAME ($instance_id):"
            print_status "  State: $STATE"
            print_status "  Public IP: $PUBLIC_IP"
            print_status "  Private IP: $PRIVATE_IP"
            echo
        fi
    done
}

# Function to show next steps
show_next_steps() {
    print_header "Next Steps"
    
    print_status "1. Wait 2-3 minutes for SSM agents to register"
    print_status "2. Check SSM readiness:"
    print_status "   cd scripts && ./check-ssm.sh"
    print_status "3. Test FortiCNAPP deployment:"
    print_status "   cd scripts && ./deploy-linux.sh 'your-token'"
    print_status "   cd scripts && ./deploy-windows.sh 'your-token'"
    echo
    print_status "Instance IDs for testing:"
    if [ -n "$LINUX_INSTANCE_ID" ] && [ "$LINUX_INSTANCE_ID" != "None" ]; then
        print_status "  Linux: $LINUX_INSTANCE_ID"
    fi
    if [ -n "$WINDOWS_INSTANCE_ID" ] && [ "$WINDOWS_INSTANCE_ID" != "None" ]; then
        print_status "  Windows: $WINDOWS_INSTANCE_ID"
    fi
    echo
    print_warning "Remember to terminate instances when done testing to avoid charges!"
    print_status "Terminate command:"
    if [ -n "$LINUX_INSTANCE_ID" ] && [ "$LINUX_INSTANCE_ID" != "None" ]; then
        print_status "  aws ec2 terminate-instances --region $AWS_REGION --instance-ids $LINUX_INSTANCE_ID"
    fi
    if [ -n "$WINDOWS_INSTANCE_ID" ] && [ "$WINDOWS_INSTANCE_ID" != "None" ]; then
        print_status "  aws ec2 terminate-instances --region $AWS_REGION --instance-ids $WINDOWS_INSTANCE_ID"
    fi
}

# Main execution
main() {
    print_header "FortiCNAPP Test Instance Creator"
    print_status "Region: $AWS_REGION"
    echo
    
    check_prerequisites
    create_key_pair
    create_security_group
    create_ssm_role
    create_linux_instance
    create_windows_instance
    wait_for_instances
    get_instance_info
    show_next_steps
    
    print_header "Test instances created successfully!"
}

# Show usage if help requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0"
    echo
    echo "Creates test EC2 instances for FortiCNAPP deployment testing:"
    echo "  - Linux instance (Amazon Linux 2, t3.micro)"
    echo "  - Windows instance (Windows Server 2022, t3.medium)"
    echo "  - Both instances configured with SSM support"
    echo
    echo "Environment variables:"
    echo "  AWS_REGION    AWS region (default: us-east-1)"
    echo
    echo "Note: This script creates resources that will incur AWS charges."
    echo "Remember to terminate instances when done testing!"
    exit 0
fi

# Run main function
main "$@"
