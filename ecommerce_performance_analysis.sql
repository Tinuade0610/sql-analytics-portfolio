-- Retail E-commerce Performance Analysis (SQL)
-- Table: retail_user_behaviour | Database: PostgreSQL (Supabase)
  
-- DEFINITIONS
-- Event:    one row = one user action (view, click, add_to_cart, purchase...)
-- Session:  one visit = all rows sharing a session_id, ordered by event_index
-- Purchase: an event where user_action = 'purchase' (is_conversion = 1)


-- PART 1: DATA PROFILING 

-- QUESTION: What do the columns and first rows look like?
SELECT *
FROM retail_user_behaviour
LIMIT 100;
-- FINDING: 18 columns covering user, session, event, product, channel
-- and outcome fields (see data dictionary in README).


-- QUESTION: What does one row represent?
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT session_id) AS unique_sessions
FROM retail_user_behaviour;
-- FINDING: 108,584 rows but only 18,000 unique session_ids (about 6 rows
-- per session). One row = one event (view, click, add_to_cart, purchase...),
-- not one session.


-- QUESTION: What does a single session look like?
SELECT
    session_id,
    event_index,
    timestamp_utc,
    user_action,
    product_id,
    price,
    is_conversion,
    drop_off_flag
FROM retail_user_behaviour
WHERE session_id = 'S0000003'
ORDER BY event_index;
-- FINDING: Events in a session share a session_id and are ordered by
-- event_index. In the sessions inspected (S0000001, S0000002, S0000003),
-- a non-converting session ended with a 'drop' row where drop_off_flag = 1,
-- and the converting session ended with a 'purchase' row where
-- is_conversion = 1.


-- QUESTION: Purchase rows vs. sessions that contain a purchase
SELECT
    COUNT(*) AS purchase_rows,
    COUNT(DISTINCT session_id) AS converting_sessions
FROM retail_user_behaviour
WHERE is_conversion = 1;
-- FINDING: 4,203 purchase rows and 4,203 converting sessions.
-- Every converting session has exactly one purchase.


-- QUESTION: Do all purchase rows have is_conversion = 1?
SELECT
    is_conversion,
    COUNT(*) AS row_count
FROM retail_user_behaviour
WHERE user_action = 'purchase'
GROUP BY is_conversion;
-- FINDING: All 4,203 purchase rows have is_conversion = 1 and none have 0.
-- is_conversion = 1 and user_action = 'purchase' identify the same rows.


-- QUESTION: Does any session have more than one channel?
SELECT
    COUNT(*) AS sessions_with_multiple_channels
FROM (
    SELECT session_id
    FROM retail_user_behaviour
    GROUP BY session_id
    HAVING COUNT(DISTINCT channel) > 1
) AS multi_channel;
-- FINDING: 0 sessions. Each session sits on one channel,
-- so grouping by channel does not double count.


-- QUESTION: Does any session span more than one UTC date?
SELECT
    COUNT(*) AS sessions_spanning_dates
FROM (
    SELECT session_id
    FROM retail_user_behaviour
    GROUP BY session_id
    HAVING COUNT(DISTINCT DATE(timestamp_utc)) > 1
) AS multi_date;
-- FINDING (date span): 22 of 18,000 sessions (about 0.1%) span more than
-- one UTC date. Daily counts use each session's start date, so none is
-- counted twice.


-- QUESTION: Does every session have exactly one first event?
SELECT
    COUNT(*) AS first_events
FROM retail_user_behaviour
WHERE event_index = 1;
-- FINDING (first events): 18,000 rows have event_index = 1, one per
-- session. Filtering on it gives exactly one row per session.


-- QUESTION: How many NULLs are in the key columns?
SELECT
    COUNT(*) - COUNT(session_id)    AS null_session_id,
    COUNT(*) - COUNT(user_id)       AS null_user_id,
    COUNT(*) - COUNT(timestamp_utc) AS null_timestamp,
    COUNT(*) - COUNT(event_index)   AS null_event_index,
[10/21/2026 1:15 AM] Atinuke Adegbola: COUNT(*) - COUNT(user_action)   AS null_user_action,
    COUNT(*) - COUNT(category)      AS null_category,
    COUNT(*) - COUNT(price)         AS null_price,
    COUNT(*) - COUNT(channel)       AS null_channel,
    COUNT(*) - COUNT(is_conversion) AS null_is_conversion
FROM retail_user_behaviour;
-- FINDING: No NULLs in session_id, user_id, timestamp_utc, event_index,
-- user_action, category, price, channel or is_conversion (checked across
-- all 108,584 rows). No missing-value handling was needed.


-- QUESTION: Is any (session_id, event_index) pair repeated?
SELECT
    session_id,
    event_index,
    COUNT(*) AS times_seen
FROM retail_user_behaviour
GROUP BY session_id, event_index
HAVING COUNT(*) > 1;
-- FINDING: No (session_id, event_index) pair appears more than once, so no
-- event is recorded twice within a session. No de-duplication was needed.


-- QUESTION: What date range does the data cover?
SELECT
    MIN(DATE(timestamp_utc)) AS first_date,
    MAX(DATE(timestamp_utc)) AS last_date
FROM retail_user_behaviour;
-- FINDING: Data runs from 2026-01-01 to 2026-05-01 (121 days).


-- PART 2: KPIs 

-- KPI 1 -------------------------------------------------------------
-- QUESTION: What is the session-level conversion rate?
SELECT
    COUNT(DISTINCT session_id) AS total_sessions,
    COUNT(DISTINCT CASE WHEN is_conversion = 1 THEN session_id END)
        AS converting_sessions,
    ROUND(
        COUNT(DISTINCT CASE WHEN is_conversion = 1 THEN session_id END) * 100.0
        / NULLIF(COUNT(DISTINCT session_id), 0), 2
    ) AS conversion_rate_pct
FROM retail_user_behaviour;
-- FINDING: 4,203 / 18,000 = 23.35% of sessions end in a purchase.


-- KPI 2 -------------------------------------------------------------
-- QUESTION: What is the session-level conversion rate by channel?
SELECT
    channel,
    COUNT(DISTINCT session_id) AS total_sessions,
    COUNT(DISTINCT CASE WHEN is_conversion = 1 THEN session_id END)
        AS converting_sessions,
    ROUND(
        COUNT(DISTINCT CASE WHEN is_conversion = 1 THEN session_id END) * 100.0
        / NULLIF(COUNT(DISTINCT session_id), 0), 2
    ) AS conversion_rate_pct
FROM retail_user_behaviour
GROUP BY channel
ORDER BY conversion_rate_pct DESC;
-- FINDING: App 26.74% (1,592 of 5,953), mobile 22.37% (1,351 of 6,040),
-- web 20.98% (1,260 of 6,007). Sessions sum to 18,000 and conversions
-- sum to 4,203, matching the totals. App converts about 27.5% better
-- than web (5.8 percentage points). Observed difference only; the
-- cause has not been investigated.


-- KPI 3 -------------------------------------------------------------
-- QUESTION: How much revenue does each category generate from purchases?
SELECT
    category,
    COUNT(*) AS purchases,
    ROUND(SUM(price), 2) AS total_revenue,
    ROUND(AVG(price), 2) AS avg_purchase_price
FROM retail_user_behaviour
WHERE user_action = 'purchase'
GROUP BY category
ORDER BY total_revenue DESC;
-- FINDING: Counting purchase rows only, Sports leads with 141,378.93 and
-- Beauty is last with 119,683.21. The eight categories total 1,044,466.59.
-- Sports is about 13.5% of the total and Beauty about 11.5%, so the
-- categories are close: Sports is only about 18% above Beauty.
-- FINDING (drivers): Sports has 543 purchases at an average of 260.37,
-- while Beauty has 513 purchases at an average of 233.30. Purchase
-- counts are close across categories (506-545); differences in revenue
-- come mostly from average price, with Groceries having the most
-- purchases (545) but a lower average price than Sports.


-- KPI 4 -------------------------------------------------------------
-- QUESTION: Which day had the most new sessions (by start date)?
SELECT
    DATE(timestamp_utc) AS session_date,
COUNT(*) AS daily_sessions
FROM retail_user_behaviour
WHERE event_index = 1
GROUP BY session_date
ORDER BY daily_sessions DESC
LIMIT 1;
-- FINDING: Counting each session once on its start date (event_index = 1),
-- the busiest day was 2026-01-30 with 183 new sessions. Dates are UTC.
-- Observed pattern only; cause not investigated.


-- QUESTION: What is the average number of new sessions per day?
SELECT
    ROUND(AVG(daily_sessions), 1) AS avg_daily_sessions,
    MIN(daily_sessions) AS quietest_day,
    MAX(daily_sessions) AS busiest_day
FROM (
    SELECT DATE(timestamp_utc) AS session_date, COUNT(*) AS daily_sessions
    FROM retail_user_behaviour
    WHERE event_index = 1
    GROUP BY session_date
) AS daily;
-- FINDING (daily average): The average day has about 149 new sessions
-- (range 58 to 183).


-- QUESTION: Which days are quietest, and where do they fall in the range?
SELECT
    DATE(timestamp_utc) AS session_date,
    COUNT(*) AS daily_sessions
FROM retail_user_behaviour
WHERE event_index = 1
GROUP BY session_date
ORDER BY daily_sessions ASC
LIMIT 3;
-- FINDING (quietest days): The three lowest days were 2026-05-01 (58),
-- 2026-01-01 (89) and 2026-03-24 (125). The first two are the first and
-- last dates in the data, so their low counts may reflect where the data
-- starts and stops, not real slow days. Excluding them, the quietest day
-- is 2026-03-24 (125 sessions). Cause not investigated.


-- ============================ NOTES ===================================
-- NOTE: price is the product's listed price, repeated on every row of a
-- session, so SUM(price) over all rows is not revenue. Revenue uses
-- purchase rows only.
-- NOTE: The currency of price is unverified, so no currency symbol is used.
-- NOTE: channel and device_type are separate columns and can disagree
-- (S0000001: channel = mobile, device_type = desktop). Not investigated.
