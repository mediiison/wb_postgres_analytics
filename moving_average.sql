WITH days AS (
    SELECT d::date AS day
    FROM generate_series(
        (SELECT MIN(sale_date) FROM sales)::timestamp,
        (SELECT MAX(sale_date) FROM sales)::timestamp,
        interval '1 day'
    ) AS d
),
daily AS (
    SELECT days.day,
           COALESCE(s.qty, 0) AS qty
    FROM days
    LEFT JOIN sales s
           ON s.sale_date = days.day
          AND s.article = %(article)s
)
SELECT day,
       qty,
       ROUND(
           AVG(qty) OVER (ORDER BY day ROWS BETWEEN %(preceding)s PRECEDING AND CURRENT ROW),
           2
       ) AS moving_avg
FROM daily
ORDER BY day;
