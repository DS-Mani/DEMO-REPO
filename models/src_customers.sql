with stg_customers as (
select * from customers
),

silver_customers as (
select * from silver_customers
),

changes as (
select src.id,
src.name,
src.price,
src.start_date,
'9999-01-13' as end_date 
from customers src 
left join silver_customers sc on src.id = sc.id
where sc.id is NULL or (src.name <> sc.name or src.price <> sc.price)
),

final_changes as (
select sc.id,
sc.name,
sc.price,
sc.start_date,
current_date as end_date
from silver_customers sc
join changes on src.id = sc.id
where sc.id is not null

union all

select * from changes )

select * from final_changes;
