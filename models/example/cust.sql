{{
    config(
        materialized = 'incremental'

    )
}}

with inc_cte as (
    select * from {{ref('stg_customers')}}
)
select 
    f.customer_id,
    f.first_name,
    f.last_name
    from inc_cte F

{% if is_incremental() %}
 left join {{ this }} I on I.customer_id = F.customer_id
 union all


 select 
    f.customer_id,
    f.first_name,
    f.last_name
    from inc_cte F
    left join {{ this }} I on I.customer_id = F.customer_id

{% endif %}