SELECT article,
       category,
       revenue,
       ROUND(100 * share, 2)     AS share_pct,
       ROUND(100 * cum_share, 2) AS cum_share_pct,
       ROUND(mean_qty, 1)        AS mean_monthly_qty,
       ROUND(cv, 3)              AS cv,
       segment
FROM v_abc_xyz
WHERE segment = %(segment)s
ORDER BY revenue DESC;
