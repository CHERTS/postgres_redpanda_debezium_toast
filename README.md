# PostgreSQL + Redpanda + Debezium and TOAST

So what’s that? TOAST (The Oversized-Attribute Storage Technique) is a mechanism in Postgres which stores large column values in
multiple physical rows, circumventing the page size limit of 8 KB.

Typically, TOAST storage is transparent to the user, so you don’t really have to care about it. There’s an exception, though: if a table row has changed,
any unchanged values that were stored using the TOAST mechanism are not included in the message that Debezium receives from the database, unless they are
part of the table’s replica identity. Consequently, such unchanged TOAST column value will not be contained in Debezium data change events sent to Apache Kafka (Redpanda).

When encountering an unchanged TOAST column value in the logical replication message received from the database, the Debezium Postgres connector will represent
that value with a configurable placeholder. By default, that’s the literal `__debezium_unavailable_value`, but that value can be overridden using the
`toasted.value.placeholder` connector property.

In this git repository I will show how to reproduce this issue.

### Requirements

- Docker
- Docker Compose
- httpie

### List of running containers and ports

- postgres (listen port: 5432)
- redpanda (listen port: 18081, 18082, 19092, 9644)
- redpanda-console (listen port: 8080)
- debezium (listen port: 8083)

### Quick start

Prepare data directory:

```bash
cat docker-compose.yml | grep device | awk -F' ' '{print $2}' | sed -e 's/${PWD}\///g' | xargs mkdir -p
cat docker-compose.yml | grep device | awk -F' ' '{print $2}' | sed -e 's/${PWD}\///g' | xargs chmod 777
```

Start all containers:
```bash
docker-compose -f docker-compose.yml up -d
```

Then register an instance of the Debezium Postgres connector:
```bash
http PUT http://localhost:8083/connectors/toast-connector/config < register-postgres-toast.json
```

Observe the marker value in the biography field of corresponding change events:
```bash
docker run -it --rm \
    --network postgres_redpanda_debezium_toast_debezium_network \
    quay.io/debezium/tooling:1.2 \
    /bin/bash -c "kafkacat -b redpanda:9092 \
    -C -o beginning -q -u -t toast_topic.public.customers | jq ."
```

Connect to PostgreSQL and run query:
```bash
docker run --tty --rm -i \
    --network postgres_redpanda_debezium_toast_debezium_network \
    quay.io/debezium/tooling:1.2 \
    bash -c 'pgcli postgresql://toast:toast@postgres:5432/toast'
```

Test scenario:
```sql
UPDATE customers SET biography = random_string(7000) WHERE id=1;
-- View the "biography" field in kafkacat output.
-- We see that the changes are being pushed to Redpanda.

UPDATE customers SET age = 1 WHERE id=1;
-- Now view at the "biography" field in the kafkacat output again.
-- We see that the "biography" field is not present in Redpanda, it contains __debezium_unavailable_value

-- Let's try to fix this problem. 
ALTER TABLE customers REPLICA IDENTITY FULL;
UPDATE customers SET age = 2 WHERE id=1;
-- Now view the "biography" field in kafkacat output.
-- We see that the contents of the "biography" field began to appear in before and after payload

-- Change REPLICA IDENTITY to default value
ALTER TABLE customers REPLICA IDENTITY DEFAULT;
UPDATE customers SET age = 3 WHERE id=1;
-- Now view at the "biography" field in the kafkacat output again.
-- And again we don't see any data in the "biography" field.
```

Run query for show TOAST name and size:
```sql
SELECT c.relnamespace::regnamespace::text AS schema_name, c.relname AS source_table_name,
c.relpages AS source_table_num_of_pages, to_char(c.reltuples, '9G999G999G999') AS source_table_num_of_tup,
t.relname AS toast_table_name, t.relpages AS toast_table_num_of_pages, to_char(t.reltuples, '9G999G999G999') AS toast_table_num_of_tup,
pg_size_pretty(pg_relation_size(c.reltoastrelid)) AS toast_size 
FROM pg_class c 
JOIN pg_class t ON c.reltoastrelid = t.oid 
JOIN pg_namespace n ON n.oid = t.relnamespace 
WHERE c.relnamespace::regnamespace::text NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(c.reltoastrelid) DESC;
```


### Stop and cleanup data

```
docker-compose -f docker-compose.yml down --volumes
rm -rf postgres/pg_data/* postgres/pg_wal_data/* debezium_data/* redpanda_data/*
```
