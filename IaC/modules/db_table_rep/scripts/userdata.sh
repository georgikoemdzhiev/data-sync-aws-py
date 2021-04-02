#!/bin/bash

# e - stops the script if there is an error
# x - output every command in /var/log/syslog
set -e -x

# Set AWS region
echo "export AWS_DEFAULT_REGION=${region}" >> /etc/profile
source /etc/profile
# Copy python script from the s3 bucket
aws s3 cp s3://${bucket_name}/ /home/ec2-user --recursive

# Run main python script
/usr/bin/python3 /home/ec2-user/${python_script_file_name}