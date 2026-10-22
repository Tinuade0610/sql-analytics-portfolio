/* =====================================================================
   PROJECT 2: CUSTOMER SEGMENTATION BY SPEND AND ACTIVITY
   File:     customer_segmentation.sql
   Dialect:  PostgreSQL (run on Supabase)
   Table:    retail_user_behaviour (renamed from retail_user_behavior_100k)
   Source:   Kaggle [URL, creator and license: add from the dataset page]
   Window:   2026-01-01 08:15 UTC to 2026-05-01 07:57 UTC
             (about four months, first and last days are partial)
   Currency: unknown

   QUICK DEFINITIONS
   - Event:     one row (view, click, wishlist, add_to_cart, drop, purchase)
   - Session:   one distinct session_id
   - Conversion: a session with a purchase event (is_conversion = 1)
   - Customer:  one distinct user_id
   - Spend:     SUM(price) on purchase events only

   SEGMENTS (working cutoffs, not business rules)
   - Spend:     No purchase | Low (under 200) | Medium (200 to under 400)
                | High (400+)
   - Frequency: One-time (1 session) | Occasional (2-3) | Frequent (4+)
   - Segment labels start with a number only to control sort order.

   CONTENTS
   PART 1  DATA PROFILING     P1 to P7b
   PART 2  THRESHOLDS         T1 to T3
   PART 3  KPIs AND ANALYSIS  K0 to K5
   PART 4  VALIDATION         V1 to V3
   ===================================================================== */


/* =====================================================================
   PART 1: DATA PROFILING
   Get to know the table before calculating any KPI.
   ===================================================================== */

-- P1 | QUESTION: What does one row represent, and are user IDs reliable?
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT session_id) AS distinct_sessions,
    COUNT(DISTINCT user_id) AS distinct_users,
    COUNT(*) - COUNT(user_id) AS null_user_ids
FROM retail_user_behaviour;
-- FINDING: 108,584 rows but only 18,000 distinct sessions, so a row is not a session (roughly 6 rows per session). There are 6,806 distinct users and no NULL user IDs.


-- P2 | QUESTION: What do the rows inside one session look like, in time order?
SELECT *
FROM retail_user_behaviour
WHERE session_id = (
    SELECT session_id
    FROM retail_user_behaviour
    GROUP BY session_id
    HAVING COUNT(*) >= 5
    LIMIT 1
)
ORDER BY timestamp_utc;
-- FINDING: In session S0013795, each row is an event (view, click, wishlist, drop), numbered by event_index from 1 to 8, matching session_length = 8. User, channel, device, region and traffic source stay the same across the session, while action, product, price and time spent change. Price repeats on every event for the same product (495.08 on five rows), so it's a listed price, not a purchase amount.


-- P3 | QUESTION: What actions exist, and where does is_conversion = 1 appear?
SELECT
    user_action,
    is_conversion,
    COUNT(*) AS event_rows
FROM retail_user_behaviour
GROUP BY user_action, is_conversion
ORDER BY user_action, is_conversion;
-- FINDING: Six event types. is_conversion = 1 shows up only on purchase events (4,203 rows), and every other action is 0. No NULLs in either column. The flag marks the purchase event, not the whole session.


-- P4 | QUESTION: How many purchase events does each session have?
SELECT
    purchases_in_session,
    COUNT(*) AS sessions
FROM (
    SELECT
        session_id,
        SUM(is_conversion) AS purchases_in_session
    FROM retail_user_behaviour
    GROUP BY session_id
) AS session_purchases
GROUP BY purchases_in_session
ORDER BY purchases_in_session;
-- FINDING: A session has at most one purchase: 13,797 sessions have none and 4,203 have one (18,000 total). So purchase events = converted sessions.


-- P5 | QUESTION: What period does the data cover, and does price have gaps?
SELECT
    MIN(timestamp_utc) AS first_event,
    MAX(timestamp_utc) AS last_event,
    COUNT(*) - COUNT(price) AS null_prices,
    MIN(price) AS lowest_price,
    MAX(price) AS highest_price
FROM retail_user_behaviour;
-- FINDING: Events run from 2026-01-01 08:15 UTC to 2026-05-01 07:57 UTC (about four months). No NULL prices, and prices range from 7.29 to 499.86. Spend here means spend in this window, not lifetime.


-- P6 | QUESTION: In a converting session, does the purchase price match the products viewed earlier?
SELECT
    session_id,
    event_index,
    user_action,
    product_id,
    price
FROM retail_user_behaviour
WHERE session_id = (
    SELECT session_id
    FROM retail_user_behaviour
    WHERE is_conversion = 1
    ORDER BY session_id
    LIMIT 1
)
ORDER BY event_index;
-- FINDING: In session S0000003, the purchase is the last of six events and has the same product (P1816) and price (261.82) as the earlier view, click and add_to_cart events. So price is the product's listed price, and spend comes from purchase events only. There's no quantity or discount column, so the purchase price is taken as the amount paid.


-- P7 | QUESTION: Is each purchase the last event of its session, and does it share a product with earlier events?
SELECT
    COUNT(*) AS purchase_events,
    SUM(CASE WHEN p.event_index = s.last_index THEN 1 ELSE 0 END) AS purchase_is_last,
    SUM(CASE WHEN p.product_id IN (
            SELECT e.product_id
            FROM retail_user_behaviour AS e
            WHERE e.session_id = p.session_id
              AND e.event_index < p.event_index
        ) THEN 1 ELSE 0 END) AS product_seen_earlier
FROM retail_user_behaviour AS p
JOIN (
    SELECT session_id, MAX(event_index) AS last_index
    FROM retail_user_behaviour
    GROUP BY session_id
) AS s ON s.session_id = p.session_id
WHERE p.user_action = 'purchase';
-- FINDING: All 4,203 purchases are the last event of their session. Only 3,153 (75.0%) are of a product seen earlier in the same session; 1,050 (25.0%) are of a product with no earlier event. Cause not investigated, so spend uses the purchase row's own price and isn't tied back to earlier browsing.


-- P7b | QUESTION: What do sessions look like where the purchased product was never seen earlier?
SELECT
    p.session_id,
    p.product_id AS purchased_product,
    p.price AS purchase_price,
    (SELECT COUNT(*)
     FROM retail_user_behaviour AS e
     WHERE e.session_id = p.session_id
       AND e.event_index < p.event_index) AS earlier_events,
    (SELECT STRING_AGG(DISTINCT e.product_id, ', ')
     FROM retail_user_behaviour AS e
     WHERE e.session_id = p.session_id
       AND e.event_index < p.event_index) AS earlier_products
FROM retail_user_behaviour AS p
WHERE p.user_action = 'purchase'
  AND p.product_id NOT IN (
      SELECT e.product_id
      FROM retail_user_behaviour AS e
      WHERE e.session_id = p.session_id
        AND e.event_index < p.event_index
  )
ORDER BY p.session_id
LIMIT 5;
-- FINDING: In the first five such sessions (not a random sample), users had 4 to 9 earlier events on other products, then bought something different.


/* =====================================================================
   PART 2: THRESHOLDS
   Pick segment cutoffs from the real distributions, not guesses.
   ===================================================================== */

-- T1 | QUESTION: How is purchase spend distributed across customers?
SELECT
    COUNT(*) AS customers_with_purchase,
    ROUND(MIN(total_spend), 2) AS lowest_spend,
    ROUND(AVG(total_spend), 2) AS average_spend,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_spend)::numeric, 2) AS median_spend,
    ROUND(MAX(total_spend), 2) AS highest_spend
FROM (
    SELECT
        user_id,
        SUM(price) AS total_spend
    FROM retail_user_behaviour
    WHERE user_action = 'purchase'
    GROUP BY user_id
) AS customer_spend;
-- FINDING: 3,238 of 6,806 customers made at least one purchase (3,568 didn't). Spend per buyer runs from 7.29 to 1,454.22, with an average of 322.57 and a median of 312.35.


-- T2 | QUESTION: What spend values split buyers into three equal-sized groups?
SELECT
    ROUND(PERCENTILE_CONT(0.33) WITHIN GROUP (ORDER BY total_spend)::numeric, 2) AS p33_spend,
    ROUND(PERCENTILE_CONT(0.67) WITHIN GROUP (ORDER BY total_spend)::numeric, 2) AS p67_spend
FROM (
    SELECT
        user_id,
        SUM(price) AS total_spend
    FROM retail_user_behaviour
    WHERE user_action = 'purchase'
    GROUP BY user_id
) AS customer_spend;
-- FINDING: The 33rd and 67th percentiles of buyer spend are 201.94 and 402.59, which cut the 3,238 buyers into roughly equal thirds. Rounded to 200 and 400 for the spend segments. These cover buyers only, so the 3,568 non-buyers are left out.


-- T3 | QUESTION: How many sessions does each customer have?
SELECT
    sessions_per_customer,
    COUNT(*) AS customers
FROM (
    SELECT
        user_id,
        COUNT(DISTINCT session_id) AS sessions_per_customer
    FROM retail_user_behaviour
    GROUP BY user_id
) AS customer_sessions
GROUP BY sessions_per_customer
ORDER BY sessions_per_customer;
-- FINDING: Customers have 1 to 11 sessions. 1,609 have one session, 3,545 have two or three, and 1,652 have four or more. Only one customer goes past 9. The frequency cutoffs (1, 2-3, 4+) come from this spread.


/* =====================================================================
   PART 3: KPIs AND ANALYSIS
   Answer the business questions using the definitions above.
   ===================================================================== */

-- K0 | CUSTOMER PROFILE (reference, first 10 rows)
-- QUESTION: What does one customer profile look like (one row per customer)?
SELECT
    user_id,
    COUNT(DISTINCT session_id) AS total_sessions,
    COUNT(DISTINCT CASE WHEN user_action = 'purchase' THEN session_id END) AS converted_sessions,
    COALESCE(SUM(CASE WHEN user_action = 'purchase' THEN price END), 0) AS total_spend
FROM retail_user_behaviour
GROUP BY user_id
ORDER BY user_id
LIMIT 10;
-- FINDING: One row per customer with total sessions, converted sessions and purchase spend. In these 10 customers, converted sessions never exceed total sessions, and spend is 0 exactly when converted sessions is 0. Spend and frequency move independently (U000005: 4 sessions, 176.18 spend; U000011: 1 session, 436.70 spend).


-- K1 | KPI: SPEND SEGMENT SIZE
-- QUESTION: How many customers fall in each spend segment?
WITH customer_profiles AS (
    SELECT
        user_id,
        COUNT(DISTINCT session_id) AS total_sessions,
        COUNT(DISTINCT CASE WHEN user_action = 'purchase' THEN session_id END) AS converted_sessions,
        COALESCE(SUM(CASE WHEN user_action = 'purchase' THEN price END), 0) AS total_spend,
        CASE
            WHEN COUNT(CASE WHEN user_action = 'purchase' THEN 1 END) = 0 THEN '1 No purchase'
            WHEN SUM(CASE WHEN user_action = 'purchase' THEN price END) >= 400 THEN '4 High spender'
            WHEN SUM(CASE WHEN user_action = 'purchase' THEN price END) >= 200 THEN '3 Medium spender'
            ELSE '2 Low spender'
        END AS spend_segment
    FROM retail_user_behaviour
    GROUP BY user_id
)
SELECT
    spend_segment,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM customer_profiles), 0), 2) AS pct_of_customers
FROM customer_profiles
GROUP BY spend_segment
ORDER BY spend_segment;
-- FINDING: 3,568 of 6,806 customers (52.42%) made no purchase. The 3,238 buyers split almost evenly: 1,058 low spenders (15.55%), 1,096 medium (16.10%) and 1,084 high (15.93%). Segments add up to all 6,806 customers.


-- K2 | KPI: FREQUENCY SEGMENT SIZE
-- QUESTION: How many customers fall in each frequency segment?
WITH customer_profiles AS (
    SELECT
        user_id,
        COUNT(DISTINCT session_id) AS total_sessions,
        CASE
            WHEN COUNT(DISTINCT session_id) >= 4 THEN '3 Frequent'
            WHEN COUNT(DISTINCT session_id) >= 2 THEN '2 Occasional'
            ELSE '1 One-time'
        END AS frequency_segment
    FROM retail_user_behaviour
    GROUP BY user_id
)
SELECT
    frequency_segment,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM customer_profiles), 0), 2) AS pct_of_customers
FROM customer_profiles
GROUP BY frequency_segment
ORDER BY frequency_segment;
-- FINDING: 1,609 customers (23.64%) had one session, 3,545 (52.09%) had two or three, and 1,652 (24.27%) had four or more. Totals match the 6,806 customers and the T3 distribution.


-- K3 | KPI: SPEND x FREQUENCY OVERLAP
-- QUESTION: How do spend segments and frequency segments overlap?
WITH customer_profiles AS (
    SELECT
        user_id,
        CASE
            WHEN COUNT(CASE WHEN user_action = 'purchase' THEN 1 END) = 0 THEN '1 No purchase'
            WHEN SUM(CASE WHEN user_action = 'purchase' THEN price END) >= 400 THEN '4 High spender'
            WHEN SUM(CASE WHEN user_action = 'purchase' THEN price END) >= 200 THEN '3 Medium spender'
            ELSE '2 Low spender'
        END AS spend_segment,
        CASE
            WHEN COUNT(DISTINCT session_id) >= 4 THEN '3 Frequent'
            WHEN COUNT(DISTINCT session_id) >= 2 THEN '2 Occasional'
            ELSE '1 One-time'
        END AS frequency_segment
    FROM retail_user_behaviour
    GROUP BY user_id
)
SELECT
    spend_segment,
    frequency_segment,
    COUNT(*) AS customers
FROM customer_profiles
GROUP BY spend_segment, frequency_segment
ORDER BY spend_segment, frequency_segment;
-- FINDING: The 12 combinations add up to 6,806 customers and match K1 and K2. Frequent customers are 46.96% of high spenders (509 of 1,084), compared with 24.27% of all customers and 13.17% of non-buyers. 74 high spenders had just one session, and 470 frequent customers never bought. More sessions mean more chances to buy, so this is an observed association, not a cause.


-- K4 | KPIs: SESSION CONVERSION RATE and SPEND PER CONVERTED SESSION, by frequency segment
-- QUESTION: How do frequency segments compare on session conversion and spend?
WITH customer_profiles AS (
    SELECT
        user_id,
        COUNT(DISTINCT session_id) AS total_sessions,
        COUNT(DISTINCT CASE WHEN user_action = 'purchase' THEN session_id END) AS converted_sessions,
        COALESCE(SUM(CASE WHEN user_action = 'purchase' THEN price END), 0) AS total_spend,
        CASE
            WHEN COUNT(DISTINCT session_id) >= 4 THEN '3 Frequent'
            WHEN COUNT(DISTINCT session_id) >= 2 THEN '2 Occasional'
            ELSE '1 One-time'
        END AS frequency_segment
    FROM retail_user_behaviour
    GROUP BY user_id
)
SELECT
    frequency_segment,
    COUNT(*) AS customers,
    SUM(total_sessions) AS sessions,
    SUM(converted_sessions) AS converted_sessions,
    ROUND(SUM(converted_sessions) * 100.0 / NULLIF(SUM(total_sessions), 0), 2) AS session_conversion_pct,
    ROUND(SUM(total_spend) / NULLIF(SUM(converted_sessions), 0), 2) AS spend_per_converted_session
FROM customer_profiles
GROUP BY frequency_segment
ORDER BY frequency_segment;
-- FINDING: Session conversion is about the same everywhere: 23.93% for one-time (385 of 1,609 sessions), 23.27% for occasional (2,018 of 8,672) and 23.32% for frequent (1,800 of 7,719). Spend per converted session is also close (about 248 to 250). Sessions total 18,000 and converted sessions 4,203. So frequent customers make more purchases because they have more sessions, not because each session converts better. The rate is pooled: all converted sessions over all sessions in the group.


-- K5 | KPI: TOP 3 SPENDERS PER BUYER SEGMENT (window function)
-- QUESTION: Who are the top 3 spenders in each buyer segment?
WITH buyer_spend AS (
    SELECT
        user_id,
        SUM(price) AS total_spend,
        CASE
            WHEN SUM(price) >= 400 THEN '3 High spender'
            WHEN SUM(price) >= 200 THEN '2 Medium spender'
            ELSE '1 Low spender'
        END AS spend_segment
    FROM retail_user_behaviour
    WHERE user_action = 'purchase'
    GROUP BY user_id
),
ranked AS (
    SELECT
        user_id,
        spend_segment,
        total_spend,
        RANK() OVER (
            PARTITION BY spend_segment
            ORDER BY total_spend DESC
        ) AS rank_in_segment
    FROM buyer_spend
)
SELECT
    spend_segment,
    rank_in_segment,
    user_id,
    ROUND(total_spend, 2) AS total_spend
FROM ranked
WHERE rank_in_segment <= 3
ORDER BY spend_segment, rank_in_segment;
-- FINDING: The top spender is U003733 at 1,454.22, which matches the max buyer spend from T1. Ties show up at the edges: two low spenders tie at rank 1 (199.58) and the next is rank 3 (199.37); three medium spenders tie at rank 1 (399.73). RANK() gives ties the same rank and skips the numbers after them. Top low and medium spenders sit just under the 200 and 400 cutoffs, so their segment depends on where the line is drawn.


/* =====================================================================
   PART 4: VALIDATION
   Check that the profiles add up to the raw table.
   ===================================================================== */

-- V1 | QUESTION: Do customer profiles reconcile to the raw table totals?
WITH customer_profiles AS (
    SELECT
        user_id,
        COUNT(DISTINCT session_id) AS total_sessions,
        COUNT(DISTINCT CASE WHEN user_action = 'purchase' THEN session_id END) AS converted_sessions,
        COALESCE(SUM(CASE WHEN user_action = 'purchase' THEN price END), 0) AS total_spend
    FROM retail_user_behaviour
    GROUP BY user_id
)
SELECT
    COUNT(*) AS customers,
    SUM(total_sessions) AS sessions,
    SUM(converted_sessions) AS converted_sessions,
    ROUND(SUM(total_spend), 2) AS profile_spend,
    (SELECT ROUND(SUM(price), 2)
     FROM retail_user_behaviour
     WHERE user_action = 'purchase') AS raw_purchase_spend
FROM customer_profiles;
-- FINDING: Everything lines up: 6,806 customers, 18,000 sessions, 4,203 converted sessions, and 1,044,466.59 total purchase spend in both the profiles and the raw purchase rows. The profile logic doesn't drop or double-count anything.


-- V2 | QUESTION: Are the first and last days of the data partial days?
SELECT
    DATE(timestamp_utc) AS event_date,
    COUNT(*) AS events,
    COUNT(DISTINCT session_id) AS sessions
FROM retail_user_behaviour
WHERE DATE(timestamp_utc) IN (
    '2026-01-01', '2026-01-02', '2026-01-03',
    '2026-04-29', '2026-04-30', '2026-05-01'
)
GROUP BY DATE(timestamp_utc)
ORDER BY event_date;
-- FINDING: Yes, the edge days are partial. 2026-01-01 has 550 events (89 sessions) and 2026-05-01 has 354 events (58 sessions), versus 899 to 938 events on Jan 2-3 and 776 to 993 on Apr 29-30. So the window is about four months with partial first and last days.


-- V3 | QUESTION: Does user U000002 appear anywhere in the table?
SELECT COUNT(*) AS rows_for_u000002
FROM retail_user_behaviour
WHERE user_id = 'U000002';
-- FINDING: U000002 has no rows, so it isn't one of the 6,806 customers. User IDs aren't contiguous (U000010 was also missing from the first-10 profile output). "Customers" here means users who appear in the table.
