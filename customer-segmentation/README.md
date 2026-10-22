## Customer Segmentation by Spend and Activity

A SQL analysis of a retail user-behaviour event log. It builds one profile per customer, segments customers by purchase spend and by session frequency, and compares the segments on conversion and spend.

**Tools:** PostgreSQL (Supabase) · **Query file:** [customer_segmentation.sql](customer_segmentation.sql)

## TL;DR

- The data holds **108,584 events** across **18,000 sessions** and **6,806 customers**, from 2026-01-01 to 2026-05-01 (about four months).
- **52.42% of customers (3,568) made no purchase** in the window. The other 3,238 buyers split almost evenly into low, medium and high spenders.
- **Session conversion is about 23% in every frequency segment** (23.93%, 23.27%, 23.32%), and spend per converted session is about 248 to 250 in each. Frequent customers buy more often because they have more sessions, not because each session converts better.
- **Frequent customers are 46.96% of high spenders** but 24.27% of all customers. This is an observed association, not a cause.
- All profile totals reconcile to the raw table (6,806 customers, 18,000 sessions, 4,203 converted sessions, 1,044,466.59 total purchase spend). **Currency is unverified.**

## Business questions

1. How many customers buy at all, and how are buyers spread across spend levels?
2. How often do customers return, and how are they spread across frequency levels?
3. Do customers who visit more also spend more?
4. Do frequent customers convert better per session, or do they simply visit more?
5. Who are the top spenders within each spend segment?

## Key findings

| KPI | Result |
|---|---|
| Customers | 6,806 |
| Sessions | 18,000 |
| Converted sessions (sessions with a purchase) | 4,203 |
| Overall session conversion rate | 23.35% (4,203 / 18,000) |
| Total purchase spend (window) | 1,044,466.59 |
| Average spend per converted session | 248.50 |
| Customers with at least one purchase | 3,238 (47.58%) |
| Average / median spend per buyer | 322.57 / 312.35 |

**Spend segments** (total purchase spend per customer)

| Segment | Rule | Customers | % of customers |
|---|---|---|---|
| No purchase | no purchase event | 3,568 | 52.42% |
| Low spender | under 200 | 1,058 | 15.55% |
| Medium spender | 200 to under 400 | 1,096 | 16.10% |
| High spender | 400 or more | 1,084 | 15.93% |

**Frequency segments** (distinct sessions per customer)

| Segment | Rule | Customers | % of customers | Session conversion | Spend per converted session |
|---|---|---|---|---|---|
| One-time | 1 session | 1,609 | 23.64% | 23.93% | 250.25 |
| Occasional | 2 to 3 sessions | 3,545 | 52.09% | 23.27% | 247.77 |
| Frequent | 4 or more sessions | 1,652 | 24.27% | 23.32% | 248.95 |

**Share of each spend segment that is Frequent**

| Spend segment | Frequent customers | Segment size | Share |
|---|---|---|---|
| No purchase | 470 | 3,568 | 13.17% |
| Low spender | 319 | 1,058 | 30.15% |
| Medium spender | 354 | 1,096 | 32.30% |
| High spender | 509 | 1,084 | 46.96% |

**Top spenders:** the highest-spending customer is U003733 at 1,454.22. Ties occur at the segment edges (two low spenders tie at 199.58; three medium spenders tie at 399.73). Full top-3 lists are in query K5.

**Observed:**

- Frequent customers account for a larger share of high spenders. Since more sessions give more chances to buy, part of this link is probably built in. No cause was tested.
- 25% of purchases (1,050 of 4,203) are of a product that had no earlier event in the same session.

## Method notes

**Order of work:** profile the data, define terms, ask questions, query, validate, then write up.

**Grain.** One row is one **event**. A session has about six events on average. Counting rows as sessions would overstate sessions by a factor of six, so all session counts use `COUNT(DISTINCT session_id)`.

### Definitions

| Term | Definition |
|---|---|
| Event | One row (view, click, wishlist, add_to_cart, drop or purchase) |
| Session | One distinct `session_id` |
| Conversion | A session containing a purchase event. Every session has at most one, so converted sessions equal purchase events (4,203) |
| Customer | One distinct `user_id` that appears in the table |
| Spend | `SUM(price)` on purchase events only, over the window |

**Why spend uses purchase rows only.** `price` is the product's listed price and repeats on every event for that product (view, click, cart, purchase). Summing it across all events would count products customers only looked at. The `is_conversion` flag appears only on purchase events.

**Thresholds.** Spend cutoffs come from the 33rd and 67th percentiles of buyer spend (201.94 and 402.59), rounded to 200 and 400. Frequency cutoffs (1, 2 to 3, 4 or more) come from the observed spread of sessions per customer, which runs from 1 to 11. Both are working definitions, not validated business rules.

**Metrics**

- `session_conversion_pct` is a **pooled** rate: all converted sessions divided by all sessions in the group.
- Customers with no purchase get their own segment instead of being labelled low spenders.
- Every denominator uses `NULLIF`.

## Validation

| Check | Result |
|---|---|
| Customers, sessions and converted sessions in profiles vs raw table | 6,806 / 18,000 / 4,203, all match |
| Total purchase spend, profiles vs raw purchase rows | 1,044,466.59 in both |
| Spend segment counts sum to total customers | 6,806 |
| Frequency segment counts sum to total customers | 6,806 |
| Spend-by-frequency grid vs single-segment tables | Row and column totals match both |
| Sessions and converted sessions across frequency segments | 18,000 and 4,203 |
| Highest ranked spender vs maximum buyer spend | Both 1,454.22 |
| Sessions with 0 / 1 / 2+ purchases | 13,797 / 4,203 / 0 |

## Data dictionary

One row is one **event** inside a session. Only columns used or checked in this analysis are listed.

| Column | Meaning |
|---|---|
| `session_id` | Session identifier (18,000 distinct values) |
| `user_id` | Customer identifier (6,806 distinct values, no NULLs) |
| `timestamp_utc` | Event time in UTC, 2026-01-01 08:15 to 2026-05-01 07:57 |
| `event_index` | Order of the event within its session |
| `user_action` | Event type: view, click, wishlist, add_to_cart, drop, purchase |
| `product_id` | Product the event refers to |
| `price` | Listed product price, repeated on each event for that product; no NULLs, range 7.29 to 499.86. Currency unverified |
| `is_conversion` | 1 on purchase events only, 0 otherwise; no NULLs |

## Limitations

- **Currency is unknown.** All spend figures and the 200 / 400 cutoffs are in the dataset's own price units.
- **Price is a listed price.** No quantity or discount column exists, so a purchase's price is treated as the amount paid without verification.
- **Observation window, not lifetime.** Spend and sessions cover about four months. The first day (2026-01-01, 89 sessions) and last day (2026-05-01, 58 sessions) are partial days, so customer totals at the edges are slightly understated. Day boundaries follow the database time zone, assumed to be UTC.
- **Thresholds are analytical choices.** Customers near a cutoff change segment if it moves (for example, U000008 spent 399.73 and is a medium spender).
- **25% of purchases** are of a product with no earlier event in the same session. The cause was not investigated, so spend is not linked back to earlier browsing.
- **Customers means users who appear in the table.** User IDs are not contiguous (U000002 has no rows); the reason is not known.
- **Descriptive segments, not predictions.** A high spender is not necessarily loyal or profitable, and a frequent visitor is not necessarily a high-value customer.

## Files

| File | Purpose |
|---|---|
| `README.md` | This write-up |
| `customer_segmentation.sql` | All queries with questions and findings: profiling (P), thresholds (T), KPIs (K) and validation (V) |
