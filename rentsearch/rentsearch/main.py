import sys
import os
sys.path.insert(0, 'package/')

import boto3
import requests
from bs4 import BeautifulSoup

def lambda_handler(event, context):
    base_url = 'https://www.daft.ie'

    sqs = boto3.resource('sqs')
    queue = sqs.get_queue_by_name(QueueName=os.environ['sqsname'])

    resp = requests.get(f'{base_url}/property-for-rent/limerick-city?sort=publishDateDesc')

    soup = BeautifulSoup(resp.text, 'html.parser')
    for link in soup.select('a[href^="/for-rent/"]'):
        queue.send_message(MessageBody=f'{base_url}{link["href"]}')

    return {'statusCode': 200}