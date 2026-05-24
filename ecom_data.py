# dataset generation script for ecommerce analytics project
# generates CSVs for users, sessions, events, orders, order_items, ad_spend
# Q1 2024 (Jan-Mar), ~284k users

import random
import hashlib
import csv
import os
from datetime import datetime, timedelta
from collections import defaultdict

random.seed(2024)

START = datetime(2024, 1, 1)
END   = datetime(2024, 3, 31, 23, 59, 59)
DAYS  = 90

# targets i'm aiming for
TARGET_USERS     = 284000
TARGET_VISITORS  = 512400
TARGET_PURCHASES = 16590

# funnel drop probabilities at each stage (session level)
# overall = 0.622 * 0.298 * 0.300 * 0.583 = ~3.24%
P_V2VIEW   = 0.622
P_VIEW2ATC = 0.298
P_ATC2CHK  = 0.300
P_CHK2BUY  = 0.583

# channel: name, share of visitors, target cvr, average order value
CHANNELS = [
    ('organic_search', 0.36, 0.0315,  86),
    ('paid_search',    0.24, 0.0360,  91),
    ('social_paid',    0.17, 0.0250,  74),
    ('email',          0.14, 0.0524, 102),
    ('direct',         0.09, 0.0290,  88),
]

# work out per-channel checkout->purchase probability to hit the cvr targets
# had to back-calculate this from the upstream funnel rates
UPSTREAM = P_V2VIEW * P_VIEW2ATC * P_ATC2CHK
CH_CHK2BUY = {ch: min(cvr / UPSTREAM, 0.97) for ch, _, cvr, _ in CHANNELS}
CH_AOV     = {ch: aov for ch, _, _, aov in CHANNELS}

# desktop converts better than mobile - scalars relative to overall 3.24%
DEVICES = [('desktop', 0.48), ('mobile', 0.42), ('tablet', 0.10)]
DEV_SCALAR = {'desktop': 4.88/3.24, 'mobile': 2.41/3.24, 'tablet': 3.50/3.24}

# categories with browse weight and price range
CATEGORIES = [
    ('electronics',  0.22,  45, 195),
    ('clothing',     0.20,  18,  95),
    ('home_garden',  0.14,  22, 140),
    ('beauty',       0.13,  12,  72),
    ('sports',       0.12,  20, 120),
    ('books',        0.08,   8,  42),
    ('toys',         0.06,  10,  68),
    ('automotive',   0.05,  28, 165),
]
CAT_W = [(c[0], c[1]) for c in CATEGORIES]

COUNTRIES = [
    ('US',0.45),('IN',0.18),('UK',0.10),('CA',0.07),('AU',0.05),
    ('DE',0.05),('FR',0.04),('BR',0.03),('SG',0.02),('MX',0.01)
]

LANDING_PAGES = [
    '/', '/deals', '/category/electronics', '/category/clothing',
    '/search', '/blog/', '/new-arrivals', '/'
]

# rough hourly traffic pattern - peaks mid-morning and evening
HOUR_W = [
    .010,.005,.004,.004,.008,.015,.035,.055,
    .068,.072,.072,.070,.068,.065,.060,.058,
    .058,.062,.065,.062,.055,.042,.030,.018
]


def wc(opts):
    """weighted random choice"""
    r = random.random()
    c = 0
    for v, w in opts:
        c += w
        if r < c:
            return v
    return opts[-1][0]


def make_id(prefix, n=7):
    return prefix + hashlib.md5(str(random.random()).encode()).hexdigest()[:n].upper()


def fmt(dt):
    return dt.strftime('%Y-%m-%d %H:%M:%S')


def rand_dt(after=None):
    lo = int((after - START).total_seconds()) if after else 0
    hi = int((END - START).total_seconds())
    if lo >= hi:
        lo = max(0, hi - 60)
    sec  = random.randint(lo, hi)
    base = START + timedelta(seconds=sec)
    return base.replace(
        hour=random.choices(range(24), weights=HOUR_W)[0],
        minute=random.randint(0, 59),
        second=random.randint(0, 59)
    )


def clamp(dt):
    return min(dt, END)


# build product catalog first - roughly 500 products spread across categories
products = []
cat_products = defaultdict(list)

for cat, sh, plo, phi in CATEGORIES:
    n = max(50, int(500 * sh * 8))
    for _ in range(n):
        pid   = make_id('P', 6)
        price = round(random.uniform(plo, phi), 2)
        products.append((pid, cat, price))
        cat_products[cat].append((pid, cat, price))

print(f"built product catalog: {len(products)} products")

# output folder
out = 'csv_output/'
os.makedirs(out, exist_ok=True)

f_users  = open(out + 'users.csv',       'w', newline='')
f_sess   = open(out + 'sessions.csv',    'w', newline='')
f_events = open(out + 'events.csv',      'w', newline='')
f_orders = open(out + 'orders.csv',      'w', newline='')
f_items  = open(out + 'order_items.csv', 'w', newline='')

w_users  = csv.writer(f_users)
w_sess   = csv.writer(f_sess)
w_events = csv.writer(f_events)
w_orders = csv.writer(f_orders)
w_items  = csv.writer(f_items)

w_users.writerow(['user_id','created_at','channel','country','device_type','is_registered'])
w_sess.writerow(['session_id','user_id','session_start','session_end','channel','landing_page','device_type'])
w_events.writerow(['event_id','user_id','session_id','event_type','event_ts','page_url','product_id','category','device_type','channel'])
w_orders.writerow(['order_id','user_id','session_id','order_ts','total_amount','channel','device_type','coupon_used'])
w_items.writerow(['order_id','product_id','category','quantity','unit_price'])

# counters for the calibration check at the end
total_users    = 0
total_sessions = 0
total_events   = 0
total_visits   = 0
total_views    = 0
total_atc      = 0
total_checkout = 0
total_purchase = 0

ch_stats  = defaultdict(lambda: {'vis': 0, 'pur': 0, 'rev': 0.0})
dev_stats = defaultdict(lambda: {'vis': 0, 'pur': 0})
cat_rev   = defaultdict(float)

# figure out how many sessions to give each user
# avg is ~1.8 sessions per user - using a rough power law distribution
print(f"planning sessions for {TARGET_USERS:,} users...")

sessions_per_user = []
for _ in range(TARGET_USERS):
    r = random.random()
    if r < 0.45:
        sessions_per_user.append(1)
    elif r < 0.75:
        sessions_per_user.append(2)
    elif r < 0.90:
        sessions_per_user.append(3)
    elif r < 0.97:
        sessions_per_user.append(random.randint(4, 6))
    else:
        sessions_per_user.append(random.randint(7, 15))

total_planned = sum(sessions_per_user)

# adjust to hit the exact visitor target
diff = TARGET_VISITORS - total_planned
print(f"planned {total_planned:,}, target {TARGET_VISITORS:,}, diff {diff:,} - adjusting...")

idx = 0
while diff > 0:
    sessions_per_user[idx % TARGET_USERS] += 1
    diff -= 1
    idx  += 1
while diff < 0:
    i = idx % TARGET_USERS
    if sessions_per_user[i] > 1:
        sessions_per_user[i] -= 1
        diff += 1
    idx += 1

print(f"adjusted to {sum(sessions_per_user):,} total sessions")
print("generating data - this takes a minute...")

for u_idx in range(TARGET_USERS):
    uid     = make_id('U', 7)
    channel = wc([(ch, sh) for ch, sh, _, _ in CHANNELS])
    country = wc(COUNTRIES)
    device  = wc(DEVICES)
    is_reg  = 1 if random.random() < 0.74 else 0

    # signup date - skewed toward start of quarter
    days_off = int(random.betavariate(1.1, 2.5) * 89)
    created  = START + timedelta(days=days_off)
    created  = created.replace(
        hour=random.choices(range(24), weights=HOUR_W)[0],
        minute=random.randint(0, 59),
        second=random.randint(0, 59)
    )

    w_users.writerow([uid, fmt(created), channel, country, device, is_reg])
    total_users += 1

    n_sess = sessions_per_user[u_idx]
    avail  = max(1, (END - created).days + 1)
    sdays  = sorted(random.sample(range(avail), min(n_sess, avail)))

    # top up if we couldn't get enough unique days
    if len(sdays) < n_sess:
        while len(sdays) < n_sess:
            sdays.append(random.randint(0, avail - 1))
        sdays.sort()

    for sd in sdays:
        sess_id = make_id('S', 7)
        st  = created + timedelta(days=sd)
        st  = clamp(st.replace(
            hour=random.choices(range(24), weights=HOUR_W)[0],
            minute=random.randint(0, 59),
            second=random.randint(0, 59)
        ))
        dur = max(1, int(random.lognormvariate(2.2, 0.9)))
        en  = clamp(st + timedelta(minutes=dur))
        land = random.choice(LANDING_PAGES)

        w_sess.writerow([sess_id, uid, fmt(st), fmt(en), channel, land, device])
        total_sessions += 1

        # every session starts with a visit event
        ets = st
        eid = make_id('E', 7)
        w_events.writerow([eid, uid, sess_id, 'visit', fmt(ets), '/', '', '', device, channel])
        total_visits += 1
        total_events += 1
        ch_stats[channel]['vis']  += 1
        dev_stats[device]['vis']  += 1

        if random.random() > P_V2VIEW:
            continue

        # product view
        cat2          = wc(CAT_W)
        prod          = random.choice(cat_products.get(cat2, products[:5]))
        pid2, pcat2, pprice = prod
        ets  = clamp(ets + timedelta(seconds=random.randint(8, 160)))
        eid  = make_id('E', 7)
        w_events.writerow([eid, uid, sess_id, 'product_view', fmt(ets),
                           f'/product/{pid2}', pid2, pcat2, device, channel])
        total_views  += 1
        total_events += 1

        if random.random() > P_VIEW2ATC:
            continue

        # add to cart
        ets  = clamp(ets + timedelta(seconds=random.randint(15, 350)))
        eid  = make_id('E', 7)
        w_events.writerow([eid, uid, sess_id, 'add_to_cart', fmt(ets),
                           f'/product/{pid2}', pid2, pcat2, device, channel])
        total_atc    += 1
        total_events += 1

        if random.random() > P_ATC2CHK:
            continue

        # checkout
        ets  = clamp(ets + timedelta(seconds=random.randint(30, 600)))
        eid  = make_id('E', 7)
        w_events.writerow([eid, uid, sess_id, 'checkout_start', fmt(ets),
                           '/checkout', pid2, pcat2, device, channel])
        total_checkout += 1
        total_events   += 1

        # purchase probability varies by channel and device
        p_buy = min(CH_CHK2BUY[channel] * DEV_SCALAR[device], 0.97)
        if random.random() > p_buy:
            continue

        # purchase
        ets  = clamp(ets + timedelta(seconds=random.randint(60, 840)))
        eid  = make_id('E', 7)
        w_events.writerow([eid, uid, sess_id, 'purchase', fmt(ets),
                           '/order-confirm', pid2, pcat2, device, channel])
        total_purchase += 1
        total_events   += 1
        ch_stats[channel]['pur'] += 1
        dev_stats[device]['pur'] += 1

        # create the order and line items
        oid     = make_id('O', 7)
        tgt_aov = CH_AOV.get(channel, 86.0)
        n_items = random.choices([1, 2, 3, 4], weights=[55, 25, 13, 7])[0]
        coupon  = 1 if random.random() < 0.18 else 0

        order_total = 0.0
        item_rows   = []

        for k in range(n_items):
            if k == 0:
                ip, ic, bp = prod
            else:
                tmp = random.choice(cat_products.get(pcat2, products[:5]))
                ip, ic, bp = tmp

            # nudge price toward channel aov
            scale = (tgt_aov / max(pprice, 1)) if k == 0 else 1.0
            scale = min(max(scale, 0.4), 3.0)
            fp    = round(bp * scale, 2)
            if coupon:
                fp = round(fp * 0.88, 2)
            fp  = max(fp, 0.99)
            qty = random.choices([1, 2, 3], weights=[78, 16, 6])[0]

            order_total += fp * qty
            item_rows.append((oid, ip, ic, qty, fp))
            cat_rev[ic] += fp * qty

        order_total = round(order_total, 2)
        w_orders.writerow([oid, uid, sess_id, fmt(ets), order_total, channel, device, coupon])
        for row in item_rows:
            w_items.writerow(row)
        ch_stats[channel]['rev'] += order_total

    if (u_idx + 1) % 50000 == 0:
        print(f"  {u_idx+1:,} / {TARGET_USERS:,} users done")

for f in [f_users, f_sess, f_events, f_orders, f_items]:
    f.close()

# ad spend - daily spend per channel across 90 days
# display is in here even though it generates zero orders (intentional - flags it as 0 ROAS)
SPEND_90 = {'paid_search': 82400, 'social_paid': 64100, 'email': 8200, 'display': 24000}

with open(out + 'ad_spend.csv', 'w', newline='') as fa:
    w = csv.writer(fa)
    w.writerow(['spend_date', 'channel', 'spend_usd'])
    cur = START
    while cur.date() <= END.date():
        dow_f = 0.82 if cur.weekday() >= 5 else 1.0  # weekends spend a bit less
        for ch2, t90 in SPEND_90.items():
            sp = round(t90 / 91 * dow_f * random.uniform(0.88, 1.12), 2)
            w.writerow([cur.strftime('%Y-%m-%d'), ch2, sp])
        cur += timedelta(days=1)

# quick sanity check on the numbers
print("\n--- QUICK SANITY CHECK ---")
tv = float(total_visits)

print(f"\nfunnel:")
print(f"  visits:     {total_visits:>9,}   (target 512,400)")
print(f"  views:      {total_views:>9,}   {total_views/tv*100:.1f}% of visits  (target 62.2%)")
print(f"  add to cart:{total_atc:>9,}   {total_atc/total_views*100:.1f}% of views   (target 29.8%)")
print(f"  checkout:   {total_checkout:>9,}   {total_checkout/total_atc*100:.1f}% of ATC     (target 30.0%)")
print(f"  purchase:   {total_purchase:>9,}   {total_purchase/total_checkout*100:.1f}% of checkout (target 58.3%)")
print(f"\n  overall cvr:      {total_purchase/tv*100:.2f}%  (target 3.24%)")
print(f"  cart abandonment: {(total_atc-total_purchase)/total_atc*100:.1f}%")

print(f"\nchannel performance:")
tgts = {'organic_search':3.15,'paid_search':3.60,'email':5.24,'direct':2.90,'social_paid':2.50}
for ch, sh, _, _ in CHANNELS:
    s   = ch_stats[ch]
    cvr = s['pur']/s['vis']*100 if s['vis'] else 0
    aov = s['rev']/s['pur'] if s['pur'] else 0
    ok  = '✓' if abs(cvr - tgts[ch]) < 0.5 else '~'
    print(f"  {ch:<20}  cvr:{cvr:.2f}% (target {tgts[ch]:.2f}%) {ok}   aov:${aov:.0f}")

print(f"\ndevice cvr:")
dtgts = {'desktop':4.88,'mobile':2.41,'tablet':3.50}
for dv, _ in DEVICES:
    s   = dev_stats[dv]
    cvr = s['pur']/s['vis']*100 if s['vis'] else 0
    ok  = '✓' if abs(cvr - dtgts[dv]) < 0.6 else '~'
    print(f"  {dv:<10}  {cvr:.2f}%  (target {dtgts[dv]:.2f}%) {ok}")

tr = sum(s['rev'] for s in ch_stats.values())
print(f"\nrevenue by channel:")
for ch, _, _, _ in CHANNELS:
    s    = ch_stats[ch]
    sp   = SPEND_90.get(ch, 0)
    roas = s['rev']/sp if sp else float('inf')
    print(f"  {ch:<20}  ${s['rev']:>9,.0f}   roas: {roas:.1f}x")
print(f"  total: ${tr:,.0f}")

print(f"\nrow counts:")
print(f"  users:        {total_users:>9,}")
print(f"  sessions:     {total_sessions:>9,}")
print(f"  events:       {total_events:>9,}")
print(f"  orders:       {total_purchase:>9,}")

print(f"\nfiles saved to {out}")
print("done.")
