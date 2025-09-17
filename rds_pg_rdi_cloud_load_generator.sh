#!/bin/bash

# Connection details
PGHOST="10.0.0.28"
PGPORT="5432"
PGUSER="postgres"
PGDATABASE="rdi_tag_team_demo"
PGPASSWORD="Secret_42"
export PGPASSWORD

i=1
while true; do
  echo "=== Cycle $i ==="

  # Insert 10 users (let Postgres fill created_at with now())
  for j in {1..10}; do
    full_name="User_$i$j"
    email="user${i}_${j}@example.com"
    region="Region_$((RANDOM % 3))"

    psql --host=$PGHOST --port=$PGPORT --username=$PGUSER --dbname=$PGDATABASE -c \
      "INSERT INTO public.rdi_tag_team (full_name, email, region)
       VALUES ('$full_name', '$email', '$region');"

    sleep 1
  done

  # Update those 10 users (simulate changes)
  for j in {1..10}; do
    email="user${i}_${j}@example.com"
    new_region="UpdatedRegion_$((RANDOM % 5))"

    psql --host=$PGHOST --port=$PGPORT --username=$PGUSER --dbname=$PGDATABASE -c \
      "UPDATE public.rdi_tag_team
       SET region = '$new_region',
           full_name = full_name || '_upd'
       WHERE email = '$email';"

    sleep 1
  done

  # Delete 9 of them (keep 1 alive per batch)
  for j in {1..9}; do
    email="user${i}_${j}@example.com"

    psql --host=$PGHOST --port=$PGPORT --username=$PGUSER --dbname=$PGDATABASE -c \
      "DELETE FROM public.rdi_tag_team WHERE email = '$email';"

    sleep 1
  done

  ((i++))
done