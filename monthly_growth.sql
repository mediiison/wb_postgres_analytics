WITH monthly AS (
    SELECT date_trunc('month', sale_date::timestamp)::date AS month,
           SUM(revenue) AS revenue,
           SUM(qty)     AS qty
    FROM sales
    GROUP BY 1
)
SELECT month,
       revenue,
       qty,
       ROUND(
           100 * (revenue - LAG(revenue) OVER (ORDER BY month))
               / NULLIF(LAG(revenue) OVER (ORDER BY month), 0),
           1
       ) AS revenue_mom_pct
FROM monthly
ORDER BY month;
