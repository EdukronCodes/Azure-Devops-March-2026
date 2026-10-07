import os
import json
import secrets
import sqlite3
from functools import wraps
from pathlib import Path
from flask import Flask, g, session, request, jsonify, render_template
from werkzeug.security import generate_password_hash, check_password_hash

def create_app(config=None):
    app = Flask(__name__)
    app.config.update(SECRET_KEY=os.environ.get('SECRET_KEY') or secrets.token_hex(32), DATABASE=os.environ.get('DATABASE_PATH', 'data/shop.db'), SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE='Lax', SESSION_COOKIE_SECURE=os.environ.get('PRODUCTION') == '1', MAX_CONTENT_LENGTH=65536)
    if config:
        app.config.update(config)

    def db():
        if 'db' not in g:
            g.db = sqlite3.connect(app.config['DATABASE'], timeout=30)
            g.db.row_factory = sqlite3.Row
            g.db.execute('PRAGMA foreign_keys=ON')
        return g.db

    @app.teardown_appcontext
    def close_db(error):
        if 'db' in g:
            g.pop('db').close()

    Path(app.config['DATABASE']).parent.mkdir(parents=True, exist_ok=True)
    with app.app_context():
        db().executescript('''
        CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY,email TEXT UNIQUE NOT NULL,password TEXT NOT NULL,is_admin INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS products(id INTEGER PRIMARY KEY,name TEXT NOT NULL,description TEXT NOT NULL,category TEXT NOT NULL,price INTEGER NOT NULL CHECK(price>0),stock INTEGER NOT NULL CHECK(stock>=0),icon TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS cart(user_id INTEGER REFERENCES users(id),product_id INTEGER REFERENCES products(id),quantity INTEGER NOT NULL CHECK(quantity>0),PRIMARY KEY(user_id,product_id));
        CREATE TABLE IF NOT EXISTS orders(id INTEGER PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id),total INTEGER NOT NULL,address TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'placed',created_at TEXT DEFAULT CURRENT_TIMESTAMP);
        CREATE TABLE IF NOT EXISTS order_items(order_id INTEGER REFERENCES orders(id),product_id INTEGER REFERENCES products(id),name TEXT NOT NULL,price INTEGER NOT NULL,quantity INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS wishlist(user_id INTEGER REFERENCES users(id),product_id INTEGER REFERENCES products(id),PRIMARY KEY(user_id,product_id));
        ''')
        columns={row['name'] for row in db().execute('PRAGMA table_info(products)')}
        for name,definition in {'brand':"TEXT NOT NULL DEFAULT ''",'specs':"TEXT NOT NULL DEFAULT '{}'",'image':"TEXT NOT NULL DEFAULT ''",'compare_price':'INTEGER NOT NULL DEFAULT 0','active':'INTEGER NOT NULL DEFAULT 1'}.items():
            if name not in columns:
                db().execute(f'ALTER TABLE products ADD COLUMN {name} {definition}')
        if not db().execute("SELECT 1 FROM metadata WHERE key='electronics_catalog_v1'").fetchone():
            # Archive the former demo catalog; order item snapshots remain unchanged.
            db().execute("UPDATE products SET active=0 WHERE name IN ('The Cozy Collection','Bloom & Celebrate','Morning Ritual','Sweet Little Joys','A Moment of Calm','Grow Together')")
            db().execute('DELETE FROM cart WHERE product_id IN (SELECT id FROM products WHERE active=0)')
            from catalog import PRODUCTS
            for product in PRODUCTS:
                db().execute('INSERT INTO products(name,description,category,price,stock,icon,brand,specs,image,compare_price) VALUES(?,?,?,?,?,?,?,?,?,?)', (
                    product['name'],product['description'],product['category'],product['price'],product['stock'],'',product['brand'],json.dumps(product['specs']),product['image'],product['compare_price']))
            db().execute("INSERT INTO metadata VALUES('electronics_catalog_v1','1')")
        admin_email, admin_password = os.environ.get('ADMIN_EMAIL'), os.environ.get('ADMIN_PASSWORD')
        if admin_email and admin_password:
            db().execute('INSERT OR IGNORE INTO users(email,password,is_admin) VALUES(?,?,1)', (admin_email.lower(), generate_password_hash(admin_password)))
        db().commit()

    def login_required(fn):
        @wraps(fn)
        def wrapped(*args, **kwargs):
            if not session.get('uid'):
                return jsonify(error='Please sign in first'), 401
            return fn(*args, **kwargs)
        return wrapped

    @app.before_request
    def csrf():
        if request.method in ('POST','PUT','DELETE','PATCH') and (not session.get('csrf') or not secrets.compare_digest(request.headers.get('X-CSRF-Token',''),session['csrf'])):
            return jsonify(error='Refresh the page and try again'),403

    @app.after_request
    def headers(response):
        response.headers['X-Content-Type-Options']='nosniff'
        response.headers['X-Frame-Options']='DENY'
        response.headers['Content-Security-Policy']="default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; frame-ancestors 'none'"
        if request.path.startswith('/api/'):
            response.headers['Cache-Control']='no-store'
        return response

    @app.get('/')
    def home():
        return render_template('index.html')

    @app.get('/products/<int:product_id>')
    def product_page(product_id):
        if not db().execute('SELECT id FROM products WHERE id=? AND active=1',(product_id,)).fetchone():
            return render_template('index.html'),404
        return render_template('index.html')

    def serialize_product(product):
        result=dict(product)
        result['specs']=json.loads(result['specs'])
        return result

    @app.get('/health')
    def health():
        db().execute('SELECT 1')
        return jsonify(status='healthy')

    @app.get('/api/session')
    def current_session():
        session.setdefault('csrf',secrets.token_hex(32))
        user=db().execute('SELECT id,email,is_admin FROM users WHERE id=?',(session.get('uid'),)).fetchone()
        return jsonify(csrf=session['csrf'],user=dict(user) if user else None)

    @app.post('/api/auth/<action>')
    def auth(action):
        if action=='logout':
            session.clear()
            return jsonify(ok=True)
        data=request.get_json(silent=True) or {}
        email=str(data.get('email','')).strip().lower()
        password=data.get('password','')
        if not isinstance(password,str) or len(password)<10 or len(password)>200 or '@' not in email or len(email)>254:
            return jsonify(error='Enter an email and password of 10–200 characters'),400
        if action=='register':
            try:
                db().execute('INSERT INTO users(email,password) VALUES(?,?)',(email,generate_password_hash(password)))
                db().commit()
            except sqlite3.IntegrityError:
                return jsonify(error='Account already exists'),409
        elif action!='login':
            return jsonify(error='Unknown action'),404
        user=db().execute('SELECT * FROM users WHERE email=?',(email,)).fetchone()
        if not user or not check_password_hash(user['password'],password):
            return jsonify(error='Invalid email or password'),401
        session.clear()
        session['uid']=user['id']
        session['csrf']=secrets.token_hex(32)
        return jsonify(ok=True)

    @app.get('/api/products')
    def products():
        return jsonify([serialize_product(p) for p in db().execute('SELECT * FROM products WHERE active=1 ORDER BY id')])

    @app.route('/api/wishlist',methods=['GET','POST'])
    @login_required
    def wishlist():
        if request.method=='POST':
            data=request.get_json(silent=True) or {}
            pid=data.get('product_id')
            if type(pid)!=int or not db().execute('SELECT id FROM products WHERE id=? AND active=1',(pid,)).fetchone():
                return jsonify(error='Product not found'),404
            if db().execute('SELECT 1 FROM wishlist WHERE user_id=? AND product_id=?',(session['uid'],pid)).fetchone():
                db().execute('DELETE FROM wishlist WHERE user_id=? AND product_id=?',(session['uid'],pid))
            else:
                db().execute('INSERT INTO wishlist VALUES(?,?)',(session['uid'],pid))
            db().commit()
        return jsonify([row['product_id'] for row in db().execute('SELECT product_id FROM wishlist WHERE user_id=?',(session['uid'],))])

    @app.route('/api/cart',methods=['GET','POST'])
    @login_required
    def cart():
        if request.method=='POST':
            data=request.get_json(silent=True) or {}
            pid,q=data.get('product_id'),data.get('quantity')
            if type(pid)!=int or type(q)!=int or not 0<=q<=99:
                return jsonify(error='Invalid quantity'),400
            product=db().execute('SELECT stock FROM products WHERE id=? AND active=1',(pid,)).fetchone()
            if not product or q>product['stock']:
                return jsonify(error='Insufficient stock'),409
            if q==0:
                db().execute('DELETE FROM cart WHERE user_id=? AND product_id=?',(session['uid'],pid))
            else:
                db().execute('INSERT INTO cart VALUES(?,?,?) ON CONFLICT(user_id,product_id) DO UPDATE SET quantity=excluded.quantity',(session['uid'],pid,q))
            db().commit()
        items=[serialize_product(p) for p in db().execute('SELECT p.*,c.quantity FROM cart c JOIN products p ON p.id=c.product_id WHERE c.user_id=? AND p.active=1',(session['uid'],))]
        return jsonify(items=items,total=sum(p['price']*p['quantity'] for p in items))

    @app.post('/api/checkout')
    @login_required
    def checkout():
        data=request.get_json(silent=True) or {}
        address=data.get('address','')
        if not isinstance(address,str) or not 10<=len(address.strip())<=1000:
            return jsonify(error='Enter a complete delivery address'),400
        connection=db()
        try:
            connection.execute('BEGIN IMMEDIATE')
            items=connection.execute('SELECT p.*,c.quantity FROM cart c JOIN products p ON p.id=c.product_id WHERE c.user_id=?',(session['uid'],)).fetchall()
            if not items or any(p['quantity']>p['stock'] for p in items):
                connection.rollback()
                return jsonify(error='Cart is empty or an item is out of stock'),409
            total=sum(p['price']*p['quantity'] for p in items)
            oid=connection.execute('INSERT INTO orders(user_id,total,address) VALUES(?,?,?)',(session['uid'],total,address.strip())).lastrowid
            for p in items:
                connection.execute('UPDATE products SET stock=stock-? WHERE id=?',(p['quantity'],p['id']))
                connection.execute('INSERT INTO order_items VALUES(?,?,?,?,?)',(oid,p['id'],p['name'],p['price'],p['quantity']))
            connection.execute('DELETE FROM cart WHERE user_id=?',(session['uid'],))
            connection.commit()
            return jsonify(order_id=oid,total=total,payment='demo — no charge made'),201
        except Exception:
            connection.rollback()
            raise

    @app.get('/api/orders')
    @login_required
    def orders():
        result=[dict(o) for o in db().execute('SELECT * FROM orders WHERE user_id=? ORDER BY id DESC',(session['uid'],))]
        for order in result:
            order['items']=[dict(i) for i in db().execute('SELECT name,price,quantity FROM order_items WHERE order_id=?',(order['id'],))]
        return jsonify(result)

    @app.route('/api/admin',methods=['GET','POST'])
    @login_required
    def admin():
        user=db().execute('SELECT is_admin FROM users WHERE id=?',(session['uid'],)).fetchone()
        if not user or not user['is_admin']:
            return jsonify(error='Admin access required'),403
        if request.method=='POST':
            data=request.get_json(silent=True) or {}
            if data.get('order_id'):
                if data.get('status') not in ['placed','shipped','delivered']:
                    return jsonify(error='Invalid status'),400
                db().execute('UPDATE orders SET status=? WHERE id=?',(data['status'],data['order_id']))
            else:
                if type(data.get('stock'))!=int or data['stock']<0:
                    return jsonify(error='Invalid stock'),400
                db().execute('UPDATE products SET stock=? WHERE id=?',(data['stock'],data.get('product_id')))
            db().commit()
        return jsonify(orders=[dict(o) for o in db().execute('SELECT * FROM orders ORDER BY id DESC')],products=[serialize_product(p) for p in db().execute('SELECT * FROM products WHERE active=1')])
    return app

app=create_app()
if __name__=='__main__':
    app.run(host='127.0.0.1',port=8000)
