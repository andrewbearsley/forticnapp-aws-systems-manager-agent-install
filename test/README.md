# Test Environment Setup

This folder contains scripts to create and manage test EC2 instances for testing FortiCNAPP agent deployment.

## Scripts

### `create-test-instances.sh`
Creates test EC2 instances with Systems Manager support:
- **Linux instance**: Amazon Linux 2 (t3.micro)
- **Windows instance**: Windows Server 2022 (t3.medium)
- **SSM support**: Both instances configured with SSM agent
- **Security**: Key pair, security group, and IAM role created

### `cleanup-test-instances.sh`
Cleans up all test resources:
- Terminates EC2 instances
- Deletes key pair
- Deletes security group
- Deletes IAM role and instance profile

## Usage

### 1. Create Test Instances

```bash
# In AWS CloudShell or local environment
cd test
./create-test-instances.sh
```

**What it creates:**
- Key pair: `forticnapp-test-key`
- Security group: `forticnapp-test-sg`
- IAM role: `FortiCNAPP-SSM-Role`
- Linux instance: `forticnapp-test-linux`
- Windows instance: `forticnapp-test-windows`

### 2. Wait for SSM Registration

```bash
# Wait 2-3 minutes, then check SSM readiness
cd ../scripts
./check-ssm.sh
```

### 3. Test FortiCNAPP Deployment

```bash
# Test Linux deployment
cd scripts
./deploy-linux.sh "your-forticnapp-token"

# Test Windows deployment
./deploy-windows.sh "your-forticnapp-token"
```

### 4. Clean Up Resources

```bash
# When done testing, clean up to avoid charges
cd ../test
./cleanup-test-instances.sh
```

## Cost Considerations

**⚠️ Important**: These instances will incur AWS charges:
- **Linux (t3.micro)**: ~$0.0104/hour
- **Windows (t3.medium)**: ~$0.0416/hour

**Total cost**: ~$0.05/hour for both instances

**Remember to run cleanup script when done testing!**

## Prerequisites

- AWS CLI configured with appropriate permissions
- EC2, IAM, and Systems Manager permissions
- Default VPC in the target region

## Environment Variables

```bash
# Use specific region (default: us-east-1)
export AWS_REGION="eu-west-1"
./create-test-instances.sh
```

## Troubleshooting

### Instances not appearing in SSM
- Wait 2-3 minutes for SSM agent to register
- Check IAM role permissions
- Verify security group allows outbound HTTPS (443)

### Permission errors
- Ensure your AWS credentials have EC2, IAM, and SSM permissions
- Check if you have permission to create IAM roles

### Region-specific issues
- Some regions may have different AMI IDs
- Update AMI IDs in the script if needed

## Manual Cleanup

If the cleanup script fails, manually clean up:

```bash
# Find and terminate instances
aws ec2 describe-instances --filters "Name=tag:Purpose,Values=FortiCNAPP-Test" --query 'Reservations[*].Instances[*].InstanceId' --output text

# Delete key pair
aws ec2 delete-key-pair --key-name forticnapp-test-key

# Delete security group
aws ec2 delete-security-group --group-name forticnapp-test-sg

# Delete IAM role
aws iam detach-role-policy --role-name FortiCNAPP-SSM-Role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam remove-role-from-instance-profile --instance-profile-name FortiCNAPP-SSM-Role --role-name FortiCNAPP-SSM-Role
aws iam delete-instance-profile --instance-profile-name FortiCNAPP-SSM-Role
aws iam delete-role --role-name FortiCNAPP-SSM-Role
```
