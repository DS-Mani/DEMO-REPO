{{ 
  config(
    materialized='incremental',
    incremental_strategy='merge',
    target_schema='dev',
    unique_key=['ID']

  ) 
}}

select * from cl_dbt.jaffle_shop.customers