import os
import tempfile
import unittest
import sqlite3
from contextlib import closing
from unittest.mock import patch
from app import create_app

class ShopTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.app=create_app({'TESTING':True,'DATABASE':os.path.join(self.tmp.name,'test.db'),'SECRET_KEY':'test-key'})
        self.client=self.app.test_client()
        self.token=self.client.get('/api/session').json['csrf']

    def tearDown(self):
        self.tmp.cleanup()

    def post(self,url,data):
        return self.client.post(url,json=data,headers={'X-CSRF-Token':self.token})

    def register(self):
        self.assertEqual(self.post('/api/auth/register',{'email':'buyer@example.com','password':'a-secure-password'}).status_code,200)
        self.token=self.client.get('/api/session').json['csrf']

    def test_checkout_stock_and_history(self):
        self.register()
        initial=self.client.get('/api/products').json[0]
        self.assertEqual(self.post('/api/cart',{'product_id':initial['id'],'quantity':2}).status_code,200)
        response=self.post('/api/checkout',{'address':'12 Example Street, Bengaluru 560001','total':1})
        self.assertEqual(response.status_code,201)
        self.assertEqual(response.json['total'],initial['price']*2)
        self.assertEqual(self.client.get('/api/products').json[0]['stock'],initial['stock']-2)
        self.assertEqual(self.client.get('/api/cart').json['items'],[])
        self.assertEqual(len(self.client.get('/api/orders').json),1)
        self.assertEqual(self.post('/api/checkout',{'address':'12 Example Street'}).status_code,409)

    def test_auth_csrf_and_admin(self):
        self.assertEqual(self.client.post('/api/auth/register',json={}).status_code,403)
        self.assertEqual(self.client.get('/api/cart').status_code,401)
        self.register()
        self.assertEqual(self.client.get('/api/admin').status_code,403)
        other=self.app.test_client()
        token=other.get('/api/session').json['csrf']
        other.post('/api/auth/register',json={'email':'other@example.com','password':'other-password'},headers={'X-CSRF-Token':token})
        self.assertEqual(other.get('/api/orders').json,[])

    def test_invalid_cart_and_stock(self):
        self.register()
        self.assertEqual(self.post('/api/cart',{'product_id':1,'quantity':99}).status_code,409)
        self.assertEqual(self.post('/api/cart',{'product_id':1,'quantity':-1}).status_code,400)
        self.assertEqual(self.post('/api/cart',{'product_id':1,'quantity':True}).status_code,400)
        self.assertEqual(self.post('/api/checkout',{'address':'short'}).status_code,400)

    def test_electronics_catalog_details_and_wishlist(self):
        products=self.client.get('/api/products').json
        self.assertEqual(len(products),12)
        self.assertEqual({p['category'] for p in products},{'Laptops','Phones','Audio','Wearables','Gaming','Tablets','Accessories'})
        self.assertTrue(all(isinstance(p['specs'],dict) and p['image'] for p in products))
        pid=products[0]['id']
        self.assertEqual(self.client.get(f'/products/{pid}').status_code,200)
        self.assertEqual(self.client.get('/products/999999').status_code,404)
        self.assertEqual(self.client.get('/api/wishlist').status_code,401)
        self.register()
        self.assertEqual(self.post('/api/wishlist',{'product_id':pid}).json,[pid])
        self.assertEqual(self.client.get('/api/wishlist').json,[pid])
        other=self.app.test_client()
        token=other.get('/api/session').json['csrf']
        other.post('/api/auth/register',json={'email':'second@example.com','password':'other-password'},headers={'X-CSRF-Token':token})
        self.assertEqual(other.get('/api/wishlist').json,[])
        self.assertEqual(self.post('/api/wishlist',{'product_id':pid}).json,[])
        self.assertEqual(self.post('/api/wishlist',{'product_id':999999}).status_code,404)

    def test_last_item_cannot_be_sold_twice(self):
        self.register()
        with closing(sqlite3.connect(self.app.config['DATABASE'])) as connection:
            connection.execute('UPDATE products SET stock=1 WHERE id=1')
            connection.commit()
        self.post('/api/cart',{'product_id':1,'quantity':1})
        other=self.app.test_client()
        token=other.get('/api/session').json['csrf']
        other.post('/api/auth/register',json={'email':'lastitem@example.com','password':'other-password'},headers={'X-CSRF-Token':token})
        token=other.get('/api/session').json['csrf']
        other.post('/api/cart',json={'product_id':1,'quantity':1},headers={'X-CSRF-Token':token})
        self.assertEqual(self.post('/api/checkout',{'address':'12 Example Street'}).status_code,201)
        self.assertEqual(other.post('/api/checkout',json={'address':'14 Example Street'},headers={'X-CSRF-Token':token}).status_code,409)
        self.assertEqual(self.client.get('/api/products').json[0]['stock'],0)

    def test_legacy_catalog_migration_preserves_orders(self):
        legacy=os.path.join(self.tmp.name,'legacy.db')
        with closing(sqlite3.connect(legacy)) as connection:
            connection.executescript('''CREATE TABLE products(id INTEGER PRIMARY KEY,name TEXT NOT NULL,description TEXT NOT NULL,category TEXT NOT NULL,price INTEGER NOT NULL,stock INTEGER NOT NULL,icon TEXT NOT NULL);
            INSERT INTO products VALUES(1,'The Cozy Collection','Legacy gift','Gift boxes',249900,10,'gift');
            CREATE TABLE users(id INTEGER PRIMARY KEY,email TEXT UNIQUE NOT NULL,password TEXT NOT NULL,is_admin INTEGER NOT NULL DEFAULT 0);
            INSERT INTO users VALUES(1,'existing@example.com','legacy-hash',0);
            CREATE TABLE orders(id INTEGER PRIMARY KEY,user_id INTEGER NOT NULL,total INTEGER NOT NULL,address TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'placed',created_at TEXT DEFAULT CURRENT_TIMESTAMP);
            INSERT INTO orders(id,user_id,total,address) VALUES(1,1,249900,'Existing address');
            CREATE TABLE order_items(order_id INTEGER,product_id INTEGER,name TEXT NOT NULL,price INTEGER NOT NULL,quantity INTEGER NOT NULL);
            INSERT INTO order_items VALUES(1,1,'The Cozy Collection',249900,1);''')
        migrated=create_app({'TESTING':True,'DATABASE':legacy})
        self.assertEqual(len(migrated.test_client().get('/api/products').json),12)
        create_app({'TESTING':True,'DATABASE':legacy})
        with closing(sqlite3.connect(legacy)) as connection:
            self.assertEqual(connection.execute('SELECT COUNT(*) FROM products WHERE active=1').fetchone()[0],12)
            self.assertEqual(connection.execute('SELECT name FROM order_items WHERE order_id=1').fetchone()[0],'The Cozy Collection')
            self.assertEqual(connection.execute('SELECT email FROM users WHERE id=1').fetchone()[0],'existing@example.com')

    def test_login_logout_and_duplicate_registration(self):
        self.register()
        self.assertEqual(self.post('/api/auth/register',{'email':'buyer@example.com','password':'a-secure-password'}).status_code,409)
        self.post('/api/auth/logout',{})
        self.assertIsNone(self.client.get('/api/session').json['user'])
        self.token=self.client.get('/api/session').json['csrf']
        self.assertEqual(self.post('/api/auth/login',{'email':'buyer@example.com','password':'wrong-password'}).status_code,401)
        self.assertEqual(self.post('/api/auth/login',{'email':'buyer@example.com','password':'a-secure-password'}).status_code,200)

    def test_admin_inventory_and_fulfillment(self):
        self.register()
        self.post('/api/cart',{'product_id':1,'quantity':1})
        order=self.post('/api/checkout',{'address':'12 Demo Address'}).json['order_id']
        with patch.dict(os.environ,{'ADMIN_EMAIL':'admin@example.com','ADMIN_PASSWORD':'sample-admin-password'}):
            admin_app=create_app({'TESTING':True,'DATABASE':self.app.config['DATABASE'],'SECRET_KEY':'test-key'})
        client=admin_app.test_client()
        token=client.get('/api/session').json['csrf']
        client.post('/api/auth/login',json={'email':'admin@example.com','password':'sample-admin-password'},headers={'X-CSRF-Token':token})
        token=client.get('/api/session').json['csrf']
        headers={'X-CSRF-Token':token}
        self.assertEqual(client.post('/api/admin',json={'product_id':1,'stock':12},headers=headers).status_code,200)
        self.assertEqual(client.post('/api/admin',json={'product_id':1,'stock':-1},headers=headers).status_code,400)
        self.assertEqual(client.post('/api/admin',json={'order_id':order,'status':'shipped'},headers=headers).status_code,200)
        self.assertEqual(client.post('/api/admin',json={'order_id':order,'status':'invalid'},headers=headers).status_code,400)
        self.assertEqual(self.client.get('/api/orders').json[0]['status'],'shipped')

    def test_cart_removal_and_security_headers(self):
        self.register()
        self.post('/api/cart',{'product_id':1,'quantity':1})
        self.assertEqual(self.post('/api/cart',{'product_id':1,'quantity':0}).json['items'],[])
        response=self.client.get('/api/products')
        self.assertEqual(response.headers['Cache-Control'],'no-store')
        self.assertEqual(response.headers['X-Frame-Options'],'DENY')
        self.assertIn("frame-ancestors 'none'",response.headers['Content-Security-Policy'])

if __name__=='__main__':
    unittest.main()
