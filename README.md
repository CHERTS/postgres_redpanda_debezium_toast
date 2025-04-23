# PostgreSQL + Redpanda + Debezium

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
    --network redpanda_debezium_network \
    quay.io/debezium/tooling:1.2 \
    /bin/bash -c "kafkacat -b redpanda:9092 \
    -C -o beginning -q -u -t toast_topic.public.customers | jq ."
```

Connect to PostgreSQL and run query:
```bash
docker run --tty --rm -i \
    --network redpanda_debezium_network \
    quay.io/debezium/tooling:1.2 \
    bash -c 'pgcli postgresql://toast:toast@postgres:5432/toast'
```

Run query:
```sql
UPDATE customers SET biography = random_string(7000) WHERE id=1;
```

Run query for show TOAST name and size:
```sql
SELECT c.relnamespace::regnamespace::text AS schema_name, c.relname AS source_table_name, c.relpages AS source_table_num_of_pages, to_char(c.reltuples, '9G999G999G999') AS source_table_num_of_tup, t.relname AS toast_table_name, t.relpages AS toast_table_num_of_pages, to_char(t.reltuples, '9G999G999G999') AS toast_table_num_of_tup, pg_size_pretty(pg_relation_size(c.reltoastrelid)) AS toast_size FROM pg_class c JOIN pg_class t ON c.reltoastrelid = t.oid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.relnamespace::regnamespace::text NOT IN ('pg_catalog', 'information_schema') ORDER BY pg_total_relation_size(c.reltoastrelid) DESC;
```


### Stop and cleanup data

```
docker-compose -f docker-compose.yml down --volumes
rm -rf postgres/pg_data/* postgres/pg_wal_data/* debezium_data/* redpanda_data/*
```
