# Stopgap System

Overall design of the stopgap system

![Overall_infra.png](../diagrams/rendered/Overall_infra.png)

The Python script that get's executed as part of the  db sync goes through the following workflow:

![Overall_infra.png](../diagrams/rendered/Script_workflow.png)

## Prerequisite

* Install `terraform-cli` from [here](https://www.terraform.io/downloads.html)
* Install `octo-cli` from [here](https://git.mdevlab.com/octo/octo-cli)

## Deployment

* (Optional) Create a AMI image (see `Build EC2 AMI Image` steps bellow) and update `ami_image` variable in `vars.ts`
* Run `octo-cli` to login to AWS. When asked for `Profile` type `PreProd` or `Prod` depending on the environment you are deploying into
* Change directory to `prod` or `dev` folders depending where you would like to deploy/make changes
* (Optional) Create a new *Key-Pair* and update the `vars.tf`'s `key_pair_name` variable 
* Make sure that you have the latest Terraform state - `git pull` (**that will change if we decide to use `s3` as backend**)
* Set the `auroraArn`,`resourceId`,`username` and `password` to the DEV/PROD Aurora db in `vars.tf`'s `secrets` variable
* Execute `terraform apply`, type `yes` and wait for the resources to be created. When the infrastructure is created, note down the `Outputs` values and update `secretsArn` & `snsTopicArn` arns in the `vars.tf` `secrets` map
* Execute `terraform apply` again so we update the *Secrets*
* Add/Create SNS Subscription\s to the SNS Topic name (look for the `sns_topic_name` variable in `vars.tf`)
* (Optional) attach `CloudWatchAgentServerPolicy`, `AmazonSSMManagedInstanceCore` and `SSMRequiredS3Permissions` policies to the `StopgapRole` using AWS console (that avoids emails from Global-ENR-Cloud-Admin - those get automatically added if we do not do it)
* (Optional) Block public access to the S3 bucket using AWS Console (same as above)

## Scheduled Run

We can schedule the execution of the database sync (i.e. the launch of the EC2 instance) by changing the CloudWatch rule (see `vars.tf`  `cloudwatch_event_name` value) using the AWS console. For example, navigate to AWS Console and open CloudWatch. Select `Rules` and search for "*launch-stopgap-ec2-instance*" rule. Change the "*Scheedule*" to an appropriate value (see [Cron Expressions](https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html)); Save and Enable the rule. When the rule gets invokes it will call our lambda (see "Overall design" image) which in turn will start the sync process

## Updating python script

Terraform runds md5 hash of the python script to detect changes. The only thing we have to do in order to make sure that the EC2 instance will use the most up-to-date script is to to perform the following steps:

1. Apply changes to the script, Save
2. Execute `terraform apply`. You will see that the `aws_s3_bucket_object.python_script` s3 object will be updated in place (i.e. the script will be uploaded in the bucket)
3. type `yes`
4. (Optional) Launch EC2 instance

## Build custom EC2 AMI Image

We can build/rebuild the AMI image used by the Launch Template (i.e. EC2 instance) we can do the following steps:

* Pick the latest Amazon Linux 2 AMI 
* Launch an EC2 instance using `t2.large` instance type
* Install the Python3, boto3, pyodbc and MSSQL 17 driver:

``` 

# Install Python dependencies
sudo yum -y install gcc-c++.x86_64
sudo yum -y install python3-devel.x86_64
sudo yum -y install unixODBC.x86_64
sudo yum -y install unixODBC-devel.x86_64
# Install python packages
sudo /usr/bin/python3 -m pip install boto3 pyodbc

# Install MSSQL 17 driver
sudo su

#Download appropriate package for the OS version
#Choose only ONE of the following, corresponding to your OS version
curl https://packages.microsoft.com/config/rhel/6/prod.repo > /etc/yum.repos.d/mssql-release.repo
exit
sudo yum remove unixODBC-utf16 unixODBC-utf16-devel #to avoid conflicts
sudo ACCEPT_EULA=Y yum -y install msodbcsql17
# optional: for bcp and sqlcmd
sudo ACCEPT_EULA=Y yum -y install mssql-tools
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bash_profile
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
source ~/.bashrc
# optional: for unixODBC development headers
sudo yum -y install unixODBC-devel
```

* Open the EC2 panel on AWS Console, Change the Instance State to `Stopped`
* Create AMI Image
* Update the `vars.tf` file with the new AMI image

## Troubleshooting

* The Python script doesn't get executed when the EC2 instance starts

Check for any meaningful debug messages in the `cloud-init-output.log` located in `var/log/` directory

* No email notifications are being sent

Check if you have created/added a *Subscription* to the SNS topic
