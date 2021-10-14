import requests

def lambda_handler(event, context):
    resp = requests.get('https://www.daft.ie/property-for-rent/limerick-city?sort=publishDateDesc')
    
    return { 
        'response' : f'{resp}'
    }