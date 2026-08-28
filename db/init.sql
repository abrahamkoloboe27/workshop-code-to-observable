-- Schema and seed data for the workshop.
-- Loaded once by the Postgres entrypoint, on an empty volume. Small on purpose:
-- a cold start must cost a few seconds, not a coffee break. The startup race of
-- floor 4 lives in that short window, not in a heavy seed.

CREATE TABLE items (
    id    SERIAL PRIMARY KEY,
    name  TEXT           NOT NULL,
    price NUMERIC(10, 2) NOT NULL
);

CREATE TABLE orders (
    id       SERIAL PRIMARY KEY,
    customer TEXT           NOT NULL,
    amount   NUMERIC(10, 2) NOT NULL,
    status   TEXT           NOT NULL,
    created  TIMESTAMPTZ    NOT NULL DEFAULT now()
);

INSERT INTO items (name, price)
SELECT 'item-' || g, (random() * 100)::numeric(10, 2)
FROM generate_series(1, 200) AS g;

INSERT INTO orders (customer, amount, status)
SELECT
    'customer-' || (g % 500),
    (random() * 500)::numeric(10, 2),
    (ARRAY['pending', 'paid', 'shipped', 'cancelled'])[1 + (g % 4)]
FROM generate_series(1, 20000) AS g;

CREATE INDEX orders_customer_idx ON orders (customer);
