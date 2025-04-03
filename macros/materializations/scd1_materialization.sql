{% materialization merge_scd1, default %}

-- Define variables
{%- set target_table = this %}
{%- set source_table = config.get('source_table') %}
{%- set unique_keys = config.get('unique_key') %} {# Expecting a list now #}
{%- set soft_delete_column = config.get('soft_delete_column') %}
{%- set delete_flag_value = config.get('delete_flag_value') %}
{%- set non_delete_flag_value = config.get('non_delete_flag_value') %}

-- Log the configuration parameters
{% do log("Starting merge process for table: " ~ target_table, info=true) %}
{% do log("Source table: " ~ source_table, info=true) %}
{% do log("Unique keys: " ~ unique_keys | join(', '), info=true) %}
{% do log("Soft delete column: " ~ soft_delete_column, info=true) %}

{# Get the list of columns from the source table #}
{% set source_columns = adapter.get_columns_in_relation(source_table) %}
{% do log("Columns in the source table: " ~ source_columns | map(attribute='name') | join(', '), info=true) %}

{# Create a list for column names initialized to NULL #}
{% set select_columns = [] %}
{% for column in source_columns %}
    {% if column.name not in unique_keys %}
        {% do select_columns.append('NULL AS ' ~ column.name) %}
    {% endif %}
{% endfor %}
{% set select_columns_csv = select_columns | join(', ') %}

{# Log the select columns #}
{% do log("Select columns initialized to NULL for missing records: " ~ select_columns_csv, info=true) %}

{# Create comparison conditions for updating records #}
{% set comparison_conditions = [] %}
{% for column in source_columns %}
    {% if column.name not in unique_keys %}
        {% do comparison_conditions.append('(source.' ~ column.name ~ ' <> target.' ~ column.name ~ ')') %}
    {% endif %}
{% endfor %}
{% set comparison_conditions_csv = comparison_conditions | join(' OR ') %}

{# Log the comparison conditions #}
{% do log("Comparison conditions for updates: " ~ comparison_conditions_csv, info=true) %}

{# Define the update set clauses #}
{% set update_set_clauses = [] %}
{% for column in source_columns %}
    {% if column.name not in unique_keys %}
        {% do update_set_clauses.append('target.' ~ column.name ~ ' = source.' ~ column.name) %}
    {% endif %}
{% endfor %}
{% do update_set_clauses.append('target.UPDATE_TS = CURRENT_TIMESTAMP') %}
{% set update_set_csv = update_set_clauses | join(', ') %}

{# Log the update set clauses #}
{% do log("Update set clauses: " ~ update_set_csv, info=true) %}

{# Get the list of columns from the target table #}
{% set target_columns = adapter.get_columns_in_relation(this) %}
{% do log("Columns in the target table: " ~ target_columns | map(attribute='name') | join(', '), info=true) %}

{# Prepare column names and values for insertion #}
{% set insert_cols = [] %}
{% for column in target_columns %}
    {% do insert_cols.append(column.name) %}
{% endfor %}
{% set insert_cols_csv = insert_cols | join(', ') %}
{% do log("Insert columns for new records: " ~ insert_cols_csv, info=true) %}

{% set values_cols = [] %}
{% for column in source_columns %}
    {% do values_cols.append('source.' ~ adapter.quote(column.name)) %}
{% endfor %}
{% set values_cols_csv = values_cols | join(', ') ~ ', CURRENT_TIMESTAMP, ' ~ '\'' ~ non_delete_flag_value ~ '\'' %}
{% do log("Values for new record insertion: " ~ values_cols_csv, info=true) %}

{# Create NULL checks for conditions #}
{% set null_checks = [] %}
{% for column in source_columns %}
    {% if column.name not in unique_keys %}
        {% do null_checks.append('source.' ~ column.name ~ ' IS NULL') %}
    {% endif %}
{% endfor %}
{% set null_checks_csv = null_checks | join(' AND ') %}
{% do log("NULL check conditions for soft delete: " ~ null_checks_csv, info=true) %}

{% set not_in_conditions = [] %}
{% for key in unique_keys %}
    {% do not_in_conditions.append(key ~ ' NOT IN (SELECT ' ~ key ~ ' FROM ' ~ source_table ~ ')') %}
{% endfor %}
{% set not_in_conditions_csv = not_in_conditions | join(' AND ') %}


{# Create the ON condition for multiple unique keys #}
{% set on_conditions = [] %}
{% for key in unique_keys %}
    {% do on_conditions.append('target.' ~ key ~ ' = source.' ~ key) %}
{% endfor %}
{% set on_conditions_csv = on_conditions | join(' AND ') %}
{% do log("ON condition for the merge: " ~ on_conditions_csv, info=true) %}

{# Execute the main MERGE statement #}
{% call statement('main') %}
MERGE INTO {{ target_table }} AS target
USING (
    SELECT * FROM {{ source_table }}
    UNION ALL
    SELECT {{ unique_keys | join(', ') }},
           {{ select_columns_csv }}
    FROM {{ target_table }}
    WHERE {{ not_in_conditions_csv }}
) AS source
ON {{ on_conditions_csv }}
WHEN MATCHED
    AND (
        {{ comparison_conditions_csv }}
    )
    AND target.{{ soft_delete_column }} = '{{ non_delete_flag_value }}'
THEN UPDATE SET
    {{ update_set_csv }}
WHEN MATCHED
    AND ({{ null_checks_csv }})
    AND target.{{ soft_delete_column }} = '{{ non_delete_flag_value }}'
THEN UPDATE SET
    target.{{ soft_delete_column }} = '{{ delete_flag_value }}',
    target.UPDATE_TS = CURRENT_TIMESTAMP
WHEN NOT MATCHED
THEN INSERT ({{ insert_cols_csv }})
VALUES ({{ values_cols_csv }});
{% endcall %}
{% do log("Merge completed successfully.", info=true) %}
{{ adapter.commit() }}

-- Return the result
{% do log("Returning the result of the materialization.", info=true) %}
{% do return({'relations': [target_table]}) %}

{% endmaterialization %}
