CREATE SCHEMA bronze.lakehouse;
CREATE SCHEMA silver.lakehouse;
CREATE SCHEMA gold.lakehouse;
drop table bronze.lakehouse.customer;
drop table bronze.lakehouse.orders;
drop table bronze.lakehouse.lineitem;

--bronze
SET SESSION bronze.compression_codec = 'SNAPPY';
SET SESSION bronze.compression_codec = 'GZIP';
SET SESSION bronze.compression_codec = 'ZSTD';

CREATE TABLE bronze.lakehouse.customer
WITH (format = 'PARQUET')
AS
SELECT custkey, mktsegment
FROM tpch.sf10.customer;

CREATE TABLE bronze.lakehouse.orders
WITH (format = 'PARQUET')
AS
SELECT orderkey, custkey, orderdate, shippriority
FROM tpch.sf10.orders;

CREATE TABLE bronze.lakehouse.lineitem
WITH (format = 'PARQUET')
AS
SELECT orderkey, shipdate, extendedprice, discount
FROM tpch.sf10.lineitem;

SELECT count(*)                AS files,
       sum(file_size_in_bytes) AS bytes
FROM bronze.lakehouse."customer$files";

SELECT count(*)                AS files,
       sum(file_size_in_bytes) AS bytes
FROM bronze.lakehouse."orders$files";

SELECT count(*)                AS files,
       sum(file_size_in_bytes) AS bytes
FROM bronze.lakehouse."lineitem$files";

SELECT count(*) FROM bronze.lakehouse.customer;
SELECT count(*) FROM bronze.lakehouse.orders;
SELECT count(*) FROM bronze.lakehouse.lineitem;

-- silver
SET SESSION silver.compression_codec = 'ZSTD';

CREATE TABLE silver.lakehouse.customer_building
WITH (format = 'PARQUET')
AS
SELECT custkey
FROM bronze.lakehouse.customer
WHERE mktsegment = 'BUILDING';

CREATE TABLE silver.lakehouse.orders_shipping
WITH (
  format = 'PARQUET',
  partitioning = ARRAY['month(orderdate)']
)
AS
SELECT orderkey, custkey, orderdate, shippriority
FROM bronze.lakehouse.orders
WHERE orderdate < DATE '1995-03-15';

CREATE TABLE silver.lakehouse.lineitem_shipping
WITH (format = 'PARQUET')
AS
SELECT orderkey, extendedprice, discount
FROM bronze.lakehouse.lineitem
WHERE shipdate > DATE '1995-03-15';

SELECT count(*)                AS files,
       sum(file_size_in_bytes) AS bytes
FROM silver.lakehouse."customer_building$files";

SELECT count(*)                AS files,
       sum(file_size_in_bytes) AS bytes
FROM silver.lakehouse."orders_shipping$files";

SELECT count(*)                AS files,
       sum(file_size_in_bytes) AS bytes
FROM silver.lakehouse."lineitem_shipping$files";

SELECT count(*) FROM silver.lakehouse.customer_building;
SELECT count(*) FROM silver.lakehouse.orders_shipping;
SELECT count(*) FROM silver.lakehouse.lineitem_shipping;

ALTER TABLE silver.lakehouse.customer_building 
ADD COLUMN delivery_zone varchar;

SELECT * FROM silver.lakehouse.customer_building LIMIT 10;

ALTER TABLE silver.lakehouse.customer_building 
RENAME COLUMN delivery_zone TO shipping_zone;

-- gold
SET SESSION gold.compression_codec = 'ZSTD';

CREATE TABLE gold.lakehouse.top10_orders
WITH (format = 'PARQUET')
AS
SELECT
  l.orderkey,
  sum(l.extendedprice * (1 - l.discount)) AS revenue,
  o.orderdate,
  o.shippriority
FROM silver.lakehouse.customer_building c
JOIN silver.lakehouse.orders_shipping o ON c.custkey = o.custkey
JOIN silver.lakehouse.lineitem_shipping l ON l.orderkey = o.orderkey
GROUP BY l.orderkey, o.orderdate, o.shippriority
ORDER BY revenue DESC
LIMIT 10;

SELECT * FROM gold.lakehouse.top10_orders ORDER BY revenue DESC;

SELECT count(*)                AS files,
       sum(file_size_in_bytes) AS bytes
FROM gold.lakehouse."top10_orders$files";

SELECT
  l.orderkey,
  sum(l.extendedprice * (1 - l.discount)) AS revenue,
  o.orderdate,
  o.shippriority
FROM bronze.lakehouse.customer c
JOIN bronze.lakehouse.orders   o ON c.custkey = o.custkey
JOIN bronze.lakehouse.lineitem l ON l.orderkey = o.orderkey
WHERE c.mktsegment = 'BUILDING'
  AND o.orderdate < DATE '1995-03-15'
  AND l.shipdate > DATE '1995-03-15'
GROUP BY l.orderkey, o.orderdate, o.shippriority
ORDER BY revenue DESC
LIMIT 10;

-- Все снапшоты
SELECT * FROM silver.lakehouse."orders_shipping$snapshots";

-- Данные конкретного снапшота
SELECT * FROM silver.lakehouse.orders_shipping
FOR VERSION
AS OF 1886831075717560526;

-- Откат
ALTER TABLE silver.lakehouse.orders_shipping EXECUTE rollback_to_snapshot(1886831075717560526);