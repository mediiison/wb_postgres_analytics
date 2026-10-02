WITH last_day AS (
    SELECT MAX(sale_date) AS d FROM sales
)
SELECT a.article,
       a.category,
       MAX(s.sale_date)           AS last_sale,
       l.d - MAX(s.sale_date)     AS days_idle
FROM articles a
JOIN sales s ON s.article = a.article
CROSS JOIN last_day l
GROUP BY a.article, a.category, l.d
HAVING l.d - MAX(s.sale_date) >= %(days)s
ORDER BY days_idle DESC, a.article;
