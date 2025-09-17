BEGIN;

CREATE SEQUENCE IF NOT EXISTS public.rdi_tag_team_id_seq;

CREATE TABLE IF NOT EXISTS public.rdi_tag_team (
  id         integer NOT NULL DEFAULT nextval('public.rdi_tag_team_id_seq'::regclass),
  created_at timestamp without time zone DEFAULT now(),
  full_name  varchar(100) NOT NULL,
  email      varchar(150) NOT NULL,
  region     varchar(50),
  CONSTRAINT rdi_tag_team_pkey PRIMARY KEY (id)
);

ALTER SEQUENCE public.rdi_tag_team_id_seq OWNED BY public.rdi_tag_team.id;

-- Seed data (10 rows)
INSERT INTO public.rdi_tag_team (full_name, email, region) VALUES
  ('Alice Martins',   'alice.martins@example.com',   'us-east-1'),
  ('Bruno Lima',      'bruno.lima@example.com',      'us-west-2'),
  ('Carla Souza',     'carla.souza@example.com',     'eu-west-1'),
  ('Diego Ramos',     'diego.ramos@example.com',     'sa-east-1'),
  ('Elisa Rocha',     'elisa.rocha@example.com',     'ap-southeast-1'),
  ('Fabio Nunes',     'fabio.nunes@example.com',     'us-east-2'),
  ('Giulia Alves',    'giulia.alves@example.com',    'eu-central-1'),
  ('Henrique Costa',  'henrique.costa@example.com',  'sa-east-1'),
  ('Isabela Prado',   'isabela.prado@example.com',   'us-west-1'),
  ('João Pereira',    'joao.pereira@example.com',    'us-east-1')
ON CONFLICT DO NOTHING;

COMMIT;

-- Use the output nlb_dns_name value as the host (5432)
-- psql -h <nlb_dns_name_from_outputs> -p 5432 -U postgres -d rdi_tag_team_demo -f ./db_init.sql

-- psql -h rdi-rds-nlb-gabs-13-tn9oa7-38477518efc84c46.elb.us-east-1.amazonaws.com -p 5432 -U postgres -d rdi_tag_team_demo -f ./db_init.sql