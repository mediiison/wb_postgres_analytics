SELECT category,
       pos,
       article,
       revenue,
       abc,
       xyz
FROM (
    SELECT category,
           article,
           revenue,
           abc,
           xyz,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY revenue DESC) AS pos
    FROM v_abc_xyz
) t
WHERE pos <= %(n)s
ORDER BY category, pos;
