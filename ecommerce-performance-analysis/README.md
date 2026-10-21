# Retail E-commerce Performance Analysis in SQL

TL;DR: 23.35% of sessions end in a purchase, app shoppers convert best, and
the product categories are in a surprisingly tight race.

Database: PostgreSQL (Supabase) | Data: 108,584 events across 18,000 sessions, 2026-01-01 to 2026-05-01. 

Skills shown: data profiling, conditional aggregation, COUNT(DISTINCT), GROUP BY / HAVING, derived tables (subqueries in FROM), validation checks.

## Overview
This project analyzes session-level behavior in an e-commerce store, following
shoppers from first view to purchase (or to the moment they wander off). It
measures conversion, compares channels, ranks categories by purchase revenue
and tracks daily traffic.

Every query sits in ecommerce_analysis.sql with its question above it and
its finding below it, so the reasoning is easy to follow.

## Business questions
1. What share of sessions end in a purchase?
2. Does conversion differ by channel (app, mobile, web)?
3. Which categories generate the most purchase revenue?
4. How does new-session traffic move day to day?

## Key findings
| Question | Result |
|---|---|
| Session conversion rate | 23.35% (4,203 of 18,000 sessions) |
| By channel | App 26.74%, mobile 22.37%, web 20.98% |
| Top category by revenue | Sports, 141,378.93 (about 13.5% of 1,044,466.59) |
| Lowest category | Beauty, 119,683.21 (about 11.5%) |
| Busiest day | 2026-01-30, 183 new sessions (average day: about 149) |

- App vs web: App sessions had a 26.74% conversion rate, compared with 20.98% for web, a difference of 5.8 percentage points.
  This is an observed association; further testing and investigation of traffic mix would be needed to assess its robustness
  and possible explanations.
- Categories are in a tight race. Sports leads Beauty by only about 18%.
  Purchase counts are nearly level (506 to 545 per category, with Groceries
  highest at 545), so revenue differences come mostly from average purchase
  price (260.37 for Sports vs. 233.30 for Beauty).
- Traffic is steady. The average day brings about 149 new sessions, ranging
  from 58 to 183.
- Currency is unverified, so revenue carries no symbol.

## Method notes
- Grain: one row is one *event* (view, click, wishlist, add_to_cart, drop
  or purchase). A session is all rows sharing a session_id, ordered by
  event_index. Sessions are counted with COUNT(DISTINCT session_id).
- Conversion: is_conversion = 1 marks the purchase event. It identifies
  exactly the same 4,203 rows as user_action = 'purchase', and each
  converting session contains exactly one purchase.
- Revenue: price is the product's listed price and repeats on every row
  of a session, so revenue is calculated from purchase rows only.
- Daily traffic: sessions are counted once, on their start date
  (event_index = 1), in UTC.

## Validation
Trust, but COUNT:
- Channel sessions sum to 18,000 and channel purchases sum to 4,203, matching
  the overall totals.
- The category total (1,044,466.59) was confirmed with a separate query.
- The conversion rate was calculated by hand (4,203 / 18,000) and by query.
  They agreed.
- No NULLs in the key columns, and no repeated (session_id, event_index)
  pair.
- No session spans more than one channel.
- 22 sessions (about 0.1%) cross midnight UTC. Counting by start date means
  nobody appears on two days.

## About the data
- Source: Kaggle, retail_user_behavior_100k
- Coverage: 2026-01-01 to 2026-05-01 (121 days), timestamps in UTC

| Column | Meaning |
|---|---|
| session_id | One visit |
| user_id | The user (one user can have many sessions) |
| timestamp_utc | When the event happened (UTC) |
| event_index | Position of the event within its session (1, 2, 3...) |
| user_action | view, click, wishlist, add_to_cart, drop, purchase |
| product_id, category, brand | The product involved |
| price | Listed price of the product, repeated on every row |
| channel | app, mobile or web |
| device_type, region, traffic_source | Device, country code, arrival source |
| is_conversion | 1 on the purchase event, otherwise 0 |
| drop_off_flag | 1 on the drop event in the sessions inspected |
| time_spent_sec, session_length, interaction_count | Not verified, not used |


## Limitations (the fine print)
- price may not reflect quantity or discounts. This is revenue, not profit.
- It is a single table, so results cannot be cross-checked against order, cost
  or marketing data.
- The two quietest days (2026-01-01 and 2026-05-01) are the first and last
  dates in the data, so they may be partial days. The quietest full day is
  2026-03-24 with 125 sessions.
- channel and device_type sometimes disagree (for example, channel
  mobile with device desktop). 
- drop_off_flag was confirmed only on the sessions inspected.

## Where this could go next
Hypotheses to test, not conclusions:
- Why does app convert better? Check traffic mix, user type and funnel steps.
- Break conversion down by category, device and region.
- Study drop-off by step to see where sessions end.

## Reproduce it
1. Download the dataset from the Kaggle.
2. Load it into PostgreSQL as retail_user_behaviour.
