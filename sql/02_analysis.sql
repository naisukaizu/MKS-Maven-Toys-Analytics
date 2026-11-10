-- =====================================================
-- Maven Toys: sales and profit analysis
-- Run after 01_checks.sql. Data: 1 Jan 2022 - 30 Sep 2023.
-- Each query answers one business question; record answers in notes.md.
-- Answers (-- A:): data through 2023-09-30, run 2026-11-10.
-- =====================================================


-- -----------------------------------------------------
-- 1. OVERALL
-- -----------------------------------------------------

-- Q: How big is the business? Total revenue, cost, profit and margin.
-- A: About 1.1M units sold: $14.4M revenue, $10.4M cost, $4.0M profit (27.8% margin).
SELECT SUM(s.Units)                                   AS units,
       SUM(s.Units * p.price)                         AS revenue,
       SUM(s.Units * p.cost)                          AS cost,
       SUM(s.Units * (p.price - p.cost))              AS profit,
       ROUND(100 * SUM(s.Units * (p.price - p.cost))
                 / SUM(s.Units * p.price), 1)         AS margin_pct
FROM sales s
JOIN products p ON s.Product_ID = p.Product_ID;

-- Q: Is the business growing? Jan-Sep 2022 vs Jan-Sep 2023
--    (same months only, because 2023 ends in September).
--    % change = (2023 - 2022) / 2022 x 100, calculated by hand from these two rows.
-- A: Yes. Revenue rose 30.9% ($5.3M to $7.0M), but profit rose only 16.0% ($1.6M to $1.8M),
--    so the profit margin fell: growth came mostly from lower-margin products.
SELECT YEAR(s.Date)                       AS yr,
       SUM(s.Units * p.price)             AS revenue,
       SUM(s.Units * (p.price - p.cost))  AS profit
FROM sales s
JOIN products p ON s.Product_ID = p.Product_ID
WHERE MONTH(s.Date) <= 9
GROUP BY yr
ORDER BY yr;

-- Q: Did any store open during the data period?
--    (A new store adds sales that aren't real growth; mention it next to YoY.)
-- A: No. Every store opened before 2022, so the growth is not from new stores.
SELECT Store_Name, Store_City, Store_Open_Date
FROM stores
WHERE Store_Open_Date >= '2022-01-01'
ORDER BY Store_Open_Date;


-- -----------------------------------------------------
-- 2. STORES AND LOCATIONS
-- -----------------------------------------------------

-- Q: Which stores make the most (and least) profit?
-- A: Most: Maven Toys Ciudad de Mexico 2 ($170K). Least: Maven Toys Cuernavaca 1 ($57K).
SELECT st.Store_Name, st.Store_City, st.Store_Location,
       SUM(s.Units * p.price)             AS revenue,
       SUM(s.Units * (p.price - p.cost))  AS profit
FROM sales s
JOIN products p ON s.Product_ID = p.Product_ID
JOIN stores st  ON s.Store_ID   = st.Store_ID
GROUP BY st.Store_ID, st.Store_Name, st.Store_City, st.Store_Location
ORDER BY profit DESC;

-- Q: Which location type (Downtown, Commercial, Residential, Airport) earns
--    the most, in total and per store?
-- A: Downtown earns the most in total ($2.2M); Airport earns the most per store ($126K).
SELECT st.Store_Location,
       COUNT(DISTINCT st.Store_ID)                            AS stores,
       SUM(s.Units * (p.price - p.cost))                      AS profit,
       ROUND(SUM(s.Units * (p.price - p.cost))
             / COUNT(DISTINCT st.Store_ID), 2)                AS profit_per_store
FROM sales s
JOIN products p ON s.Product_ID = p.Product_ID
JOIN stores st  ON s.Store_ID   = st.Store_ID
GROUP BY st.Store_Location
ORDER BY profit_per_store DESC;


-- -----------------------------------------------------
-- 3. PRODUCTS AND CATEGORIES
-- -----------------------------------------------------

-- Q: Which categories bring in the most profit, and at what margin?
-- A: Toys earn the most profit ($1.1M), at a 21.2% margin, below the 27.8% overall margin.
SELECT p.Product_Category,
       SUM(s.Units)                                   AS units,
       SUM(s.Units * p.price)                         AS revenue,
       SUM(s.Units * (p.price - p.cost))              AS profit,
       ROUND(100 * SUM(s.Units * (p.price - p.cost))
                 / SUM(s.Units * p.price), 1)         AS margin_pct
FROM sales s
JOIN products p ON s.Product_ID = p.Product_ID
GROUP BY p.Product_Category
ORDER BY profit DESC;

-- Q: How does each category's profit change month by month?
--    (Look for seasonality, e.g. a December peak, and for growing or shrinking categories.)
-- A: Not answered here: 105 rows (5 categories x 21 months) are too many to read
--    by eye. This query feeds the monthly profit line chart in the Power BI dashboard.
SELECT YEAR(s.Date)                       AS yr,
       MONTH(s.Date)                      AS mo,
       p.Product_Category,
       SUM(s.Units * (p.price - p.cost))  AS profit
FROM sales s
JOIN products p ON s.Product_ID = p.Product_ID
GROUP BY yr, mo, p.Product_Category
ORDER BY yr, mo, p.Product_Category;

-- Q: Which products sell the most units, and are any of them low-margin?
--    (A best seller with a below-average margin is a pricing or cost question.)
-- A: Colorbuds sell the most (104K units) at a 53.4% margin. Dino Eggs (11th, 38K units)
--    has only a 9.1% margin. Mini Basketball Hoop sells the fewest (2K) at the highest margin (64.0%).
SELECT p.Product_Name, p.Product_Category,
       SUM(s.Units)                                   AS units,
       SUM(s.Units * (p.price - p.cost))              AS profit,
       ROUND(100 * (p.price - p.cost) / p.price, 1)   AS margin_pct
FROM sales s
JOIN products p ON s.Product_ID = p.Product_ID
GROUP BY p.Product_ID, p.Product_Name, p.Product_Category, p.price, p.cost
ORDER BY units DESC;

-- Q: What are the top 3 products by profit in each store?
--    (Do the same products win everywhere, or does it differ by store?)
-- A: 150 rows (3 products x 50 stores), too many to read by eye;
--    summarised by the next query.
WITH ranked AS (
  SELECT st.Store_Name,
         p.Product_Name,
         SUM(s.Units * (p.price - p.cost)) AS profit,
         RANK() OVER (PARTITION BY s.Store_ID
                      ORDER BY SUM(s.Units * (p.price - p.cost)) DESC) AS rnk
  FROM sales s
  JOIN products p ON s.Product_ID = p.Product_ID
  JOIN stores st  ON s.Store_ID   = st.Store_ID
  GROUP BY s.Store_ID, st.Store_Name, p.Product_ID, p.Product_Name
)
SELECT Store_Name, rnk, Product_Name, profit
FROM ranked
WHERE rnk <= 3
ORDER BY Store_Name, rnk;

-- Q: Which products are top earners in the most stores?
--    (Summarises the previous query: how many stores rank each product 1st,
--    and how many have it in their top 3.)
-- A: Colorbuds is the top earner in 39 of 50 stores and in the top 3 of every store.
--    Action Figure ranks 1st in 6 stores (top 3 in 37); Lego Bricks ranks 1st in
--    only 1 store but is in the top 3 of 29. The remaining 4 stores have other leaders.
WITH ranked AS (
  SELECT s.Store_ID,
         p.Product_Name,
         RANK() OVER (PARTITION BY s.Store_ID
                      ORDER BY SUM(s.Units * (p.price - p.cost)) DESC) AS rnk
  FROM sales s
  JOIN products p ON s.Product_ID = p.Product_ID
  GROUP BY s.Store_ID, p.Product_ID, p.Product_Name
)
SELECT Product_Name,
       SUM(rnk = 1)  AS stores_ranked_1st,
       SUM(rnk <= 3) AS stores_in_top_3
FROM ranked
WHERE rnk <= 3
GROUP BY Product_Name
ORDER BY stores_ranked_1st DESC, stores_in_top_3 DESC;
