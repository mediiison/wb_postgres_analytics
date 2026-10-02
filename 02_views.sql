DROP VIEW IF EXISTS v_segment_matrix;
DROP VIEW IF EXISTS v_abc_xyz;
DROP VIEW IF EXISTS v_xyz;
DROP VIEW IF EXISTS v_abc;
DROP VIEW IF EXISTS v_article_revenue;
DROP MATERIALIZED VIEW IF EXISTS mv_monthly_qty;

CREATE VIEW v_article_revenue AS
SELECT a.article,
       a.category,
       SUM(s.revenue) AS revenue,
       SUM(s.qty)     AS qty
FROM articles a
JOIN sales s ON s.article = a.article
GROUP BY a.article, a.category;

CREATE VIEW v_abc AS
WITH ranked AS (
    SELECT article,
           category,
           revenue,
           qty,
           revenue / SUM(revenue) OVER () AS share,
           SUM(revenue) OVER (ORDER BY revenue DESC, article) / SUM(revenue) OVER () AS cum_share
    FROM v_article_revenue
)
SELECT article,
       category,
       revenue,
       qty,
       share,
       cum_share,
       CASE
           WHEN cum_share - share < 0.80 THEN 'A'
           WHEN cum_share - share < 0.95 THEN 'B'
           ELSE 'C'
       END AS abc
FROM ranked;

CREATE MATERIALIZED VIEW mv_monthly_qty AS
WITH bounds AS (
    SELECT MIN(sale_date) AS d_min, MAX(sale_date) AS d_max
    FROM sales
),
months AS (
    SELECT g::date AS month_start
    FROM bounds,
         generate_series(date_trunc('month', d_min::timestamp),
                         date_trunc('month', d_max::timestamp),
                         interval '1 month') AS g
    WHERE g::date >= d_min
      AND (g + interval '1 month' - interval '1 day')::date <= d_max
),
grid AS (
    SELECT a.article, m.month_start
    FROM articles a
    CROSS JOIN months m
)
SELECT g.article,
       g.month_start,
       COALESCE(SUM(s.qty), 0) AS qty
FROM grid g
LEFT JOIN sales s
       ON s.article = g.article
      AND s.sale_date >= g.month_start
      AND s.sale_date <  g.month_start + interval '1 month'
GROUP BY g.article, g.month_start;

CREATE INDEX idx_mv_monthly_qty_article ON mv_monthly_qty (article);

CREATE VIEW v_xyz AS
SELECT article,
       AVG(qty)                                      AS mean_qty,
       STDDEV_POP(qty) / NULLIF(AVG(qty), 0)         AS cv,
       CASE
           WHEN STDDEV_POP(qty) / NULLIF(AVG(qty), 0) <= 0.25 THEN 'X'
           WHEN STDDEV_POP(qty) / NULLIF(AVG(qty), 0) <= 0.50 THEN 'Y'
           ELSE 'Z'
       END                                           AS xyz
FROM mv_monthly_qty
GROUP BY article;

CREATE VIEW v_abc_xyz AS
SELECT a.article,
       a.category,
       a.revenue,
       a.qty,
       a.share,
       a.cum_share,
       a.abc,
       x.mean_qty,
       x.cv,
       x.xyz,
       a.abc || x.xyz AS segment
FROM v_abc a
JOIN v_xyz x ON x.article = a.article;

CREATE VIEW v_segment_matrix AS
SELECT abc,
       COUNT(*) FILTER (WHERE xyz = 'X') AS x_articles,
       COUNT(*) FILTER (WHERE xyz = 'Y') AS y_articles,
       COUNT(*) FILTER (WHERE xyz = 'Z') AS z_articles,
       ROUND(100 * COALESCE(SUM(share) FILTER (WHERE xyz = 'X'), 0), 1) AS x_revenue_pct,
       ROUND(100 * COALESCE(SUM(share) FILTER (WHERE xyz = 'Y'), 0), 1) AS y_revenue_pct,
       ROUND(100 * COALESCE(SUM(share) FILTER (WHERE xyz = 'Z'), 0), 1) AS z_revenue_pct
FROM v_abc_xyz
GROUP BY abc
ORDER BY abc;
