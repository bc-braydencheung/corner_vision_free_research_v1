import requests, json
URL = 'https://info.cld.hkjc.com/graphql/base/'
H = {'Content-Type': 'application/json'}
for qs in ['lotteryResult','drawResult','marksixResult','m6Result','lastDraw','lottery','markSix']:
    r = requests.post(URL, json={'query':f'query{{{qs}(startDate:\"20240101\",endDate:\"20240131\"){{id}}}}'}, headers=H, timeout=10)
    d = json.loads(r.text)
    ok = 'data' in d
    print(f'{qs}: {r.status_code} {"DATA" if ok else d.get("errors",[{}])[0].get("message","")[:100]}')
