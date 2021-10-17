from unittest import mock

import pytest
from rentextract.main import (extract_json_props, extract_property_datas,
                              extract_url_from_body, get_html_from_url,
                              lambda_handler)


def get_test_html() -> str:
    return '''
    <html>
        <script id="__NEXT_DATA__">
            {"props":{"pageProps":{"daftCookies":{},"listing":{"id":3578774,
            "title":"Woodlawn Drive, Dooradoyle, Co. Limerick","seoTitle":
            "Woodlawn Drive, Dooradoyle, Dooradoyle, Co. Limerick","sections":
            ["Property","Residential","House"],"featuredLevel":"STANDARD","lastUpdateDate":
            "15/10/2021","price":"€1,700 per month","numBedrooms":"3 Bed","numBathrooms":
            "2 Bath","propertyType":"House","daftShortcode":"26547020","seller":
            {"sellerId":3220,"name":"Hogan Durkan Lettings"}}}}}
        </script>
    </html>
    '''

def test_extract_url_from_body() -> None:
    EXPECTED_URL = 'http://url.fake'
    with pytest.raises(Exception):
        extract_url_from_body({})
    
    with pytest.raises(Exception):
        extract_url_from_body({'Records': [{''}]})
    
    assert extract_url_from_body({'Records': [{'body': EXPECTED_URL}]}) == EXPECTED_URL

def test_get_html_from_url() -> None:
    MOCK_URL = 'test'
    MOCK_RESPONSE = 'response'

    with mock.patch('requests.get') as requests_get_mock:
        requests_get_mock.return_value.status_code = 201

        with pytest.raises(Exception):
            get_html_from_url(MOCK_URL)
        
    with mock.patch('requests.get') as requests_get_mock:
        requests_get_mock.return_value.status_code = 200
        requests_get_mock.return_value.text = MOCK_RESPONSE

        
        assert get_html_from_url(MOCK_URL) == MOCK_RESPONSE

def test_extract_json_props() -> None:
    assert "props" in extract_json_props(get_test_html())

def test_extract_property_datas() -> None:
    EXPECTED_RESULT = [
        {'name': 'title', 'value': {'stringValue': 'Woodlawn Drive, Dooradoyle, Dooradoyle, Co. Limerick'}}, 
        {'name': 'lastname', 'value': {'longValue': 1700}},
    ]

    assert extract_property_datas(extract_json_props(get_test_html())) == EXPECTED_RESULT

def test_lambda_handler() -> None:
    # lambda_handler({'Records': [{'body': 'https://www.daft.ie/for-rent/house-woodlawn-drive-dooradoyle-co-limerick/3578774'}]}, {})
    ...