"""Read-only release checks. Creates no accounts, orders or payments."""
import argparse
import json
import time
from urllib.request import urlopen
from urllib.error import URLError

def verify(base,commit=None):
    def read(path):
        with urlopen(base.rstrip('/')+path,timeout=20) as response:
            if response.status!=200:
                raise RuntimeError(f'{path}: HTTP {response.status}')
            return response.read()
    if json.loads(read('/health')).get('status')!='healthy':
        raise RuntimeError('Database health check failed')
    products=json.loads(read('/api/products'))
    if not isinstance(products,list) or not products or any(p.get('price',0)<=0 for p in products):
        raise RuntimeError('Catalog is empty or invalid')
    if b'volt' not in read('/').lower():
        raise RuntimeError('Storefront did not render')
    read('/static/app.js')
    read('/static/style.css')
    if commit and json.loads(read('/static/build.json')).get('commit')!=commit:
        raise RuntimeError('Deployed commit does not match this build')
    print('PASS: health, catalog, storefront, assets'+(' and deployed commit' if commit else ''))

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('url')
    parser.add_argument('--commit')
    parser.add_argument('--attempts',type=int,default=12)
    args=parser.parse_args()
    for attempt in range(args.attempts):
        try:
            verify(args.url,args.commit)
            break
        except (URLError,RuntimeError,ValueError,TimeoutError) as error:
            if attempt+1==args.attempts:
                raise SystemExit(f'Release verification failed: {error}')
            print(f'Waiting for deployment ({attempt+1}/{args.attempts}): {error}')
            time.sleep(10)
