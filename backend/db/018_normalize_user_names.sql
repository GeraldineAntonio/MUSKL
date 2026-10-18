UPDATE users
SET first_name = initcap(regexp_replace(trim(first_name), '[[:space:]]+', ' ', 'g')),
    last_name = initcap(regexp_replace(trim(last_name), '[[:space:]]+', ' ', 'g'))
WHERE first_name IS DISTINCT FROM initcap(regexp_replace(trim(first_name), '[[:space:]]+', ' ', 'g'))
   OR last_name IS DISTINCT FROM initcap(regexp_replace(trim(last_name), '[[:space:]]+', ' ', 'g'));
