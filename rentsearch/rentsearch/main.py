import sys
import os
sys.path.insert(0, 'package/')

import boto3
import requests
from bs4 import BeautifulSoup

def lambda_handler(event, context):
    PROPERTIES_PER_PAGE = 20
    NO_PROPERTIES_FOUND = "We didn't find any properties"

    base_url = 'https://www.daft.ie'

    sqs = boto3.resource('sqs')
    queue = sqs.get_queue_by_name(QueueName=os.environ['sqsname'])

    counter = 0
    while True:
        resp = requests.get(f'{base_url}/property-for-rent/limerick?sort=publishDateDesc&pageSize=20&from={counter}')
        html = resp.text

        if NO_PROPERTIES_FOUND in html:
            break

        soup = BeautifulSoup(html, 'html.parser')
        for link in soup.select('a[href^="/for-rent/"]'):
            queue.send_message(MessageBody=f'{base_url}{link["href"]}')
        
        counter += PROPERTIES_PER_PAGE

    return {'statusCode': 200}