# Maven Toys: Sales, Profit and Inventory Analysis

> 🚧 **In progress.** The SQL data checks and sales analysis are done. Restock analysis (SQL) and a Power BI dashboard are next.

An analysis of 21 months of sales from **Maven Toys**, a fictional chain of 50 toy stores in Mexico, built in **MySQL**. It checks the data, measures revenue and profit by store, location and product, and will flag which products need restocking.

---

## The business problem

Maven Toys wants to know:
- Is the business growing, and is the growth profitable?
- Which stores, locations and products earn the most?
- Which products are out of stock, or about to run out, and what does that cost?

## The data

| Table | Rows | What it holds |
|---|---|---|
| `sales` | 829,262 | One row per transaction: date, store, product, units (1 Jan 2022 – 30 Sep 2023) |
| `products` | 35 | Product name, category, cost and price |
| `stores` | 50 | Store name, city, location type (Downtown, Commercial, Residential, Airport), opening date |
| `inventory` | 1,593 | Stock on hand for each store and product (a single snapshot) |

Source: [Mexico Toy Sales](https://mavenanalytics.io/data-playground/mexico-toy-sales), Maven Analytics (public domain).

## Key findings so far

- **The business grew, but margins fell.** Comparing January–September of each year, revenue rose **30.9%** ($5.3M to $7.0M) while profit rose only **16.0%** ($1.6M to $1.8M). No new stores opened, so the growth came from existing stores, mostly through **lower-margin products**.
- **Toys is the most profitable category ($1.1M)**, but at a **21.2%** margin, below the **27.8%** overall margin.
- **Colorbuds is the star product.** It sells the most units (104K) at a **53.4%** margin, is the top earner in **39 of 50 stores**, and is in the top 3 of every store.
- **Some high sellers earn very little.** Dino Eggs is the 11th best seller (38K units) but has only a **9.1%** margin.
- **Downtown stores earn the most in total ($2.2M); Airport stores earn the most per store ($126K).**

## Data checks

Before any analysis, I checked the data in MySQL ([`sql/01_checks.sql`](sql/01_checks.sql)).

**Completeness**
- All four tables imported completely; row counts match the CSV files (sales: 829,262; products: 35; stores: 50; inventory: 1,593).
- Sales run from **1 January 2022 to 30 September 2023**, with sales recorded on every day, so no month is partial. 2023 covers only January to September, so year-over-year comparisons use **January–September of each year**.

**Sales**
- No duplicate sales.
- No missing, zero or negative quantities. The largest sale is 30 units, so there are no unrealistic values.
- Every sale links to a valid product and store.

**Inventory**
- One row per store-product pair (1,593 of the 1,750 possible pairs), with no missing or negative stock values and no links to non-existent stores or products.
- Stock on hand ranges from 0 to 139 units (average 18.7).
- **77 store-product pairs had zero stock** on the snapshot date. These will be analysed in the restock step.

**Limitations**
- **41 store-product pairs appear in sales but have no inventory record** (0.75% of sales rows, 0.61% of units sold), too few to affect the sales analysis.
  - 18 had no sales in the last 90 days, so they appear to be discontinued at those stores.
  - 23 sold recently, so the inventory snapshot is likely missing them, and the restock analysis can't assess these pairs.
- Inventory is a single snapshot, so stock levels over time can't be analysed.
- With only one October–December in the data (2022), holiday seasonality can be suggested but not confirmed.

## Approach

1. **Setup** ([`sql/00_setup.sql`](sql/00_setup.sql)): created the tables, loaded the CSVs with `LOAD DATA`, and converted prices stored as text (`"$9.99 "`) to numbers.
2. **Data checks** ([`sql/01_checks.sql`](sql/01_checks.sql)): completeness, duplicates, invalid values, orphan rows and inventory coverage.
3. **Analysis** ([`sql/02_analysis.sql`](sql/02_analysis.sql)): totals, year-over-year growth, and profit by store, location type, category and product, including a window function (`RANK()`) for each store's top products.

Every query in the `.sql` files starts with the question it answers (`-- Q:`) and its result (`-- A:`), so you can read the answers and rerun any query to check them.

**Next:** restock analysis in SQL (safety stock and reorder points), then a Power BI dashboard.

## Challenges and what I learned

- **Prices stored as text.** Costs and prices came as text like `"$9.99 "`, so I loaded them as text and converted them with `REPLACE`, `TRIM` and `CAST`, keeping the original columns.
- **Estimated vs. exact row counts.** MySQL Workbench showed 827,717 rows for `sales`, but `COUNT(*)` returned 829,262, matching the CSV. The Workbench figure is an estimate from sampled data pages, so I rely on `COUNT(*)`.
- **Questioning the question.** I first planned to find seasonality in SQL, but a 105-row result can't be read by eye, so it will be answered with a line chart instead. I also kept the year-over-year comparison as a simple two-row query, because a window function wasn't worth it for two years.

## Tools

MySQL 8 (MySQL Workbench): joins, CTEs, window functions (`RANK()`), conditional aggregation, data cleaning with `REPLACE`, `TRIM` and `CAST`

## Files

```
maven-toys-sales-inventory/
├── README.md
├── data/
│   ├── sales.csv
│   ├── products.csv
│   ├── stores.csv
│   └── inventory.csv
└── sql/
    ├── 00_setup.sql
    ├── 01_checks.sql
    └── 02_analysis.sql
```

## Author

**Marvic Kaizz D.J. Sobreviñas** · Data analyst (career shifter from science teaching)
[LinkedIn](https://www.linkedin.com/in/naisukaizu/) · [GitHub](https://github.com/naisukaizu)
