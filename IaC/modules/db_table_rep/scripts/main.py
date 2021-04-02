import boto3
from botocore.exceptions import ClientError
import csv
import os
import pyodbc
import subprocess
import time
import json

# FUNCTIONS


def get_secret(secret_name):
    """
    Returns the list of secrets from the Secrets Manager by secret name
    """

    session = boto3.session.Session()
    client = session.client(service_name='secretsmanager')

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name)
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            print("The requested secret " + secret_name + " was not found")
        elif e.response['Error']['Code'] == 'InvalidRequestException':
            print("The request was invalid due to:", e)
        elif e.response['Error']['Code'] == 'InvalidParameterException':
            print("The request had invalid params:", e)
    else:
        # Secrets Manager decrypts the secret value using the associated KMS CMK
        # Depending on whether the secret was a string or binary, only one of these fields will be populated
        if 'SecretString' in get_secret_value_response:
            secret = get_secret_value_response['SecretString']
        else:
            secret = get_secret_value_response['SecretBinary']
    return json.loads(secret)


def calculate_elapsed_time():
    """
    Calculates how much time it took for the whole sync process to complete (in minutes)
    """
    end_time = time.monotonic()
    time_in_minutes = (end_time - start_time) / 60
    return round(time_in_minutes, 2)


def batch_execute_statement(sql, sql_parameter_sets, transaction_id=None):
    parameters = {
        'secretArn': db_credentials_secrets_store_arn,
        'database': aurora_database_name,
        'resourceArn': db_cluster_arn,
        'sql': sql,
        'parameterSets': sql_parameter_sets
    }
    if transaction_id is not None:
        parameters['transactionId'] = transaction_id
    response = rds_client.batch_execute_statement(**parameters)
    return response


def try_execute_bath_transaction(sql, parameter_set):
    transaction = rds_client.begin_transaction(
        secretArn=db_credentials_secrets_store_arn, resourceArn=db_cluster_arn, database=aurora_database_name)
    try:
        response = batch_execute_statement(
            sql, parameter_set, transaction['transactionId'])
    except Exception as e:
        transaction_response = rds_client.rollback_transaction(
            secretArn=db_credentials_secrets_store_arn,
            resourceArn=db_cluster_arn,
            transactionId=transaction['transactionId'])

        global num_of_failed_transactions
        num_of_failed_transactions = num_of_failed_transactions + 1
    else:
        transaction_response = rds_client.commit_transaction(
            secretArn=db_credentials_secrets_store_arn,
            resourceArn=db_cluster_arn,
            transactionId=transaction['transactionId'])
        print(f'Number of records updated: {len(response["updateResults"])}')
    print(f'Transaction Status: {transaction_response["transactionStatus"]}')


def get_entry(row):
    entry = [
        {'name': 'ID', 'value': {'stringValue': row['ID']}},
        {'name': 'STATUS_DATE', 'typeHint': 'TIMESTAMP',
            'value': {'stringValue': row['STATUS_DATE']}}]

    # RATING
    if row['RATING'] == '':
        entry.append({'name': 'RATING',
                      'value': {'isNull': True}})
    else:
        entry.append({'name': 'RATING', 'value': {
            'longValue': int(row['RATING'])}})
    return entry


def export_source_db_data():

    result = False
    # Database connection variable.
    connect = None
    # Check if the file path exists.
    if os.path.exists(filePath):

        try:

            connect = pyodbc.connect('DRIVER={ODBC Driver 17 for SQL Server};SERVER=' +
                                     server+';DATABASE='+database+';UID='+username+';PWD=' + password)

        except pyodbc.Error as e:

            # Confirm unsuccessful connection and stop program execution.
            print("Database connection unsuccessful.")
            # quit()
            result = False

        # Cursor to execute query.
        cursor = connect.cursor()

        try:

            # Execute query.
            cursor.execute(source_db_export_sql)

            # Fetch the data returned.
            results = cursor.fetchall()

            # Extract the table headers.
            headers = [i[0] for i in cursor.description]

            # Open CSV file for writing.
            csvFile = csv.writer(open(filePath + fileName, 'w', newline=''),
                                 delimiter=',', lineterminator='\r\n',
                                 quoting=csv.QUOTE_ALL, escapechar='\\')

            # Add the headers and data to the CSV file.
            csvFile.writerow(headers)
            csvFile.writerows(results)

            # Message stating export successful.
            print("Data export successful.")
            result = True

        except pyodbc.Error as e:

            # Message stating export unsuccessful.
            print("Data export unsuccessful.")
            # quit()
            result = False

        finally:

            # Close database connection.
            connect.close()

    else:

        # Message stating file path does not exist.
        print("File path does not exist.")
        result = False

    return result


def get_current_table_name():
    """
    Returns the name of the currently used table by the views by calling the DynamoDB table
    """
    current_table_name = 'TABLE_BLUE'
    try:
        response = table.get_item(
            Key={
                'ItemKey': 'CurrentTableName'
            },
            ConsistentRead=True
        )
        current_table_name = response['Item']['CurrentTableName']
    except KeyError as _:
        print(
            f"'CurrentTableName' doesn't exist (i.e. first sync run) => use {current_table_name}")
        # Item with 'CurrentTableName' doesn't exist yet (i.e. first run) so return 'BLUE' for example, it doesn't matter
        return current_table_name

    return current_table_name


def update_current_table_name(name):
    """
    Updates the currently used table with the provided name
    """
    table.update_item(
        Key={
            'ItemKey': 'CurrentTableName'
        },
        UpdateExpression='SET CurrentTableName = :name',
        ExpressionAttributeValues={
            ':name': name
        }
    )


def update_db_views(table_name):
    """
    Update the source table of the 'latest' & 'history_data' views
    """
    drop_view_sql = 'DROP VIEW IF EXISTS my_view;'

    create_view_sql = 'CREATE VIEW {view_name} AS SELECT \
    ID AS "ID",\
    STATUS_DATE AS "Date",\
    CAST(RATING AS float) AS "Rating",\
    FROM {table_name} '

    create_my_view_sql = create_view_sql.format(
        view_name='my_view', table_name=table_name)

    # drop view
    rds_client.execute_statement(resourceArn=db_cluster_arn, secretArn=db_credentials_secrets_store_arn,
                                 database=aurora_database_name, sql=drop_view_sql)

    # create view
    rds_client.execute_statement(resourceArn=db_cluster_arn, secretArn=db_credentials_secrets_store_arn,
                                 database=aurora_database_name, sql=create_view_sql)


def notify_devs(message):
    """
    Sends a notification to an SNS topic with content set to the 'message'
    """
    sns.publish(
        TopicArn=sns_toplic_arn,
        Message=message,
    )


def main():

    # start inserting records in the DB if there was a successfull export
    if(export_source_db_data()):

        # get the 'CurrentTableName' from the DynamoDB table
        current_table = get_current_table_name()

        if current_table == 'TABLE_BLUE':
            new_table_name = 'TABLE_GREEN'
        else:
            new_table_name = 'TABLE_BLUE'

        # use string interpolation to populate the name of the current table
        insert_sql = insert_sql.format(current_table_name=new_table_name)

        delete_all_from_new_table_sql = "delete from {new_table_name}".format(
            new_table_name=new_table_name)
        # delete all of the records in the 'new_table' before we start inserting records into it
        rds_client.execute_statement(resourceArn=db_cluster_arn, secretArn=db_credentials_secrets_store_arn,
                                     database=aurora_database_name, sql=delete_all_from_new_table_sql)

        parameter_set = []

        with open(fileName, 'r') as file:
            reader = csv.DictReader(file, delimiter=',')

            for row in reader:

                entry = get_entry(row)

                if(len(parameter_set) == batch_size):
                    try_execute_bath_transaction(insert_sql, parameter_set)

                    transaction_count = transaction_count + 1
                    print(
                        f'Transaction count: {transaction_count}. Num of failed transactions: {num_of_failed_transactions}')

                    parameter_set.clear()
                    parameter_set.append(entry)
                else:
                    parameter_set.append(entry)
            # check if we have records that didn't fit into a batch (i.e. less than batch_size)
            if(len(parameter_set) > 0):
                try_execute_bath_transaction(insert_sql, parameter_set)
                transaction_count = transaction_count + 1
                print(f'Transaction count: {transaction_count}')

        # if we have inserted all of the records without an issue
        if(num_of_failed_transactions == 0):
            update_current_table_name(new_table_name)
            update_db_views(new_table_name)
            notify_devs('Full database sync completed successfully! Currently used table: {new_table_name}.\n The sync took: {elapsed_time} minutes'.format(
                new_table_name=new_table_name, elapsed_time=calculate_elapsed_time()))
        else:
            notify_devs('Failed to perform Source database sync.')
    else:
        notify_devs('Failed to export source database.')

    # Self-Terminate the Instance
    subprocess.Popen(self_terminate_bash_commnand.split())
# END OF FUNCTIONS


# VARIABLES
secrets = get_secret('secret-manager-secret-name-here')

rds_client = boto3.client('rds-data')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(secrets['dynamodb_table_name'])
sns = boto3.client('sns')

# AURORA Vars
aurora_database_name = secrets['dbName']
db_cluster_arn = secrets['auroraArn']
db_credentials_secrets_store_arn = secrets['secretsArn']

# Source db Params/Vars
# csv data file path and name.
filePath = os.getcwd() + '/'
fileName = 'DATA.csv'
server = secrets['SourceServer']
database = secrets['SourceDatabase']
username = secrets['SourceDbUsername']
password = secrets['SourceDbPassword']
# SQL to select data from the source table.
source_db_export_sql = "SELECT ID, STATUS_DATE,RATING FROM dbo.T_SOURCE"

# SNS toplic Params/Vars
sns_toplic_arn = secrets['snsTopicArn']

# Bash Commands
self_terminate_bash_commnand = 'sudo shutdown -h now'
# measure record the start time
start_time = time.monotonic()

batch_size = 250
transaction_count = 0
num_of_failed_transactions = 0

insert_sql = 'INSERT INTO {current_table_name} VALUES (\
:ID, :STATUS_DATE, :DRAW_WORKS_RATING);'

if __name__ == "__main__":
    main()
