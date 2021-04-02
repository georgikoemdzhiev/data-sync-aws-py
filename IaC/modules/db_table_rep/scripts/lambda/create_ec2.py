import boto3

ec2 = boto3.resource('ec2')
template_name = 'stopgap'

lt = {
    'LaunchTemplateName': template_name,
    'Version': '$Latest'
}


def handler(event, context):

    ec2.create_instances(
        LaunchTemplate=lt,
        MinCount=1,
        MaxCount=1
    )
