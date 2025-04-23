CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE USER toast WITH NOCREATEDB NOCREATEROLE LOGIN PASSWORD 'toast';
SELECT 'CREATE DATABASE toast WITH OWNER = toast' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'toast')\gexec
GRANT ALL PRIVILEGES ON DATABASE toast TO toast;
\c toast
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
\c toast toast
CREATE OR REPLACE FUNCTION random_string(length integer) RETURNS text AS
$$
DECLARE
  chars text[] := '{0,1,2,3,4,5,6,7,8,9,A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z}';
  result text := '';
  i integer := 0;
BEGIN
  if length < 0 then
    raise exception 'Given length cannot be less than 0';
  end if;
  for i in 1..length loop
    result := result || chars[1+random()*(array_length(chars, 1)-1)];
  end loop;
  return result;
END;
$$ LANGUAGE plpgsql;
CREATE TABLE customers (
  id BIGINT GENERATED ALWAYS AS IDENTITY NOT NULL PRIMARY KEY,
  first_name VARCHAR(255) NOT NULL,
  last_name VARCHAR(255) NOT NULL,
  age integer NOT NULL,
  biography TEXT
);
INSERT INTO customers(first_name,last_name,age,biography) VALUES(CONCAT('FirstName',generate_series(1, 100)), CONCAT('LastName',round((random()*100)::integer,0)), round((random()*100)::integer,0), random_string(7000));
ANALYZE customers;
