CREATE TABLE "items" (
    id int8 PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    partition_id uuid,
    value text,
    mutating text,
    inserted_at timestamp with time zone default current_timestamp
);

CREATE INDEX ON "items" (partition_id);

CREATE TABLE partitioned_items (
    id int8 PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    partition_id uuid NOT NULL,
    value text
);

CREATE INDEX ON "partitioned_items" (partition_id);
