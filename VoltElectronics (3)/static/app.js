let csrf = '', user = null, products = [], cartItems = [], wishlist = [], comparison = [], category = 'All products', authMode = 'login', pendingAdd = null;
const $ = selector => document.querySelector(selector);
const money = value => new Intl.NumberFormat('en-IN', {style:'currency', currency:'INR', maximumFractionDigits:0}).format(value / 100);
const escape = value => String(value).replace(/[&<>"']/g, character => ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'}[character]));
const image = product => `/static/images/${encodeURIComponent(product.image)}.svg`;
const shortSpecs = product => [product.specs.Display || product.specs.Type || product.specs.Power || product.specs.Sensor || product.specs.Layout || product.specs.Output, product.specs.Memory || product.specs.Battery || product.specs.Connectivity || product.specs.Ports].filter(Boolean).map(escape).join(' / ');
let toastTimer;
async function api(path, data) {
  const response = await fetch(`/api/${path}`, {method:data ? 'POST' : 'GET', headers:{'Content-Type':'application/json','X-CSRF-Token':csrf}, body:data ? JSON.stringify(data) : undefined});
  const result = await response.json();
  if (!response.ok) throw Error(result.error || 'Something went wrong. Please try again.');
  return result;
}
function toast(message) {
  clearTimeout(toastTimer);
  $('#toast').textContent = message;
  $('#toast').style.display = 'block';
  toastTimer = setTimeout(() => $('#toast').style.display = 'none', 4000);
}
function modal(html) {
  $('#modal-content').innerHTML = html;
  if (!$('#modal').open) $('#modal').showModal();
  $('#modal').scrollTop = 0;
}
async function refresh() {
  const current = await api('session');
  csrf = current.csrf; user = current.user;
  $('#account').textContent = user ? 'Account' : 'Sign in';
  if (user) [cartItems, wishlist] = await Promise.all([api('cart').then(result => result.items), api('wishlist')]);
  else {cartItems = []; wishlist = [];}
  $('#count').textContent = cartItems.reduce((sum, item) => sum + item.quantity, 0);
  $('#wish-count').textContent = wishlist.length;
}
function card(product) {
  const discount = product.compare_price > product.price ? Math.round((1 - product.price / product.compare_price) * 100) : 0;
  return `<article class="product-card"><div class="product-visual">${discount ? `<span class="deal-badge">SAVE ${discount}%</span>` : ''}<button data-detail="${product.id}" aria-label="View ${escape(product.name)}"><img src="${image(product)}" alt="${escape(product.name)} illustration" loading="lazy"></button><button class="save-button ${wishlist.includes(product.id) ? 'saved' : ''}" data-save="${product.id}" aria-label="${wishlist.includes(product.id) ? 'Remove from' : 'Add to'} wishlist: ${escape(product.name)}">${wishlist.includes(product.id) ? '♥' : '♡'}</button></div><div class="product-brand">${escape(product.brand)}</div><h3><button data-detail="${product.id}">${escape(product.name)}</button></h3><div class="product-summary">${shortSpecs(product)}</div><div class="price-row"><strong>${money(product.price)}</strong>${discount ? `<del>${money(product.compare_price)}</del>` : ''}</div><button class="add-button" data-add="${product.id}" ${product.stock ? '' : 'disabled'}>${product.stock ? 'Add to cart +' : 'Out of stock'}</button><div class="product-meta"><span>${product.stock ? `${product.stock} in stock` : 'Currently unavailable'}</span><label><input type="checkbox" data-compare="${product.id}" ${comparison.includes(product.id) ? 'checked' : ''}> Compare</label></div></article>`;
}
function render() {
  const term = $('#search').value.trim().toLowerCase(), brand = $('#brand-filter').value, maximum = $('#max-price').value;
  let selected = products.filter(product => (category === 'All products' || product.category === category) && (brand === 'all' || product.brand === brand) && (!maximum || product.price <= Number(maximum) * 100) && (!$('#in-stock').checked || product.stock > 0) && `${product.name} ${product.brand} ${product.category} ${product.description} ${Object.values(product.specs).join(' ')}`.toLowerCase().includes(term));
  const sort = $('#sort').value;
  if (sort === 'price-low') selected.sort((a,b) => a.price - b.price);
  if (sort === 'price-high') selected.sort((a,b) => b.price - a.price);
  if (sort === 'name') selected.sort((a,b) => a.name.localeCompare(b.name));
  $('#result-count').textContent = `${selected.length} product${selected.length === 1 ? '' : 's'}${category !== 'All products' ? ` in ${category}` : ''}`;
  $('#products').innerHTML = selected.map(card).join('') || '<div class="empty-state"><h3>No matches this time.</h3><p>Try a different search or reset your filters.</p><button data-action="reset" class="secondary">Reset filters</button></div>';
  document.querySelectorAll('#filters button').forEach(button => {const selected = button.dataset.category === category; button.classList.toggle('active', selected); button.setAttribute('aria-pressed', String(selected));});
  $('#compare-count').textContent = comparison.length;
}
function selectCategory(value) {category = value; render(); $('#collection').scrollIntoView({behavior:'smooth'});}
function resetFilters() {category = 'All products'; $('#search').value = ''; $('#brand-filter').value = 'all'; $('#max-price').value = ''; $('#in-stock').checked = false; $('#sort').value = 'featured'; render();}
function detail(id) {
  const product = products.find(item => item.id === id);
  if (!product) {toast('This product is unavailable.'); return;}
  modal(`<div class="detail-grid"><div class="detail-image"><img src="${image(product)}" alt="${escape(product.name)} illustration"></div><div class="detail-copy"><p class="eyebrow">${escape(product.brand)} / ${escape(product.category)}</p><h2>${escape(product.name)}</h2><p>${escape(product.description)}</p><div class="price-row"><strong>${money(product.price)}</strong><del>${money(product.compare_price)}</del></div><p>${product.stock ? `${product.stock} available` : 'Currently out of stock'}</p><button class="primary full-width" data-add="${product.id}" ${product.stock ? '' : 'disabled'}>Add to cart +</button><button class="secondary full-width" data-save="${product.id}">${wishlist.includes(id) ? 'Remove from wishlist' : '♡ Save to wishlist'}</button><a class="text-button" href="/products/${product.id}">Product permalink ↗</a></div></div><h3>Specifications</h3><table class="spec-table"><tbody>${Object.entries(product.specs).map(([key,value]) => `<tr><th scope="row">${escape(key)}</th><td>${escape(value)}</td></tr>`).join('')}</tbody></table><p>Sample product · Specifications and prices are fictional demo data.</p>`);
}
function auth() {
  if (user) {modal(`<h2>Your account</h2><p>Signed in as ${escape(user.email)}</p><p>Your cart, wishlist, and orders are saved to your account.</p><button class="primary" data-action="orders">View orders</button> <button class="secondary" data-action="wishlist">My wishlist</button>${user.is_admin ? '<p><button class="primary" data-action="admin">Manage inventory & orders</button></p>' : ''}<p><button class="text-button" data-action="logout">Sign out</button></p>`); return;}
  modal(`<div class="auth-box"><p class="eyebrow">WELCOME TO VOLT</p><h2>${authMode === 'register' ? 'Your next chapter starts here.' : 'Good to see you again.'}</h2><p>Save your favorites, keep your cart, and follow your orders.</p><div class="auth-tabs"><button data-auth="login" class="${authMode === 'login' ? 'active' : ''}">Sign in</button><button data-auth="register" class="${authMode === 'register' ? 'active' : ''}">Create account</button></div><form id="auth-form"><label>Email address<input name="email" type="email" required maxlength="254" autocomplete="email"></label><label>Password<input name="password" type="password" minlength="10" maxlength="200" required autocomplete="${authMode === 'register' ? 'new-password' : 'current-password'}"></label><p>Use at least 10 characters.</p><button class="primary full-width">${authMode === 'register' ? 'Create account' : 'Sign in'}</button><p class="error" id="error" role="alert"></p></form></div>`);
}
async function addToCart(id) {
  if (!user) {pendingAdd = id; auth(); return;}
  const existing = cartItems.find(product => product.id === id);
  await api('cart', {product_id:id, quantity:(existing?.quantity || 0) + 1});
  await refresh(); toast('Added to your cart.');
}
function showCart() {
  if (!user) {auth(); return;}
  const total = cartItems.reduce((sum,item) => sum + item.price * item.quantity, 0);
  modal(`<h2>Your cart <span class="muted">(${cartItems.reduce((sum,item) => sum + item.quantity,0)} items)</span></h2>${cartItems.map(product => `<div class="cart-item"><img src="${image(product)}" alt=""><div><h3>${escape(product.name)}</h3><p>${money(product.price)} each</p><div class="quantity-control"><button data-quantity-action="${product.id}" data-delta="-1" aria-label="Decrease ${escape(product.name)} quantity">−</button><input type="number" min="0" max="${Math.min(product.stock,99)}" value="${product.quantity}" data-quantity="${product.id}" aria-label="Quantity for ${escape(product.name)}"><button data-quantity-action="${product.id}" data-delta="1" aria-label="Increase ${escape(product.name)} quantity">+</button></div></div><div><strong>${money(product.price * product.quantity)}</strong><p><button class="remove-button" data-remove="${product.id}">Remove</button></p></div></div>`).join('') || '<div class="empty-state"><h3>Your next upgrade is waiting.</h3><p>Explore the collection to get started.</p><button class="primary" data-action="shop">Browse products ↗</button></div>'}${cartItems.length ? `<div class="cart-total"><span>Total</span><strong>${money(total)}</strong></div><p>Demo order total · No payment, tax, or shipping charge is collected.</p><button class="primary full-width" data-action="checkout">Continue to checkout →</button>` : ''}`);
}
function checkout() {
  if (!cartItems.length) {showCart(); return;}
  const total = cartItems.reduce((sum,item) => sum + item.price * item.quantity,0);
  modal(`<h2>Complete your order.</h2><p>Delivery details</p><form id="checkout-form"><div class="checkout-grid"><label>Full name<input name="name" required maxlength="100" autocomplete="name"></label><label>Phone number<input name="phone" type="tel" required pattern="[0-9+() -]{7,20}" maxlength="20" autocomplete="tel"></label></div><label>Street address<textarea name="street" required minlength="10" maxlength="500" autocomplete="street-address"></textarea></label><div class="checkout-grid"><label>City<input name="city" required maxlength="80" autocomplete="address-level2"></label><label>State<input name="state" required maxlength="80" autocomplete="address-level1"></label><label>Postal code<input name="postal" required pattern="[0-9]{6}" inputmode="numeric" maxlength="6" autocomplete="postal-code"></label><label>Country<input value="India" readonly autocomplete="country-name"></label></div><div class="cart-total"><span>Order total</span><strong>${money(total)}</strong></div><p>Payment method: demo checkout. No card information is requested and no money is charged.</p><button class="primary full-width">Place demo order →</button><p class="error" id="error" role="alert"></p></form>`);
}
async function showOrders() {
  if (!user) {auth(); return;}
  const orders = await api('orders');
  modal(`<h2>Your orders</h2><p>Follow your orders from placed to delivered.</p>${orders.map(order => `<article class="order-card"><div class="order-heading"><strong>Order #${order.id}</strong><span class="status-badge">${escape(order.status)}</span></div><p>${escape(order.created_at)} UTC</p><ul>${order.items.map(item => `<li>${escape(item.name)} × ${item.quantity} — ${money(item.price * item.quantity)}</li>`).join('')}</ul><strong>Total ${money(order.total)}</strong><p>${escape(order.address).replace(/\n/g,'<br>')}</p></article>`).join('') || '<div class="empty-state"><h3>No orders yet.</h3><p>Your next upgrade could be your first.</p><button class="primary" data-action="shop">Shop the collection</button></div>'}`);
}
function showWishlist() {
  if (!user) {auth(); return;}
  modal(`<h2>Your saved upgrades</h2><p>All the things you have your eye on.</p><div class="product-grid">${products.filter(product => wishlist.includes(product.id)).map(card).join('') || '<div class="empty-state"><h3>A little inspiration goes a long way.</h3><p>Tap the heart on a product to save it here.</p></div>'}</div>`);
}
function showCompare() {
  const selected = products.filter(product => comparison.includes(product.id));
  if (selected.length < 2) {toast('Select two or three products to compare.'); return;}
  const keys = [...new Set(selected.flatMap(product => Object.keys(product.specs)))];
  modal(`<h2>Find your perfect fit.</h2><div class="table-scroll"><table class="compare-table"><thead><tr><th>Feature</th>${selected.map(product => `<th><img src="${image(product)}" alt=""><p>${escape(product.name)}</p><strong>${money(product.price)}</strong></th>`).join('')}</tr></thead><tbody>${keys.map(key => `<tr><th scope="row">${escape(key)}</th>${selected.map(product => `<td>${escape(product.specs[key] || '—')}</td>`).join('')}</tr>`).join('')}<tr><th>Availability</th>${selected.map(product => `<td>${product.stock ? 'In stock' : 'Out of stock'}</td>`).join('')}</tr><tr><th></th>${selected.map(product => `<td><button class="primary" data-add="${product.id}" ${product.stock ? '' : 'disabled'}>Add to cart</button></td>`).join('')}</tr></tbody></table></div>`);
}
async function admin() {
  const data = await api('admin');
  modal(`<h2>Store dashboard</h2><p>${data.products.length} products · ${data.orders.length} orders</p><h3>Inventory</h3><div class="admin-grid">${data.products.map(product => `<span>${escape(product.name)}<br><small>${money(product.price)}</small></span><label>Stock<input type="number" min="0" value="${product.stock}" data-stock="${product.id}"></label>`).join('')}</div><h3>Fulfillment</h3>${data.orders.map(order => `<article class="order-card"><strong>Order #${order.id} · ${money(order.total)}</strong><p>${escape(order.address).replace(/\n/g,'<br>')}</p><label>Status<select data-order="${order.id}">${['placed','shipped','delivered'].map(status => `<option ${order.status === status ? 'selected' : ''}>${status}</option>`).join('')}</select></label></article>`).join('') || '<p>No orders to fulfill yet.</p>'}`);
}
function support() {
  modal('<p class="eyebrow">THE VOLT HELP CENTER</p><h2>A little clarity before you click.</h2><details open><summary>Is this a real electronics store?</summary><p>This is a working demo ecommerce application. Product brands, specifications, discounts and prices are fictional sample data. Orders are stored in the database, but no physical goods are shipped.</p></details><details><summary>How does checkout work?</summary><p>Create an account, add products to your cart, and enter delivery details. Demo checkout records an order and deducts stock. It never collects a real payment.</p></details><details><summary>Where are my orders?</summary><p>Sign in, open your account, and select View orders. The store administrator can update an order to shipped or delivered for testing.</p></details><details><summary>Can I save or compare products?</summary><p>Use the heart to save products to your account wishlist. Check Compare on up to three products, then open Compare above the catalog.</p></details><details><summary>What about shipping, returns and warranties?</summary><p>These services are not enabled in the demo. No real delivery, return window, or manufacturer warranty is offered.</p></details>');
}
function policy(type) {modal(type === 'privacy' ? '<h2>Privacy in this demo</h2><p>Your email, password hash, cart, wishlist, order history and supplied delivery details are saved in this application’s SQLite database. Passwords are hashed. A session cookie keeps you signed in.</p><p>No payment card data is requested. Use sample delivery details while testing. Account deletion and production privacy controls are not implemented.</p>' : '<h2>About VOLT</h2><p>A complete electronics shopping demo with a SQLite backend, account-based carts and wishlists, stock-aware checkout, order history, admin fulfillment, and Azure deployment files.</p><p>The products and specifications are fictional. Payments, shipping, and returns are not connected to real services.</p>');}
$('#close').onclick = () => $('#modal').close();
$('#account').onclick = auth; $('#cart').onclick = showCart; $('#wishlist').onclick = showWishlist;
$('#orders').onclick = () => showOrders().catch(error => toast(error.message));
$('#support').onclick = support; $('#compare-open').onclick = showCompare;
$('#clear-filters').onclick = resetFilters;
['#search','#max-price'].forEach(selector => $(selector).addEventListener('input', render));
['#sort','#brand-filter','#in-stock'].forEach(selector => $(selector).addEventListener('change', render));
document.addEventListener('click', async event => {
  const button = event.target.closest('button'); if (!button) return;
  try {
    if (button.dataset.category) selectCategory(button.dataset.category);
    if (button.dataset.detail) detail(Number(button.dataset.detail));
    if (button.dataset.add) await addToCart(Number(button.dataset.add));
    if (button.dataset.save) {
      if (!user) {auth(); return;}
      wishlist = await api('wishlist', {product_id:Number(button.dataset.save)});
      $('#wish-count').textContent = wishlist.length; render();
      const saved = wishlist.includes(Number(button.dataset.save));
      button.classList.toggle('saved', saved);
      button.textContent = button.classList.contains('save-button') ? (saved ? '♥' : '♡') : (saved ? 'Remove from wishlist' : '♡ Save to wishlist');
      if ($('#modal-content .product-grid')) showWishlist();
      toast('Wishlist updated.');
    }
    if (button.dataset.auth) {authMode = button.dataset.auth; auth();}
    if (button.dataset.policy) policy(button.dataset.policy);
    if (button.dataset.remove || button.dataset.quantityAction) {
      const id = Number(button.dataset.remove || button.dataset.quantityAction), item = cartItems.find(item => item.id === id);
      await api('cart', {product_id:id, quantity:button.dataset.remove ? 0 : item.quantity + Number(button.dataset.delta)});
      await refresh(); showCart();
    }
    const action = button.dataset.action;
    if (action === 'orders') await showOrders();
    if (action === 'wishlist') showWishlist();
    if (action === 'account') auth();
    if (action === 'support') support();
    if (action === 'checkout') checkout();
    if (action === 'admin') await admin();
    if (action === 'reset') resetFilters();
    if (action === 'shop') {$('#modal').close(); $('#collection').scrollIntoView({behavior:'smooth'});}
    if (action === 'logout') {await api('auth/logout', {}); await refresh(); pendingAdd = null; render(); $('#modal').close();}
  } catch (error) {toast(error.message);}
});
document.addEventListener('change', async event => {
  const target = event.target;
  try {
    if (target.dataset.compare) {
      const id = Number(target.dataset.compare);
      if (target.checked && comparison.length >= 3) {target.checked = false; toast('Compare up to three products at a time.'); return;}
      comparison = target.checked ? [...comparison,id] : comparison.filter(item => item !== id);
      $('#compare-count').textContent = comparison.length;
    }
    if (target.dataset.quantity) {await api('cart', {product_id:Number(target.dataset.quantity), quantity:Number(target.value)}); await refresh(); showCart();}
    if (target.dataset.stock) {await api('admin', {product_id:Number(target.dataset.stock), stock:Number(target.value)}); products = await api('products'); render(); toast('Inventory saved.');}
    if (target.dataset.order) {await api('admin', {order_id:Number(target.dataset.order), status:target.value}); toast('Order status updated.');}
  } catch (error) {toast(error.message);}
});
document.addEventListener('submit', async event => {
  if (!['auth-form','checkout-form'].includes(event.target.id)) return;
  event.preventDefault(); const button = event.submitter || event.target.querySelector('button'); button.disabled = true;
  try {
    const data = Object.fromEntries(new FormData(event.target));
    if (event.target.id === 'auth-form') {
      await api(`auth/${authMode}`, data); await refresh(); render(); $('#modal').close();
      if (pendingAdd) {const id = pendingAdd; pendingAdd = null; await addToCart(id);}
      else toast(authMode === 'register' ? 'Your account is ready.' : 'Welcome back.');
    }
    if (event.target.id === 'checkout-form') {
      const address = `${data.name}\n${data.phone}\n${data.street}\n${data.city}, ${data.state} ${data.postal}\nIndia`;
      const order = await api('checkout', {address}); await refresh(); products = await api('products'); render();
      modal(`<div class="confirmation"><span>✓</span><p class="eyebrow">ORDER CONFIRMED</p><h2>Your next upgrade is on the list.</h2><p>Order #${order.order_id} has been saved.</p><h3>${money(order.total)}</h3><p>This is a demo order. No payment was collected and no shipment will be made.</p><button class="primary" data-action="orders">View your order →</button></div>`);
    }
  } catch (error) {if ($('#error')) $('#error').textContent = error.message; else toast(error.message);}
  finally {button.disabled = false;}
});
(async () => {
  try {
    await refresh(); products = await api('products');
    $('#filters').innerHTML = ['All products', ...new Set(products.map(product => product.category))].map(value => `<button data-category="${escape(value)}" aria-pressed="${value === category}">${escape(value)}</button>`).join('');
    $('#brand-filter').innerHTML += [...new Set(products.map(product => product.brand))].sort().map(value => `<option value="${escape(value)}">${escape(value)}</option>`).join('');
    render(); const match = location.pathname.match(/^\/products\/(\d+)$/); if (match) detail(Number(match[1]));
  } catch (error) {$('#products').innerHTML = '<div class="empty-state">The store could not load. Please refresh and try again.</div>'; toast(error.message);}
})();

