-- =====================================================
-- Maven Toys: restock analysis
-- Run after 02_analysis.sql. Uses the cleaned price and cost columns
-- from 00_setup.sql.
-- Which store-product pairs need restocking now, which are overstocked,
-- and what the current stockouts cost.
-- Assumptions (also stated in the README):
--   * "Today" is the last date in the sales data (2023-09-30), and the
--     inventory table is a snapshot taken on that date.
--   * Lead time from warehouse to store is 7 days on average, 10 days
--     in the worst case. The data has no lead time; these are assumed.
--   * Demand = average daily units over the last 90 days of data.
--   * Final reorder point (section 2b): 95% service level (z = 1.65).
-- Answers below: data through 2023-09-30, run 2026-11-17.
-- =====================================================


-- -----------------------------------------------------
-- 1. DEMAND OVER THE LAST 90 DAYS
-- -----------------------------------------------------

-- Why: restocking depends on recent demand, not on the full 21 months,
--    which include the 2022 holiday season and older sales patterns.
--    One row per store, product and day that had at least one sale.
DROP TABLE IF EXISTS daily_units;
CREATE TABLE daily_units AS
SELECT Store_ID, Product_ID, Date, SUM(Units) AS units
FROM sales
WHERE Date > (SELECT MAX(Date) FROM sales) - INTERVAL 90 DAY
GROUP BY Store_ID, Product_ID, Date;

-- Q: Does the 90-day window cover exactly 90 days?
-- A: Yes. 2023-07-03 to 2023-09-30, exactly 90 days.
SELECT MIN(Date) AS first_day, MAX(Date) AS last_day,
       DATEDIFF(MAX(Date), MIN(Date)) + 1 AS days
FROM daily_units;

-- Why: days with zero sales have no row in daily_units, so AVG(units)
--    would average only the days that had sales and overstate demand.
--    Dividing the 90-day total by 90 counts the zero days too.
--    Starting from inventory keeps every pair the stores carry,
--    including pairs with no sales in the window (they get 0).
--    units_sq_90d (the sum of squared daily units) is for the standard
--    deviation in section 2b; zero days add 0 to it, so they still count.
DROP TABLE IF EXISTS restock;
CREATE TABLE restock AS
SELECT i.Store_ID, i.Product_ID, i.Stock_On_Hand,
       COALESCE(SUM(d.units), 0)      AS units_90d,
       COALESCE(SUM(d.units), 0) / 90 AS avg_daily_units,
       COALESCE(MAX(d.units), 0)      AS max_daily_units,
       COALESCE(SUM(d.units * d.units), 0) AS units_sq_90d
FROM inventory i
LEFT JOIN daily_units d
  ON d.Store_ID = i.Store_ID AND d.Product_ID = i.Product_ID
GROUP BY i.Store_ID, i.Product_ID, i.Stock_On_Hand;

-- Q: Does restock keep every inventory row, and how many recent units does it cover?
--    (The row counts should be equal. restock_units_90d can be lower than
--    sales_units_90d only by sales of pairs with no inventory record, the
--    snapshot gaps found in 01_checks.sql.)
-- A: Yes. 1,593 inventory rows and 1,593 restock rows. Restock covers 161,934 of the
--    162,305 units sold in the window (99.8%); the other 371 are snapshot gaps.
SELECT (SELECT COUNT(*) FROM inventory)       AS inventory_rows,
       (SELECT COUNT(*) FROM restock)         AS restock_rows,
       (SELECT SUM(units_90d) FROM restock)   AS restock_units_90d,
       (SELECT SUM(units) FROM daily_units)   AS sales_units_90d;

-- Q: Which pairs sold in the last 90 days but have no inventory record?
--    (Their units are the gap between sales_units_90d and restock_units_90d.
--    Expect up to the 23 recently sold pairs found in 01_checks.sql.)
-- A: 23 pairs and 371 units: the same 23 pairs as 01_checks.sql, and exactly the
--    gap in the check above.
SELECT COUNT(DISTINCT d.Store_ID, d.Product_ID) AS pairs_without_inventory,
       SUM(d.units)                             AS units_without_inventory
FROM daily_units d
LEFT JOIN inventory i
  ON i.Store_ID = d.Store_ID AND i.Product_ID = d.Product_ID
WHERE i.Store_ID IS NULL;


-- -----------------------------------------------------
-- 2. FIRST RULE: REORDER POINT FROM THE BIGGEST DAY
-- -----------------------------------------------------

-- Why: a view (not a table) so the status always reflects the restock
--    table. This first rule is kept for comparison; the sanity check below
--    shows why section 2b replaces it.
--    Safety stock = worst-case demand over the worst-case lead time
--                   minus average demand over the average lead time.
--    Reorder point = average demand over the lead time + safety stock
--                  = max_daily_units x 10 (the long form shows the logic).
--    Status is checked in order; the first true condition wins:
--      No recent sales: no sales in 90 days, so no demand to plan for.
--      Out of stock:    demand, but zero stock.
--      Reorder now:     stock at or below the reorder point.
--      Overstocked:     more than 60 days of stock at the current pace.
--      OK:              everything else.
DROP VIEW IF EXISTS restock_status_max;
CREATE VIEW restock_status_max AS
SELECT r.Store_ID, r.Product_ID, r.Stock_On_Hand,
       r.avg_daily_units, r.max_daily_units,
       (r.max_daily_units * 10) - (r.avg_daily_units * 7)     AS safety_stock,
       (r.avg_daily_units * 7)
         + ((r.max_daily_units * 10) - (r.avg_daily_units * 7)) AS reorder_point,
       CASE WHEN r.avg_daily_units = 0 THEN NULL
            ELSE r.Stock_On_Hand / r.avg_daily_units END       AS days_of_stock_left,
       CASE WHEN r.avg_daily_units = 0                        THEN 'No recent sales'
            WHEN r.Stock_On_Hand = 0                          THEN 'Out of stock'
            WHEN r.Stock_On_Hand <= r.max_daily_units * 10    THEN 'Reorder now'
            WHEN r.Stock_On_Hand / r.avg_daily_units > 60     THEN 'Overstocked'
            ELSE 'OK' END                                     AS status
FROM restock r;

-- Q: How many store-product pairs are in each status?
-- A: Reorder now 1,419 (89.1%), No recent sales 93 (5.8%), Out of stock 77 (4.8%),
--    Overstocked 4 (0.3%). 89% "Reorder now" is too many to be useful: see the sanity check.
SELECT status,
       COUNT(*)                                AS pairs,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM restock_status_max
GROUP BY status
ORDER BY pairs DESC;

-- Q: Which pairs need reordering first?
--    (Fewest days of stock left first: these run out soonest.)
-- A: Three pairs have only 0.4 days of stock left: Magic Sand at Zacatecas 1,
--    Lego Bricks at Ciudad de Mexico 2 and Playfoam at Saltillo 2.
SELECT st.Store_Name, p.Product_Name,
       rs.Stock_On_Hand,
       ROUND(rs.avg_daily_units, 2)    AS avg_daily_units,
       ROUND(rs.reorder_point)         AS reorder_point,
       ROUND(rs.days_of_stock_left, 1) AS days_of_stock_left
FROM restock_status_max rs
JOIN products p ON rs.Product_ID = p.Product_ID
JOIN stores st  ON rs.Store_ID   = st.Store_ID
WHERE rs.status = 'Reorder now'
ORDER BY rs.days_of_stock_left
LIMIT 20;

-- Q: Sanity check: do any "Reorder now" pairs have plenty of stock?
--    (Rows here have more than 30 days of stock but still hit the reorder point,
--    usually because one very large sales day set max_daily_units. Look at a few
--    by hand before trusting the status.)
-- A: Yes, 494 of the 1,419 "Reorder now" pairs (35%) have more than 30 days of stock.
--    Most sell under 1 unit a day on average but had one big day, which sets
--    max_daily_units x 10 far above real need. The max-based reorder point is too strict.
SELECT st.Store_Name, p.Product_Name,
       rs.Stock_On_Hand,
       ROUND(rs.avg_daily_units, 2)    AS avg_daily_units,
       rs.max_daily_units,
       ROUND(rs.days_of_stock_left, 1) AS days_of_stock_left
FROM restock_status_max rs
JOIN products p ON rs.Product_ID = p.Product_ID
JOIN stores st  ON rs.Store_ID   = st.Store_ID
WHERE rs.status = 'Reorder now'
  AND rs.days_of_stock_left > 30
ORDER BY rs.days_of_stock_left DESC;


-- -----------------------------------------------------
-- 2b. FINAL RULE: REORDER POINT FROM DAY-TO-DAY VARIATION
-- -----------------------------------------------------

-- Why: the first rule let one unusually big day set the reorder point, so
--    89% of pairs said "Reorder now" and 494 of them had 30+ days of stock.
--    This rule sizes safety stock by how much daily sales usually vary, the
--    standard textbook method:
--      sd_daily_units = standard deviation of daily units over the 90 days,
--                       zero days included: sqrt(sum of squares / 90 - avg^2)
--      safety_stock   = 1.65 x sd_daily_units x sqrt(7)
--                       (95% service level over the 7-day average lead time)
--      reorder_point  = avg_daily_units x 7 + safety_stock
--    Same statuses in the same order; only the reorder point changes.
--    This is the view Power BI reads.
DROP VIEW IF EXISTS restock_status;
CREATE VIEW restock_status AS
SELECT b.Store_ID, b.Product_ID, b.Stock_On_Hand,
       b.avg_daily_units, b.max_daily_units, b.sd_daily_units,
       b.safety_stock,
       b.avg_daily_units * 7 + b.safety_stock                      AS reorder_point,
       CASE WHEN b.avg_daily_units = 0 THEN NULL
            ELSE b.Stock_On_Hand / b.avg_daily_units END            AS days_of_stock_left,
       CASE WHEN b.avg_daily_units = 0                              THEN 'No recent sales'
            WHEN b.Stock_On_Hand = 0                                THEN 'Out of stock'
            WHEN b.Stock_On_Hand <= b.avg_daily_units * 7 + b.safety_stock
                                                                    THEN 'Reorder now'
            WHEN b.Stock_On_Hand / b.avg_daily_units > 60           THEN 'Overstocked'
            ELSE 'OK' END                                           AS status
FROM (
    SELECT r.Store_ID, r.Product_ID, r.Stock_On_Hand,
           r.avg_daily_units, r.max_daily_units,
           SQRT(GREATEST(r.units_sq_90d / 90
                         - r.avg_daily_units * r.avg_daily_units, 0)) AS sd_daily_units,
           1.65 * SQRT(GREATEST(r.units_sq_90d / 90
                         - r.avg_daily_units * r.avg_daily_units, 0)) * SQRT(7) AS safety_stock
    FROM restock r
) b;

-- Q: How many pairs are in each status under the final rule?
--    (Compare with the first rule: Reorder now 1,419, No recent sales 93,
--    Out of stock 77, Overstocked 4.)
-- A: Reorder now 868 (54.5%), OK 348 (21.8%), Overstocked 207 (13.0%), No recent sales
--    93 (5.8%), Out of stock 77 (4.8%). "Reorder now" fell from 89.1% to 54.5%.
SELECT status,
       COUNT(*)                                AS pairs,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM restock_status
GROUP BY status
ORDER BY pairs DESC;

-- Q: How do the two rules compare, pair by pair?
--    (Each row is first-rule status -> final-rule status. "No recent sales" and
--    "Out of stock" can't change; the big move should be "Reorder now" -> "OK".)
-- A: Of the first rule's 1,419 "Reorder now" pairs, 868 stay, 348 become OK and 203
--    become Overstocked. The 4 first-rule Overstocked pairs stay; the other statuses
--    don't change.
SELECT m.status AS first_rule, s.status AS final_rule, COUNT(*) AS pairs
FROM restock_status_max m
JOIN restock_status s
  ON s.Store_ID = m.Store_ID AND s.Product_ID = m.Product_ID
GROUP BY m.status, s.status
ORDER BY m.status, pairs DESC;

-- Q: Sanity check again: do any "Reorder now" pairs still have plenty of stock?
--    (Expect few. Any left are usually very slow sellers holding 1-2 units,
--    where a single sale empties the shelf, so reordering is reasonable.)
-- A: 45 pairs, down from 494, with 30 to 45 days of stock left. These are slow
--    sellers whose daily sales vary a lot relative to their average, so a few units
--    is still within a week-plus-buffer of demand.
SELECT st.Store_Name, p.Product_Name,
       rs.Stock_On_Hand,
       ROUND(rs.avg_daily_units, 2)    AS avg_daily_units,
       ROUND(rs.sd_daily_units, 2)     AS sd_daily_units,
       ROUND(rs.reorder_point, 1)      AS reorder_point,
       ROUND(rs.days_of_stock_left, 1) AS days_of_stock_left
FROM restock_status rs
JOIN products p ON rs.Product_ID = p.Product_ID
JOIN stores st  ON rs.Store_ID   = st.Store_ID
WHERE rs.status = 'Reorder now'
  AND rs.days_of_stock_left > 30
ORDER BY rs.days_of_stock_left DESC;

-- Q: Which pairs need reordering first under the final rule?
--    (Fewest days of stock left first: these run out soonest.)
-- A: The same three lead, at 0.4 days of stock left: Magic Sand at Zacatecas 1,
--    Lego Bricks at Ciudad de Mexico 2 and Playfoam at Saltillo 2.
SELECT st.Store_Name, p.Product_Name,
       rs.Stock_On_Hand,
       ROUND(rs.avg_daily_units, 2)    AS avg_daily_units,
       ROUND(rs.reorder_point, 1)      AS reorder_point,
       ROUND(rs.days_of_stock_left, 1) AS days_of_stock_left
FROM restock_status rs
JOIN products p ON rs.Product_ID = p.Product_ID
JOIN stores st  ON rs.Store_ID   = st.Store_ID
WHERE rs.status = 'Reorder now'
ORDER BY rs.days_of_stock_left
LIMIT 20;

-- Q: How urgent are the "Reorder now" pairs?
--    (Under 7 days of stock: they run out before a 7-day delivery arrives, so
--    order today and check for a transfer. 7-14 days: order this week.
--    14+ days: on the list mainly because of the safety buffer.)
-- A: Roughly a third each: 289 pairs (33.3%) under 7 days, 267 (30.8%) at 7-14 days
--    and 312 (35.9%) at 14+ days. The 289 are today's order list.
SELECT CASE WHEN days_of_stock_left < 7  THEN '1. Under 7 days'
            WHEN days_of_stock_left < 14 THEN '2. 7-14 days'
            ELSE '3. 14+ days' END                   AS urgency,
       COUNT(*)                                       AS pairs,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM restock_status
WHERE status = 'Reorder now'
GROUP BY urgency
ORDER BY urgency;


-- -----------------------------------------------------
-- 3. STOCKOUTS
-- -----------------------------------------------------

-- Q: What share of carried store-product pairs had zero stock on the snapshot date?
--    (01_checks.sql counted 77.)
-- A: 77 of 1,593 carried pairs (4.8% of pairs) had zero stock on 2023-09-30.
SELECT SUM(Stock_On_Hand = 0)                             AS stockouts,
       COUNT(*)                                           AS pairs,
       ROUND(100 * SUM(Stock_On_Hand = 0) / COUNT(*), 1)  AS pct
FROM inventory;

-- Q: Which products run out in the most stores?
--    (Out at many stores points to a supply or ordering problem for that product.)
-- A: Playfoam (out at 13 stores), Hot Wheels 5-Pack (12) and Etch A Sketch (7).
--    Out at that many stores points to a supply or ordering problem for those products.
SELECT p.Product_Name, p.Product_Category, COUNT(*) AS stores_out
FROM inventory i
JOIN products p ON i.Product_ID = p.Product_ID
WHERE i.Stock_On_Hand = 0
GROUP BY p.Product_ID, p.Product_Name, p.Product_Category
ORDER BY stores_out DESC;

-- Q: Which stores are out of the most products?
--    (Out of many products points to a problem with that store's restocking.)
-- A: La Paz 1 and Mexicali 2 (5 products out each), then Hermosillo 2, Pachuca 1 and
--    Aguascalientes 1 (4 each).
SELECT st.Store_Name, st.Store_Location, COUNT(*) AS products_out
FROM inventory i
JOIN stores st ON i.Store_ID = st.Store_ID
WHERE i.Stock_On_Hand = 0
GROUP BY st.Store_ID, st.Store_Name, st.Store_Location
ORDER BY products_out DESC;

-- Q: How much profit does each stocked-out pair lose per day?
--    (Lost profit per day = average daily units x profit per unit. Pairs with no
--    recent sales show 0: low priority, or candidates to stop carrying.)
-- A: 77 rows (one per stocked-out pair); the total is in the next query.
--    Top 3 by lost profit per day: Playfoam at Hermosillo 2 ($18.43),
--    Animal Figures at Culiacan 1 ($15.20) and Etch A Sketch at Puebla 3 ($14.33).
SELECT st.Store_Name, p.Product_Name,
       ROUND(r.avg_daily_units, 2)                      AS avg_daily_units,
       ROUND(r.avg_daily_units * (p.price - p.cost), 2) AS lost_profit_per_day
FROM restock r
JOIN products p ON r.Product_ID = p.Product_ID
JOIN stores st  ON r.Store_ID   = st.Store_ID
WHERE r.Stock_On_Hand = 0
ORDER BY lost_profit_per_day DESC;

-- Q: How much profit do all stockouts lose per day combined, and over a 7-day restock?
-- A: $322.83 a day combined, about $2,259.84 over a 7-day restock.
SELECT COUNT(*)                                              AS stocked_out_pairs,
       SUM(r.avg_daily_units > 0)                            AS with_recent_demand,
       ROUND(SUM(r.avg_daily_units * (p.price - p.cost)), 2)     AS lost_profit_per_day,
       ROUND(SUM(r.avg_daily_units * (p.price - p.cost)) * 7, 2) AS lost_profit_7_days
FROM restock r
JOIN products p ON r.Product_ID = p.Product_ID
WHERE r.Stock_On_Hand = 0;


-- -----------------------------------------------------
-- 4. MONEY TIED UP IN STOCK
-- -----------------------------------------------------

-- Q: How much money sits in stock, at cost, in each category?
-- A: $300,209.58 in total: Toys $99,861.47, Art & Crafts $65,075.65,
--    Sports & Outdoors $53,077.19, Games $51,489.45, Electronics $30,705.82.
SELECT p.Product_Category,
       SUM(i.Stock_On_Hand)           AS units_on_hand,
       SUM(i.Stock_On_Hand * p.cost)  AS stock_value_at_cost
FROM inventory i
JOIN products p ON i.Product_ID = p.Product_ID
GROUP BY p.Product_Category
ORDER BY stock_value_at_cost DESC;

-- Q: How much of that money is in overstocked pairs or pairs with no recent sales?
--    (This is stock that could be moved to stores that are running out.)
-- A: $55,801.88 in overstocked pairs (18.6% of all stock value) and $16,656.51 in
--    pairs with no recent sales (5.5%): $72,458.39 together, about a quarter of the
--    $300,209.58 in stock.
SELECT rs.status,
       COUNT(*)                               AS pairs,
       SUM(rs.Stock_On_Hand)                  AS units_on_hand,
       SUM(rs.Stock_On_Hand * p.cost)         AS stock_value_at_cost
FROM restock_status rs
JOIN products p ON rs.Product_ID = p.Product_ID
WHERE rs.status IN ('Overstocked', 'No recent sales')
GROUP BY rs.status
ORDER BY stock_value_at_cost DESC;

-- Q: Are any products overstocked in some stores and out of stock in others?
--    (If so, moving stock between stores could fix stockouts without new orders.)
-- A: Yes. The biggest: Playfoam (out at 13 stores, overstocked at 1), Hot Wheels
--    5-Pack (out at 12, overstocked at 1) and Etch A Sketch (out at 7, overstocked
--    at 3). One overstocked store can't cover 13 empty ones, so transfers ease these
--    stockouts but Playfoam and Hot Wheels still need new orders.
SELECT p.Product_Name,
       SUM(rs.status = 'Out of stock') AS stores_out,
       SUM(rs.status = 'Overstocked')  AS stores_overstocked
FROM restock_status rs
JOIN products p ON rs.Product_ID = p.Product_ID
GROUP BY p.Product_ID, p.Product_Name
HAVING stores_out > 0 AND stores_overstocked > 0
ORDER BY stores_out DESC;
