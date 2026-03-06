-- ============================================================
-- E-Commerce Analytics — All Analysis Queries
-- 20 queries covering funnel, retention, channels, categories
-- Run each section separately and export results as CSV
-- ============================================================

USE ecom_analytics;

-- Fix hidden carriage return characters if data was loaded from Windows CSVs
-- Run these once before any other queries
SET SQL_SAFE_UPDATES = 0;
UPDATE orders     SET channel     = TRIM(REPLACE(channel,     '\r', '')) WHERE channel     LIKE '%\r%';
UPDATE events     SET channel     = TRIM(REPLACE(channel,     '\r', '')) WHERE channel     LIKE '%\r%';
UPDATE events     SET event_type  = TRIM(REPLACE(event_type,  '\r', '')) WHERE event_type  LIKE '%\r%';
UPDATE events     SET device_type = TRIM(REPLACE(device_type, '\r', '')) WHERE device_type LIKE '%\r%';
UPDATE sessions   SET channel     = TRIM(REPLACE(channel,     '\r', '')) WHERE channel     LIKE '%\r%';
UPDATE users      SET channel     = TRIM(REPLACE(channel,     '\r', '')) WHERE channel     LIKE '%\r%';
UPDATE order_items SET category   = TRIM(REPLACE(category,    '\r', '')) WHERE category    LIKE '%\r%';
SET SQL_SAFE_UPDATES = 1;


-- ============================================================
-- SECTION 1 — DATA OVERVIEW
-- ============================================================

-- 1A: Row counts for all tables — quick sanity check
SELECT 'users'       AS table_name, COUNT(*) AS row_count FROM users
UNION ALL SELECT 'sessions',        COUNT(*)              FROM sessions
UNION ALL SELECT 'events',          COUNT(*)              FROM events
UNION ALL SELECT 'orders',          COUNT(*)              FROM orders
UNION ALL SELECT 'order_items',     COUNT(*)              FROM order_items
UNION ALL SELECT 'ad_spend',        COUNT(*)              FROM ad_spend;

-- 1B: Event type distribution — how many of each action type
SELECT
    event_type,
    COUNT(*) AS event_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_of_total
FROM events
GROUP BY event_type
ORDER BY event_count DESC;

-- 1C: Date range of the dataset
SELECT
    MIN(DATE(event_ts)) AS first_event,
    MAX(DATE(event_ts)) AS last_event,
    DATEDIFF(MAX(DATE(event_ts)), MIN(DATE(event_ts))) AS days_covered
FROM events;


-- ============================================================
-- SECTION 2 — FUNNEL ANALYSIS
-- Export result as: result_funnel.csv
-- ============================================================

-- 2A: Full purchase funnel — users at each stage with drop-off rates
WITH funnel_counts AS (
    SELECT
        event_type                  AS stage,
        COUNT(DISTINCT user_id)     AS users,
        -- Stage order number for sorting
        CASE event_type
            WHEN 'visit'          THEN 1
            WHEN 'product_view'   THEN 2
            WHEN 'add_to_cart'    THEN 3
            WHEN 'checkout_start' THEN 4
            WHEN 'purchase'       THEN 5
        END                         AS stage_order
    FROM events
    WHERE event_type IN ('visit','product_view','add_to_cart','checkout_start','purchase')
    GROUP BY event_type
)
SELECT
    stage,
    users,
    -- Drop-off from previous stage
    ROUND(users * 100.0 /
        LAG(users) OVER (ORDER BY stage_order), 1)   AS stage_cvr_pct,
    -- Overall conversion from visit
    ROUND(users * 100.0 /
        MAX(CASE WHEN stage_order = 1 THEN users END)
        OVER (), 2)                                   AS overall_cvr_pct
FROM funnel_counts
ORDER BY stage_order;


-- 2B: Cart abandonment rate — users who added to cart but did not purchase
-- Export result as: result_cart_abandonment.csv
SELECT
    COUNT(DISTINCT CASE WHEN event_type = 'add_to_cart' THEN user_id END)  AS atc_users,
    COUNT(DISTINCT CASE WHEN event_type = 'purchase'    THEN user_id END)  AS purchasers,
    COUNT(DISTINCT CASE WHEN event_type = 'add_to_cart' THEN user_id END)
    - COUNT(DISTINCT CASE WHEN event_type = 'purchase'  THEN user_id END)  AS abandoned,
    ROUND(
        (COUNT(DISTINCT CASE WHEN event_type = 'add_to_cart' THEN user_id END)
        - COUNT(DISTINCT CASE WHEN event_type = 'purchase'   THEN user_id END))
        * 100.0
        / COUNT(DISTINCT CASE WHEN event_type = 'add_to_cart' THEN user_id END)
    , 1)                                                                    AS abandonment_rate_pct
FROM events;


-- 2C: Funnel CVR by device type — shows mobile vs desktop gap
-- Export result as: result_funnel_device.csv
SELECT
    device_type,
    COUNT(DISTINCT CASE WHEN event_type = 'visit'    THEN user_id END)  AS visitors,
    COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN user_id END)  AS purchasers,
    ROUND(
        COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN user_id END) * 100.0
        / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'visit' THEN user_id END), 0)
    , 2)                                                                  AS cvr_pct,
    ROUND(
        (COUNT(DISTINCT CASE WHEN event_type = 'add_to_cart' THEN user_id END)
        - COUNT(DISTINCT CASE WHEN event_type = 'purchase'   THEN user_id END))
        * 100.0
        / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'add_to_cart' THEN user_id END), 0)
    , 1)                                                                  AS cart_abandonment_pct
FROM events
GROUP BY device_type
ORDER BY cvr_pct DESC;


-- ============================================================
-- SECTION 3 — REVENUE AND GROWTH METRICS
-- ============================================================

-- 3A: Overall revenue summary for the period
-- Export result as: result_revenue_summary.csv
SELECT
    COUNT(*)                                    AS total_orders,
    ROUND(SUM(total_amount), 2)                 AS total_revenue,
    ROUND(AVG(total_amount), 2)                 AS avg_order_value,
    ROUND(MIN(total_amount), 2)                 AS min_order,
    ROUND(MAX(total_amount), 2)                 AS max_order,
    SUM(coupon_used)                            AS orders_with_coupon,
    ROUND(SUM(coupon_used) * 100.0 / COUNT(*), 1) AS coupon_usage_pct
FROM orders;


-- 3B: Monthly active users (MAU) — unique users per month
-- Export result as: result_mau.csv
SELECT
    DATE_FORMAT(event_ts, '%M')     AS month,
    COUNT(DISTINCT user_id)         AS mau
FROM events
WHERE event_type = 'visit'
GROUP BY DATE_FORMAT(event_ts, '%Y-%m'), DATE_FORMAT(event_ts, '%M')
ORDER BY DATE_FORMAT(event_ts, '%Y-%m');


-- 3C: DAU/MAU ratio — measures engagement/stickiness
-- Export result as: result_dau_mau.csv
WITH daily_active AS (
    SELECT
        DATE_FORMAT(event_ts, '%Y-%m') AS month,
        DATE(event_ts)                 AS day,
        COUNT(DISTINCT user_id)        AS dau
    FROM events
    WHERE event_type = 'visit'
    GROUP BY month, day
)
SELECT
    month,
    ROUND(AVG(dau), 0)                          AS avg_dau,
    MAX(dau)                                    AS peak_dau,
    -- MAU from subquery for the same month
    (SELECT COUNT(DISTINCT user_id)
     FROM events e2
     WHERE DATE_FORMAT(e2.event_ts, '%Y-%m') = da.month
     AND e2.event_type = 'visit')               AS mau,
    ROUND(AVG(dau) * 100.0 /
     (SELECT COUNT(DISTINCT user_id)
      FROM events e2
      WHERE DATE_FORMAT(e2.event_ts, '%Y-%m') = da.month
      AND e2.event_type = 'visit'), 1)          AS dau_mau_ratio_pct
FROM daily_active da
GROUP BY month
ORDER BY month;


-- 3D: Average revenue per user (ARPU) by month
-- Export result as: result_arpu.csv
SELECT
    DATE_FORMAT(o.order_ts, '%M')               AS month,
    COUNT(DISTINCT o.user_id)                   AS paying_users,
    ROUND(SUM(o.total_amount), 2)               AS total_revenue,
    ROUND(SUM(o.total_amount)
          / COUNT(DISTINCT o.user_id), 2)       AS arpu
FROM orders o
GROUP BY DATE_FORMAT(o.order_ts, '%Y-%m'), DATE_FORMAT(o.order_ts, '%M')
ORDER BY DATE_FORMAT(o.order_ts, '%Y-%m');


-- ============================================================
-- SECTION 4 — COHORT RETENTION ANALYSIS
-- Export result as: result_cohort_wide.csv
-- ============================================================

-- 4A: Weekly cohort retention heatmap
-- Shows % of users who return each week after their first visit
WITH first_visit AS (
    -- Find each user's first ever visit date
    SELECT
        user_id,
        MIN(event_ts)   AS first_date
    FROM events
    WHERE event_type = 'visit'
    GROUP BY user_id
),
cohort_assign AS (
    -- Assign users to Jan/Feb/Mar cohort based on first visit month
    SELECT
        user_id,
        first_date,
        CASE
            WHEN MONTH(first_date) = 1 THEN 'January'
            WHEN MONTH(first_date) = 2 THEN 'February'
            WHEN MONTH(first_date) = 3 THEN 'March'
        END AS cohort_month
    FROM first_visit
),
weekly_activity AS (
    -- Calculate which week number each return visit falls in
    SELECT
        c.user_id,
        c.cohort_month,
        FLOOR(DATEDIFF(e.event_ts, c.first_date) / 7) AS week_num
    FROM cohort_assign c
    JOIN events e
        ON c.user_id = e.user_id
        AND e.event_type = 'visit'
    WHERE FLOOR(DATEDIFF(e.event_ts, c.first_date) / 7) BETWEEN 0 AND 11
    GROUP BY c.user_id, c.cohort_month, week_num
),
cohort_size AS (
    -- Total users per cohort (denominator for retention %)
    SELECT
        cohort_month,
        COUNT(DISTINCT user_id) AS total_users
    FROM cohort_assign
    WHERE cohort_month IS NOT NULL
    GROUP BY cohort_month
)
SELECT
    cs.cohort_month,
    cs.total_users                                                                             AS cohort_size,
    100                                                                                        AS W0,
    ROUND(COUNT(DISTINCT CASE WHEN wa.week_num = 1  THEN wa.user_id END)*100.0/cs.total_users,1) AS W1,
    ROUND(COUNT(DISTINCT CASE WHEN wa.week_num = 2  THEN wa.user_id END)*100.0/cs.total_users,1) AS W2,
    ROUND(COUNT(DISTINCT CASE WHEN wa.week_num = 3  THEN wa.user_id END)*100.0/cs.total_users,1) AS W3,
    ROUND(COUNT(DISTINCT CASE WHEN wa.week_num = 4  THEN wa.user_id END)*100.0/cs.total_users,1) AS W4,
    ROUND(COUNT(DISTINCT CASE WHEN wa.week_num = 5  THEN wa.user_id END)*100.0/cs.total_users,1) AS W5,
    ROUND(COUNT(DISTINCT CASE WHEN wa.week_num = 6  THEN wa.user_id END)*100.0/cs.total_users,1) AS W6,
    ROUND(COUNT(DISTINCT CASE WHEN wa.week_num = 7  THEN wa.user_id END)*100.0/cs.total_users,1) AS W7,
    ROUND(COUNT(DISTINCT CASE WHEN wa.week_num = 8  THEN wa.user_id END)*100.0/cs.total_users,1) AS W8,
    ROUND(COUNT(DISTINCT CASE WHEN wa.week_num = 9  THEN wa.user_id END)*100.0/cs.total_users,1) AS W9,
    ROUND(COUNT(DISTINCT CASE WHEN wa.week_num = 10 THEN wa.user_id END)*100.0/cs.total_users,1) AS W10,
    ROUND(COUNT(DISTINCT CASE WHEN wa.week_num = 11 THEN wa.user_id END)*100.0/cs.total_users,1) AS W11
FROM cohort_size cs
LEFT JOIN weekly_activity wa ON cs.cohort_month = wa.cohort_month
GROUP BY cs.cohort_month, cs.total_users
ORDER BY FIELD(cs.cohort_month, 'January', 'February', 'March');


-- 4B: Cohort retention in long format — for line chart in Power BI
-- Export result as: result_cohort_long.csv
WITH first_visit AS (
    SELECT
        user_id,
        MIN(event_ts)                          AS first_date,
        DATE_FORMAT(MIN(event_ts), '%M')       AS cohort_month
    FROM events
    WHERE event_type = 'visit'
    GROUP BY user_id
),
weekly_activity AS (
    SELECT
        f.user_id,
        f.cohort_month,
        FLOOR(DATEDIFF(e.event_ts, f.first_date) / 7) AS week_number
    FROM first_visit f
    JOIN events e ON f.user_id = e.user_id
    WHERE e.event_type = 'visit'
    AND FLOOR(DATEDIFF(e.event_ts, f.first_date) / 7) BETWEEN 0 AND 11
    GROUP BY f.user_id, f.cohort_month, week_number
),
cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT user_id) AS total_users
    FROM first_visit
    GROUP BY cohort_month
)
SELECT
    a.cohort_month,
    a.week_number,
    COUNT(DISTINCT a.user_id)                                    AS active_users,
    c.total_users                                                AS cohort_size,
    ROUND(COUNT(DISTINCT a.user_id) * 100.0 / c.total_users, 1) AS retention_pct
FROM weekly_activity a
JOIN cohort_size c ON a.cohort_month = c.cohort_month
GROUP BY a.cohort_month, a.week_number, c.total_users
ORDER BY
    FIELD(a.cohort_month, 'January', 'February', 'March'),
    a.week_number;


-- ============================================================
-- SECTION 5 — CHANNEL ATTRIBUTION
-- ============================================================

-- 5A: Full channel performance — visitors, CVR, revenue, ROAS, CPA
-- Export result as: result_channels.csv
WITH channel_funnel AS (
    -- Visitors and purchasers per channel from events table
    SELECT
        channel,
        COUNT(DISTINCT CASE WHEN event_type = 'visit'    THEN user_id END) AS visitors,
        COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN user_id END) AS purchasers
    FROM events
    GROUP BY channel
),
channel_revenue AS (
    -- Revenue and order metrics per channel from orders table
    SELECT
        channel,
        COUNT(*)                    AS total_orders,
        ROUND(SUM(total_amount), 0) AS revenue,
        ROUND(AVG(total_amount), 2) AS aov
    FROM orders
    GROUP BY channel
),
channel_spend AS (
    -- Total ad spend per channel from ad_spend table
    SELECT
        channel,
        ROUND(SUM(spend_usd), 0) AS total_spend
    FROM ad_spend
    GROUP BY channel
)
SELECT
    f.channel,
    f.visitors,
    f.purchasers,
    ROUND(f.purchasers * 100.0 / NULLIF(f.visitors, 0), 2)   AS cvr_pct,
    r.revenue,
    r.aov,
    COALESCE(s.total_spend, 0)                                AS ad_spend,
    -- ROAS: revenue divided by spend (free channels shown separately)
    CASE
        WHEN COALESCE(s.total_spend, 0) = 0
        THEN 'No Spend (Free)'
        ELSE CONCAT(ROUND(r.revenue / s.total_spend, 1), 'x')
    END                                                       AS roas,
    -- CPA: cost per acquired customer
    CASE
        WHEN COALESCE(s.total_spend, 0) = 0
        THEN 'No Spend (Free)'
        ELSE CONCAT('$', ROUND(s.total_spend / NULLIF(f.purchasers, 0), 2))
    END                                                       AS cpa
FROM channel_funnel f
LEFT JOIN channel_revenue r ON f.channel = r.channel
LEFT JOIN channel_spend    s ON f.channel = s.channel
ORDER BY r.revenue DESC;


-- 5B: Channel revenue share — % of total revenue per channel
-- Export result as: result_channel_revenue.csv
SELECT
    channel,
    ROUND(SUM(total_amount), 0)                                             AS revenue,
    ROUND(SUM(total_amount) * 100.0 / SUM(SUM(total_amount)) OVER (), 1)   AS revenue_share_pct,
    COUNT(*)                                                                AS orders,
    ROUND(AVG(total_amount), 2)                                             AS avg_order_value
FROM orders
GROUP BY channel
ORDER BY revenue DESC;


-- ============================================================
-- SECTION 6 — PRODUCT AND CATEGORY ANALYSIS
-- ============================================================

-- 6A: Revenue and performance by product category
-- Export result as: result_categories.csv
SELECT
    category,
    COUNT(DISTINCT order_id)                                                AS orders,
    ROUND(SUM(quantity * unit_price), 0)                                    AS revenue,
    ROUND(SUM(quantity * unit_price) * 100.0
          / SUM(SUM(quantity * unit_price)) OVER (), 1)                     AS revenue_share_pct,
    ROUND(AVG(unit_price), 2)                                               AS avg_unit_price,
    SUM(quantity)                                                           AS units_sold
FROM order_items
GROUP BY category
ORDER BY revenue DESC;


-- 6B: Top 10 products by total revenue
-- Export result as: result_top_10_products.csv
SELECT
    oi.product_id,
    oi.category,
    COUNT(DISTINCT oi.order_id)         AS times_ordered,
    SUM(oi.quantity)                    AS units_sold,
    ROUND(SUM(oi.quantity * oi.unit_price), 2) AS total_revenue,
    ROUND(AVG(oi.unit_price), 2)        AS avg_price
FROM order_items oi
GROUP BY oi.product_id, oi.category
ORDER BY total_revenue DESC
LIMIT 10;


-- 6C: Average order value by category — shows premium vs budget categories
SELECT
    oi.category,
    ROUND(AVG(o.total_amount), 2)   AS avg_order_value,
    COUNT(DISTINCT o.order_id)      AS order_count,
    ROUND(AVG(oi.unit_price), 2)    AS avg_unit_price
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY oi.category
ORDER BY avg_order_value DESC;


-- ============================================================
-- SECTION 7 — CUSTOMER SEGMENTATION
-- ============================================================

-- 7A: Buyer segments by order frequency — one-time vs loyal vs VIP
-- Export result as: result_buyer_segments.csv
WITH user_order_counts AS (
    -- Count total orders per user
    SELECT
        user_id,
        COUNT(*) AS order_count
    FROM orders
    GROUP BY user_id
)
SELECT
    CASE
        WHEN order_count >= 6 THEN '6+ orders (VIP)'
        WHEN order_count BETWEEN 3 AND 5 THEN '3-5 orders'
        WHEN order_count = 2             THEN '2 orders'
        ELSE                                  '1 order (One-time buyer)'
    END                                                           AS buyer_segment,
    COUNT(*)                                                      AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)           AS pct_of_buyers,
    -- Average lifetime spend per segment
    ROUND(AVG(
        (SELECT SUM(total_amount) FROM orders o2
         WHERE o2.user_id = uoc.user_id)
    ), 2)                                                         AS avg_lifetime_spend
FROM user_order_counts uoc
GROUP BY buyer_segment
ORDER BY MIN(order_count) DESC;


-- 7B: Coupon usage impact on revenue and order value
SELECT
    coupon_used,
    COUNT(*)                        AS orders,
    ROUND(AVG(total_amount), 2)     AS avg_order_value,
    ROUND(SUM(total_amount), 0)     AS total_revenue
FROM orders
GROUP BY coupon_used;


-- 7C: New vs returning users by month
SELECT
    DATE_FORMAT(o.order_ts, '%M')   AS month,
    COUNT(DISTINCT o.user_id)       AS paying_users,
    -- Users who had their first order this month
    COUNT(DISTINCT CASE
        WHEN o.order_ts = (SELECT MIN(o2.order_ts)
                           FROM orders o2
                           WHERE o2.user_id = o.user_id)
        THEN o.user_id END)         AS new_buyers,
    -- Users who ordered before this month too
    COUNT(DISTINCT CASE
        WHEN o.order_ts != (SELECT MIN(o2.order_ts)
                            FROM orders o2
                            WHERE o2.user_id = o.user_id)
        THEN o.user_id END)         AS returning_buyers
FROM orders o
GROUP BY DATE_FORMAT(o.order_ts, '%Y-%m'), DATE_FORMAT(o.order_ts, '%M')
ORDER BY DATE_FORMAT(o.order_ts, '%Y-%m');


-- 7D: Weekly revenue trend — used for the line chart on Page 1
-- Export result as: result_weekly_trend.csv
SELECT
    YEAR(order_ts)                              AS year,
    WEEK(order_ts, 1)                           AS week_num,
    DATE(DATE_SUB(order_ts,
        INTERVAL WEEKDAY(order_ts) DAY))        AS week_start,
    COUNT(*)                                    AS orders,
    ROUND(SUM(total_amount), 2)                 AS weekly_revenue,
    ROUND(AVG(total_amount), 2)                 AS avg_order_value
FROM orders
GROUP BY year, week_num, week_start
ORDER BY week_start;
