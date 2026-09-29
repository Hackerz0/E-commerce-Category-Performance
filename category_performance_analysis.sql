-- ============================================================
-- PROJECT 2: E-COMMERCE CATEGORY PERFORMANCE ANALYSIS
-- Tool: SQL Server
-- Dataset: Brazilian E-Commerce Public Dataset by Olist
-- Purpose: Data inspection, data validation, category analysis,
--          delivery performance, reviews, and sales trends
-- ============================================================


-- ============================================================
-- 1. CHECK TABLE SIZE AND SAMPLE DATA
-- Inspect the main tables and their record counts.
-- ============================================================

SELECT TOP 10 *
FROM dbo.raw_orders;

SELECT COUNT(*) AS total_orders
FROM dbo.raw_orders;


SELECT TOP 10 *
FROM dbo.raw_order_items;

SELECT COUNT(*) AS total_order_items
FROM dbo.raw_order_items;


SELECT TOP 10 *
FROM dbo.raw_products;

SELECT COUNT(*) AS total_products
FROM dbo.raw_products;


SELECT TOP 10 *
FROM dbo.raw_order_reviews;

SELECT COUNT(*) AS total_reviews
FROM dbo.raw_order_reviews;


SELECT *
FROM dbo.product_category_name_translation;

SELECT COUNT(*) AS total_categories
FROM dbo.product_category_name_translation;


-- ============================================================
-- 2. BASIC DATA QUALITY CHECKS
-- Check order statuses, delivery-date coverage,
-- invalid prices, and negative freight values.
-- ============================================================

SELECT DISTINCT order_status
FROM raw_orders;


SELECT
    COUNT(*) AS total,
    COUNT(order_delivered_customer_date) AS has_delivery_date
FROM raw_orders;


SELECT
    COUNT(*) AS total_count_price
FROM raw_order_items
WHERE price <= 0;


-- Negative freight is the actual data quality issue.
-- Zero can legitimately represent free shipping.
SELECT
    COUNT(*) AS total_count_negative_freight
FROM raw_order_items
WHERE freight_value < 0;


-- ============================================================
-- 3. CHECK CATEGORY TRANSLATION COVERAGE
-- Compare the original product categories with their
-- English translations.
-- ============================================================

SELECT
    DISTINCT p.product_category_name,
    t.product_category_name_english
FROM raw_products p
LEFT JOIN dbo.product_category_name_translation t
    ON t.product_category_name = p.product_category_name
ORDER BY product_category_name;


-- ============================================================
-- 4. CHECK REVIEW SCORES
-- Inspect the distinct review scores in the dataset.
-- ============================================================

SELECT DISTINCT review_score
FROM raw_order_reviews
ORDER BY review_score;


-- ============================================================
-- 5. CHECK REPEATED ORDER/PRODUCT COMBINATIONS
-- Investigate repeated order_id + product_id combinations.
--
-- Finding: order_id + product_id is not unique in the raw
-- order_items table. These repeated combinations are retained
-- because repetition alone does not prove that the rows are
-- erroneous duplicates.
-- ============================================================

SELECT
    order_id,
    product_id,
    COUNT(*) AS row_count
FROM raw_order_items
GROUP BY order_id, product_id
HAVING COUNT(*) > 1;


-- ============================================================
-- 6. CREATE CATEGORY PERFORMANCE VIEW
-- Combine orders, products, categories, and reviews into
-- one analysis-ready dataset.
--
-- Only delivered orders with non-negative freight values are
-- included. Repeated order_id + product_id combinations are
-- intentionally retained because they are not proven duplicates.
-- ============================================================

CREATE VIEW category_performance AS
(
    SELECT
        oi.order_id,
        oi.product_id,
        ROUND(oi.price, 2) AS price,
        ROUND(oi.freight_value, 2) AS freight_cost,
        ROUND(oi.price + oi.freight_value, 2) AS total_revenue,
        o.order_status,
        CAST(o.order_purchase_timestamp AS DATE) AS order_purchase_date,
        CAST(o.order_delivered_customer_date AS DATE) AS order_delivered_date,
        DATEDIFF(
            day,
            o.order_purchase_timestamp,
            o.order_delivered_customer_date
        ) AS delivery_days,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'Unknown'
        ) AS category_name,
        r.review_score
    FROM raw_order_items oi
    LEFT JOIN raw_orders o
        ON oi.order_id = o.order_id
    LEFT JOIN raw_products p
        ON oi.product_id = p.product_id
    LEFT JOIN product_category_name_translation ct
        ON p.product_category_name = ct.product_category_name
    LEFT JOIN raw_order_reviews r
        ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND oi.freight_value >= 0
);


-- Check the resulting analysis view.
SELECT TOP 20 *
FROM category_performance;

SELECT COUNT(*) AS total_count
FROM category_performance;


-- Confirm repeated order/product combinations carry through
-- the view unchanged.
SELECT
    order_id,
    product_id,
    COUNT(*) AS row_count
FROM category_performance
GROUP BY order_id, product_id
HAVING COUNT(*) > 1;


-- Inspect repeated rows in more detail.
-- Repetition alone is not treated as an error.
WITH flagged AS (
    SELECT *,
           COUNT(*) OVER (
               PARTITION BY order_id, product_id
           ) AS dup_count
    FROM category_performance
)
SELECT TOP 100 *
FROM flagged
WHERE dup_count > 1
ORDER BY order_id;


-- ============================================================
-- 7. REVENUE BY CATEGORY
-- Compare product sales, items sold, and sales value per item.
-- ============================================================

SELECT
    category_name,
    ROUND(SUM(price), 2) AS product_sales,
    COUNT(*) AS items_sold,
    ROUND(SUM(price) / COUNT(*), 2) AS sales_per_item
FROM category_performance
GROUP BY category_name
ORDER BY product_sales DESC;


-- ============================================================
-- 8. AVERAGE DELIVERY TIME BY CATEGORY
-- Compare delivery performance across categories.
-- ============================================================

SELECT
    category_name,
    ROUND(AVG(CAST(delivery_days AS FLOAT)), 1) AS avg_delivery_days
FROM category_performance
GROUP BY category_name
ORDER BY avg_delivery_days DESC;


-- ============================================================
-- 9. ORDER VOLUME BY CATEGORY
-- Compare unique orders and total items by category.
-- ============================================================

SELECT
    category_name,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(*) AS total_items
FROM category_performance
GROUP BY category_name
ORDER BY total_orders DESC;


-- ============================================================
-- 10. AVERAGE ORDER VALUE BY CATEGORY
-- Calculate the average revenue of an order within each category.
-- ============================================================

WITH order_category_totals AS (
    SELECT
        category_name,
        order_id,
        SUM(total_revenue) AS order_revenue
    FROM category_performance
    GROUP BY category_name, order_id
)
SELECT
    category_name,
    ROUND(AVG(order_revenue), 2) AS avg_order_value
FROM order_category_totals
GROUP BY category_name
ORDER BY avg_order_value DESC;


-- ============================================================
-- 11. AVERAGE REVIEW SCORE BY CATEGORY
-- Compare customer review scores across categories.
-- ============================================================

SELECT
    category_name,
    ROUND(AVG(CAST(review_score AS FLOAT)), 2) AS avg_review
FROM category_performance
GROUP BY category_name
ORDER BY avg_review DESC;


-- ============================================================
-- 12. REVIEW COVERAGE
-- Measure the percentage of category item records associated
-- with an order that received a review.
-- ============================================================

SELECT
    category_name,
    COUNT(review_score) AS review_given,
    COUNT(*) AS total_items,
    ROUND(
        COUNT(review_score) * 100.0 / COUNT(*),
        1
    ) AS review_rate_pct
FROM category_performance
GROUP BY category_name
ORDER BY review_rate_pct ASC;


-- ============================================================
-- 13. HIGH-REVENUE CATEGORIES AND REVIEW SCORES
-- Compare review scores among categories exceeding the
-- selected revenue threshold.
-- ============================================================

SELECT
    category_name,
    ROUND(SUM(price), 2) AS product_sales,
    ROUND(AVG(CAST(review_score AS FLOAT)), 2) AS avg_review
FROM category_performance
GROUP BY category_name
HAVING SUM(price) > 50000
ORDER BY avg_review ASC;


-- ============================================================
-- 14. MONTHLY SALES TREND
-- Compare monthly revenue and order volume.
-- ============================================================

SELECT
    FORMAT(order_purchase_date, 'yyyy-MM') AS month,
    ROUND(SUM(price), 2) AS product_sales,
    COUNT(DISTINCT order_id) AS orders
FROM category_performance
GROUP BY FORMAT(order_purchase_date, 'yyyy-MM')
ORDER BY month;


-- ============================================================
-- END OF PROJECT 2 SQL ANALYSIS
-- ============================================================
