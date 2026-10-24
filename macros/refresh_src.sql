{#- Test environment only: zero-copy clones of the ENPAL_RAW.PIPEDRIVE tables into <target database>.SRC,
    under the same table names. A clone costs no storage until the data diverges. Re-running replaces the
    whole SRC schema, so it resets the test data and nothing else may live in it. Prod reads ENPAL_RAW directly.

    Tables are cloned one by one rather than as one schema clone: a schema clone keeps each table's
    original owner (SYSADMIN), so the dbt role could not replace them; a table clone is owned by the
    role that creates it.

    Usage:  dbt run-operation refresh_src          (then dbt build) -#}
{% macro refresh_src() %}
    {% if target.name == 'prod' %}
        {{ exceptions.raise_compiler_error("refresh_src is test-only: the prod target reads ENPAL_RAW.PIPEDRIVE directly.") }}
    {% endif %}

    {% set tables = ['ACTIVITY', 'ACTIVITY_TYPES', 'DEAL_CHANGES', 'FIELDS', 'STAGES', 'USERS'] %}
    {% set src = target.database ~ '.SRC' %}

    {% do run_query('create or replace schema ' ~ src ~ " comment = 'Zero-copy clones of ENPAL_RAW.PIPEDRIVE (macros/refresh_src.sql)'") %}
    {% for table in tables %}
        {% do run_query('create table ' ~ src ~ '.' ~ table ~ ' clone ENPAL_RAW.PIPEDRIVE.' ~ table) %}
    {% endfor %}

    {{ log('Cloned ' ~ (tables | length) ~ ' tables from ENPAL_RAW.PIPEDRIVE into ' ~ src, info=True) }}
{% endmacro %}
