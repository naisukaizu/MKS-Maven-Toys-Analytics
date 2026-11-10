-- =====================================================
-- Maven Toys: data checks
-- Run after 00_setup.sql (tables created, CSVs imported, prices converted to numbers).
-- Each query answers one question; record answers in notes.md.
-- Answers (-- A:): data through 2023-09-30, run 2026-11-10.
-- =====================================================


-- -----------------------------------------------------
-- 1. ROW COUNTS
-- -----------------------------------------------------

-- Q: Did every row import? (Compare with the row counts of the CSV files.)
-- A: All four tables match their CSV row counts:
--    sales 829,262; products 35; stores 50; inventory 1,593.
SELECT 'sales' AS tbl, COUNT(*) AS n_rows FROM sales
UNION ALL SELECT 'products',  COUNT(*) FROM products
UNION ALL SELECT 'stores',    COUNT(*) FROM stores
UNION ALL SELECT 'inventory', COUNT(*) FROM inventory;


-- -----------------------------------------------------
-- 2. DATES
-- -----------------------------------------------------

-- Q: What period does the sales data cover?
-- A: 1 January 2022 to 30 September 2023 (21 months).
SELECT MIN(Date) AS first_date, MAX(Date) AS last_date
FROM sales;

-- Q: Is any month only partly covered (missing days at the start or end)?
--    (days_with_sales should equal days_in_month for every month.)
-- A: No. Every month has sales on every calendar day, so all 21 months are complete.
--    2023 covers January-September only, so year-over-year comparisons use Jan-Sep.
SELECT YEAR(Date)               AS yr,
       MONTH(Date)              AS mo,
       MIN(Date)                AS first_day,
       MAX(Date)                AS last_day,
       COUNT(DISTINCT Date)     AS days_with_sales,
       DAY(LAST_DAY(MIN(Date))) AS days_in_month
FROM sales
GROUP BY yr, mo
ORDER BY yr, mo;


-- -----------------------------------------------------
-- 3. SALES ROWS
-- -----------------------------------------------------

-- Q: Is any sale recorded more than once? (Expect 0 rows.)
-- A: No. 0 duplicate Sale_IDs.
SELECT Sale_ID, COUNT(*) AS n
FROM sales
GROUP BY Sale_ID
HAVING COUNT(*) > 1;

-- Q: Are any unit quantities missing, zero or negative? (Expect 0.)
-- A: No. 0 rows.
SELECT COUNT(*) AS bad_units
FROM sales
WHERE Units IS NULL OR Units <= 0;

-- Q: Are there unrealistic quantities? (Look at the top and bottom of the list.)
-- A: No. Most sales are small quantities; the maximum is 30 units (two products).
SELECT Units, COUNT(*) AS n
FROM sales
GROUP BY Units
ORDER BY Units;


-- -----------------------------------------------------
-- 4. LINKS BETWEEN TABLES (ORPHANS)
-- -----------------------------------------------------

-- Q: Does every sale point to a product that exists? (Expect 0.)
-- A: Yes. 0 orphan rows.
SELECT COUNT(*) AS orphan_products
FROM sales s
LEFT JOIN products p ON s.Product_ID = p.Product_ID
WHERE p.Product_ID IS NULL;

-- Q: Does every sale point to a store that exists? (Expect 0.)
-- A: Yes. 0 orphan rows.
SELECT COUNT(*) AS orphan_stores
FROM sales s
LEFT JOIN stores st ON s.Store_ID = st.Store_ID
WHERE st.Store_ID IS NULL;


-- -----------------------------------------------------
-- 5. INVENTORY
-- -----------------------------------------------------

-- Q: Is any stock figure missing or negative? (Expect 0 rows.)
-- A: No. 0 rows.
SELECT *
FROM inventory
WHERE Stock_On_Hand IS NULL OR Stock_On_Hand < 0;

-- Q: Does each store-product pair appear only once? (Expect 0 rows.)
-- A: Yes. 0 duplicate pairs.
SELECT Store_ID, Product_ID, COUNT(*) AS n
FROM inventory
GROUP BY Store_ID, Product_ID
HAVING COUNT(*) > 1;

-- Q: Does every inventory row point to a store that exists? (Expect 0.)
-- A: Yes. 0 orphan rows.
SELECT COUNT(*) AS orphan_stores
FROM inventory i
LEFT JOIN stores st ON i.Store_ID = st.Store_ID
WHERE st.Store_ID IS NULL;

-- Q: Does every inventory row point to a product that exists? (Expect 0.)
-- A: Yes. 0 orphan rows.
SELECT COUNT(*) AS orphan_products
FROM inventory i
LEFT JOIN products p ON i.Product_ID = p.Product_ID
WHERE p.Product_ID IS NULL;

-- Q: Are the stock levels realistic?
-- A: Yes. Stock ranges from 0 to 139 units (average 18.67).
SELECT MIN(Stock_On_Hand) AS min_stock,
       MAX(Stock_On_Hand) AS max_stock,
       AVG(Stock_On_Hand) AS avg_stock
FROM inventory;

-- Q: How many store-product pairs are carried but out of stock?
--    (Not an error: record the count; 03_restock.sql analyses it.)
-- A: 77 pairs had zero stock on the snapshot date (analysed in 03_restock.sql).
SELECT COUNT(*) AS zero_stock_pairs
FROM inventory
WHERE Stock_On_Hand = 0;

-- Q: Were any products sold at a store that has no inventory record for them?
-- A: Yes. 41 store-product pairs.
SELECT DISTINCT s.Store_ID, s.Product_ID
FROM sales s
LEFT JOIN inventory i
  ON s.Store_ID = i.Store_ID AND s.Product_ID = i.Product_ID
WHERE i.Store_ID IS NULL;

-- Q: For those pairs, are they discontinued (last sold long ago)
--    or a gap in the snapshot (sold recently)?
-- A: 18 pairs had no sales in the last 90 days (likely discontinued);
--    23 sold within the last 90 days (likely missing from the snapshot).
SELECT s.Store_ID, s.Product_ID,
       MAX(s.Date)  AS last_sale,
       SUM(s.Units) AS total_units,
       DATEDIFF((SELECT MAX(Date) FROM sales), MAX(s.Date)) AS days_since_last_sale
FROM sales s
LEFT JOIN inventory i
  ON s.Store_ID = i.Store_ID AND s.Product_ID = i.Product_ID
WHERE i.Store_ID IS NULL
GROUP BY s.Store_ID, s.Product_ID
ORDER BY last_sale DESC;

-- Q: How much of the sales data do those pairs represent? Does it matter?
--    (pct_of_rows and pct_of_units are shares of ALL sales.)
-- A: 6,232 sales rows (0.75%) and 6,674 units (0.61%). Under 1%, so they don't
--    affect the sales analysis; the 23 recent pairs are a limitation for the restock analysis.
SELECT COUNT(*)     AS sales_rows,
       SUM(s.Units) AS units,
       ROUND(100 * COUNT(*)     / (SELECT COUNT(*)   FROM sales), 2) AS pct_of_rows,
       ROUND(100 * SUM(s.Units) / (SELECT SUM(Units) FROM sales), 2) AS pct_of_units
FROM sales s
LEFT JOIN inventory i
  ON s.Store_ID = i.Store_ID AND s.Product_ID = i.Product_ID
WHERE i.Store_ID IS NULL;