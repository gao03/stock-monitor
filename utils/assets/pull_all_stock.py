
import requests
import json

def pull():
    try:
        response = requests.get(
            url="http://84.push2.eastmoney.com/api/qt/clist/get",
            params={
                "pn": "1",
                "pz": "6000",
                "fs": "m:1+t:2,m:1+t:23,m:0+t:6,m:0+t:80",
                "fields": "f12,f13,f14",  # f12:Code, f13:Type(0-SH,1-SZ), f14:Name
            },
        )
        return response.json()
    except requests.exceptions.RequestException:
        print('HTTP Request failed')


lst = [{"code": i['f12'], 'type':i['f13'], 'name':i['f14']} for i in pull()['data']['diff'].values()]

with open('all_stock.json', 'w') as f:
    f.write(json.dumps(lst).encode("utf-8").decode("unicode-escape"))