-- =====================================================
-- Maven Toys: database setup
-- Creates the tables, loads the four raw CSVs from data/, and converts
-- prices from text to numbers. Run once, before 01_checks.sql.
-- Source: Mexico Toy Sales, Maven Analytics (public domain).
-- =====================================================


-- -----------------------------------------------------
-- 1. DATABASE
-- -----------------------------------------------------

-- Why: keep the project's tables in their own database.
--    To rebuild from scratch, uncomment the DROP line first
--    (it deletes the database and everything in it).
-- DROP DATABASE IF EXISTS maven_toys;
CREATE DATABASE maven_toys;
USE maven_toys;


-- -----------------------------------------------------
-- 2. TABLES
-- -----------------------------------------------------

-- Why: one table per CSV, with column names kept as in the files so they
--    are easy to match. IDs are primary keys so MySQL rejects duplicates.
--    Prices load as TEXT because the CSV stores them like "$9.99 ";
--    loading them straight into a number column would fail or give 0.
CREATE TABLE products (
  Product_ID       INT PRIMARY KEY,
  Product_Name     VARCHAR(100),
  Product_Category VARCHAR(50),
  Product_Cost     VARCHAR(20),   -- text, e.g. "$9.99 "; converted in section 4
  Product_Price    VARCHAR(20)    -- text; converted in section 4
);

CREATE TABLE stores (
  Store_ID        INT PRIMARY KEY,
  Store_Name      VARCHAR(100),
  Store_City      VARCHAR(50),
  Store_Location  VARCHAR(50),    -- Downtown, Commercial, Residential, Airport
  Store_Open_Date DATE
);

-- Why: the fact table. One row per transaction; Store_ID and Product_ID
--    link it to stores and products.
CREATE TABLE sales (
  Sale_ID    INT PRIMARY KEY,
  Date       DATE,
  Store_ID   INT,
  Product_ID INT,
  Units      INT
);

-- Why: a single snapshot of stock on hand per store and product.
--    No primary key here; 01_checks.sql confirms each pair appears once.
CREATE TABLE inventory (
  Store_ID      INT,
  Product_ID    INT,
  Stock_On_Hand INT
);


-- -----------------------------------------------------
-- 3. LOAD THE CSVs
-- -----------------------------------------------------

-- Why LOAD DATA: sales has 829,262 rows, which the Table Data Import
--    Wizard takes a very long time to load. LOAD DATA takes seconds, and
--    using it for every table makes the whole setup repeatable.
-- Requires local_infile: run SET GLOBAL local_infile = 1; and add
--    OPT_LOCAL_INFILE=1 under Advanced > Others in the Workbench connection.
-- Paths: change C:/path/to/ to where data/ is on your machine.
-- IGNORE 1 ROWS skips the header row. If the files have Windows line
--    endings and the last column loads wrong, change '\n' to '\r\n'.

LOAD DATA LOCAL INFILE 'C:/path/to/data/products.csv'
INTO TABLE products
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'C:/path/to/data/stores.csv'
INTO TABLE stores
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'C:/path/to/data/sales.csv'
INTO TABLE sales
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'C:/path/to/data/inventory.csv'
INTO TABLE inventory
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- Why: LOAD DATA turns problems (e.g. a blank number) into warnings, not
--    errors, and silently stores 0. Check right after loading.
SHOW WARNINGS;


-- -----------------------------------------------------
-- 4. CONVERT PRICES TO NUMBERS
-- -----------------------------------------------------

-- Why: revenue and profit need numeric prices. Keep the original text
--    columns and add clean ones next to them, so the raw value is never lost.
ALTER TABLE products
  ADD COLUMN cost  DECIMAL(10,2),
  ADD COLUMN price DECIMAL(10,2);

-- Why: Workbench's "safe updates" mode blocks an UPDATE without a
--    key-based WHERE clause. Turn it off for this one update.
SET SQL_SAFE_UPDATES = 0;

-- Why: remove the "$" and the trailing space, then convert to a decimal.
UPDATE products
SET cost  = CAST(TRIM(REPLACE(Product_Cost,  '$', '')) AS DECIMAL(10,2)),
    price = CAST(TRIM(REPLACE(Product_Price, '$', '')) AS DECIMAL(10,2));

SET SQL_SAFE_UPDATES = 1;

-- Q: Did every price convert, and does any product sell at or below cost?
--    (Expect 0 rows.)
-- A: 0 rows. Every price converted, and every product sells above cost.
SELECT *
FROM products
WHERE cost IS NULL OR price IS NULL OR price <= cost;