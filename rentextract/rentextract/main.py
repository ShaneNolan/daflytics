import sys

sys.path.insert(0, 'package/')

import json
import os
from typing import Any, Dict

import boto3
from botocore.exceptions import ClientError
import requests
from bs4 import BeautifulSoup
from time import sleep


def extract_url_from_body(event: Dict[str, Any]) -> str:
    KEY_RECORDS = 'Records'
    KEY_BODY = 'body'

    if KEY_RECORDS not in event:
        raise Exception(f'[BadRequest] Key: "{KEY_RECORDS}" missing from request.')

    payload = event[KEY_RECORDS][0]

    if KEY_BODY not in payload:
        raise Exception(f'[BadRequest] Key: "{KEY_BODY}" missing from record.')
    
    return payload[KEY_BODY]

def get_html_from_url(url: str) -> str:
    SUCCESSFUL_RESPONSE = 200

    resp = requests.get(url)
    
    if resp.status_code == SUCCESSFUL_RESPONSE:
        return resp.text
    
    raise Exception(f'[BadRequest] URL: {url} returned a status code of: {resp.status_code}.')

def extract_json_props(html: str) -> Dict[str, Any]:
    soup = BeautifulSoup(html, 'html.parser')

    script = soup.find('script', id='__NEXT_DATA__').text

    return json.loads(script)

def extract_property_datas(props: Dict[str, Any]) -> Dict[str, Any]:
    KEY_FACILITIES = 'facilities'
    KEY_PROPERTY_OVERVIEW = 'propertyOverview'
    listing = props['props']['pageProps']['listing']

    facilities = ''
    if KEY_FACILITIES in listing:
        facilities = json.dumps(listing[KEY_FACILITIES])
    
    property_overview = ''
    if KEY_PROPERTY_OVERVIEW in listing:
        property_overview = json.dumps(listing[KEY_PROPERTY_OVERVIEW])

    return [
        {'name': 'title', 'value': {'stringValue': listing['seoTitle']}},
        {'name': 'price', 'value': {'longValue': int(listing['nonFormatted']['price'])}},
        {'name': 'propertyType', 'value': {'stringValue': listing['propertyType']}},
        {'name': 'numBedrooms', 'value': {'stringValue': listing['numBedrooms']}},
        {'name': 'numBathrooms', 'value': {'stringValue': listing['numBathrooms']}},
        {'name': 'ber', 'value': {'stringValue': listing['ber']['rating']}},
        {'name': 'facilities', 'value': {'stringValue': facilities}},
        {'name': 'propertyOverview', 'value': {'stringValue': property_overview}},
    ]

def _wait_for_serverless(rds_data_client: Any) -> None:
    MAX_ATTEMPTS = 6
    TIME_TO_WAKEUP = 10

    for _ in range(MAX_ATTEMPTS):
        try:
            rds_data_client.execute_statement(
                resourceArn=os.environ['clusterarn'],
                secretArn=os.environ['secretarn'],
                database=os.environ['database'],
                sql='select id from property',
            )
            return
        except ClientError as ex:
            error_code = ex.response.get("Error").get('Code')
            error_msg = ex.response.get("Error").get('Message')

            if error_code == 'BadRequestException' and 'Communications link failure' in error_msg:
                print('Waiting for Aurora Serverless to wake up.')
                sleep(TIME_TO_WAKEUP)

                continue
            
            raise ex
        
    raise Exception('[BadRequest] unable to connect to database (serverless).')

def insert_property_datas_into_aurora(property_datas: Dict[str, Any]) -> str:
    rds_data_client = boto3.client('rds-data')

    _wait_for_serverless(rds_data_client)

    response = rds_data_client.execute_statement(
        resourceArn=os.environ['clusterarn'],
        secretArn=os.environ['secretarn'],
        database=os.environ['database'],
        sql='''
        insert into property(title, price, propertyType, numBedrooms, numBathrooms, ber, facilities, propertyOverview) 
        VALUES(:title, :price, :propertyType, :numBedrooms, :numBathrooms, :ber, :facilities, :propertyOverview)
        ''',
        parameters=property_datas,
    )

    return str(response)

def lambda_handler(event, context):
    # Messages are sent one at a time. Batch can handle 10.

    rent_link = extract_url_from_body(event)

    rent_html = get_html_from_url(rent_link)

    props = extract_json_props(rent_html)

    property_datas = extract_property_datas(props)

    print(property_datas)

    insert_property_datas_into_aurora(property_datas)

    return {'statusCode': 200}
