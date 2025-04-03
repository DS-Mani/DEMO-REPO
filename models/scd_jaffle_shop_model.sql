
{{
 config(
    materialized='snapshot',
    target_schema='DEV',
    unique_key='id',
    strategy='check',
    check_cols='all',  
    invalidate_hard_deletes=True
 )
}}
select * FROM {{ source('jaffle_shop', 'customers') }}
