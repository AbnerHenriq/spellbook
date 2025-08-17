{{ config(
    materialized='table',
    unique_key = ['day', 'address'],
    cluster_by = ['day']
    )
}}

-- This model calculates the daily balance for each Bitcoin wallet.
-- It considers all transactions (inputs and outputs) to compute the net change for each day.
-- The final balance is the cumulative sum of these daily changes.
-- Note: This model only creates a record for days where a wallet had activity.

WITH daily_deltas AS (
    -- First, we calculate the net change (delta) for each wallet on each day.
    -- We get all outputs (credits) and inputs (debits) and sum them up.
    SELECT
        address,
        CAST(time AS DATE) AS day,
        SUM(value) AS delta
    FROM (
        -- Credits from outputs
        SELECT
            address,
            time,
            value
        FROM {{ source('bitcoin', 'outputs') }}
        WHERE address IS NOT NULL

        UNION ALL

        -- Debits from inputs
        -- Coinbase inputs are excluded as they are new coins, not a transfer from another wallet.
        SELECT
            address,
            time,
            -value AS value
        FROM {{ source('bitcoin', 'inputs') }}
        WHERE address IS NOT NULL
        AND is_coinbase = false
    )
    GROUP BY 1, 2
)

-- Then, we calculate the running total of these deltas to get the balance for each day.
SELECT
    day,
    address,
    -- The balance is the cumulative sum of daily deltas for each address.
    SUM(delta) OVER (PARTITION BY address ORDER BY day) AS balance
FROM daily_deltas
